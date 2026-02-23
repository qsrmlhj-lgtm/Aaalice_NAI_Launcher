import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/nai_metadata_parser.dart';
import '../models/gallery/nai_image_metadata.dart';

/// 图像元数据服务
///
/// 统一的元数据解析服务入口，使用文件内容哈希作为缓存键，支持重命名免疫。
class ImageMetadataService {
  static final ImageMetadataService _instance = ImageMetadataService._internal();
  factory ImageMetadataService() => _instance;
  ImageMetadataService._internal();

  static const int _memoryCacheCapacity = 500;
  static const int _streamBufferSize = 50 * 1024;
  static const int _preloadConcurrency = 3;
  static const int _maxQueueSize = 100;
  static const int _currentCacheVersion = 2;

  Box<String>? _persistentBox;
  final _memoryCache = _LRUCache<String, NaiImageMetadata>(capacity: _memoryCacheCapacity);
  final _pathToHashMap = <String, String>{};
  final _hashToPathsMap = <String, Set<String>>{};
  final _pendingFutures = <String, Future<NaiImageMetadata?>>{};
  final _pendingHashFutures = <String, Future<String>>{};
  final _fileSemaphore = _Semaphore(3);
  final _highPrioritySemaphore = _Semaphore(2);
  final _preloadQueue = <_PreloadTask>[];
  final _processingTaskIds = <String>{};
  bool _isProcessingQueue = false;

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _persistentCacheHits = 0;
  int _persistentCacheMisses = 0;
  int _fastParseCount = 0;
  int _fallbackParseCount = 0;
  int _parseErrors = 0;
  int _preloadSuccessCount = 0;
  int _preloadErrorCount = 0;
  int _hashComputeCount = 0;
  int _hashCacheHitCount = 0;

  Future<void> initialize() async {
    if (_persistentBox != null && _persistentBox!.isOpen) return;

    try {
      _persistentBox = Hive.isBoxOpen(StorageKeys.localMetadataCacheBox)
          ? Hive.box<String>(StorageKeys.localMetadataCacheBox)
          : await Hive.openBox<String>(StorageKeys.localMetadataCacheBox);

      await _migrateCacheIfNeeded();

      AppLogger.i(
        'ImageMetadataService initialized: persistent cache has ${_persistentBox!.length} entries',
        'ImageMetadataService',
      );
    } catch (e, stack) {
      AppLogger.e('Failed to initialize ImageMetadataService', e, stack, 'ImageMetadataService');
      rethrow;
    }
  }

  Future<void> _migrateCacheIfNeeded() async {
    try {
      final box = _persistentBox!;
      final storedVersion = int.tryParse(box.get('_cacheVersion') ?? '1') ?? 1;

      if (storedVersion < _currentCacheVersion) {
        AppLogger.i(
          'Cache migration needed: v$storedVersion -> v$_currentCacheVersion',
          'ImageMetadataService',
        );
        await clearCache();
        await box.put('_cacheVersion', _currentCacheVersion.toString());
        AppLogger.i('Cache migrated to version $_currentCacheVersion', 'ImageMetadataService');
      }
    } catch (e) {
      AppLogger.w('Cache version check failed, clearing cache', 'ImageMetadataService');
      await clearCache();
    }
  }

  Box<String> _getBox() {
    if (_persistentBox == null || !_persistentBox!.isOpen) {
      throw StateError('ImageMetadataService not initialized. Call initialize() first.');
    }
    return _persistentBox!;
  }

  /// 前台立即获取元数据（高优先级）
  Future<NaiImageMetadata?> getMetadataImmediate(String path) async {
    final hash = await _getFileHash(path);

    final memoryCached = _memoryCache.get(hash);
    if (memoryCached != null) {
      _cacheHits++;
      return memoryCached;
    }

    final persistentCached = _getFromPersistentCache(hash);
    if (persistentCached != null) {
      _cacheHits++;
      _memoryCache.put(hash, persistentCached);
      return persistentCached;
    }

    _cacheMisses++;

    if (_pendingFutures.containsKey(hash)) {
      return _pendingFutures[hash]!;
    }

    _removeFromPreloadQueue(hash);
    await _highPrioritySemaphore.acquire();

    final doubleCheck = _memoryCache.get(hash);
    if (doubleCheck != null) {
      _highPrioritySemaphore.release();
      return doubleCheck;
    }

    final future = _parseAndCache(path, hash: hash, forceFullParse: false);
    _pendingFutures[hash] = future;

    try {
      return await future;
    } finally {
      _pendingFutures.remove(hash);
      _highPrioritySemaphore.release();
    }
  }

