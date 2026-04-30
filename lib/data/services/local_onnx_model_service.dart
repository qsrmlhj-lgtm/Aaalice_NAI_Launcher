import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';

enum LocalOnnxModelKind { wd14Tagger, clTagger, unknown }

class LocalOnnxModelDescriptor {
  const LocalOnnxModelDescriptor({
    required this.name,
    required this.path,
    required this.kind,
    this.labelsPath,
  });

  final String name;
  final String path;
  final LocalOnnxModelKind kind;
  final String? labelsPath;

  bool get isOnnx => p.extension(path).toLowerCase() == '.onnx';
}

final localOnnxModelServiceProvider = Provider<LocalOnnxModelService>((ref) {
  return LocalOnnxModelService(ref.read(localStorageServiceProvider));
});

class LocalOnnxModelService {
  const LocalOnnxModelService(this._storage);

  final LocalStorageService _storage;

  String get taggerDirectory =>
      _storage.getSetting<String>(StorageKeys.onnxTaggerModelDirectory) ?? '';

  Future<void> setTaggerDirectory(String path) async {
    await _storage.setSetting(StorageKeys.onnxTaggerModelDirectory, path);
  }

  Future<List<LocalOnnxModelDescriptor>> scanTaggerModels() {
    return _scanModels(
      taggerDirectory,
      allowedKinds: const {
        LocalOnnxModelKind.wd14Tagger,
        LocalOnnxModelKind.clTagger,
        LocalOnnxModelKind.unknown,
      },
    );
  }

  Future<List<LocalOnnxModelDescriptor>> _scanModels(
    String directoryPath, {
    required Set<LocalOnnxModelKind> allowedKinds,
  }) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final directory = Directory(trimmed);
    if (!await directory.exists()) {
      return const [];
    }

    final result = <LocalOnnxModelDescriptor>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.onnx') continue;

      final kind = _inferKind(entity.path);
      if (!allowedKinds.contains(kind)) continue;

      result.add(
        LocalOnnxModelDescriptor(
          name: p.basename(entity.path),
          path: entity.path,
          kind: kind,
          labelsPath: await _findLabelsFile(entity.path),
        ),
      );
    }

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  LocalOnnxModelKind _inferKind(String filePath) {
    final lower = p.basenameWithoutExtension(filePath).toLowerCase();
    if (lower.contains('wd14') ||
        lower.contains('wd-v1-4') ||
        lower.contains('wd-v1-5') ||
        lower.contains('convnext') ||
        lower.contains('vit') ||
        lower.contains('swinv2')) {
      return LocalOnnxModelKind.wd14Tagger;
    }
    if (lower.contains('cl') && lower.contains('tagger')) {
      return LocalOnnxModelKind.clTagger;
    }
    return LocalOnnxModelKind.unknown;
  }

  Future<String?> _findLabelsFile(String onnxPath) async {
    final base = p.withoutExtension(onnxPath);
    final lowerBaseName = p.basenameWithoutExtension(onnxPath).toLowerCase();
    final directory = p.dirname(onnxPath);

    if (lowerBaseName.contains('cl_tagger')) {
      final mapping = p.join(directory, 'tag_mapping.json');
      if (await File(mapping).exists()) {
        return mapping;
      }
    }

    for (final extension in const ['.csv', '.txt', '.json']) {
      final candidate = '$base$extension';
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    for (final name in const [
      'selected_tags.csv',
      'tags.csv',
      'labels.csv',
      'labels.txt',
      'classes.txt',
      'tag_mapping.json',
    ]) {
      final candidate = p.join(directory, name);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }
}
