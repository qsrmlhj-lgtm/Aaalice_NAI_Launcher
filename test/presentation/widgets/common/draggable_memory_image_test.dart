import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/draggable_memory_image.dart';

void main() {
  group('prepareDragImageForTransfer', () {
    test('should prefer saved file bytes when metadata is retained', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'draggable_memory_image_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.png');
      await file.writeAsBytes(const [1, 2, 3, 4]);

      final result = await prepareDragImageForTransfer(
        imageBytes: Uint8List.fromList(const [9, 9, 9]),
        fileName: 'memory.png',
        stripMetadata: false,
        sourceFilePath: file.path,
      );

      expect(result.fileName, equals('sample.png'));
      expect(result.bytes, equals(const [1, 2, 3, 4]));
    });
  });
}
