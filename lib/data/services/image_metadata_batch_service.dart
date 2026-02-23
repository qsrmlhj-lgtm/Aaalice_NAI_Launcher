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
        final metadata = _extractMetadataFromChunksSync(bytes, filePathForLog: filePath);
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
  /// 【增强】添加详细日志用于诊断
  static NaiImageMetadata? _extractMetadataFromChunksSync(Uint8List bytes, {String? filePathForLog}) {
    try {
      final chunks = png_extract.extractChunks(bytes);
      final fileName = filePathForLog?.split(Platform.pathSeparator).last ?? 'unknown';

      AppLogger.d('[MetadataBatchService] [$fileName] Total chunks: ${chunks.length}', 'ImageMetadataBatchService');

      // 只检查前 10 个 chunks（NAI 元数据通常很靠前）
      final maxChunks = chunks.length > 10 ? 10 : chunks.length;

      for (var i = 0; i < maxChunks; i++) {
        final chunk = chunks[i];
        final name = chunk['name'] as String?;

        // 【修复】支持 tEXt, zTXt, iTXt 三种chunk类型
        if (name == null || !{'tEXt', 'zTXt', 'iTXt'}.contains(name)) continue;

        AppLogger.d('[MetadataBatchService] [$fileName] Found text chunk #$i: $name', 'ImageMetadataBatchService');

        final data = chunk['data'] as Uint8List?;
        if (data == null) continue;

        // 【修复】根据chunk类型选择正确的解析方法
        final String? textData;
        switch (name) {
          case 'tEXt':
            textData = _parseTextChunkSync(data);
          case 'zTXt':
            textData = _parseZTXtChunkSync(data);
          case 'iTXt':
            textData = _parseITXtChunkSync(data);
          default:
            textData = null;
        }

        if (textData == null) {
          AppLogger.d('[MetadataBatchService] [$fileName] Chunk #$i: Failed to parse text data', 'ImageMetadataBatchService');
          continue;
        }

        AppLogger.d('[MetadataBatchService] [$fileName] Chunk #$i: Text length=${textData.length}', 'ImageMetadataBatchService');

        // 快速检查：是否包含 NAI 特征
        final hasPrompt = textData.contains('prompt');
        final hasSampler = textData.contains('sampler');
        AppLogger.d('[MetadataBatchService] [$fileName] Chunk #$i: hasPrompt=$hasPrompt, hasSampler=$hasSampler', 'ImageMetadataBatchService');

        if (!hasPrompt && !hasSampler) continue;

        // 尝试解析 JSON
        final json = _tryParseNaiJsonSync(textData);
        if (json != null) {
          AppLogger.i('[MetadataBatchService] [$fileName] Successfully parsed NAI metadata from chunk #$i', 'ImageMetadataBatchService');
          return NaiImageMetadata.fromNaiComment(json, rawJson: textData);
        } else {
          AppLogger.w('[MetadataBatchService] [$fileName] Chunk #$i: Has prompt/sampler but JSON parsing failed', 'ImageMetadataBatchService');
        }
      }

      AppLogger.d('[MetadataBatchService] [$fileName] No NAI metadata found in first $maxChunks chunks', 'ImageMetadataBatchService');
      return null;
    } catch (e, stack) {
      AppLogger.e('[MetadataBatchService] Error extracting metadata', e, stack, 'ImageMetadataBatchService');
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

  /// 同步解析 zTXt chunk (压缩文本)
  /// Format: keyword\0compressionMethod\0compressedText
  static String? _parseZTXtChunkSync(Uint8List data) {
    try {
      // 找到第一个null分隔符 (keyword结束)
      final firstNull = data.indexOf(0);
      if (firstNull < 0 || firstNull + 1 >= data.length) return null;

      // 只关心 Comment 或 parameters 类型的 chunk
      final keyword = latin1.decode(data.sublist(0, firstNull));
      if (!{'Comment', 'parameters'}.contains(keyword)) return null;

      // 检查压缩方法 (必须为0表示deflate)
      if (data[firstNull + 1] != 0) return null;

      // 解压数据
      final compressedData = data.sublist(firstNull + 2);
      final inflated = ZLibCodec().decode(compressedData);
      return utf8.decode(inflated);
    } catch (e) {
      return null;
    }
  }

  /// 同步解析 iTXt chunk (国际化文本)
  /// Format: keyword\0compressedFlag\0compressionMethod\0language\0translatedKeyword\0text
  static String? _parseITXtChunkSync(Uint8List data) {
    try {
      var offset = 0;

      // 跳过 keyword
      final keywordEnd = data.indexOf(0, offset);
      if (keywordEnd < 0) return null;
      final keyword = utf8.decode(data.sublist(0, keywordEnd));
      if (!{'Comment', 'parameters'}.contains(keyword)) return null;
      offset = keywordEnd + 1;

      if (offset + 1 >= data.length) return null;
      final compressed = data[offset++];
      final method = data[offset++];

      // 跳过 language tag
      final langEnd = data.indexOf(0, offset);
      if (langEnd < 0) return null;
      offset = langEnd + 1;

      // 跳过 translated keyword
      final transEnd = data.indexOf(0, offset);
      if (transEnd < 0) return null;
      offset = transEnd + 1;

      if (offset >= data.length) return null;
      final textData = data.sublist(offset);

      if (compressed == 1) {
        // 压缩数据
        if (method != 0) return null;
        final inflated = ZLibCodec().decode(textData);
        return utf8.decode(inflated);
      } else {
        // 未压缩数据
        return utf8.decode(textData);
      }
    } catch (e) {
      return null;
    }
  }

  /// 尝试解析 NAI JSON
  /// 【修复】支持两种格式：
  /// 1. 官方格式：{"prompt": "...", "uc": "..."} - prompt在顶层
  /// 2. 应用格式：{"Comment": {"prompt": "...", "uc": "..."}} - prompt在Comment嵌套内
  static Map<String, dynamic>? _tryParseNaiJsonSync(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;

      // 格式1: 官方格式 - prompt/comment在顶层
      if (json.containsKey('prompt') || json.containsKey('comment')) {
        AppLogger.d('[MetadataBatchService] Found NAI JSON (official format)', 'ImageMetadataBatchService');
        return json;
      }

      // 格式2: 应用生成的嵌套格式 - Comment字段包含实际元数据
      if (json.containsKey('Comment')) {
        final comment = json['Comment'];
        if (comment is Map<String, dynamic>) {
          if (comment.containsKey('prompt') || comment.containsKey('uc')) {
            AppLogger.d('[MetadataBatchService] Found NAI JSON (nested Comment format)', 'ImageMetadataBatchService');
            // 返回嵌套的 Comment 对象作为元数据
            return comment;
          }
        }
        // Comment 可能是字符串，需要再次解析
        if (comment is String) {
          try {
            final nestedJson = jsonDecode(comment) as Map<String, dynamic>;
            if (nestedJson.containsKey('prompt') || nestedJson.containsKey('uc')) {
              AppLogger.d('[MetadataBatchService] Found NAI JSON (nested string format)', 'ImageMetadataBatchService');
              return nestedJson;
            }
          } catch (_) {
            // 不是有效的 JSON，忽略
          }
        }
      }

      AppLogger.d('[MetadataBatchService] JSON does not contain NAI metadata fields', 'ImageMetadataBatchService');
      return null;
    } catch (e) {
      AppLogger.d('[MetadataBatchService] JSON parse error: $e', 'ImageMetadataBatchService');
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
