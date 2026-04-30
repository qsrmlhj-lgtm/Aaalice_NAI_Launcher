import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/presentation/widgets/image_editor/painters/focused_overlay_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FocusedOverlayPainter should keep focus interior clear', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = Colors.white,
      );

      FocusedOverlayPainter(
        contextPath: Path()..addRect(const Rect.fromLTWH(10, 10, 80, 80)),
        focusPath: Path()..addRect(const Rect.fromLTWH(30, 30, 40, 40)),
      ).paint(canvas, const Size(100, 100));

      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      final decoded = img.decodePng(
        Uint8List.fromList(bytes!.buffer.asUint8List()),
      )!;

      expect(decoded.getPixel(50, 50).r.toInt(), equals(255));
      expect(decoded.getPixel(20, 20).r.toInt(), lessThan(255));
    });
  });
}
