import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/gallery_cache_manager.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../widgets/common/app_toast.dart';

/// 清除操作类型
enum _ClearAction {
  cancel,
  light,
  deep,
}

/// 清除画廊缓存按钮
///
/// 精美的带动效的按钮，用于清除本地画廊的所有缓存数据
class ClearGalleryCacheTile extends ConsumerStatefulWidget {
  const ClearGalleryCacheTile({super.key});

  @override
  ConsumerState<ClearGalleryCacheTile> createState() =>
      _ClearGalleryCacheTileState();
}

class _ClearGalleryCacheTileState extends ConsumerState<ClearGalleryCacheTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _rotationAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.5), weight: 0.2),
      TweenSequenceItem(tween: Tween(begin: -0.5, end: 0.5), weight: 0.3),
      TweenSequenceItem(tween: Tween(begin: 0.5, end: -0.5), weight: 0.3),
      TweenSequenceItem(tween: Tween(begin: -0.5, end: 0.0), weight: 0.2),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 0.2),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.1), weight: 0.3),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 0.95), weight: 0.3),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 0.2),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _clearCache(BuildContext context) async {
    if (_isClearing) return;

    // 显示清除选项对话框
    final action = await showDialog<_ClearAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.cleaning_services_rounded,
          color: Colors.orange,
          size: 48,
        ),
        title: const Text('清除画廊缓存'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请选择清除级别：'),
            SizedBox(height: 16),
            _CacheItem(
              icon: Icons.memory,
              text: '轻度：仅清除内存缓存（保留数据库）',
              color: Colors.blue,
            ),
            SizedBox(height: 8),
            _CacheItem(
              icon: Icons.storage,
              text: '深度：删除所有数据库记录',
              color: Colors.red,
            ),
            SizedBox(height: 16),
            Text(
              '提示：深度清除后需要重新进入画廊以重新扫描',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_ClearAction.cancel),
            child: const Text('取消'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(_ClearAction.light),
            icon: const Icon(Icons.delete_outline),
            label: const Text('轻度清除'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(_ClearAction.deep),
            icon: const Icon(Icons.delete_forever),
            label: const Text('深度清除'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (action == null || action == _ClearAction.cancel || !context.mounted) {
      return;
    }

    setState(() {
      _isClearing = true;
    });

    // 播放清理动画
    _controller.repeat();

    try {
      if (action == _ClearAction.light) {
        await _performLightClear();
        if (context.mounted) {
          AppToast.success(context, '内存缓存已清除');
        }
      } else {
        await _performDeepClear();
        if (context.mounted) {
          AppToast.success(
            context,
            '深度清除完成！请重新进入本地画廊以重新扫描',
          );
        }
      }

      // 等待动画完成
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e, stack) {
      AppLogger.e('Failed to clear cache', e, stack, 'ClearCache');
      if (context.mounted) {
        AppToast.error(context, '清除缓存失败: $e');
      }
    } finally {
      _controller.stop();
      _controller.reset();
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  /// 轻度清除：只清除内存缓存
  Future<void> _performLightClear() async {
    await GalleryCacheManager().clearL1MemoryCache();
    AppLogger.i('L1 memory cache cleared', 'ClearCache');
  }

  /// 深度清除：删除数据库中的所有图片索引记录
  Future<void> _performDeepClear() async {
    await GalleryCacheManager().clearAll();
    AppLogger.i('All cache layers cleared', 'ClearCache');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotationAnimation.value * math.pi,
            child: Transform.scale(
              scale: _isClearing ? _scaleAnimation.value : 1.0,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withOpacity(0.2),
                      Colors.deepOrange.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isClearing
                        ? Colors.orange
                        : Colors.orange.withOpacity(0.3),
                    width: _isClearing ? 2 : 1,
                  ),
                ),
                child: Icon(
                  Icons.cleaning_services_rounded,
                  color: _isClearing ? Colors.orange : Colors.orange.withOpacity(0.8),
                  size: 22,
                ),
              ),
            ),
          );
        },
      ),
      title: Text(
        '清除画廊缓存',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _isClearing
            ? '正在清除缓存...'
            : '清除内存缓存或重置数据库',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      trailing: _isClearing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withOpacity(0.1),
                    colorScheme.primary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '清除',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      onTap: _isClearing ? null : () => _clearCache(context),
    );
  }
}

/// 缓存项目图标
class _CacheItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _CacheItem({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
