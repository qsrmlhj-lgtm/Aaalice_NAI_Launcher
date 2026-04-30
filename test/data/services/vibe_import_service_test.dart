import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';
import 'package:nai_launcher/data/services/vibe_file_storage_service.dart';
import 'package:nai_launcher/data/services/vibe_import_service.dart';

class _FakeVibeLibraryImportRepository implements VibeLibraryImportRepository {
  final List<VibeLibraryEntry> savedEntries = <VibeLibraryEntry>[];
  int getAllEntriesCalls = 0;
  int findEntryByNameCalls = 0;

  @override
  Future<List<VibeLibraryEntry>> getAllEntries() async {
    getAllEntriesCalls++;
    return savedEntries;
  }

  @override
  Future<VibeLibraryEntry?> findEntryByName(String name) async {
    findEntryByNameCalls++;
    final normalized = name.trim().toLowerCase();
    for (final entry in savedEntries) {
      if (entry.name.trim().toLowerCase() == normalized) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<VibeLibraryEntry> saveEntry(VibeLibraryEntry entry) async {
    savedEntries.add(entry);
    return entry;
  }
}

void main() {
  group('VibeImportService.importFromImage', () {
    test('should import jpg images as raw-image vibes instead of failing',
        () async {
      final repository = _FakeVibeLibraryImportRepository();
      final service = VibeImportService(repository: repository);
      final image = img.Image(width: 4, height: 4);
      final jpgBytes = Uint8List.fromList(img.encodeJpg(image));

      final result = await service.importFromImage(
        images: const <VibeImageImportItem>[].followedBy([
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
      expect(repository.getAllEntriesCalls, 0);
      expect(repository.findEntryByNameCalls, greaterThan(0));
    });
  });

  group('VibeFileStorageService.extractVibesFromBundle', () {
    test('returns the requested child vibe range from a bundle file', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'vibe_bundle_extract_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> bundleItem(
        String name,
        String encoding,
        double strength,
      ) {
        return {
          'name': name,
          'encodings': {
            'nai-diffusion-4-full': {
              'vibe': {'encoding': encoding},
            },
          },
          'importInfo': {
            'strength': strength,
            'information_extracted': 0.5,
          },
        };
      }

      final bundleFile = File('${tempDir.path}/batch.naiv4vibebundle');
      await bundleFile.writeAsString(
        jsonEncode({
          'identifier': 'novelai-vibe-transfer-bundle',
          'version': 1,
          'vibes': [
            bundleItem('First', 'first-encoded', 0.1),
            bundleItem('Second', 'second-encoded', 0.2),
            bundleItem('Third', 'third-encoded', 0.3),
          ],
        }),
      );

      final service = VibeFileStorageService();

      final references = await service.extractVibesFromBundle(
        bundleFile.path,
        startIndex: 1,
        limit: 2,
      );

      expect(references.map((item) => item.displayName), [
        'Second',
        'Third',
      ]);
      expect(references.map((item) => item.vibeEncoding), [
        'second-encoded',
        'third-encoded',
      ]);
    });
  });
}
