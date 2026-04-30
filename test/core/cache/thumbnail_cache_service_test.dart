import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/cache/thumbnail_cache_service.dart';

void main() {
  group('ThumbnailCacheService thumbnail filename helpers', () {
    test('应能从 Windows 混合分隔符路径中提取正确文件名', () {
      expect(
        ThumbnailCacheService.extractOriginalFileNameForTest(
          r'G:\AIdarw\novelai/NAI_1775993430335.png',
        ),
        'NAI_1775993430335.png',
      );
    });

    test('应为混合分隔符路径生成稳定缩略图文件名', () {
      expect(
        ThumbnailCacheService.buildThumbnailFileNameForTest(
          r'G:\AIdarw\novelai/NAI_1775993430335.png',
          size: ThumbnailSize.small,
        ),
        'NAI_1775993430335.small.thumb.jpg',
      );
    });

    test('直接生成缩略图后并发计数应恢复到调用前状态', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nai_launcher_thumbnail_counter_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final imageFile = File('${tempDir.path}${Platform.pathSeparator}a.png');
      await imageFile.writeAsBytes(
        img.encodePng(img.Image(width: 32, height: 32)),
      );

      final service = ThumbnailCacheService.instance;
      await service.init();
      final activeBefore = service.getStats()['activeGenerations'] as int;

      final thumbnailPath = await service.generateThumbnail(
        imageFile.path,
        size: ThumbnailSize.small,
      );

      expect(thumbnailPath, isNotNull);
      expect(await File(thumbnailPath!).exists(), isTrue);
      expect(service.getStats()['activeGenerations'], activeBefore);
    });
  });
}
