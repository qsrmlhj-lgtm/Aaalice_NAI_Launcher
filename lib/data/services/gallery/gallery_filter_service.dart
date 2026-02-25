import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/database/datasources/gallery_data_source.dart';
import '../../../core/database/utils/lru_cache.dart';
import '../../../core/utils/app_logger.dart';

export 'gallery_filter_service.dart' show FilterCriteria;

/// 过滤条件
@immutable
class FilterCriteria {
  final String searchQuery;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final bool showFavoritesOnly;
  final List<String> selectedTags;
  final String? filterModel;
  final String? filterSampler;
  final int? filterMinSteps;
  final int? filterMaxSteps;
  final double? filterMinCfg;
  final double? filterMaxCfg;
  final String? filterResolution;
  final int? minWidth;
  final int? minHeight;
  final int? maxWidth;
  final int? maxHeight;
  final int? minFileSize;
  final int? maxFileSize;
  final List<String> metadataStatuses;

  const FilterCriteria({
    this.searchQuery = '',
    this.dateStart,
    this.dateEnd,
    this.showFavoritesOnly = false,
    this.selectedTags = const [],
    this.filterModel,
    this.filterSampler,
    this.filterMinSteps,
    this.filterMaxSteps,
    this.filterMinCfg,
    this.filterMaxCfg,
    this.filterResolution,
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
    this.minFileSize,
    this.maxFileSize,
    this.metadataStatuses = const [],
  });

  FilterCriteria copyWith({
    String? searchQuery,
    DateTime? dateStart,
    DateTime? dateEnd,
    bool? showFavoritesOnly,
    List<String>? selectedTags,
    String? filterModel,
    String? filterSampler,
    int? filterMinSteps,
    int? filterMaxSteps,
    double? filterMinCfg,
    double? filterMaxCfg,
    String? filterResolution,
    int? minWidth,
    int? minHeight,
    int? maxWidth,
    int? maxHeight,
    int? minFileSize,
    int? maxFileSize,
    List<String>? metadataStatuses,
    bool clearDateStart = false,
    bool clearDateEnd = false,
    bool clearFilterModel = false,
    bool clearFilterSampler = false,
    bool clearFilterMinSteps = false,
    bool clearFilterMaxSteps = false,
    bool clearFilterMinCfg = false,
    bool clearFilterMaxCfg = false,
    bool clearFilterResolution = false,
    bool clearMinWidth = false,
    bool clearMinHeight = false,
    bool clearMaxWidth = false,
    bool clearMaxHeight = false,
    bool clearMinFileSize = false,
    bool clearMaxFileSize = false,
  }) {
    return FilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      dateStart: clearDateStart ? null : (dateStart ?? this.dateStart),
      dateEnd: clearDateEnd ? null : (dateEnd ?? this.dateEnd),
      showFavoritesOnly: showFavoritesOnly ?? this.showFavoritesOnly,
      selectedTags: selectedTags ?? this.selectedTags,
      filterModel: clearFilterModel ? null : (filterModel ?? this.filterModel),
      filterSampler: clearFilterSampler ? null : (filterSampler ?? this.filterSampler),
      filterMinSteps: clearFilterMinSteps ? null : (filterMinSteps ?? this.filterMinSteps),
      filterMaxSteps: clearFilterMaxSteps ? null : (filterMaxSteps ?? this.filterMaxSteps),
      filterMinCfg: clearFilterMinCfg ? null : (filterMinCfg ?? this.filterMinCfg),
      filterMaxCfg: clearFilterMaxCfg ? null : (filterMaxCfg ?? this.filterMaxCfg),
      filterResolution: clearFilterResolution ? null : (filterResolution ?? this.filterResolution),
      minWidth: clearMinWidth ? null : (minWidth ?? this.minWidth),
      minHeight: clearMinHeight ? null : (minHeight ?? this.minHeight),
      maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
      maxHeight: clearMaxHeight ? null : (maxHeight ?? this.maxHeight),
      minFileSize: clearMinFileSize ? null : (minFileSize ?? this.minFileSize),
      maxFileSize: clearMaxFileSize ? null : (maxFileSize ?? this.maxFileSize),
      metadataStatuses: metadataStatuses ?? this.metadataStatuses,
    );
  }

  bool get hasFilters =>
      searchQuery.isNotEmpty ||
      dateStart != null ||
      dateEnd != null ||
      showFavoritesOnly ||
      selectedTags.isNotEmpty ||
      filterModel != null ||
      filterSampler != null ||
      filterMinSteps != null ||
      filterMaxSteps != null ||
      filterMinCfg != null ||
      filterMaxCfg != null ||
      filterResolution != null ||
      minWidth != null ||
      minHeight != null ||
      maxWidth != null ||
      maxHeight != null ||
      minFileSize != null ||
      maxFileSize != null ||
      metadataStatuses.isNotEmpty;

  bool get hasMetadataFilters =>
      filterModel != null ||
      filterSampler != null ||
      filterResolution != null ||
      filterMinSteps != null ||
      filterMaxSteps != null ||
      filterMinCfg != null ||
      filterMaxCfg != null;

  bool get hasAdvancedFilters =>
      minWidth != null ||
      minHeight != null ||
      maxWidth != null ||
      maxHeight != null ||
      minFileSize != null ||
      maxFileSize != null ||
      metadataStatuses.isNotEmpty;

  /// 生成缓存键
  String get cacheKey {
    final parts = <String>[
      'q:${searchQuery.toLowerCase().trim()}',
      if (dateStart != null) 'ds:${dateStart!.millisecondsSinceEpoch}',
      if (dateEnd != null) 'de:${dateEnd!.millisecondsSinceEpoch}',
      if (showFavoritesOnly) 'fav:1',
      if (selectedTags.isNotEmpty) 'tags:${selectedTags.join(",")}',
      if (filterModel != null) 'model:$filterModel',
      if (filterSampler != null) 'sampler:$filterSampler',
      if (filterMinSteps != null) 'minStep:$filterMinSteps',
      if (filterMaxSteps != null) 'maxStep:$filterMaxSteps',
      if (filterMinCfg != null) 'minCfg:$filterMinCfg',
      if (filterMaxCfg != null) 'maxCfg:$filterMaxCfg',
      if (filterResolution != null) 'res:$filterResolution',
      if (minWidth != null) 'minW:$minWidth',
      if (minHeight != null) 'minH:$minHeight',
      if (maxWidth != null) 'maxW:$maxWidth',
      if (maxHeight != null) 'maxH:$maxHeight',
      if (minFileSize != null) 'minFS:$minFileSize',
      if (maxFileSize != null) 'maxFS:$maxFileSize',
      if (metadataStatuses.isNotEmpty) 'meta:${metadataStatuses.join(",")}',
    ];
    return parts.join('|');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterCriteria && other.cacheKey == cacheKey;
  }

  @override
  int get hashCode => cacheKey.hashCode;
}

