import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/inpaint_mask_utils.dart';

void main() {
  group('InpaintMaskUtils', () {
    test('normalizeMaskBytes should output an opaque black white mask', () {
      final source = img.Image(width: 2, height: 1);
      source.setPixelRgba(0, 0, 0, 0, 0, 255);
      source.setPixelRgba(1, 0, 80, 180, 255, 96);

      final result = InpaintMaskUtils.normalizeMaskBytes(
        Uint8List.fromList(img.encodePng(source)),
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(0, 0).r.toInt(), equals(0));
      expect(decoded.getPixel(0, 0).g.toInt(), equals(0));
      expect(decoded.getPixel(0, 0).b.toInt(), equals(0));
      expect(decoded.getPixel(0, 0).a.toInt(), equals(255));

      expect(decoded.getPixel(1, 0).r.toInt(), equals(255));
      expect(decoded.getPixel(1, 0).g.toInt(), equals(255));
      expect(decoded.getPixel(1, 0).b.toInt(), equals(255));
      expect(decoded.getPixel(1, 0).a.toInt(), equals(255));
    });

    test(
        'maskToEditorOverlay should remove black background and keep mask visible',
        () {
      final source = img.Image(width: 2, height: 1);
      source.setPixelRgba(0, 0, 0, 0, 0, 255);
      source.setPixelRgba(1, 0, 255, 255, 255, 255);

      final result = InpaintMaskUtils.maskToEditorOverlay(
        Uint8List.fromList(img.encodePng(source)),
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(0, 0).a.toInt(), equals(0));
      expect(decoded.getPixel(1, 0).a.toInt(), greaterThan(0));
    });

    test('prepareInpaintMaskBytes should close pinholes and expand mask edges',
        () {
      final source = img.Image(width: 7, height: 7);
      for (var y = 2; y <= 4; y++) {
        for (var x = 2; x <= 4; x++) {
          source.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
      source.setPixelRgba(3, 3, 0, 0, 0, 255);

      final result = InpaintMaskUtils.prepareInpaintMaskBytes(
        Uint8List.fromList(img.encodePng(source)),
        closingIterations: 1,
        expansionIterations: 1,
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(3, 3).r.toInt(), equals(255));
      expect(decoded.getPixel(1, 3).r.toInt(), equals(255));
      expect(decoded.getPixel(0, 0).r.toInt(), equals(0));
    });

    test(
        'prepareRequestMaskBytes should align v4 inpaint masks to the latent 8px grid',
        () {
      final source = img.Image(width: 16, height: 16);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
      for (var y = 10; y <= 13; y++) {
        for (var x = 10; x <= 13; x++) {
          source.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }

      final result = InpaintMaskUtils.prepareRequestMaskBytes(
        Uint8List.fromList(img.encodePng(source)),
        alignToLatentGrid: true,
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(8, 8).r.toInt(), equals(255));
      expect(decoded.getPixel(15, 15).r.toInt(), equals(255));
      expect(decoded.getPixel(7, 9).r.toInt(), equals(0));
      expect(decoded.getPixel(9, 7).r.toInt(), equals(0));
    });

    test('fillClosedMaskRegions should fill enclosed transparent holes', () {
      final source = img.Image(width: 24, height: 24);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
      img.drawRect(
        source,
        x1: 4,
        y1: 4,
        x2: 19,
        y2: 19,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      final result = InpaintMaskUtils.fillClosedMaskRegions(
        Uint8List.fromList(img.encodePng(source)),
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(12, 12).r.toInt(), equals(255));
      expect(decoded.getPixel(2, 2).r.toInt(), equals(0));
    });

    test('fillClosedMaskRegions should keep open contours unfilled', () {
      final source = img.Image(width: 24, height: 24);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
      img.drawRect(
        source,
        x1: 4,
        y1: 4,
        x2: 19,
        y2: 19,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      for (var y = 10; y <= 13; y++) {
        source.setPixelRgba(4, y, 0, 0, 0, 255);
      }

      final result = InpaintMaskUtils.fillClosedMaskRegions(
        Uint8List.fromList(img.encodePng(source)),
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(12, 12).r.toInt(), equals(0));
    });

    test('fillMaskRegionAtPoint should fill only the clicked closed region', () {
      final source = img.Image(width: 32, height: 24);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
      img.drawRect(
        source,
        x1: 2,
        y1: 4,
        x2: 12,
        y2: 18,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      img.drawRect(
        source,
        x1: 18,
        y1: 4,
        x2: 28,
        y2: 18,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      final result = InpaintMaskUtils.fillMaskRegionAtPoint(
        Uint8List.fromList(img.encodePng(source)),
        x: 7,
        y: 11,
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(7, 11).r.toInt(), equals(255));
      expect(decoded.getPixel(23, 11).r.toInt(), equals(0));
    });

    test('fillMaskRegionAtPoint should keep open regions unchanged', () {
      final source = img.Image(width: 24, height: 24);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
      img.drawRect(
        source,
        x1: 4,
        y1: 4,
        x2: 19,
        y2: 19,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      for (var y = 10; y <= 13; y++) {
        source.setPixelRgba(4, y, 0, 0, 0, 255);
      }

      final result = InpaintMaskUtils.fillMaskRegionAtPoint(
        Uint8List.fromList(img.encodePng(source)),
        x: 12,
        y: 12,
      );
      final decoded = img.decodeImage(result)!;

      expect(decoded.getPixel(12, 12).r.toInt(), equals(0));
    });

    test('extractFilledMaskDelta should only keep newly filled regions', () {
      final source = img.Image(width: 24, height: 24);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 255));
      img.drawRect(
        source,
        x1: 4,
        y1: 4,
        x2: 19,
        y2: 19,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      final originalBytes = Uint8List.fromList(img.encodePng(source));
      final filledBytes = InpaintMaskUtils.fillClosedMaskRegions(originalBytes);
      final deltaBytes = InpaintMaskUtils.extractFilledMaskDelta(
        originalBytes,
        filledBytes,
      );
      final decoded = img.decodeImage(deltaBytes)!;

      expect(decoded.getPixel(12, 12).r.toInt(), equals(255));
      expect(decoded.getPixel(4, 4).r.toInt(), equals(0));
      expect(decoded.getPixel(2, 2).r.toInt(), equals(0));
    });
  });
}
