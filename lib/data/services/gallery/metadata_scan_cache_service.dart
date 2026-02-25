import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../../core/utils/app_logger.dart';

/// 文件元数据扫描状态
enum FileMetadataStatus {
  /// 已确认有元数据
  hasMetadata,

  /// 已确认无元数据
  noMetadata,

  /// 需要重新检查（文件已修改）
  needsCheck,
}

/// 单个文件的元数据扫描缓存条目
class MetadataScanCacheEntry {
  /// 文件路径
  final String filePath;

  /// 文件修改时间（用于检测变化）
  final DateTime modifiedTime;

  /// 文件大小（用于检测变化）
  final int fileSize;

  /// 扫描状态
  final FileMetadataStatus status;

  /// 扫描时间
  final DateTime scannedAt;

  /// 文件内容哈希（可选，用于精确检测变化）
  final String? contentHash;

  const MetadataScanCacheEntry({
    required this.filePath,
    required this.modifiedTime,
    required this.fileSize,
    required this.status,
    required this.scannedAt,
    this.contentHash,
  });

  Map<String, dynamic> toJson() => {
        'path': filePath,
        'modified': modifiedTime.millisecondsSinceEpoch,
        'size': fileSize,
        'status': status.index,
        'scannedAt': scannedAt.millisecondsSinceEpoch,
        'hash': contentHash,
      };

  factory MetadataScanCacheEntry.fromJson(Map<String, dynamic> json) {
    return MetadataScanCacheEntry(
      filePath: json['path'] as String,
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(json['modified'] as int),
      fileSize: json['size'] as int,
      status: FileMetadataStatus.values[json['status'] as int],
      scannedAt: DateTime.fromMillisecondsSinceEpoch(json['scannedAt'] as int),
      contentHash: json['hash'] as String?,
    );
  }