/// 过滤结果
@immutable
class FilterResult {
  final List<File> files;
  final int totalCount;
  final Duration executionTime;
  final bool fromCache;
  final FilterCriteria criteria;

  const FilterResult({
    required this.files,
    required this.totalCount,
    required this.executionTime,
    this.fromCache = false,
    required this.criteria,
  });

  FilterResult copyWith({
    List<File>? files,
    int? totalCount,
    Duration? executionTime,
    bool? fromCache,
    FilterCriteria? criteria,
  }) {
    return FilterResult(
      files: files ?? this.files,
      totalCount: totalCount ?? this.totalCount,
      executionTime: executionTime ?? this.executionTime,
      fromCache: fromCache ?? this.fromCache,
      criteria: criteria ?? this.criteria,
    );
  }
}

/// 画廊过滤服务
///
/// 提供异步过滤、缓存和多条件组合查询功能。
/// 所有过滤操作都是异步的，避免阻塞 UI 线程。
class GalleryFilterService {
  final GalleryDataSource _dataSource;

  // 过滤结果缓存
  static const int _maxCacheSize = 50;
  final LRUCache<String, FilterResult> _filterCache =
      LRUCache(maxSize: _maxCacheSize);

  // 批量处理配置
  static const int _dateBatchSize = 50;

  // 取消令牌
  final Map<String, CancelToken> _activeFilters = {};

  GalleryFilterService(this._dataSource);

  /// 获取缓存统计
  Map<String, dynamic> get cacheStatistics => _filterCache.statistics;

  /// 清除缓存
  void clearCache() {
    _filterCache.clear();
    AppLogger.i('Filter cache cleared', 'GalleryFilterService');
  }

