import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../l10n/app_localizations.dart';

/// 缩略图裁剪调整结果
class ThumbnailCropResult {
  final double offsetX;
  final double offsetY;
  final double scale;

  const ThumbnailCropResult({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
  });

  @override
  String toString() =>
      'ThumbnailCropResult(offsetX: $offsetX, offsetY: $offsetY, scale: $scale)';
}

/// 缩略图裁剪调整对话框
///
/// 使用 InteractiveViewer 实现拖拽平移和缩放功能，
/// 允许用户调整图片在 EntryCard 中的显示范围。
class ThumbnailCropDialog extends StatefulWidget {
  final String imagePath;
  final double initialOffsetX;
  final double initialOffsetY;
  final double initialScale;
  final ValueChanged<ThumbnailCropResult> onConfirm;

  const ThumbnailCropDialog({
    super.key,
    required this.imagePath,
    this.initialOffsetX = 0.0,
    this.initialOffsetY = 0.0,
    this.initialScale = 1.0,
    required this.onConfirm,
  });

  @override
  State<ThumbnailCropDialog> createState() => _ThumbnailCropDialogState();
}

class _ThumbnailCropDialogState extends State<ThumbnailCropDialog> {
  late final TransformationController _controller;
  double _currentScale = 1.0;
  Size? _imageSize;

