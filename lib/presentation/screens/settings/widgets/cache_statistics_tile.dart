import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/gallery_cache_manager.dart';
import '../../../widgets/common/app_toast.dart';

/// 缓存统计 Provider
final cacheStatisticsProvider = FutureProvider.autoDispose<CacheStatistics>((ref) async {
  return await GalleryCacheManager().getStatistics();
});

/// 缓存统计展示组件
class CacheStatisticsTile extends ConsumerWidget {
  const CacheStatisticsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            '点击刷新统计信息',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '刷新',
                onPressed: () { ref.invalidate(cacheStatisticsProvider); },
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, size: 20),
                tooltip: '重置统计',
                onPressed: () {
                  GalleryCacheManager().resetStatistics();
                  ref.invalidate(cacheStatisticsProvider);
                  AppToast.success(context, '统计已重置');
                },
              ),
            ],
          ),
          onTap: () => ref.invalidate(cacheStatisticsProvider),
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
                  '$count 条记录',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(hitRate * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _getHitRateColor(hitRate),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '命中率',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getHitRateColor(double rate) {
    if (rate >= 0.8) return Colors.green;
    if (rate >= 0.5) return Colors.orange;
    return Colors.red;
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
    final theme = Theme.of(context);
    const color = Colors.purple;

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
            child: const Icon(Icons.table_chart, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'L3 SQLite 数据库',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$imageCount 张图片 · $metadataCount 条元数据',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
