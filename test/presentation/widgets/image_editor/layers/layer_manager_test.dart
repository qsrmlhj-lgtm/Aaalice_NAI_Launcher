import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/inpaint_mask_utils.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/history_manager.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/layers/layer_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reopened mask layer should remain visible above source and show new strokes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layerManager = LayerManager();
      layerManager.addLayer(name: '图层 1');

      final sourceLayer = await layerManager.addLayerFromImage(
        _buildSolidPng(64, 64, const Color(0xFFAA3322)),
        name: '底图',
      );

      expect(sourceLayer, isNotNull);

      final existingMask = _buildMaskPng(
        width: 64,
        height: 64,
        rect: const Rect.fromLTWH(18, 18, 28, 28),
      );
      final overlayBytes = InpaintMaskUtils.maskToEditorOverlay(
        existingMask,
        overlayAlpha: 255,
      );

      final maskLayer = await layerManager.addLayerFromImage(
        overlayBytes,
        name: '已有蒙版',
        index: layerManager.layers.indexOf(sourceLayer!),
      );

      expect(maskLayer, isNotNull);

      layerManager.addStrokeToLayer(
        maskLayer!.id,
        StrokeData(
          points: const [
            Offset(20, 32),
            Offset(44, 32),
          ],
          size: 8,
          color: Colors.green,
          opacity: 1,
          hardness: 1,
        ),
      );

      final merged = await layerManager.exportMergedImage(const Size(64, 64));
      final bytes = await merged.toByteData(format: ui.ImageByteFormat.png);
      final decoded = img.decodePng(
        Uint8List.fromList(bytes!.buffer.asUint8List()),
      )!;

      final overlayPixel = decoded.getPixel(24, 24);
      expect(overlayPixel.g.toInt(), equals(170));
      expect(overlayPixel.b.toInt(), equals(255));

      final strokePixel = decoded.getPixel(32, 32);
      expect(strokePixel.g.toInt(), greaterThan(170));
      expect(strokePixel.r.toInt(), lessThan(120));

      merged.dispose();
      layerManager.dispose();
    });
  });
}

Uint8List _buildSolidPng(int width, int height, Color color) {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgba8(
      (color.r * 255).round().clamp(0, 255),
      (color.g * 255).round().clamp(0, 255),
      (color.b * 255).round().clamp(0, 255),
      (color.a * 255).round().clamp(0, 255),
    ),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _buildMaskPng({
  required int width,
  required int height,
  required Rect rect,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 255));
  img.fillRect(
    image,
    x1: rect.left.round(),
    y1: rect.top.round(),
    x2: rect.right.round() - 1,
    y2: rect.bottom.round() - 1,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}