  /// 异步应用过滤条件
  ///
  /// [allFiles] 所有文件列表
  /// [criteria] 过滤条件
  /// [operationId] 操作 ID（用于取消）
  Future<FilterResult> applyFilters(
    List<File> allFiles,
    FilterCriteria criteria, {
    String? operationId,
  }) async {
    final id = operationId ?? 'filter_${DateTime.now().millisecondsSinceEpoch}';
    final stopwatch = Stopwatch()..start();

    // 创建取消令牌
    final cancelToken = CancelToken();
    _activeFilters[id] = cancelToken;

    try {
      // 检查缓存
      final cacheKey = criteria.cacheKey;
      final cached = _filterCache.get(cacheKey);
      if (cached != null) {
        AppLogger.d('Filter cache hit: $cacheKey', 'GalleryFilterService');
        return cached.copyWith(fromCache: true);
      }

      // 【调试】记录过滤前状态
      AppLogger.d(
        'applyFilters START: allFiles=${allFiles.length}, hasFilters=${criteria.hasFilters}, cacheKey=$cacheKey',
        'GalleryFilterService',
      );

      // 无过滤条件
      if (!criteria.hasFilters) {
        final result = FilterResult(
          files: allFiles,
          totalCount: allFiles.length,
          executionTime: stopwatch.elapsed,
          criteria: criteria,
        );
        _filterCache.put(cacheKey, result);
        AppLogger.d(
          'applyFilters NO FILTERS: returning ${allFiles.length} files',
          'GalleryFilterService',
        );
        return result;
      }

      // 检查是否取消
      if (cancelToken.isCancelled) {
        throw const FilterCancelledException();
      }

      // 执行过滤
      List<File> filtered;

      if (criteria.searchQuery.isNotEmpty) {
        // 有搜索关键词：使用数据库搜索
        filtered = await _searchInDatabase(allFiles, criteria, cancelToken);
      } else {
        // 本地过滤
        filtered = await _applyLocalFilters(allFiles, criteria, cancelToken);
      }

      // 检查是否取消
      if (cancelToken.isCancelled) {
        throw const FilterCancelledException();
      }

      stopwatch.stop();

      final result = FilterResult(
        files: filtered,
        totalCount: filtered.length,
        executionTime: stopwatch.elapsed,
        criteria: criteria,
      );

      // 缓存结果
      _filterCache.put(cacheKey, result);

      AppLogger.d(
        'Filter completed in ${stopwatch.elapsedMilliseconds}ms: ${filtered.length} results (from ${allFiles.length} files)'
        ' | search="${criteria.searchQuery}" | tags=${criteria.selectedTags} | fav=${criteria.showFavoritesOnly}',
        'GalleryFilterService',
      );

      return result;
    } finally {
      _activeFilters.remove(id);
    }
  }

  /// 在数据库中搜索
  Future<List<File>> _searchInDatabase(
    List<File> allFiles,
    FilterCriteria criteria,
    CancelToken cancelToken,
  ) async {
    try {
      // 使用高级搜索
      final imageIds = await _dataSource.advancedSearch(
        textQuery: criteria.searchQuery.toLowerCase().trim(),
        favoritesOnly: criteria.showFavoritesOnly,
        dateStart: criteria.dateStart,
        dateEnd: criteria.dateEnd,
        minWidth: criteria.minWidth,
        minHeight: criteria.minHeight,
        maxWidth: criteria.maxWidth,
        maxHeight: criteria.maxHeight,
        minFileSize: criteria.minFileSize,
        maxFileSize: criteria.maxFileSize,
        metadataStatuses: criteria.metadataStatuses.isNotEmpty
            ? criteria.metadataStatuses
            : null,
        limit: 10000,
      );

      if (cancelToken.isCancelled) return [];

      // 获取图片记录
      final images = await _dataSource.getImagesByIds(imageIds);
      final validPaths = images.map((img) => img.filePath).toSet();

      // 只返回存在于 allFiles 中的文件
      return allFiles.where((file) => validPaths.contains(file.path)).toList();
    } catch (e) {
      AppLogger.w('Search failed: $e', 'GalleryFilterService');
      // 回退到本地过滤
      return _applyLocalFilters(allFiles, criteria, cancelToken);
    }
  }

  /// 应用本地过滤
  Future<List<File>> _applyLocalFilters(
    List<File> allFiles,
    FilterCriteria criteria,
    CancelToken cancelToken,
  ) async {
    var filtered = List<File>.from(allFiles);

    AppLogger.d(
      '_applyLocalFilters START: ${filtered.length} files, '
      'tags=${criteria.selectedTags}, dateStart=${criteria.dateStart}, dateEnd=${criteria.dateEnd}, favOnly=${criteria.showFavoritesOnly}',
      'GalleryFilterService',
    );

    // 标签过滤（需要数据库查询）
    if (criteria.selectedTags.isNotEmpty) {
      filtered = await _filterByTags(filtered, criteria.selectedTags, cancelToken);
      AppLogger.d('_applyLocalFilters after tags filter: ${filtered.length} files', 'GalleryFilterService');
    }

    if (cancelToken.isCancelled) return [];

    // 日期过滤
    if (criteria.dateStart != null || criteria.dateEnd != null) {
      filtered = await _filterByDateRange(filtered, criteria, cancelToken);
      AppLogger.d('_applyLocalFilters after date filter: ${filtered.length} files', 'GalleryFilterService');
    }

    if (cancelToken.isCancelled) return [];

    // 收藏过滤
    if (criteria.showFavoritesOnly) {
      filtered = await _filterByFavorites(filtered, cancelToken);
      AppLogger.d('_applyLocalFilters after fav filter: ${filtered.length} files', 'GalleryFilterService');
    }

    AppLogger.d('_applyLocalFilters END: ${filtered.length} files', 'GalleryFilterService');
    return filtered;
  }

