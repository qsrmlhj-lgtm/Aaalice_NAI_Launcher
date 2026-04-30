import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';
import 'package:nai_launcher/data/services/vibe_import_service.dart';

class _FakeVibeLibraryImportRepository implements VibeLibraryImportRepository {
  final List<VibeLibraryEntry> savedEntries = <VibeLibraryEntry>[];

  @override
  Future<List<VibeLibraryEntry>> getAllEntries() async => savedEntries;

  @override
  Future<VibeLibraryEntry> saveEntry(VibeLibraryEntry entry) async {
    savedEntries.add(entry);
    return entry;
  }
}

void main() {
  group('VibeImportService.importFromImage', () {
    test('should import jpg images as raw-image vibes instead of failing', () async {
      final repository = _FakeVibeLibraryImportRepository();
      final service = VibeImportService(repository: repository);
      final image = img.Image(width: 4, height: 4);
      final jpgBytes = Uint8List.fromList(img.encodeJpg(image));

      final result = await service.importFromImage(
        images: const <VibeImageImportItem>[] .followedBy([
          VibeImageImportItem(
            source: 'sample.jpg',
            bytes: jpgBytes,
          ),
        ]).toList(),
      );

      expect(result.successCount, 1);
      expect(result.failCount, 0);
      expect(repository.savedEntries, hasLength(1));
      expect(
        repository.savedEntries.single.sourceType,
        equals(VibeSourceType.rawImage),
      );
      expect(
        repository.savedEntries.single.rawImageData,
        isNotEmpty,
      );
    });
  });
}