  /// 检查此缓存条目是否仍然有效
  bool isValidFor(File file) {
    try {
      final stat = file.statSync();
      if (!stat.modified.isAtSameMomentAs(modifiedTime)) return false;
      if (stat.size != fileSize) return false;
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// 元数据扫描缓存服务
///
/// 用于缓存元数据扫描结果，避免每次都要重新检查所有图片：
/// - 记录已确认有元数据的文件
/// - 记录已确认无元数据的文件（避免重复解析）
/// - 通过文件修改时间检测变化，只检查新增或修改的文件
class MetadataScanCacheService {
  static const String _hiveBoxName = 'metadata_scan_cache';
  static const String _entriesKey = 'entries';
  static const String _lastFullScanKey = 'last_full_scan';

  // 缓存有效期（7天）
  static const Duration _cacheValidity = Duration(days: 7);

  static MetadataScanCacheService? _instance;
  static MetadataScanCacheService get instance => _instance ??= MetadataScanCacheService._();

  Box<String>? _box;
  Map<String, MetadataScanCacheEntry> _cache = {};
  bool _isLoaded = false;

  // 统计信息
  int _hitCount = 0;
  int _missCount = 0;

  MetadataScanCacheService._();

  /// 初始化服务
  Future<void> initialize() async {
    if (_isLoaded) return;

    try {
      _box = await Hive.openBox<String>(_hiveBoxName);
      await _loadCache();
      _isLoaded = true;
      AppLogger.i('MetadataScanCacheService initialized with ${_cache.length} entries', 'MetadataScanCache');
    } catch (e, stack) {
      AppLogger.e('Failed to initialize MetadataScanCacheService', e, stack, 'MetadataScanCache');
      _cache = {};
      _isLoaded = true;
    }
  }

  /// 关闭服务
  Future<void> dispose() async {
    await _box?.close();
    _box = null;
    _cache = {};
    _isLoaded = false;
  }

  /// 从存储加载缓存
  Future<void> _loadCache() async {
    try {
      final json = _box?.get(_entriesKey);
      if (json == null) return;

      final Map<String, dynamic> data = jsonDecode(json) as Map<String, dynamic>;
      final now = DateTime.now();

      for (final entry in data.entries) {
        try {
          final cacheEntry = MetadataScanCacheEntry.fromJson(entry.value as Map<String, dynamic>);

          // 跳过过期条目
          if (now.difference(cacheEntry.scannedAt) > _cacheValidity) continue;

          _cache[entry.key] = cacheEntry;
        } catch (e) {
          // 跳过无效条目
          continue;
        }
      }

      // 清理过期条目
      await _saveCache();
    } catch (e) {
      AppLogger.w('Failed to load metadata scan cache: $e', 'MetadataScanCache');
      _cache = {};
    }
  }

  /// 保存缓存到存储
  Future<void> _saveCache() async {
    try {
      final data = <String, dynamic>{
        for (final entry in _cache.entries) entry.key: entry.value.toJson(),
      };
      await _box?.put(_entriesKey, jsonEncode(data));
    } catch (e) {
      AppLogger.w('Failed to save metadata scan cache: $e', 'MetadataScanCache');
    }
  }

  /// 获取文件的缓存状态
  ///
  /// 返回 null 表示没有缓存或缓存已过期
  MetadataScanCacheEntry? getEntry(String filePath) {
    if (!_isLoaded) return null;

    final entry = _cache[filePath];
    if (entry == null) {
      _missCount++;
      return null;
    }

    final file = File(filePath);
    if (!entry.isValidFor(file)) {
      // 文件已修改，缓存无效
      _cache.remove(filePath);
      _missCount++;
      return null;
    }

    _hitCount++;
    return entry;
  }

  /// 检查文件是否需要扫描
  ///
  /// - 如果缓存显示已确认有/无元数据且文件未修改，返回 false
  /// - 否则返回 true 需要重新扫描
  bool needsScan(String filePath) {
    final entry = getEntry(filePath);
    return entry == null;
  }

  /// 记录文件扫描结果
  Future<void> recordScanResult({
    required String filePath,
    required bool hasMetadata,
    String? contentHash,
  }) async {
    if (!_isLoaded) return;

    try {
      final file = File(filePath);
      final stat = await file.stat();

      final entry = MetadataScanCacheEntry(
        filePath: filePath,
        modifiedTime: stat.modified,
        fileSize: stat.size,
        status: hasMetadata ? FileMetadataStatus.hasMetadata : FileMetadataStatus.noMetadata,
        scannedAt: DateTime.now(),
        contentHash: contentHash,
      );

      _cache[filePath] = entry;

      // 批量保存，每 100 条保存一次
      if (_cache.length % 100 == 0) {
        await _saveCache();
      }
    } catch (e) {
      AppLogger.w('Failed to record scan result for $filePath: $e', 'MetadataScanCache');
    }
  }

  /// 批量记录扫描结果
  Future<void> recordBatchScanResults(Map<String, bool> results) async {
    if (!_isLoaded) return;

    for (final entry in results.entries) {
      await recordScanResult(
        filePath: entry.key,
        hasMetadata: entry.value,
      );
    }

    // 批量保存
    await _saveCache();
  }

  /// 获取缓存统计
  Map<String, dynamic> getStatistics() {
    final total = _hitCount + _missCount;
    return {
      'cachedEntries': _cache.length,
      'cacheHits': _hitCount,
      'cacheMisses': _missCount,
      'hitRate': total > 0 ? _hitCount / total : 0.0,
    };
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
    await _box?.delete(_entriesKey);
    AppLogger.i('Metadata scan cache cleared', 'MetadataScanCache');
  }

  /// 获取最后全量扫描时间
  DateTime? getLastFullScanTime() {
    try {
      final timestamp = _box?.get(_lastFullScanKey);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    } catch (e) {
      return null;
    }
  }

  /// 设置最后全量扫描时间
  Future<void> setLastFullScanTime(DateTime time) async {
    await _box?.put(_lastFullScanKey, time.millisecondsSinceEpoch.toString());
  }

  /// 过滤出需要扫描的文件列表
  ///
  /// 输入完整文件列表，返回需要扫描的子集
  List<File> filterFilesNeedingScan(List<File> files) {
    if (!_isLoaded) return files;

    final result = <File>[];
    int skipped = 0;

    for (final file in files) {
      if (needsScan(file.path)) {
        result.add(file);
      } else {
        skipped++;
      }
    }

    if (skipped > 0) {
      AppLogger.i('Metadata scan cache: skipped $skipped files, need to scan ${result.length}', 'MetadataScanCache');
    }

    return result;
  }
}