  /// 按标签过滤
  Future<List<File>> _filterByTags(
    List<File> files,
    List<String> tags,
    CancelToken cancelToken,
  ) async {
    try {
      // 获取文件路径到图片 ID 的映射
      final pathToIdMap = await _dataSource.getImageIdsByPaths(
        files.map((f) => f.path).toList(),
      );

      // 获取所有图片的标签
      final imageIds = pathToIdMap.values.whereType<int>().toList();
      final tagsMap = await _dataSource.getTagsByImageIds(imageIds);

      return files.where((file) {
        if (cancelToken.isCancelled) return false;

        final imageId = pathToIdMap[file.path];
        if (imageId == null) return false;

        final fileTags = tagsMap[imageId] ?? [];
        return tags.every((tag) => fileTags.contains(tag));
      }).toList();
    } catch (e) {
      AppLogger.w('Failed to filter by tags: $e', 'GalleryFilterService');
      return files;
    }
  }

  /// 按日期范围过滤
  Future<List<File>> _filterByDateRange(
    List<File> files,
    FilterCriteria criteria,
    CancelToken cancelToken,
  ) async {
    final effectiveEndDate = criteria.dateEnd?.add(const Duration(days: 1));
    final result = <File>[];

    // 分批处理避免阻塞
    for (var i = 0; i < files.length; i += _dateBatchSize) {
      if (cancelToken.isCancelled) return [];

      final end = min(i + _dateBatchSize, files.length);
      final batch = files.sublist(i, end);

      // 使用 compute 在后台 isolate 处理
      final batchResult = await compute(
        _filterBatchByDate,
        _DateFilterParams(
          filePaths: batch.map((f) => f.path).toList(),
          dateStart: criteria.dateStart,
          dateEnd: effectiveEndDate,
        ),
      );

      result.addAll(batchResult.map((path) => File(path)));

      // 让出时间片
      if (i + _dateBatchSize < files.length) {
        await Future.delayed(Duration.zero);
      }
    }

    return result;
  }

  /// 按收藏状态过滤
  Future<List<File>> _filterByFavorites(
    List<File> files,
    CancelToken cancelToken,
  ) async {
    try {
      final pathToIdMap = await _dataSource.getImageIdsByPaths(
        files.map((f) => f.path).toList(),
      );

      final imageIds = pathToIdMap.values.whereType<int>().toList();
      final favoritesMap = await _dataSource.getFavoritesByImageIds(imageIds);

      return files.where((file) {
        if (cancelToken.isCancelled) return false;

        final imageId = pathToIdMap[file.path];
        if (imageId == null) return false;

        return favoritesMap[imageId] ?? false;
      }).toList();
    } catch (e) {
      AppLogger.w('Failed to filter favorites: $e', 'GalleryFilterService');
      return files;
    }
  }

  /// 取消过滤操作
  void cancelFilter(String operationId) {
    final token = _activeFilters[operationId];
    if (token != null) {
      token.cancel();
      AppLogger.d('Filter cancelled: $operationId', 'GalleryFilterService');
    }
  }

  /// 取消所有过滤操作
  void cancelAllFilters() {
    for (final entry in _activeFilters.entries) {
      entry.value.cancel();
    }
    AppLogger.d('All filters cancelled', 'GalleryFilterService');
  }

  /// 清空所有过滤条件
  FilterCriteria clearAllFilters(FilterCriteria current) {
    return const FilterCriteria();
  }
}

/// 取消令牌
class CancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// 过滤取消异常
class FilterCancelledException implements Exception {
  const FilterCancelledException();

  @override
  String toString() => 'Filter operation was cancelled';
}

/// 日期过滤参数
class _DateFilterParams {
  final List<String> filePaths;
  final DateTime? dateStart;
  final DateTime? dateEnd;

  _DateFilterParams({
    required this.filePaths,
    this.dateStart,
    this.dateEnd,
  });
}

/// 在 isolate 中批量过滤日期
List<String> _filterBatchByDate(_DateFilterParams params) {
  final result = <String>[];

  for (final path in params.filePaths) {
    try {
      final file = File(path);
      if (!file.existsSync()) continue;

      final modifiedAt = file.lastModifiedSync();

      if (params.dateStart != null && modifiedAt.isBefore(params.dateStart!)) {
        continue;
      }
      if (params.dateEnd != null && modifiedAt.isAfter(params.dateEnd!)) {
        continue;
      }

      result.add(path);
    } catch (_) {
      // 忽略文件访问错误
    }
  }

  return result;
}
