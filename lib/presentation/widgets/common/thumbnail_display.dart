import 'dart:io';

import 'package:flutter/material.dart';

/// 缩略图显示组件
///
/// 支持偏移和缩放调整，用于词库条目的预览图显示
class ThumbnailDisplay extends StatelessWidget {
  /// 图片路径
  final String imagePath;

  /// 水平偏移 (-1.0 ~ 1.0)
  final double offsetX;

  /// 垂直偏移 (-1.0 ~ 1.0)
  final double offsetY;

  /// 缩放比例 (1.0 ~ 3.0)
  final double scale;

  /// 容器宽度
  final double? width;

  /// 容器高度
  final double? height;

  /// 圆角
  final BorderRadius? borderRadius;

  /// 图片填充模式
  final BoxFit fit;

  const ThumbnailDisplay({
    super.key,
    required this.imagePath,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    // 确保值在有效范围内
    final effectiveOffsetX = offsetX.clamp(-1.0, 1.0);
    final effectiveOffsetY = offsetY.clamp(-1.0, 1.0);
    final effectiveScale = scale.clamp(1.0, 3.0);

    Widget image = Image.file(
      File(imagePath),
      fit: fit,
      width: width != null ? width! * effectiveScale : null,
      height: height != null ? height! * effectiveScale : null,
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorPlaceholder();
      },
    );

    // 应用变换
    if (effectiveOffsetX != 0.0 || effectiveOffsetY != 0.0 || effectiveScale != 1.0) {
      image = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(
            effectiveOffsetX * (width ?? 0) / 2,
            effectiveOffsetY * (height ?? 0) / 2,
          )
          ..scale(effectiveScale),
        child: image,
      );
    }

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        alignment: Alignment.center,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: image,
      ),
    );
  }

  /// 构建错误占位图
  Widget _buildErrorPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade700,
            Colors.grey.shade900,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 32,
          color: Colors.white38,
        ),
      ),
    );
  }
}
