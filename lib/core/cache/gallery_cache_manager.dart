import 'dart:io';

import 'package:hive/hive.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/gallery/gallery_scan_service.dart';
import '../../data/services/image_metadata_service.dart';
import '../database/datasources/gallery_data_source.dart';

/// 缓存统计信息
class CacheStatistics {
  /// L1 内存缓存大小
  final int l1MemorySize;

  /// L1 内存缓存命中率（0.0 - 1.0）
  final double l1HitRate;

  /// L2 Hive 缓存大小
  final int l2HiveSize;

  /// L2 Hive 缓存命中率（0.0 - 1.0）
  final double l2HitRate;

  /// L3 数据库图片记录数
  final int l3DatabaseImageCount;

  /// L3 数据库元数据记录数
  final int l3DatabaseMetadataCount;

  const CacheStatistics({
    required this.l1MemorySize,
    required this.l1HitRate,
    required this.l2HiveSize,
    required this.l2HitRate,
    required this.l3DatabaseImageCount,
    required this.l3DatabaseMetadataCount,
  });

  @override
  String toString() =>
      'CacheStatistics(L1: $l1MemorySize, hitRate: ${(l1HitRate * 100).toStringAsFixed(1)}%, '
      'L2: $l2HiveSize, hitRate: ${(l2HitRate * 100).toStringAsFixed(1)}%, '
      'DB: $l3DatabaseImageCount images, $l3DatabaseMetadataCount metadata)';
}

/// 画廊缓存管理器
///
/// 提供统一接口管理三层缓存：
/// - L1: 内存缓存 (ImageMetadataService._memoryCache)
/// - L2: Hive 缓存 (ImageMetadataService._persistentBox)
/// - L3: SQLite 数据库 (GalleryDataSource)
class GalleryCacheManager {
  static final GalleryCacheManager _instance = GalleryCacheManager._internal();
  factory GalleryCacheManager() => _instance;
  GalleryCacheManager._internal();

  /// 清除所有层级缓存
  Future<void> clearAll() async {
    await clearL1MemoryCache();
    await clearL2HiveCache();
    await clearL3DatabaseCache();
    AppLogger.i('All cache layers cleared', 'GalleryCacheManager');
  }

  /// 清除 L1 内存缓存
  Future<void> clearL1MemoryCache() async {
    await ImageMetadataService().clearCache();
    GalleryScanService.instance.clearCache();
    // GalleryDataSource.clearCache() 不再清除 _metadataCache
    GalleryDataSource().clearCache();
    AppLogger.i('L1 memory cache cleared', 'GalleryCacheManager');
  }

  /// 清除 L2 Hive 缓存
  Future<void> clearL2HiveCache() async {
    await ImageMetadataService().clearPersistentCache();
    AppLogger.i('L2 Hive cache cleared', 'GalleryCacheManager');
  }

  /// 清除 L3 数据库（谨慎使用）
  Future<void> clearL3DatabaseCache() async {
    final dataSource = GalleryDataSource();
    await dataSource.deleteAllImages();
    await dataSource.deleteAllMetadata();
    AppLogger.i('L3 database cache cleared', 'GalleryCacheManager');
  }

  /// 获取缓存统计
  Future<CacheStatistics> getStatistics() async {
    final imageService = ImageMetadataService();
    final dataSource = GalleryDataSource();

    // 获取 L3 数据库统计
    final imageCount = await dataSource.countImages();
    final metadataCount = await _getMetadataCount(dataSource);

    return CacheStatistics(
      l1MemorySize: imageService.memoryCacheSize,
      l1HitRate: imageService.memoryCacheHitRate,
      l2HiveSize: await imageService.persistentCacheSize,
      l2HitRate: imageService.persistentCacheHitRate,
      l3DatabaseImageCount: imageCount,
      l3DatabaseMetadataCount: metadataCount,
    );
  }

  Future<int> _getMetadataCount(GalleryDataSource dataSource) async {
    try {
      // 获取所有图片的元数据数量（通过 getMetadataByImageIds 的批量查询方式）
      // 这里我们简单地返回图片数量作为近似值
      // 如果需要精确值，可以通过 doCheckHealth 获取
      final health = await dataSource.checkHealth();
      final metadataCount = health.details['metadataCount'] as int? ?? 0;
      return metadataCount;
    } catch (e) {
      AppLogger.w('Failed to get metadata count: $e', 'GalleryCacheManager');
      return 0;
    }
  }

  /// 重置所有缓存统计计数器
  void resetStatistics() {
    ImageMetadataService().resetStatistics();
    AppLogger.i('Cache statistics reset', 'GalleryCacheManager');
  }
}

/// L2 Hive 缓存清理器
///
/// 定期清理策略：
/// 1. 应用启动时检查
/// 2. 每7天执行一次完整清理
/// 3. 清理不存在的文件对应的缓存条目
class L2CacheCleaner {
  static const String _lastCleanupKey = 'l2_cache_last_cleanup';
  static const Duration _cleanupInterval = Duration(days: 7);

  /// 检查并执行清理
  Future<void> checkAndClean() async {
    try {
      final box = await _getSettingsBox();
      final lastCleanup = box.get(_lastCleanupKey);
      final lastCleanupTime = lastCleanup != null
          ? DateTime.fromMillisecondsSinceEpoch(int.parse(lastCleanup))
          : DateTime(2000);
      final now = DateTime.now();

      if (now.difference(lastCleanupTime) > _cleanupInterval) {
        AppLogger.i('L2 cache cleanup due (last: $lastCleanupTime)', 'L2CacheCleaner');
        await performCleanup();
        await box.put(_lastCleanupKey, now.millisecondsSinceEpoch.toString());
      } else {
        AppLogger.d('L2 cache cleanup not needed yet', 'L2CacheCleaner');
      }
    } catch (e, stack) {
      AppLogger.e('Failed to check L2 cache cleanup', e, stack, 'L2CacheCleaner');
    }
  }

  /// 执行清理
  Future<void> performCleanup() async {
    try {
      final imageService = ImageMetadataService();
      final box = imageService.persistentBox;

      if (box == null || !box.isOpen) {
        AppLogger.w('Persistent box not available for cleanup', 'L2CacheCleaner');
        return;
      }

      final keysToDelete = <String>[];
      int checkedCount = 0;

      for (final key in box.keys) {
        if (key is! String) continue;
        // 跳过版本键
        if (key.startsWith('_')) continue;

        checkedCount++;

        // 获取该哈希对应的所有路径
        final paths = imageService.getPathsForHash(key);

        bool anyExists = false;
        for (final path in paths) {
          try {
            if (await File(path).exists()) {
              anyExists = true;
              break;
            }
          } catch (_) {
            // 忽略文件访问错误
          }
        }

        // 如果没有文件存在，标记为待删除
        if (!anyExists && paths.isNotEmpty) {
          keysToDelete.add(key);
        }
      }

      // 批量删除
      for (final key in keysToDelete) {
        await box.delete(key);
      }

      AppLogger.i(
        'L2 cache cleaned: ${keysToDelete.length} entries removed, $checkedCount checked',
        'L2CacheCleaner',
      );
    } catch (e, stack) {
      AppLogger.e('Failed to perform L2 cache cleanup', e, stack, 'L2CacheCleaner');
    }
  }

  Future<Box<String>> _getSettingsBox() async {
    if (Hive.isBoxOpen(StorageKeys.settingsBox)) {
      return Hive.box<String>(StorageKeys.settingsBox);
    }
    return await Hive.openBox<String>(StorageKeys.settingsBox);
  }
}
