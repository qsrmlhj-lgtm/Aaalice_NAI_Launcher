import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/gallery_scan_progress_provider.dart';

/// 画廊扫描进度条
///
/// 显示在分页栏旁边的扫描进度指示器
class GalleryScanProgressBar extends ConsumerWidget {
  final bool compact;

  const GalleryScanProgressBar({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(galleryScanProgressProvider);

    // 如果没有扫描或已完成且隐藏，显示静态信息
    if (!scanState.isScanning && scanState.phase != 'completed') {
      return const SizedBox.shrink();
    }

    if (compact) {
      return _buildCompactView(context, scanState);
    }

    return _buildFullView(context, scanState);
  }

  Widget _buildCompactView(BuildContext context, ScanProgressState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: state.progress > 0 ? state.progress : null,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(state.progress * 100).toInt()}%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullView(BuildContext context, ScanProgressState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withOpacity(0.2),
            colorScheme.secondaryContainer.withOpacity(0.1),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 带动画的扫描图标
          _AnimatedScanIcon(color: colorScheme.primary),
          const SizedBox(width: 12),
          // 进度信息
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _getPhaseText(state.phase),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${state.processed}/${state.total}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 进度条
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: state.progress > 0 ? state.progress : null,
                    minHeight: 4,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 统计信息
          if (state.filesAdded > 0 || state.filesUpdated > 0) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatsColor(colorScheme).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.filesAdded > 0)
                    _buildStatChip(
                      theme,
                      Icons.add_circle_outline,
                      '+${state.filesAdded}',
                      Colors.green,
                    ),
                  if (state.filesUpdated > 0) ...[
                    const SizedBox(width: 4),
                    _buildStatChip(
                      theme,
                      Icons.update,
                      '~${state.filesUpdated}',
                      Colors.orange,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(ThemeData theme, IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _getStatsColor(ColorScheme scheme) {
    return scheme.primary;
  }

  String _getPhaseText(String phase) {
    switch (phase) {
      case 'detecting':
        return '检测文件中...';
      case 'indexing':
        return '索引中...';
      case 'scanning':
        return '扫描中...';
      case 'completed':
        return '扫描完成';
      default:
        return '处理中...';
    }
  }
}

/// 动画扫描图标
class _AnimatedScanIcon extends StatefulWidget {
  final Color color;

  const _AnimatedScanIcon({required this.color});

  @override
  State<_AnimatedScanIcon> createState() => _AnimatedScanIconState();
}

class _AnimatedScanIconState extends State<_AnimatedScanIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
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
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Transform.rotate(
              angle: _controller.value * 2 * math.pi,
              child: Icon(
                Icons.sync,
                size: 16,
                color: widget.color,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 用于嵌入到PaginationBar的扫描进度指示器
class ScanProgressIndicator extends ConsumerWidget {
  const ScanProgressIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(galleryScanProgressProvider);

    if (!scanState.isScanning) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: scanState.progress > 0 ? scanState.progress : null,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${scanState.processed}/${scanState.total}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (scanState.filesAdded > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+${scanState.filesAdded}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
