import 'package:flutter_test/flutter_test.dart';
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
  });
}
