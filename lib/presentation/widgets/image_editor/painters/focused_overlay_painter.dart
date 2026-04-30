import 'package:flutter/material.dart';

/// Focused Inpaint 双框覆盖层绘制器。
///
/// 仅对 context band 与外部区域做遮罩，保持内框本身透明，
/// 避免覆盖真实蒙版笔迹。
class FocusedOverlayPainter extends CustomPainter {
  FocusedOverlayPainter({
    required this.contextPath,
    this.focusPath,
    super.repaint,
  });

  final Path contextPath;
  final Path? focusPath;

  @override
  void paint(Canvas canvas, Size size) {
    final outsideContextPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      contextPath,
    );

    canvas.drawPath(
      outsideContextPath,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    if (focusPath != null) {
      final contextBandPath = Path.combine(
        PathOperation.difference,
        contextPath,
        focusPath!,
      );
      canvas.drawPath(
        contextBandPath,
        Paint()..color = Colors.black.withValues(alpha: 0.24),
      );
    }

    canvas.drawPath(
      contextPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3F332F).withValues(alpha: 0.9),
    );

    if (focusPath != null) {
      canvas.drawPath(
        focusPath!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF67D4FF).withValues(alpha: 0.95),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FocusedOverlayPainter oldDelegate) => true;
}
