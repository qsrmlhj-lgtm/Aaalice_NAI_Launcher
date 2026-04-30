import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../core/utils/drag_drop_utils.dart';
import '../../../core/utils/image_share_sanitizer.dart';
import '../../../data/models/gallery/local_image_record.dart';
import '../../providers/share_image_settings_provider.dart';

class DraggableMemoryImage extends ConsumerStatefulWidget {
  const DraggableMemoryImage({
    super.key,
    required this.imageBytes,
    required this.child,
    this.fileName = 'history.png',
    this.sourceFilePath,
    this.enabled = true,
    this.feedbackHint,
    this.feedbackWidth = 280,
    this.dragOpacity = 0.3,
  });

  final Uint8List imageBytes;
  final Widget child;
  final String fileName;
  final String? sourceFilePath;
  final bool enabled;
  final String? feedbackHint;
  final double feedbackWidth;
  final double dragOpacity;

  @override
  ConsumerState<DraggableMemoryImage> createState() =>
      _DraggableMemoryImageState();
}

class _DraggableMemoryImageState extends ConsumerState<DraggableMemoryImage> {
  bool _isDragging = false;
  late ImageProvider _previewProvider;

  @override
  void initState() {
    super.initState();
    _previewProvider = MemoryImage(widget.imageBytes);
  }

  @override
  void didUpdateWidget(covariant DraggableMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _previewProvider = MemoryImage(widget.imageBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final dragData = ImageDragData(
      record: LocalImageRecord(
        path: widget.fileName,
        size: widget.imageBytes.length,
        modifiedAt: DateTime.now(),
      ),
      previewBytes: widget.imageBytes,
    );

    return Listener(
      onPointerDown: (_) => setState(() => _isDragging = true),
      onPointerUp: (_) => setState(() => _isDragging = false),
      onPointerCancel: (_) => setState(() => _isDragging = false),
      child: DragItemWidget(
        allowedOperations: () => [DropOperation.copy],
        dragItemProvider: (_) => _createDragItem(),
        liftBuilder: (context, child) => buildImageDragFeedback(
          Theme.of(context),
          dragData,
          width: widget.feedbackWidth,
          hintText: widget.feedbackHint ?? '拖拽到图生图或其他区域',
          previewProvider: _previewProvider,
        ),
        dragBuilder: (context, child) => buildImageDragFeedback(
          Theme.of(context),
          dragData,
          width: widget.feedbackWidth,
          hintText: widget.feedbackHint ?? '拖拽到图生图或其他区域',
          previewProvider: _previewProvider,
        ),
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
    final stripMetadata = ref
        .read(shareImageSettingsProvider)
        .stripMetadataForCopyAndDrag;
    final image = await prepareDragImageForTransfer(
      imageBytes: widget.imageBytes,
      fileName: widget.fileName,
      stripMetadata: stripMetadata,
      sourceFilePath: widget.sourceFilePath,
    );

    final item = DragItem(
      suggestedName: image.fileName,
      localData: {'source': 'history_internal'},
    );
    item.add(Formats.png(image.bytes));
    final tempFile = await ImageShareSanitizer.writeTempShareFile(image);
    item.add(Formats.fileUri(tempFile.uri));
    return item;
  }
}

Future<SanitizedShareImage> prepareDragImageForTransfer({
  required Uint8List imageBytes,
  required String fileName,
  required bool stripMetadata,
  String? sourceFilePath,
}) async {
  if (stripMetadata) {
    return ImageShareSanitizer.sanitizeForShare(
      imageBytes,
      fileName: fileName,
    );
  }

  final normalizedSourceFilePath = sourceFilePath?.trim();
  if (normalizedSourceFilePath != null && normalizedSourceFilePath.isNotEmpty) {
    final sourceFile = File(normalizedSourceFilePath);
    if (await sourceFile.exists()) {
      return SanitizedShareImage(
        bytes: await sourceFile.readAsBytes(),
        fileName: p.basename(normalizedSourceFilePath),
        mimeType: 'image/png',
      );
    }
  }

  return SanitizedShareImage(
    bytes: imageBytes,
    fileName: fileName,
    mimeType: 'image/png',
  );
}
