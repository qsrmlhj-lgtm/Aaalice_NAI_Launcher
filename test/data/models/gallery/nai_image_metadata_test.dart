import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/enums/precise_ref_type.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'dart:convert';

void main() {
  group('NaiImageMetadata', () {
    test('displayNegativePrompt should mirror embedded raw uc text', () {
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
        equals('$preset, custom_negative, extra_tag'),
      );
    });

    test(
        'displayNegativePrompt should keep original content when no preset is active',
        () {
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
      expect(
        metadata.displayNegativePrompt,
        equals('$preset, custom_negative'),
      );
    });

    test('fromNaiComment should parse NovelAI Vibe array metadata', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'Comment': jsonEncode({
            'prompt': '1girl',
            'uc': 'bad hands',
            'reference_image_multiple': ['encoded-vibe-a', 'encoded-vibe-b'],
            'reference_strength_multiple': [0.35, -0.25],
            'reference_information_extracted_multiple': [0.4, 0.85],
          }),
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        },
      );

      expect(metadata.vibeReferences, hasLength(2));
      expect(metadata.vibeReferences[0].vibeEncoding, 'encoded-vibe-a');
      expect(metadata.vibeReferences[0].strength, 0.35);
      expect(metadata.vibeReferences[0].infoExtracted, 0.4);
      expect(metadata.vibeReferences[1].vibeEncoding, 'encoded-vibe-b');
      expect(metadata.vibeReferences[1].strength, -0.25);
      expect(metadata.vibeReferences[1].infoExtracted, 0.85);
    });

    test('fromNaiComment should parse Variety+ metadata', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'Comment': jsonEncode({
            'prompt': '1girl',
            'uc': 'bad hands',
            'variety_plus': true,
          }),
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        },
      );

      expect(metadata.varietyPlus, isTrue);
    });

    test('fromNaiComment should infer Variety+ from skip cfg metadata', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'Comment': jsonEncode({
            'prompt': '1girl',
            'uc': 'bad hands',
            'skip_cfg_above_sigma': 58.0,
          }),
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        },
      );

      expect(metadata.varietyPlus, isTrue);
    });

    test('fromNaiComment should parse legacy Vibe reference shapes', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'Comment': jsonEncode({
            'prompt': '1girl',
            'uc': 'bad hands',
            'reference_image': 'single-encoded-vibe',
            'reference_strength': 0.25,
            'reference_information_extracted': 0.45,
            'vibeReferences': [
              {
                'displayName': 'old app vibe',
                'vibeEncoding': 'app-encoded-vibe',
                'strength': 0.55,
                'infoExtracted': 0.65,
              },
            ],
          }),
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        },
      );

      expect(metadata.vibeReferences, hasLength(2));
      expect(metadata.vibeReferences[0].vibeEncoding, 'single-encoded-vibe');
      expect(metadata.vibeReferences[0].strength, 0.25);
      expect(metadata.vibeReferences[0].infoExtracted, 0.45);
      expect(metadata.vibeReferences[1].displayName, 'old app vibe');
      expect(metadata.vibeReferences[1].vibeEncoding, 'app-encoded-vibe');
      expect(metadata.vibeReferences[1].strength, 0.55);
      expect(metadata.vibeReferences[1].infoExtracted, 0.65);
    });

    test('cached rawJson metadata should upgrade Vibe and Variety+ fields', () {
      final rawJson = jsonEncode({
        'prompt': '1girl',
        'uc': 'bad hands',
        'reference_image_multiple': ['cached-encoded-vibe'],
        'reference_strength_multiple': [0.35],
        'reference_information_extracted_multiple': [0.6],
        'skip_cfg_above_sigma': 58.0,
      });
      final stale = NaiImageMetadata(
        prompt: '1girl',
        negativePrompt: 'bad hands',
        rawJson: rawJson,
        software: 'NovelAI',
        source: 'NovelAI Diffusion V4.5 4BDE2A90',
      );

      final upgraded = stale.upgradeFromRawJsonIfNeeded();

      expect(upgraded.vibeReferences, hasLength(1));
      expect(
        upgraded.vibeReferences.single.vibeEncoding,
        'cached-encoded-vibe',
      );
      expect(upgraded.varietyPlus, isTrue);
    });

    test('fromNaiComment should parse precise reference metadata', () {
      final referenceImage = base64Encode([1, 2, 3, 4]);
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'Comment': jsonEncode({
            'prompt': '1girl',
            'uc': 'bad hands',
            'director_reference_images': [referenceImage],
            'director_reference_descriptions': [
              {
                'caption': {
                  'base_caption': 'style',
                  'char_captions': [],
                },
                'legacy_uc': false,
              },
            ],
            'director_reference_strengths': [0.65],
            'director_reference_secondary_strengths': [0.2],
          }),
          'Software': 'NovelAI',
          'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        },
      );

      expect(metadata.preciseReferences, hasLength(1));
      expect(metadata.preciseReferences[0].image, [1, 2, 3, 4]);
      expect(metadata.preciseReferences[0].type, PreciseRefType.style);
      expect(metadata.preciseReferences[0].strength, 0.65);
      expect(metadata.preciseReferences[0].fidelity, 0.8);
    });
  });
}
