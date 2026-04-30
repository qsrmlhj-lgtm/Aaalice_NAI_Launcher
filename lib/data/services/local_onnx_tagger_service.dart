import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'local_onnx_model_service.dart';

final localOnnxTaggerServiceProvider = Provider<LocalOnnxTaggerService>((ref) {
  return const LocalOnnxTaggerService();
});

enum OnnxTaggerLabelCategory {
  rating,
  general,
  character,
  other,
}

class OnnxTaggerLabel {
  const OnnxTaggerLabel({
    required this.name,
    this.category,
  });

  final String name;
  final String? category;

  OnnxTaggerLabelCategory get labelCategory {
    final normalizedCategory = category?.trim().toLowerCase();
    if (normalizedCategory == '9' ||
        normalizedCategory == 'rating' ||
        name.startsWith('rating:')) {
      return OnnxTaggerLabelCategory.rating;
    }
    if (normalizedCategory == '0' ||
        normalizedCategory == 'general' ||
        normalizedCategory == 'tag' ||
        normalizedCategory == 'tags') {
      return OnnxTaggerLabelCategory.general;
    }
    if (normalizedCategory == '4' ||
        normalizedCategory == 'character' ||
        normalizedCategory == 'characters') {
      return OnnxTaggerLabelCategory.character;
    }
    return OnnxTaggerLabelCategory.other;
  }

  bool get isRating {
    return labelCategory == OnnxTaggerLabelCategory.rating;
  }

  bool get isGeneral => labelCategory == OnnxTaggerLabelCategory.general;

  bool get isCharacter => labelCategory == OnnxTaggerLabelCategory.character;
}

class OnnxTaggerTag {
  const OnnxTaggerTag({
    required this.name,
    required this.score,
    this.category,
  });

  final String name;
  final double score;
  final String? category;
}

class OnnxTaggerResult {
  const OnnxTaggerResult({
    required this.model,
    required this.tags,
  });

  final LocalOnnxModelDescriptor model;
  final List<OnnxTaggerTag> tags;

  String get prompt => tags.map((tag) => tag.name).join(', ');
}

class _OnnxImageInput {
  const _OnnxImageInput({
    required this.data,
    required this.shape,
  });

  final Float32List data;
  final List<int> shape;
}

class LocalOnnxTaggerService {
  const LocalOnnxTaggerService();

  static const int defaultInputSize = 448;

  Future<OnnxTaggerResult> tagImage({
    required Uint8List imageBytes,
    required LocalOnnxModelDescriptor model,
    double? threshold,
    double generalThreshold = 0.35,
    double characterThreshold = 0.35,
    bool includeRatings = false,
  }) async {
    if (model.labelsPath == null || model.labelsPath!.isEmpty) {
      throw StateError(
        '模型缺少标签文件，请放置 selected_tags.csv / tags.csv / labels.txt',
      );
    }

    final labels = await loadLabels(model.labelsPath!);
    if (labels.isEmpty) {
      throw StateError('标签文件为空: ${model.labelsPath}');
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw StateError('无法解码图片');
    }

    final inputSize = _resolveInputSize(model);
    final input = _preprocessImage(decoded, inputSize, model);
    final options = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    // The onnxruntime package passes file paths through UTF-8 `CreateSession`,
    // which is not reliable on Windows where ONNX Runtime expects wide paths.
    // Loading from bytes avoids garbled path failures for external model dirs.
    final modelBytes = _patchUnsupportedOpsetImports(
      await File(model.path).readAsBytes(),
    );
    final session = OrtSession.fromBuffer(modelBytes, options);
    final runOptions = OrtRunOptions();
    final inputOrt = OrtValueTensor.createTensorWithDataList(
      input.data,
      input.shape,
    );

    List<OrtValue?>? outputs;
    try {
      final inputName =
          session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
      final asyncOutputs = session.runAsync(runOptions, {inputName: inputOrt});
      outputs = asyncOutputs == null
          ? session.run(runOptions, {inputName: inputOrt})
          : await asyncOutputs;
      final scores = outputs.isNotEmpty
          ? _normalizeScores(_flattenScores(outputs.first?.value))
          : <double>[];
      return OnnxTaggerResult(
        model: model,
        tags: _buildTags(
          labels: labels,
          scores: scores,
          generalThreshold: threshold ?? generalThreshold,
          characterThreshold: threshold ?? characterThreshold,
          includeRatings: includeRatings,
        ),
      );
    } finally {
      for (final output in outputs ?? const <OrtValue?>[]) {
        output?.release();
      }
      inputOrt.release();
      runOptions.release();
      session.release();
      options.release();
    }
  }

