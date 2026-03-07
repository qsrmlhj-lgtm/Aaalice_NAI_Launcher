import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../core/utils/drag_drop_utils.dart';
import '../../../data/models/gallery/local_image_record.dart';

/// 可拖拽图像卡片组件
///
/// 基于 super_drag_and_drop 实现，支持将本地图像拖拽到其他应用
/// 支持 PNG 图像数据和文件 URI 格式
class DraggableImageCard extends StatefulWidget {
  /// 图像记录数据
  final LocalImageRecord record;

  /// 子组件（实际的卡片 UI）
  final Widget child;

  /// 是否启用拖拽功能
  final bool enabled;

  /// 可选的预览图像数据（字节）
  final Uint8List? previewBytes;

  /// 是否启用拖拽反馈预览
  final bool enableFeedback;

  /// 拖拽预览宽度
  final double feedbackWidth;

  /// 拖拽提示文字
  final String? feedbackHint;

  /// 拖拽时原位置组件的透明度
  final double dragOpacity;

  const DraggableImageCard({
    super.key,
    required this.record,
    required this.child,
    this.enabled = true,
    this.previewBytes,
    this.enableFeedback = true,
    this.feedbackWidth = 280,
    this.feedbackHint,
    this.dragOpacity = 0.3,
  });

  @override
  State<DraggableImageCard> createState() => _DraggableImageCardState();

  /// 创建拖拽包装器函数
  static Widget Function(Widget child) createDragWrapper({
    required BuildContext context,
    required LocalImageRecord record,
    Uint8List? previewBytes,
    bool enableFeedback = true,
    double feedbackWidth = 280,
    String? feedbackHint,
    double dragOpacity = 0.3,
  }) {
    return (Widget child) {
      return _DragWrapper(
        record: record,
        previewBytes: previewBytes,
        feedbackWidth: feedbackWidth,
        feedbackHint: feedbackHint,
        enableFeedback: enableFeedback,
        dragOpacity: dragOpacity,
        child: child,
      );
    };
  }
}

class _DraggableImageCardState extends State<DraggableImageCard> {
  bool _isDragging = false;
  Uint8List? _imageBytes;
  ImageProvider? _previewProvider;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    // 如果提供了预览数据，直接使用
    if (widget.previewBytes != null) {
      _setPreviewBytes(widget.previewBytes!);
      return;
    }