  /// 从文件路径获取元数据（标准入口）
  Future<NaiImageMetadata?> getMetadata(
    String path, {
    bool forceFullParse = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final hash = await _getFileHash(path);

    final memoryCached = _memoryCache.get(hash);
    if (memoryCached != null) {
      _cacheHits++;
      return memoryCached;
    }

    final persistentCached = _getFromPersistentCache(hash);
    if (persistentCached != null) {
      _cacheHits++;
      _memoryCache.put(hash, persistentCached);
      return persistentCached;
    }

    _cacheMisses++;

    if (_pendingFutures.containsKey(hash)) {
      return _pendingFutures[hash]!;
    }

    await _fileSemaphore.acquire();

    final doubleCheck = _memoryCache.get(hash);
    if (doubleCheck != null) {
      _fileSemaphore.release();
      return doubleCheck;
    }

    final future = _parseAndCache(path, hash: hash, forceFullParse: forceFullParse);
    _pendingFutures[hash] = future;

    try {
      final result = await future;
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds > 50) {
        AppLogger.w('[PERF] Slow getMetadata: ${stopwatch.elapsedMilliseconds}ms for $path', 'ImageMetadataService');
      }
      return result;
    } finally {
      _pendingFutures.remove(hash);
      _fileSemaphore.release();
    }
  }

  /// 从字节数组获取元数据
  Future<NaiImageMetadata?> getMetadataFromBytes(
    Uint8List bytes, {
    String? cacheKey,
  }) async {
    final hash = sha256.convert(bytes).toString();

    final memoryCached = _memoryCache.get(hash);
    if (memoryCached != null) {
      _cacheHits++;
      return memoryCached;
    }

    final persistentCached = _getFromPersistentCache(hash);
    if (persistentCached != null) {
      _cacheHits++;
      _memoryCache.put(hash, persistentCached);
      return persistentCached;
    }

    _cacheMisses++;

    if (_pendingFutures.containsKey(hash)) {
      return _pendingFutures[hash]!;
    }

    final future = _parseBytesAndCache(bytes, hash: hash);
    _pendingFutures[hash] = future;

    try {
      return await future;
    } finally {
      _pendingFutures.remove(hash);
    }
  }

  /// 将图像加入预加载队列
  void enqueuePreload({
    required String taskId,
    String? filePath,
    Uint8List? bytes,
  }) {
    if (_preloadQueue.any((t) => t.taskId == taskId) || _processingTaskIds.contains(taskId)) {
      return;
    }

    if (_preloadQueue.length >= _maxQueueSize) {
      _preloadQueue.removeAt(0);
      AppLogger.w('Preload queue full, dropped oldest task', 'ImageMetadataService');
    }

    _preloadQueue.add(_PreloadTask(taskId: taskId, filePath: filePath, bytes: bytes));
    _processPreloadQueue();
  }

  void enqueuePreloadBatch(List<GeneratedImageInfo> images) {
    for (final image in images) {
      enqueuePreload(taskId: image.id, filePath: image.filePath, bytes: image.bytes);
    }
  }

  /// 手动缓存元数据
  Future<void> cacheMetadata(String path, NaiImageMetadata metadata) async {
    if (!metadata.hasData) return;

    final hash = await _getFileHash(path);
    _memoryCache.put(hash, metadata);
    await _saveToPersistentCache(hash, metadata);
  }

  /// 获取缓存统计
  Map<String, dynamic> getStats() => {
    'memoryCacheSize': _memoryCache.length,
    'persistentCacheSize': _persistentBox?.length ?? 0,
    'cacheHits': _cacheHits,
    'cacheMisses': _cacheMisses,
    'hitRate': _cacheHits + _cacheMisses > 0
        ? '${(_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1)}%'
        : 'N/A',
    'fastParseCount': _fastParseCount,
    'fallbackParseCount': _fallbackParseCount,
    'parseErrors': _parseErrors,
    'hashComputeCount': _hashComputeCount,
    'hashCacheHitCount': _hashCacheHitCount,
    'pathToHashMapSize': _pathToHashMap.length,
    'preloadQueue': {
      'queueLength': _preloadQueue.length,
      'processingCount': _processingTaskIds.length,
      'successCount': _preloadSuccessCount,
      'errorCount': _preloadErrorCount,
    },
  };

  // ============================================
  // 缓存统计公共 API
  // ============================================

