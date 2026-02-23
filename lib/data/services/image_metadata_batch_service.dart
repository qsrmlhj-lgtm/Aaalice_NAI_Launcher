import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:png_chunks_extract/png_chunks_extract.dart' as png_extract;

import '../../core/utils/app_logger.dart';
import '../../data/models/gallery/nai_image_metadata.dart';

/// 批量图像元数据解析服务
///
/// 设计目标：
/// 1. 不占用主线程 - 使用长时间运行的 isolate
/// 2. 快速处理 - 流式读取（只读前100KB）
/// 3. 批量处理 - 一次处理多个文件，减少通信开销
class ImageMetadataBatchService {
  static ImageMetadataBatchService? _instance;
  static ImageMetadataBatchService get instance => _instance ??= ImageMetadataBatchService();

  Isolate? _isolate;
  SendPort? _sendPort;
  final _receivePort = ReceivePort();
  int _requestId = 0;
  final _completers = <int, Completer<_BatchParseResult>>{};

  bool get isInitialized => _isolate != null;

  /// 初始化 isolate（只需调用一次）
  Future<void> initialize() async {
    if (_isolate != null) return;

    AppLogger.i('[MetadataBatchService] Initializing isolate...', 'ImageMetadataBatchService');

    // 创建 isolate
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort.sendPort,
      debugName: 'MetadataBatchIsolate',
    );

    // 等待 isolate 发送它的 SendPort
    _sendPort = await _receivePort.first as SendPort;

    // 监听响应
    _receivePort.listen(_handleResponse);

    AppLogger.i('[MetadataBatchService] Isolate initialized', 'ImageMetadataBatchService');
  }

  /// 批量解析文件
  ///
  /// [filePaths] - 要解析的文件路径列表
  /// [maxBytesPerFile] - 每个文件最多读取字节数（默认100KB）
  Future<List<(String filePath, NaiImageMetadata? metadata, String? error)>> parseBatch(
    List<String> filePaths, {
    int maxBytesPerFile = 100 * 1024,
  }) async {
    if (filePaths.isEmpty) return [];

    await initialize();

    final requestId = ++_requestId;
    final completer = Completer<_BatchParseResult>();
    _completers[requestId] = completer;

    // 发送请求到 isolate
    _sendPort!.send(_ParseRequest(
      requestId: requestId,
      filePaths: filePaths,
      maxBytesPerFile: maxBytesPerFile,
    ),);

    final result = await completer.future;
    return result.results;
  }

  void _handleResponse(dynamic message) {
    if (message is _BatchParseResult) {
      final completer = _completers.remove(message.requestId);
      completer?.complete(message);
    }
  }

  /// 关闭 isolate
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort.close();

    // 清理未完成的请求
    for (final completer in _completers.values) {
      completer.completeError(StateError('Isolate disposed'));
    }
    _completers.clear();
  }

  /// Isolate 入口点
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is _ParseRequest) {
        _handleParseRequest(message, mainSendPort);
      }
    });
  }

  /// 在 isolate 中处理解析请求
  static void _handleParseRequest(_ParseRequest request, SendPort sendPort) {
    final results = <(String, NaiImageMetadata?, String?)>[];
    final stopwatch = Stopwatch()..start();

    for (final filePath in request.filePaths) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          results.add((filePath, null, 'File not found'));
          continue;
        }

        // 流式读取：只读前 N 字节
        final bytes = _readFileHeadSync(file, request.maxBytesPerFile);

        // 快速检查：是否有 PNG 文件头
        if (bytes.length < 8 || !_isPngHeader(bytes)) {
          results.add((filePath, null, 'Not a valid PNG file'));
          continue;
        }

        // 解析 chunks（只解析已读取的部分）
        final metadata = _extractMetadataFromChunksSync(bytes);
        results.add((filePath, metadata, null));
      } catch (e, stack) {
        AppLogger.e('[MetadataBatchService] Error parsing $filePath', e, stack, 'ImageMetadataBatchService');
        results.add((filePath, null, e.toString()));
      }
    }

    stopwatch.stop();
    AppLogger.d(
      '[MetadataBatchService] Batch processed: ${request.filePaths.length} files in ${stopwatch.elapsedMilliseconds}ms',
      'ImageMetadataBatchService',
    );

    sendPort.send(_BatchParseResult(
      requestId: request.requestId,
      results: results,
    ),);
  }

  /// 同步读取文件头部
  static Uint8List _readFileHeadSync(File file, int maxBytes) {
    final raf = file.openSync();
    try {
      final length = raf.lengthSync();
      final toRead = length < maxBytes ? length : maxBytes;
      return raf.readSync(toRead);
    } finally {
      raf.closeSync();
    }
  }

  /// 检查是否为 PNG 文件头
  static bool _isPngHeader(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 && // 'P'
        bytes[2] == 0x4E && // 'N'
        bytes[3] == 0x47 && // 'G'
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
  }

  /// 从 chunks 同步提取元数据（优化版）
  static NaiImageMetadata? _extractMetadataFromChunksSync(Uint8List bytes) {
    try {
      final chunks = png_extract.extractChunks(bytes);

      // 只检查前 10 个 chunks（NAI 元数据通常很靠前）
      final maxChunks = chunks.length > 10 ? 10 : chunks.length;

      for (var i = 0; i < maxChunks; i++) {
        final chunk = chunks[i];
        final name = chunk['name'] as String?;
        if (name != 'tEXt') continue; // NAI 元数据通常在 tEXt 中

        final data = chunk['data'] as Uint8List?;
        if (data == null) continue;

        // 解析 tEXt chunk
        final textData = _parseTextChunkSync(data);
        if (textData == null) continue;

        // 快速检查：是否包含 NAI 特征
        if (!textData.contains('prompt') && !textData.contains('sampler')) continue;

        // 尝试解析 JSON
        final json = _tryParseNaiJsonSync(textData);
        if (json != null) {
          return NaiImageMetadata.fromNaiComment(json, rawJson: textData);
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 同步解析 tEXt chunk
  static String? _parseTextChunkSync(Uint8List data) {
    try {
      // tEXt format: keyword\0text (Latin-1)
      final nullIndex = data.indexOf(0);
      if (nullIndex < 0 || nullIndex + 1 >= data.length) return null;

      // 只关心 Comment 或 parameters 类型的 chunk
      final keyword = latin1.decode(data.sublist(0, nullIndex));
      if (!{'Comment', 'parameters'}.contains(keyword)) return null;

      return latin1.decode(data.sublist(nullIndex + 1));
    } catch (e) {
      return null;
    }
  }

  /// 尝试解析 NAI JSON
  static Map<String, dynamic>? _tryParseNaiJsonSync(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json.containsKey('prompt') || json.containsKey('comment')) {
        return json;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

/// 解析请求（发送到 isolate）
class _ParseRequest {
  final int requestId;
  final List<String> filePaths;
  final int maxBytesPerFile;

  _ParseRequest({
    required this.requestId,
    required this.filePaths,
    required this.maxBytesPerFile,
  });
}

/// 解析结果（从 isolate 接收）
class _BatchParseResult {
  final int requestId;
  final List<(String filePath, NaiImageMetadata? metadata, String? error)> results;

  _BatchParseResult({
    required this.requestId,
    required this.results,
  });
}