  // 预览区域比例（与 EntryCard 一致：宽度/高度）
  static const double _previewAspectRatio = 2.5; // 200 / 80

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _loadImageSize();
    _applyInitialTransform();
    _currentScale = widget.initialScale.clamp(1.0, 3.0);
  }

  /// 加载图像尺寸以计算基础缩放
  void _loadImageSize() {
    final imageProvider = FileImage(File(widget.imagePath));
    imageProvider.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool synchronousCall) {
        if (mounted) {
          setState(() {
            _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
          });
        }
      }),
    );
  }

  /// 计算基础缩放比例（让图像完整显示在容器中）
  double get _baseScale {
    if (_imageSize == null) return 1.0;

    // 容器尺寸（固定 200x80）
    const containerWidth = 200.0;
    const containerHeight = 80.0;

    // 计算让图像完整显示所需的缩放
    final scaleX = containerWidth / _imageSize!.width;
    final scaleY = containerHeight / _imageSize!.height;

    // 取较小值，确保图像完整显示（不裁剪）
    return math.min(scaleX, scaleY);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 应用初始变换值
  void _applyInitialTransform() {
    if (_imageSize == null) return;

    final matrix = _offsetScaleToMatrix(
      widget.initialOffsetX,
      widget.initialOffsetY,
      widget.initialScale,
    );
    _controller.value = matrix;
  }

  /// 将相对 offset 和 scale 转换为 Matrix4
  Matrix4 _offsetScaleToMatrix(double offsetX, double offsetY, double scale) {
    if (_imageSize == null) return Matrix4.identity();

    // 计算实际缩放（基础缩放 * 用户缩放）
    final actualScale = _baseScale * scale.clamp(1.0, 3.0);

    // 计算平移值：offset 范围是 -1.0 ~ 1.0
    // 根据容器和图片尺寸计算最大可平移距离
    const containerWidth = 200.0;
    const containerHeight = 80.0;

    final scaledImageWidth = _imageSize!.width * actualScale;
    final scaledImageHeight = _imageSize!.height * actualScale;

    final maxTranslateX = math.max(0, (scaledImageWidth - containerWidth) / 2);
    final maxTranslateY = math.max(0, (scaledImageHeight - containerHeight) / 2);

    final translationX = offsetX * maxTranslateX;
    final translationY = offsetY * maxTranslateY;

    return Matrix4.identity()
      ..translate(translationX, translationY)
      ..scale(actualScale);
  }

  /// 从 Matrix4 提取 offset 和 scale
  ThumbnailCropResult _matrixToOffsetScale() {
    if (_imageSize == null) {
      return const ThumbnailCropResult(offsetX: 0, offsetY: 0, scale: 1);
    }

    final matrix = _controller.value;

    // 提取实际缩放值
    final actualScale = matrix.getMaxScaleOnAxis();

    // 转换为用户相对缩放（实际缩放 / 基础缩放）
    final relativeScale = (actualScale / _baseScale).clamp(1.0, 3.0);

    // 提取平移值
    final translationX = matrix.getTranslation().x;
    final translationY = matrix.getTranslation().y;

    // 计算最大可平移距离
    const containerWidth = 200.0;
    const containerHeight = 80.0;

    final scaledImageWidth = _imageSize!.width * actualScale;
    final scaledImageHeight = _imageSize!.height * actualScale;

    final maxTranslateX = math.max(0, (scaledImageWidth - containerWidth) / 2);
    final maxTranslateY = math.max(0, (scaledImageHeight - containerHeight) / 2);

    // 将绝对像素值转换为相对值 (-1.0 ~ 1.0)
    final offsetX = maxTranslateX > 0
        ? (translationX / maxTranslateX).clamp(-1.0, 1.0)
        : 0.0;
    final offsetY = maxTranslateY > 0
        ? (translationY / maxTranslateY).clamp(-1.0, 1.0)
        : 0.0;

    return ThumbnailCropResult(
      offsetX: offsetX,
      offsetY: offsetY,
      scale: relativeScale,
    );
  }

  /// 处理缩放滑块变化
  void _onScaleChanged(double value) {
    if (_imageSize == null) return;

    setState(() {
      _currentScale = value;
    });

    // 计算实际缩放比例（基础缩放 * 用户缩放）
    final actualScale = _baseScale * value;

    // 获取当前平移值
    final currentMatrix = _controller.value;
    final currentTranslation = currentMatrix.getTranslation();

    // 创建新的变换矩阵，保持平移，更新缩放
    final newMatrix = Matrix4.identity()
      ..translate(currentTranslation.x, currentTranslation.y)
      ..scale(actualScale);

    _controller.value = newMatrix;
  }

  /// 重置为默认状态
  void _reset() {
    setState(() {
      _currentScale = 1.0;
    });
    _controller.value = Matrix4.identity();
  }

  /// 确认并返回结果
  void _confirm() {
    final result = _matrixToOffsetScale();

    // 应用边界约束
    final constrainedResult = _applyBoundaryConstraints(result);

    widget.onConfirm(constrainedResult);
    Navigator.of(context).pop();
  }

  /// 应用边界约束
  /// 确保图片边缘不会进入容器内部（防止空白）
  ThumbnailCropResult _applyBoundaryConstraints(ThumbnailCropResult result) {
    // 当 scale 为 1.0 时，offset 应该为 0
    if (result.scale <= 1.01) {
      return const ThumbnailCropResult(
        offsetX: 0.0,
        offsetY: 0.0,
        scale: 1.0,
      );
    }

    // 约束 offset 在有效范围内
    return ThumbnailCropResult(
      offsetX: result.offsetX.clamp(-1.0, 1.0),
      offsetY: result.offsetY.clamp(-1.0, 1.0),
      scale: result.scale.clamp(1.0, 3.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            _buildHeader(theme, l10n),

            // 调整区域
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 预览区域说明
                      _buildPreviewLabel(theme, l10n),
                      const SizedBox(height: 12),

                      // 调整区域（使用 AspectRatio 保持与 EntryCard 一致的比例）
                      _buildAdjustArea(),
                      const SizedBox(height: 16),

                      // 实时预览（显示调整后的效果）
                      _buildLivePreview(theme, l10n),
                      const SizedBox(height: 16),

                      // 缩放控制
                      _buildScaleControl(theme),
                    ],
                  ),
                ),
              ),
            ),

            // 底部按钮
            _buildFooter(theme, l10n),
          ],
        ),
      ),
    );
  }

  /// 构建标题栏
  Widget _buildHeader(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.crop_free,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            l10n.tagLibrary_adjustThumbnailTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: l10n.common_cancel,
          ),
        ],
      ),
    );
  }

  /// 构建预览标签
  Widget _buildPreviewLabel(ThemeData theme, AppLocalizations l10n) {
    return Row(
      children: [
        Icon(
          Icons.touch_app,
          size: 16,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.tagLibrary_dragToMove,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建调整区域
  Widget _buildAdjustArea() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade700,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: _previewAspectRatio,
          child: _imageSize == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
                  transformationController: _controller,
                  boundaryMargin: EdgeInsets.zero,
                  constrained: false,
                  minScale: _baseScale,
                  maxScale: _baseScale * 3.0,
                  onInteractionUpdate: (details) {
                    // 计算相对于基础缩放的缩放值
                    final actualScale = _controller.value.getMaxScaleOnAxis();
                    final relativeScale = (actualScale / _baseScale).clamp(1.0, 3.0);
                    setState(() {
                      _currentScale = relativeScale;
                    });
                  },
                  onInteractionEnd: (details) {
                    // 交互结束时确保状态同步
                    final actualScale = _controller.value.getMaxScaleOnAxis();
                    final relativeScale = (actualScale / _baseScale).clamp(1.0, 3.0);
                    setState(() {
                      _currentScale = relativeScale;
                    });
                  },
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.contain, // 使用 contain 确保完整显示
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade800,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 48,
                            color: Colors.white38,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  /// 构建实时预览
  Widget _buildLivePreview(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tagLibrary_livePreview,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 模拟 EntryCard 尺寸的预览
              Container(
                width: 200,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildPreviewImage(),
                ),
              ),
              const SizedBox(width: 16),
              // 数值显示
              Expanded(
                child: _imageSize == null
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<Matrix4>(
                        valueListenable: _controller,
                        builder: (context, matrix, child) {
                          final result = _matrixToOffsetScale();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildValueRow(
                                l10n.tagLibrary_horizontalOffset,
                                result.offsetX.toStringAsFixed(2),
                              ),
                              const SizedBox(height: 4),
                              _buildValueRow(
                                l10n.tagLibrary_verticalOffset,
                                result.offsetY.toStringAsFixed(2),
                              ),
                              const SizedBox(height: 4),
                              _buildValueRow(
                                l10n.tagLibrary_zoomRatio,
                                '${result.scale.toStringAsFixed(2)}x',
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建预览图片（应用变换）
  Widget _buildPreviewImage() {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: _controller,
      builder: (context, matrix, child) {
        final scale = matrix.getMaxScaleOnAxis();
        final translation = matrix.getTranslation();

        // 使用实际缩放比例（基础缩放 * 用户缩放）
        final effectiveScale = scale;
        final effectiveTranslationX = translation.x;
        final effectiveTranslationY = translation.y;

        return OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform(
            transform: Matrix4.identity()
              ..translate(effectiveTranslationX, effectiveTranslationY)
              ..scale(effectiveScale),
            alignment: Alignment.center,
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade800,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建数值行
  Widget _buildValueRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  /// 构建缩放控制
  Widget _buildScaleControl(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.zoom_out,
            size: 18,
            color: theme.colorScheme.outline,
          ),
          Expanded(
            child: Slider(
              value: _currentScale,
              min: 1.0,
              max: 3.0,
              divisions: 20,
              label: '${_currentScale.toStringAsFixed(2)}x',
              onChanged: _onScaleChanged,
            ),
          ),
          Icon(
            Icons.zoom_in,
            size: 18,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_currentScale.toStringAsFixed(2)}x',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部按钮
  Widget _buildFooter(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 重置按钮
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: Text(l10n.common_reset),
          ),
          const SizedBox(width: 8),
          // 取消按钮
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.common_cancel),
          ),
          const SizedBox(width: 8),
          // 确认按钮
          FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: Text(l10n.common_confirm),
          ),
        ],
      ),
    );
  }
}

/// 显示缩略图裁剪对话框的便捷方法
Future<void> showThumbnailCropDialog({
  required BuildContext context,
  required String imagePath,
  double initialOffsetX = 0.0,
  double initialOffsetY = 0.0,
  double initialScale = 1.0,
  required ValueChanged<ThumbnailCropResult> onConfirm,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => ThumbnailCropDialog(
      imagePath: imagePath,
      initialOffsetX: initialOffsetX,
      initialOffsetY: initialOffsetY,
      initialScale: initialScale,
      onConfirm: onConfirm,
    ),
  );
}