    // 异步加载图片
    if (widget.record.path.isNotEmpty) {
      try {
        final file = File(widget.record.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (mounted) {
            _setPreviewBytes(bytes);
          }
        }
      } catch (e) {
        debugPrint('Failed to load image: $e');
      }
    }
  }

  void _setPreviewBytes(Uint8List bytes) {
    final provider = MemoryImage(bytes);
    setState(() {
      _imageBytes = bytes;
      _previewProvider = provider;
    });
    precacheImage(provider, context);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Listener(
      onPointerDown: (_) {
        setState(() => _isDragging = true);
      },
      onPointerUp: (_) {
        setState(() => _isDragging = false);
      },
      onPointerCancel: (_) {
        setState(() => _isDragging = false);
      },
      child: DragItemWidget(
        allowedOperations: () => [DropOperation.copy],
        dragItemProvider: (request) => _createDragItem(),
        // 关键修复：每次调用时动态构建，确保使用最新的 _imageBytes
        liftBuilder: widget.enableFeedback
            ? (context, child) {
                final theme = Theme.of(context);
                final dragData = ImageDragData.fromRecord(
                  widget.record,
                  previewBytes: _imageBytes,
                );
                return buildImageDragFeedback(
                  theme,
                  dragData,
                  width: widget.feedbackWidth,
                  hintText: widget.feedbackHint ?? '拖拽以分享',
                  previewProvider: _previewProvider,
                );
              }
            : null,
        dragBuilder: widget.enableFeedback
            ? (context, child) {
                final theme = Theme.of(context);
                final dragData = ImageDragData.fromRecord(
                  widget.record,
                  previewBytes: _imageBytes,
                );
                return buildImageDragFeedback(
                  theme,
                  dragData,
                  width: widget.feedbackWidth,
                  hintText: widget.feedbackHint ?? '拖拽以分享',
                  previewProvider: _previewProvider,
                );
              }
            : null,
        child: DraggableWidget(
          child: Opacity(
            opacity: _isDragging ? widget.dragOpacity : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Future<DragItem> _createDragItem() async {
    final fileName = widget.record.path.split(RegExp(r'[/\\]')).last;
    final filePath = widget.record.path;
    final extension = fileName.toLowerCase().split('.').last;
    Uint8List? dragBytes = _imageBytes;

    // 首次拖拽时 _imageBytes 可能尚未异步加载完成，这里做一次同步兜底读取
    if (dragBytes == null && extension == 'png' && filePath.isNotEmpty) {
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          dragBytes = file.readAsBytesSync();
          if (mounted) {
            _setPreviewBytes(dragBytes);
          }
        }
      } catch (e) {
        debugPrint('Failed to read image bytes for drag: $e');
      }
    }

    final item = DragItem(
      suggestedName: fileName,
      localData: {'source': 'gallery_internal', 'path': filePath},
    );

    // 添加 PNG 格式数据
    if (extension == 'png' && dragBytes != null) {
      item.add(Formats.png(dragBytes));
    }

    // 添加文件 URI 格式
    try {
      final uri = Uri.file(filePath);
      item.add(Formats.fileUri(uri));
    } catch (e) {
      debugPrint('Failed to create file URI for drag: $e');
    }

    return item;
  }
}

/// 内部拖拽包装组件
class _DragWrapper extends StatefulWidget {
  final LocalImageRecord record;
  final Uint8List? previewBytes;
  final double feedbackWidth;
  final String? feedbackHint;
  final bool enableFeedback;
  final double dragOpacity;
  final Widget child;

  const _DragWrapper({
    required this.record,
    required this.previewBytes,
    required this.feedbackWidth,
    required this.feedbackHint,
    required this.enableFeedback,
    required this.dragOpacity,
    required this.child,
  });

  @override
  State<_DragWrapper> createState() => _DragWrapperState();
}

class _DragWrapperState extends State<_DragWrapper> {
  bool _isDragging = false;
  Uint8List? _imageBytes;
  ImageProvider? _previewProvider;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (widget.previewBytes != null) {
      _setPreviewBytes(widget.previewBytes!);
      return;
    }

    if (widget.record.path.isNotEmpty) {
      try {
        final file = File(widget.record.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (mounted) {
            _setPreviewBytes(bytes);
          }
        }
      } catch (e) {
        debugPrint('Failed to load image: $e');
      }
    }
  }

  void _setPreviewBytes(Uint8List bytes) {
    final provider = MemoryImage(bytes);
    setState(() {
      _imageBytes = bytes;
      _previewProvider = provider;
    });
    precacheImage(provider, context);
  }

  Future<DragItem> _createDragItem() async {
    final fileName = widget.record.path.split(RegExp(r'[/\\]')).last;
    final filePath = widget.record.path;
    final extension = fileName.toLowerCase().split('.').last;
    Uint8List? dragBytes = _imageBytes;

    // 首次拖拽时 _imageBytes 可能尚未异步加载完成，这里做一次同步兜底读取
    if (dragBytes == null && extension == 'png' && filePath.isNotEmpty) {
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          dragBytes = file.readAsBytesSync();
          if (mounted) {
            _setPreviewBytes(dragBytes);
          }
        }
      } catch (e) {
        debugPrint('Failed to read image bytes for drag: $e');
      }
    }

    final item = DragItem(
      suggestedName: fileName,
      localData: {'source': 'gallery_internal', 'path': filePath},
    );

    // 添加 PNG 格式数据
    if (extension == 'png' && dragBytes != null) {
      item.add(Formats.png(dragBytes));
    }

    // 添加文件 URI 格式
    try {
      final uri = Uri.file(filePath);
      item.add(Formats.fileUri(uri));
    } catch (e) {
      debugPrint('Failed to create file URI for drag: $e');
    }

    return item;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        setState(() => _isDragging = true);
      },
      onPointerUp: (_) {
        setState(() => _isDragging = false);
      },
      onPointerCancel: (_) {
        setState(() => _isDragging = false);
      },
      child: DragItemWidget(
        allowedOperations: () => [DropOperation.copy],
        dragItemProvider: (request) => _createDragItem(),
        // 关键修复：每次调用时动态构建，确保使用最新的 _imageBytes
        liftBuilder: widget.enableFeedback
            ? (context, child) {
                final theme = Theme.of(context);
                final dragData = ImageDragData.fromRecord(
                  widget.record,
                  previewBytes: _imageBytes,
                );
                return buildImageDragFeedback(
                  theme,
                  dragData,
                  width: widget.feedbackWidth,
                  hintText: widget.feedbackHint ?? '拖拽以分享',
                  previewProvider: _previewProvider,
                );
              }
            : null,
        dragBuilder: widget.enableFeedback
            ? (context, child) {
                final theme = Theme.of(context);
                final dragData = ImageDragData.fromRecord(
                  widget.record,
                  previewBytes: _imageBytes,
                );
                return buildImageDragFeedback(
                  theme,
                  dragData,
                  width: widget.feedbackWidth,
                  hintText: widget.feedbackHint ?? '拖拽以分享',
                  previewProvider: _previewProvider,
                );
              }
            : null,
        child: DraggableWidget(
          child: Opacity(
            opacity: _isDragging ? widget.dragOpacity : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
