import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../core/utils/app_logger.dart';
import 'metadata/unified_metadata_parser.dart';
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
  ReceivePort? _receivePort;
  int _requestId = 0;
  final _completers = <int, Completer<_BatchParseResult>>{};

  bool get isInitialized => _isolate != null;

  /// 初始化 isolate（只需调用一次）
  Future<void> initialize() async {
    if (_isolate != null) return;

    AppLogger.i('[MetadataBatchService] Initializing isolate...', 'ImageMetadataBatchService');

    // 创建新的 ReceivePort（避免重复使用已监听的 Stream）
    _receivePort = ReceivePort();

    // 创建 isolate
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
      debugName: 'MetadataBatchIsolate',
    );

    // 等待 isolate 发送它的 SendPort，然后持续监听响应
    // 使用 broadcast stream 允许多次监听
    final broadcastStream = _receivePort!.asBroadcastStream();
    _sendPort = await broadcastStream.first as SendPort;

    // 继续监听后续响应
    broadcastStream.listen(_handleResponse);

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
    _receivePort?.close();
    _receivePort = null;

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

        // 使用统一的元数据解析器（内部处理渐进式读取）
        final result = UnifiedMetadataParser.parseFromFile(
          filePath,
          maxBytes: request.maxBytesPerFile,
          useGradualRead: false,
        );
        results.add((filePath, result.metadata, result.errorMessage));
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