  /// L1 内存缓存大小
  int get memoryCacheSize => _memoryCache.length;

  /// L1 内存缓存命中率 (0.0 - 1.0)
  double get memoryCacheHitRate {
    final total = _cacheHits + _cacheMisses;
    return total > 0 ? _cacheHits / total : 0.0;
  }

  /// L2 Hive 缓存大小
  Future<int> get persistentCacheSize async {
    final box = _persistentBox;
    if (box == null || !box.isOpen) return 0;
    // 减去内部版本键
    return box.length - (box.containsKey('_cacheVersion') ? 1 : 0);
  }

  /// L2 Hive 缓存命中率 (0.0 - 1.0)
  double get persistentCacheHitRate {
    final total = _persistentCacheHits + _persistentCacheMisses;
    return total > 0 ? _persistentCacheHits / total : 0.0;
  }

  /// Hive 缓存 Box（用于 L2CacheCleaner 访问）
  Box<String>? get persistentBox => _persistentBox;

  /// 获取哈希对应的所有路径
  List<String> getPathsForHash(String hash) {
    final paths = _hashToPathsMap[hash];
    return paths?.toList() ?? [];
  }

  /// 重置所有统计计数器
  void resetStatistics() {
    _cacheHits = 0;
    _cacheMisses = 0;
    _persistentCacheHits = 0;
    _persistentCacheMisses = 0;
    AppLogger.i('ImageMetadataService statistics reset', 'ImageMetadataService');
  }

  /// 清除持久化缓存（仅 Hive，不清除内存缓存）
  Future<void> clearPersistentCache() async {
    try {
      final box = _persistentBox;
      if (box != null && box.isOpen) {
        // 保留版本键
        final version = box.get('_cacheVersion');
        await box.clear();
        if (version != null) {
          await box.put('_cacheVersion', version);
        }
        AppLogger.i('Persistent cache cleared', 'ImageMetadataService');
      }
    } catch (e, stack) {
      AppLogger.e('Failed to clear persistent cache', e, stack, 'ImageMetadataService');
    }
  }

  /// 通知路径变更（文件重命名检测）
  void notifyPathChanged(String oldPath, String newPath) {
    final hash = _pathToHashMap[oldPath];
    if (hash == null) return;

    _pathToHashMap.remove(oldPath);
    _pathToHashMap[newPath] = hash;

    final pathSet = _hashToPathsMap[hash];
    if (pathSet != null) {
      pathSet.remove(oldPath);
      pathSet.add(newPath);
    }

    AppLogger.d('Path changed: $oldPath -> $newPath (hash: ${hash.substring(0, 8)}...)', 'ImageMetadataService');
  }

  /// 获取文件哈希（带缓存）
  Future<String> _getFileHash(String path) async {
    final cachedHash = _pathToHashMap[path];
    if (cachedHash != null) {
      _hashCacheHitCount++;
      return cachedHash;
    }

    if (_pendingHashFutures.containsKey(path)) {
      return _pendingHashFutures[path]!;
    }

    final future = _computeFileHash(path);
    _pendingHashFutures[path] = future;

    try {
      final hash = await future;
      _pathToHashMap[path] = hash;
      _hashToPathsMap.putIfAbsent(hash, () => {}).add(path);
      _hashComputeCount++;
      return hash;
    } finally {
      _pendingHashFutures.remove(path);
    }
  }