  Future<List<OnnxTaggerLabel>> loadLabels(String labelsPath) async {
    final file = File(labelsPath);
    if (!await file.exists()) {
      return const [];
    }

    final extension = labelsPath.split('.').last.toLowerCase();
    final raw = await file.readAsString();
    if (extension == 'json') {
      return _parseJsonLabels(raw);
    }
    if (extension == 'csv') {
      return _parseCsvLabels(raw);
    }
    return _parseTextLabels(raw);
  }

  int _resolveInputSize(LocalOnnxModelDescriptor model) {
    final lower = model.name.toLowerCase();
    if (lower.contains('cl_tagger')) {
      return 448;
    }
    final match = RegExp(r'(?:^|[^0-9])(224|256|384|448|512)(?:[^0-9]|$)')
        .firstMatch(lower);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    return defaultInputSize;
  }

  _OnnxImageInput _preprocessImage(
    img.Image source,
    int inputSize,
    LocalOnnxModelDescriptor model,
  ) {
    final squareSize = math.max(source.width, source.height);
    final canvas = img.Image(width: squareSize, height: squareSize);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(
      canvas,
      source,
      dstX: (squareSize - source.width) ~/ 2,
      dstY: (squareSize - source.height) ~/ 2,
    );

    final resized = img.copyResize(
      canvas,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.cubic,
    );

    final isClTagger = model.kind == LocalOnnxModelKind.clTagger ||
        model.name.toLowerCase().contains('cl_tagger');
    final data = Float32List(inputSize * inputSize * 3);
    if (isClTagger) {
      final planeSize = inputSize * inputSize;
      var bOffset = 0;
      var gOffset = planeSize;
      var rOffset = planeSize * 2;
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          data[bOffset++] = pixel.b.toDouble() / 255.0;
          data[gOffset++] = pixel.g.toDouble() / 255.0;
          data[rOffset++] = pixel.r.toDouble() / 255.0;
        }
      }
      return _OnnxImageInput(
        data: data,
        shape: [1, 3, inputSize, inputSize],
      );
    }

    var offset = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        data[offset++] = pixel.b.toDouble();
        data[offset++] = pixel.g.toDouble();
        data[offset++] = pixel.r.toDouble();
      }
    }
    return _OnnxImageInput(
      data: data,
      shape: [1, inputSize, inputSize, 3],
    );
  }

  List<double> _flattenScores(Object? value) {
    final scores = <double>[];

    void walk(Object? current) {
      if (current is num) {
        scores.add(current.toDouble());
        return;
      }
      if (current is Iterable) {
        for (final item in current) {
          walk(item);
        }
      }
    }

    walk(value);
    return scores;
  }

  List<double> _normalizeScores(List<double> scores) {
    if (scores.any((score) => score < 0 || score > 1)) {
      return scores.map((score) => 1 / (1 + math.exp(-score))).toList();
    }
    return scores;
  }

  Uint8List _patchUnsupportedOpsetImports(Uint8List bytes) {
    _patchDefaultDomainOpsetImport(bytes);
    _patchNamedDomainOpsetImport(bytes, domain: 'ai.onnx.ml', maxVersion: 3);
    return bytes;
  }

  void _patchDefaultDomainOpsetImport(Uint8List bytes) {
    final start = math.max(0, bytes.length - 4096);
    for (var i = start; i < bytes.length - 3; i++) {
      // ModelProto.opset_import field = 8 (0x42), OperatorSetIdProto with
      // only version field: [0x42, 0x02, 0x10, version]. CL tagger uses
      // ai.onnx opset 20, while the bundled Windows ORT can fail to bind
      // Shape(19) in the release runtime. CL tagger needs at least opset 18
      // because ReduceMean uses axes as an input.
      if (bytes[i] == 0x42 &&
          bytes[i + 1] == 0x02 &&
          bytes[i + 2] == 0x10 &&
          bytes[i + 3] > 18) {
        bytes[i + 3] = 18;
      }

      // Some exporters encode the default domain as an explicit empty string:
      // [0x42, 0x04, 0x0a, 0x00, 0x10, version].
      if (i < bytes.length - 5 &&
          bytes[i] == 0x42 &&
          bytes[i + 1] == 0x04 &&
          bytes[i + 2] == 0x0a &&
          bytes[i + 3] == 0x00 &&
          bytes[i + 4] == 0x10 &&
          bytes[i + 5] > 18) {
        bytes[i + 5] = 18;
      }
    }
  }

  void _patchNamedDomainOpsetImport(
    Uint8List bytes, {
    required String domain,
    required int maxVersion,
  }) {
    final needle = utf8.encode(domain);
    final start = math.max(0, bytes.length - 4096);
    for (var i = start; i <= bytes.length - needle.length; i++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (!matched) continue;

      final end = math.min(bytes.length - 1, i + needle.length + 8);
      for (var j = i + needle.length; j < end; j++) {
        if (bytes[j] == 0x10 && bytes[j + 1] > maxVersion) {
          bytes[j + 1] = maxVersion;
          return;
        }
      }
    }
  }

  List<OnnxTaggerTag> _buildTags({
    required List<OnnxTaggerLabel> labels,
    required List<double> scores,
    required double generalThreshold,
    required double characterThreshold,
    required bool includeRatings,
  }) {
    final count = math.min(labels.length, scores.length);
    final tags = <OnnxTaggerTag>[];
    for (var i = 0; i < count; i++) {
      final label = labels[i];
      final category = label.labelCategory;
      if (category == OnnxTaggerLabelCategory.rating && !includeRatings) {
        continue;
      }
      if (category != OnnxTaggerLabelCategory.general &&
          category != OnnxTaggerLabelCategory.character &&
          !(includeRatings && category == OnnxTaggerLabelCategory.rating)) {
        continue;
      }

      final score = scores[i];
      final effectiveThreshold = switch (category) {
        OnnxTaggerLabelCategory.character => characterThreshold,
        OnnxTaggerLabelCategory.rating => generalThreshold,
        OnnxTaggerLabelCategory.general => generalThreshold,
        OnnxTaggerLabelCategory.other => generalThreshold,
      };
      if (score < effectiveThreshold) continue;
      tags.add(
        OnnxTaggerTag(
          name: label.name,
          score: score,
          category: label.category,
        ),
      );
    }
    tags.sort((a, b) => b.score.compareTo(a.score));
    return tags;
  }

  List<OnnxTaggerLabel> _parseCsvLabels(String raw) {
    final rows = const CsvToListConverter(shouldParseNumbers: false)
        .convert(raw)
        .where((row) => row.isNotEmpty)
        .toList();
    final parsed = _labelsFromCsvRows(rows);
    if (parsed.isNotEmpty) {
      return parsed;
    }

    return _labelsFromCsvRows(
      raw
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => line.split(',').map((cell) => cell.trim()).toList())
          .toList(),
    );
  }

  List<OnnxTaggerLabel> _labelsFromCsvRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) {
      return const [];
    }

    final header = rows.first.map((e) => e.toString().toLowerCase()).toList();
    final hasHeader = header.contains('name') ||
        header.contains('tag') ||
        header.contains('category');
    final headerNameIndex = hasHeader
        ? math.max(header.indexOf('name'), header.indexOf('tag'))
        : -1;
    final nameIndex = headerNameIndex >= 0
        ? headerNameIndex
        : rows.first.length > 1
            ? 1
            : 0;
    final categoryIndex = hasHeader ? header.indexOf('category') : 2;
    final dataRows = hasHeader ? rows.skip(1) : rows;

    return dataRows
        .map((row) {
          if (row.length <= nameIndex) {
            return null;
          }
          final name = row[nameIndex].toString().trim();
          if (name.isEmpty) {
            return null;
          }
          final category = categoryIndex >= 0 && row.length > categoryIndex
              ? row[categoryIndex].toString().trim()
              : null;
          return OnnxTaggerLabel(name: name, category: category);
        })
        .whereType<OnnxTaggerLabel>()
        .toList();
  }

  List<OnnxTaggerLabel> _parseTextLabels(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((line) {
      final parts = line.split(RegExp(r'[\t,]'));
      return OnnxTaggerLabel(name: parts.first.trim());
    }).toList();
  }

  List<OnnxTaggerLabel> _parseJsonLabels(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .map((item) {
            if (item is String) {
              return OnnxTaggerLabel(name: item.trim());
            }
            if (item is Map<String, dynamic>) {
              final name = (item['name'] ?? item['tag'] ?? item['label'])
                  ?.toString()
                  .trim();
              if (name == null || name.isEmpty) {
                return null;
              }
              return OnnxTaggerLabel(
                name: name,
                category: item['category']?.toString(),
              );
            }
            return null;
          })
          .whereType<OnnxTaggerLabel>()
          .toList();
    }
    if (decoded is Map<String, dynamic>) {
      final numericKeys =
          decoded.keys.map(int.tryParse).whereType<int>().toList()..sort();
      if (numericKeys.isNotEmpty) {
        return numericKeys
            .map((index) {
              final item = decoded[index.toString()];
              if (item is String) {
                final name = item.trim();
                return name.isEmpty ? null : OnnxTaggerLabel(name: name);
              }
              if (item is Map<String, dynamic>) {
                final name = (item['tag'] ?? item['name'] ?? item['label'])
                    ?.toString()
                    .trim();
                if (name == null || name.isEmpty) {
                  return null;
                }
                return OnnxTaggerLabel(
                  name: name,
                  category: item['category']?.toString(),
                );
              }
              return null;
            })
            .whereType<OnnxTaggerLabel>()
            .toList();
      }

      final labels = decoded['labels'] ?? decoded['tags'];
      if (labels is List) {
        return labels
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .map((item) => OnnxTaggerLabel(name: item))
            .toList();
      }
    }
    return const [];
  }
}
