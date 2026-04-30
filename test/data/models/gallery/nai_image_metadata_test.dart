import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'dart:convert';

void main() {
  group('NaiImageMetadata', () {
    test('displayNegativePrompt should strip UC preset prefix for detail views', () {
      final preset = UcPresets.getPresetContent(
        ImageModels.animeDiffusionV45Full,
        UcPresetType.heavy,
      );

      final metadata = NaiImageMetadata(
        negativePrompt: '$preset, custom_negative, extra_tag',
        ucPreset: 0,
        model: ImageModels.animeDiffusionV45Full,
      );

      expect(
        metadata.displayNegativePrompt,
        equals('custom_negative, extra_tag'),
      );
    });

    test('displayNegativePrompt should keep original content when no preset is active', () {
      const metadata = NaiImageMetadata(
        negativePrompt: 'plain_negative',
        ucPreset: 3,
        model: ImageModels.animeDiffusionV45Full,
      );

      expect(metadata.displayNegativePrompt, equals('plain_negative'));
    });

    test(
        'fromNaiComment should infer V4.5 Full model and heavy uc preset from raw NovelAI metadata',
        () {
      final preset = UcPresets.getPresetContent(
        ImageModels.animeDiffusionV45Full,
        UcPresetType.heavy,
      );
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'Comment': jsonEncode({
            'prompt': '1girl, sunset, very aesthetic, masterpiece, no text',
            'uc': '$preset, custom_negative',
            'seed': 1,
          }),
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        },
      );

      expect(metadata.model, equals(ImageModels.animeDiffusionV45Full));
      expect(metadata.ucPreset, equals(0));
      expect(metadata.displayNegativePrompt, equals('custom_negative'));
    });
  });
}