  /// 计算文件采样哈希（SHA256）
  Future<String> _computeFileHash(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return '';

      final stat = await file.stat();
      final fileSize = stat.size;

      if (fileSize <= 16384) {
        final bytes = await file.readAsBytes();
        return sha256.convert(bytes).toString();
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        final headBytes = await raf.read(8192);
        await raf.setPosition(fileSize - 8192);
        final tailBytes = await raf.read(8192);

        final combined = Uint8List(headBytes.length + tailBytes.length + 8);
        combined.setAll(0, headBytes);
        combined.setAll(headBytes.length, tailBytes);

        final sizeBytes = ByteData(8);
        sizeBytes.setInt64(0, fileSize);
        combined.setAll(headBytes.length + tailBytes.length, sizeBytes.buffer.asUint8List());

        return sha256.convert(combined).toString();
      } finally {
        await raf.close();
      }
    } catch (e) {
      AppLogger.w('Failed to compute file hash: $path', 'ImageMetadataService');
      return '';
    }
  }

  /// 从缓存获取元数据（同步检查内存，异步检查持久化缓存）
  ///
  /// 【修复】如果内存缓存未命中，尝试从持久化缓存加载
  NaiImageMetadata? getCached(String path) {
    final cachedHash = _pathToHashMap[path];
    if (cachedHash != null) {
      final memoryResult = _memoryCache.get(cachedHash);
      if (memoryResult != null) return memoryResult;

      // 【修复】内存未命中，尝试持久化缓存
      final persistentResult = _getFromPersistentCache(cachedHash);
      if (persistentResult != null) {
        // 回填内存缓存
        _memoryCache.put(cachedHash, persistentResult);
        return persistentResult;
      }
    }
    return null;
  }

  void preload(String path) => enqueuePreload(taskId: path, filePath: path);

  void preloadBatch(List<GeneratedImageInfo> images) => enqueuePreloadBatch(images);

  Map<String, dynamic> getPreloadQueueStatus() => {
    'queueLength': _preloadQueue.length,
    'processingCount': _processingTaskIds.length,
    'isProcessing': _isProcessingQueue,
    'successCount': _preloadSuccessCount,
    'errorCount': _preloadErrorCount,
  };

  void _removeFromPreloadQueue(String taskId) {
    final initialLength = _preloadQueue.length;
    _preloadQueue.removeWhere((task) => task.taskId == taskId);
    if (_preloadQueue.length < initialLength) {
      AppLogger.d('Removed from preload queue: $taskId', 'ImageMetadataService');
    }
  }

  Future<void> clearCache() async {
    _memoryCache.clear();
    _pathToHashMap.clear();
    _hashToPathsMap.clear();
    await _persistentBox?.clear();
    AppLogger.i('All caches cleared', 'ImageMetadataService');
  }

  Future<NaiImageMetadata?> _parseAndCache(
    String path, {
    required String hash,
    required bool forceFullParse,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    try {
      final file = File(path);
      if (!await file.exists()) {
        AppLogger.w('[Metadata] File not found: $path', 'ImageMetadataService');
        return null;
      }
      if (!path.toLowerCase().endsWith('.png')) {
        AppLogger.w('[Metadata] Not a PNG file: $path', 'ImageMetadataService');
        return null;
      }

      NaiImageMetadata? metadata;

      if (!forceFullParse) {
        final fastStopwatch = Stopwatch()..start();
        metadata = await _extractMetadataFast(file);
        fastStopwatch.stop();
        if (metadata != null) {
          _fastParseCount++;
          if (fastStopwatch.elapsedMilliseconds > 10) {
            AppLogger.w('[PERF] Slow _extractMetadataFast: ${fastStopwatch.elapsedMilliseconds}ms for $path', 'ImageMetadataService');
          }
        }
      }

      if (metadata == null) {
        final fallbackStopwatch = Stopwatch()..start();
        metadata = await NaiMetadataParser.extractFromFile(file);
        fallbackStopwatch.stop();
        if (metadata != null) {
          _fallbackParseCount++;
          if (fallbackStopwatch.elapsedMilliseconds > 50) {
            AppLogger.w('[PERF] Slow NaiMetadataParser.extractFromFile: ${fallbackStopwatch.elapsedMilliseconds}ms for $path', 'ImageMetadataService');
          }
        }
      }

      if (metadata != null && metadata.hasData) {
        _memoryCache.put(hash, metadata);
        await _saveToPersistentCache(hash, metadata);
        AppLogger.d('[Metadata] Parsed and cached: $path (prompt length: ${metadata.prompt.length})', 'ImageMetadataService');
      } else if (metadata != null) {
        AppLogger.w('[Metadata] Parsed but hasData=false: $path (prompt: "${metadata.prompt}", seed: ${metadata.seed})', 'ImageMetadataService');
      } else {
        AppLogger.w('[Metadata] No metadata found: $path', 'ImageMetadataService');
      }

      totalStopwatch.stop();
      if (totalStopwatch.elapsedMilliseconds > 100) {
        AppLogger.w('[PERF] Slow _parseAndCache: ${totalStopwatch.elapsedMilliseconds}ms for $path', 'ImageMetadataService');
      }

      return metadata;
    } catch (e, stack) {
      _parseErrors++;
      AppLogger.e('[Metadata] Parse failed: $path', e, stack, 'ImageMetadataService');
      return null;
    }
  }

  Future<NaiImageMetadata?> _parseBytesAndCache(
    Uint8List bytes, {
    required String hash,
  }) async {
    try {
      if (bytes.length < 8) return null;

      NaiImageMetadata? metadata;

      if (bytes.length <= _streamBufferSize) {
        metadata = _extractFromChunks(bytes);
      } else {
        metadata = _extractFromChunks(bytes.sublist(0, _streamBufferSize));
      }

      metadata ??= await NaiMetadataParser.extractFromBytes(bytes);

      if (metadata != null && metadata.hasData) {
        _memoryCache.put(hash, metadata);
        await _saveToPersistentCache(hash, metadata);
      }

      return metadata;
    } catch (e, stack) {
      _parseErrors++;
      AppLogger.e('Parse bytes failed', e, stack, 'ImageMetadataService');
      return null;
    }
  }

  Future<NaiImageMetadata?> _extractMetadataFast(File file) async {
    final raf = await file.open();
    try {
      final buffer = await raf.read(_streamBufferSize);
      if (buffer.length < 8) return null;

      const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (var i = 0; i < 8; i++) {
        if (buffer[i] != pngSignature[i]) return null;
      }

      return _extractFromChunks(buffer);
    } finally {
      await raf.close();
    }
  }

  NaiImageMetadata? _extractFromChunks(Uint8List bytes) {
    final chunks = _extractChunks(bytes);
    for (final chunk in chunks) {
      if (chunk.name == 'tEXt' || chunk.name == 'zTXt' || chunk.name == 'iTXt') {
        final text = _parseTextChunk(chunk.data, chunk.name);
        if (text != null) {
          final json = _tryParseNaiJson(text);
          if (json != null) {
            return NaiImageMetadata.fromNaiComment(json, rawJson: text);
          }
        }
      }
    }
    return null;
  }

  List<_PngChunk> _extractChunks(Uint8List bytes) {
    final chunks = <_PngChunk>[];
    var offset = 8;
    var chunkCount = 0;
    const maxChunks = 30; // 【修复】增加最大检查chunk数量

    while (offset + 12 <= bytes.length && chunkCount < maxChunks) {
      final length = _readUint32(bytes, offset);
      offset += 4;
      if (offset + 4 > bytes.length) break;
      final name = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;
      if (offset + length > bytes.length) break;
      final data = bytes.sublist(offset, offset + length);
      offset += length + 4;
      chunks.add(_PngChunk(name: name, data: data));
      chunkCount++;
      // 【修复】移除 IDAT 终止条件，继续检查更多chunks
      // NAI元数据可能在IDAT之后（虽然通常在前）
      if (name == 'IEND') break; // 只在IEND处停止
    }

    return chunks;
  }

  String? _parseTextChunk(Uint8List data, String chunkType) {
    try {
      return switch (chunkType) {
        'tEXt' => _parseTEXt(data),
        'zTXt' => _parseZTXt(data),
        'iTXt' => _parseITXt(data),
        _ => null,
      };
    } catch (e) {
      return null;
    }
  }

  String? _parseTEXt(Uint8List data) {
    final nullIndex = data.indexOf(0);
    if (nullIndex < 0) return null;
    return latin1.decode(data.sublist(nullIndex + 1));
  }

  String? _parseZTXt(Uint8List data) {
    final firstNull = data.indexOf(0);
    if (firstNull < 0 || firstNull + 1 >= data.length) return null;
    if (data[firstNull + 1] != 0) return null;
    return _inflateZlib(data.sublist(firstNull + 2));
  }

  String? _parseITXt(Uint8List data) {
    var offset = 0;
    final keywordEnd = data.indexOf(0, offset);
    if (keywordEnd < 0) return null;
    offset = keywordEnd + 1;
    if (offset + 1 >= data.length) return null;
    final compressed = data[offset++];
    final method = data[offset++];
    final langEnd = data.indexOf(0, offset);
    if (langEnd < 0) return null;
    offset = langEnd + 1;
    final transEnd = data.indexOf(0, offset);
    if (transEnd < 0) return null;
    offset = transEnd + 1;
    if (offset >= data.length) return null;
    final textData = data.sublist(offset);
    if (compressed == 1) {
      if (method != 0) return null;
      return _inflateZlib(textData);
    }
    return utf8.decode(textData);
  }

  String? _inflateZlib(Uint8List data) {
    try {
      final inflated = ZLibCodec().decode(data);
      return utf8.decode(inflated);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _tryParseNaiJson(String text) {
    try {
      final lowerText = text.toLowerCase();
      if (!lowerText.contains('prompt') &&
          !lowerText.contains('sampler') &&
          !lowerText.contains('steps')) {
        return null;
      }
      final json = jsonDecode(text) as Map<String, dynamic>;

      // 格式1: 直接格式 - prompt在顶层
      if (json.containsKey('prompt') || json.containsKey('comment')) {
        return json;
      }

      // 格式2: PNG标准格式 - Description/Software/Source/Comment
      // Comment字段包含实际元数据（JSON字符串）
      if (json.containsKey('Comment')) {
        final comment = json['Comment'];
        if (comment is String) {
          try {
            final commentJson = jsonDecode(comment) as Map<String, dynamic>;
            if (commentJson.containsKey('prompt') || commentJson.containsKey('uc')) {
              return commentJson;
            }
          } catch (_) {
            // Comment不是有效的JSON，忽略
          }
        } else if (comment is Map<String, dynamic>) {
          if (comment.containsKey('prompt') || comment.containsKey('uc')) {
            return comment;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  int _readUint32(Uint8List bytes, int offset) {
    // 【修复】使用 & 0xFF 确保字节被当作无符号数处理
    // 修复了当字节值 > 127 时左移产生负数的问题
    return ((bytes[offset] & 0xFF) << 24) |
        ((bytes[offset + 1] & 0xFF) << 16) |
        ((bytes[offset + 2] & 0xFF) << 8) |
        (bytes[offset + 3] & 0xFF);
  }

  NaiImageMetadata? _getFromPersistentCache(String key) {
    try {
      final box = _getBox();
      final jsonString = box.get(key);
      if (jsonString == null) {
        _persistentCacheMisses++;
        return null;
      }
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      _persistentCacheHits++;
      return NaiImageMetadata.fromJson(json);
    } catch (e) {
      _persistentCacheMisses++;
      return null;
    }
  }

  Future<void> _saveToPersistentCache(String key, NaiImageMetadata metadata) async {
    try {
      final box = _getBox();
      if (box.length >= 1000) {
        final keysToDelete = box.keys.take(100).toList();
        for (final k in keysToDelete) {
          await box.delete(k);
        }
      }
      await box.put(key, jsonEncode(metadata.toJson()));
    } catch (e) {
      AppLogger.w('Failed to save to persistent cache: $key', 'ImageMetadataService');
    }
  }

  Future<void> _processPreloadQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_preloadQueue.isNotEmpty) {
      final batchSize = _preloadQueue.length < _preloadConcurrency
          ? _preloadQueue.length
          : _preloadConcurrency;
      final batch = _preloadQueue.sublist(0, batchSize);
      _preloadQueue.removeRange(0, batchSize);

      for (final task in batch) {
        _processingTaskIds.add(task.taskId);
      }

      await Future.wait(batch.map((task) => _processPreloadTask(task)));

      for (final task in batch) {
        _processingTaskIds.remove(task.taskId);
      }
    }

    _isProcessingQueue = false;
  }

  Future<void> _processPreloadTask(_PreloadTask task) async {
    try {
      NaiImageMetadata? metadata;
      if (task.filePath != null) {
        final hash = await _getFileHash(task.filePath!);

        if (_pendingFutures.containsKey(hash)) {
          await _pendingFutures[hash]!;
          return;
        }

        if (_memoryCache.get(hash) != null) return;

        metadata = await getMetadata(task.filePath!);
      } else if (task.bytes != null) {
        final hash = sha256.convert(task.bytes!).toString();

        if (_pendingFutures.containsKey(hash)) {
          await _pendingFutures[hash]!;
          return;
        }

        if (_memoryCache.get(hash) != null) return;

        metadata = await getMetadataFromBytes(task.bytes!);
      }

      if (metadata != null && metadata.hasData) {
        _preloadSuccessCount++;
      } else {
        _preloadErrorCount++;
      }
    } catch (e) {
      _preloadErrorCount++;
    }
  }
}

class _PngChunk {
  final String name;
  final Uint8List data;

  _PngChunk({required this.name, required this.data});
}

class GeneratedImageInfo {
  final String id;
  final String? filePath;
  final Uint8List? bytes;

  GeneratedImageInfo({required this.id, this.filePath, this.bytes});
}

class _PreloadTask {
  final String taskId;
  final String? filePath;
  final Uint8List? bytes;

  _PreloadTask({required this.taskId, this.filePath, this.bytes});
}

class _LRUCache<K, V> {
  final int capacity;
  final _map = <K, V>{};

  _LRUCache({required this.capacity});

  int get length => _map.length;

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value;
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    while (_map.length >= capacity) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  bool containsKey(K key) => _map.containsKey(key);

  void clear() => _map.clear();
}

class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _currentCount--;
    }
  }
}
