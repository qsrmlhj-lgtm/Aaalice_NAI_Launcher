import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/vibe_export_utils.dart';
import 'package:nai_launcher/core/utils/vibe_image_embedder.dart';
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';

void main() {
  group('VibeExportUtils', () {
    test('collectImageCandidates should deduplicate identical carrier images', () {
      final pngBytes = _createInMemoryPngBytes();
      final entry = VibeLibraryEntry.create(
        name: 'Test',
        vibeDisplayName: 'Test Vibe',
        vibeEncoding: 'dGVzdA==',
      ).copyWith(
        rawImageData: pngBytes,
        vibeThumbnail: pngBytes,
        thumbnail: pngBytes,
      );

      final candidates = VibeExportUtils.collectImageCandidates(entry);

      expect(candidates, hasLength(1));
      expect(candidates.first.label, equals('原始图片'));
    });

    test('buildEmbeddedPngBytes should embed all selected vibes into carrier image',
        () async {
      final pngBytes = _createInMemoryPngBytes();
      const first = VibeReference(
        displayName: 'First',
        vibeEncoding: 'Zmlyc3Q=',
      );
      const second = VibeReference(
        displayName: 'Second',
        vibeEncoding: 'c2Vjb25k',
      );

      final embeddedBytes = await VibeExportUtils.buildEmbeddedPngBytes(
        vibes: const [first, second],
        carrierImageBytes: pngBytes,
      );
      final extracted =
          await VibeImageEmbedder.extractVibeFromImage(embeddedBytes);

      expect(extracted.isBundle, isTrue);
      expect(extracted.vibes, hasLength(2));
      expect(
        extracted.vibes.map((item) => item.displayName),
        containsAll(<String>['First', 'Second']),
      );
    });
  });
}

Uint8List _createInMemoryPngBytes() {
  const base64Png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6qv0YAAAAASUVORK5CYII=';
  return Uint8List.fromList(base64Decode(base64Png));
}
