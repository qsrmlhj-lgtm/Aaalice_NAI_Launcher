import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/editor_state.dart';
import 'base_selection_tool.dart';

/// 套索选区工具（自由选区）
class LassoSelectionTool extends BaseSelectionTool {
  final List<Offset> _points = [];

  bool _isDraggingSelection = false;
  Offset? _dragLastPoint;

  @override
  String get id => 'lasso_selection';

  @override
  String get name => '套索选区';

  @override
  IconData get icon => Icons.gesture;

  @override
  LogicalKeyboardKey get shortcutKey => LogicalKeyboardKey.keyL;

  @override
  String? get helpText => '按住鼠标拖动绘制自由形状选区，松开自动闭合';

  @override
  void onPointerDown(PointerDownEvent event, EditorState state) {
    final pos = event.localPosition;

    if (state.selectionManager.isTransforming) {
      final bounds = state.selectionManager.transformedBounds;
      if (bounds != null && bounds.contains(pos)) {
        _isDraggingSelection = true;
        _dragLastPoint = pos;
        return;
      }
      state.selectionManager.commitTransform();
    }

    if (state.selectionManager.hasSelection &&
        state.selectionManager.hitTestSelection(pos)) {
      state.selectionManager.enterTransform(_createPlaceholderImage());
      _isDraggingSelection = true;
      _dragLastPoint = pos;
      return;
    }

    state.clearSelection(saveHistory: false);
    state.clearPreview();
    _points.clear();
    _points.add(pos);
    _updatePreviewPath(state);
  }

  @override
  void onPointerMove(PointerMoveEvent event, EditorState state) {
    if (_isDraggingSelection && _dragLastPoint != null) {
      final delta = event.localPosition - _dragLastPoint!;
      state.selectionManager.updateTransformOffset(delta);
      _dragLastPoint = event.localPosition;
      return;
    }

    if (_points.isNotEmpty) {
      final point = event.localPosition;
      if (_points.isEmpty || (_points.last - point).distance > 3) {
        _points.add(point);
        _updatePreviewPath(state);
      }
    }
  }

  @override
  void onPointerUp(PointerUpEvent event, EditorState state) {
    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      _dragLastPoint = null;
      return;
    }

    if (_points.length >= 3) {
      final path = _createPath();
      path.close();
      state.setSelection(path);
    } else {
      state.clearPreview();
    }
    _points.clear();
  }

  @override
  void onSelectionCancel() {
    _points.clear();
    _isDraggingSelection = false;
    _dragLastPoint = null;
  }

  static ui.Image _createPlaceholderImage() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPaint(Paint()..color = const Color(0x00000000));
    final picture = recorder.endRecording();
    return picture.toImageSync(1, 1);
  }

  void _updatePreviewPath(EditorState state) {
    if (_points.length < 2) {
      state.setPreviewPath(null);
      return;
    }

    final path = _createPath();
    path.lineTo(_points.first.dx, _points.first.dy);
    state.setPreviewPath(path);
  }

  Path _createPath() {
    final path = Path();
    if (_points.isEmpty) return path;

    path.moveTo(_points.first.dx, _points.first.dy);

    if (_points.length <= 2) {
      for (int i = 1; i < _points.length; i++) {
        path.lineTo(_points[i].dx, _points[i].dy);
      }
    } else {
      for (int i = 1; i < _points.length - 1; i++) {
        final p0 = _points[i];
        final p1 = _points[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;
        path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
      }
      path.lineTo(_points.last.dx, _points.last.dy);
    }

    return path;
  }
}
