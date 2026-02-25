import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/gallery_cache_manager.dart';
import '../../../widgets/common/app_toast.dart';

/// 缓存统计 Provider
///
/// 使用 autoDispose 确保组件销毁时释放资源
/// 通过统计信息失效回调机制实现实时刷新
final cacheStatisticsProvider = FutureProvider.autoDispose<CacheStatistics>((ref) async {
  GalleryCacheManager().registerOnStatisticsInvalidated(ref.invalidateSelf);
  ref.onDispose(() => GalleryCacheManager().unregisterOnStatisticsInvalidated(ref.invalidateSelf));
  return await GalleryCacheManager().getStatistics();
});

/// 缓存统计展示组件
/// 
/// 支持自动刷新，每 3 秒更新一次统计数据
class CacheStatisticsTile extends ConsumerStatefulWidget {
  const CacheStatisticsTile({super.key});

  @override
  ConsumerState<CacheStatisticsTile> createState() => _CacheStatisticsTileState();
}

class _CacheStatisticsTileState extends ConsumerState<CacheStatisticsTile> {
  Timer? _refreshTimer;
  DateTime _lastRefreshTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 启动定时器，每 3 秒自动刷新一次
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshStats(),
    );
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _refreshStats() {
    if (mounted) {
      ref.invalidate(cacheStatisticsProvider);
      setState(() {
        _lastRefreshTime = DateTime.now();
      });
    }
  }

  String _getTimeSinceLastRefresh() {
    final diff = DateTime.now().difference(_lastRefreshTime);
    if (diff.inSeconds < 5) {
      return '刚刚';
    } else if (diff.inSeconds < 60) {
      return '${diff.inSeconds}秒前';
    } else {
      return '${diff.inMinutes}分钟前';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(cacheStatisticsProvider);

    return statsAsync.when(
      data: (stats) => _buildContent(context, ref, stats),
      loading: () => const ListTile(
        leading: Icon(Icons.analytics_outlined),
        title: Text('缓存统计'),
        subtitle: LinearProgressIndicator(),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: const Text('缓存统计'),
        subtitle: Text('加载失败: $error'),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, CacheStatistics stats) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.analytics_outlined),
          title: const Text('缓存统计'),
          subtitle: Text(
            '自动刷新 · 上次更新: ${_getTimeSinceLastRefresh()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 自动刷新指示器
              _AutoRefreshIndicator(
                key: ValueKey(_lastRefreshTime.millisecondsSinceEpoch),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '立即刷新',
                onPressed: () {
                  _refreshStats();
                  AppToast.success(context, '已刷新');
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, size: 20),
                tooltip: '重置统计',
                onPressed: () {
                  GalleryCacheManager().resetStatistics();
                  _refreshStats();
                  AppToast.success(context, '统计已重置');
                },
              ),
            ],
          ),
          onTap: _refreshStats,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              _CacheLevelIndicator(
                label: 'L1 内存缓存',
                count: stats.l1MemorySize,
                hitRate: stats.l1HitRate,
                color: Colors.blue,
                icon: Icons.memory,
              ),
              const SizedBox(height: 12),
              _CacheLevelIndicator(
                label: 'L2 Hive 缓存',
                count: stats.l2HiveSize,
                hitRate: stats.l2HitRate,
                color: Colors.orange,
                icon: Icons.storage,
              ),
              const SizedBox(height: 12),
              _DatabaseIndicator(
                imageCount: stats.l3DatabaseImageCount,
                metadataCount: stats.l3DatabaseMetadataCount,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 自动刷新指示器动画
class _AutoRefreshIndicator extends StatefulWidget {
  const _AutoRefreshIndicator({super.key});

  @override
  State<_AutoRefreshIndicator> createState() => _AutoRefreshIndicatorState();
}

class _AutoRefreshIndicatorState extends State<_AutoRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: _controller.value,
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
        );
      },
    );
  }
}

class _CacheLevelIndicator extends StatelessWidget {
  final String label;
  final int count;
  final double hitRate;
  final Color color;
  final IconData icon;

  const _CacheLevelIndicator({
    required this.label,
    required this.count,
    required this.hitRate,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return _CacheIndicator(
      label: label,
      value: '$count 条记录',
      icon: icon,
      color: color,
      subValue: '${(hitRate * 100).toStringAsFixed(1)}%',
    );
  }
}

class _DatabaseIndicator extends StatelessWidget {
  final int imageCount;
  final int metadataCount;

  const _DatabaseIndicator({
    required this.imageCount,
    required this.metadataCount,
  });

  @override
  Widget build(BuildContext context) {
    return _CacheIndicator(
      label: 'L3 SQLite 数据库',
      value: '$imageCount 张图片 · $metadataCount 条元数据',
      icon: Icons.table_chart,
      color: Colors.purple,
    );
  }
}

class _CacheIndicator extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subValue;

  const _CacheIndicator({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          if (subValue != null)
            Text(
              subValue!,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}
