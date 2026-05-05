import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/enums/precise_ref_type.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/image_detail_data.dart';
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

    test('fromNaiComment should parse structured negative fixed words',
        () {
      const metadata = NaiImageMetadata(
        negativePrompt: 'bad anatomy, plain_negative, text',
        fixedNegativePrefixTags: ['bad anatomy'],
        fixedNegativeSuffixTags: ['text'],
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

    test('cached rawJson metadata should upgrade V4 character prompts', () {
      final rawJson = jsonEncode({
        'prompt': '1girl, 1boy, indoor',
        'uc': 'bad hands',
        'v4_prompt': {
          'caption': {
            'base_caption': '1girl, 1boy, indoor',
            'char_captions': [
              {
                'char_caption': '1girl, rabbit girl, target#holding hands',
              },
              {
                'char_caption': '1boy, suit, source#holding hands',
              },
            ],
          },
          'use_coords': false,
        },
        'v4_negative_prompt': {
          'caption': {
            'base_caption': 'bad hands',
            'char_captions': [
              {'char_caption': 'lowres'},
              {'char_caption': 'bad anatomy'},
            ],
          },
        },
      });
      final stale = NaiImageMetadata(
        prompt: '1girl, 1boy, indoor',
        negativePrompt: 'bad hands',
        rawJson: rawJson,
        software: 'NovelAI',
        source: 'NovelAI Diffusion V4.5 4BDE2A90',
      );

      final upgraded = stale.upgradeFromRawJsonIfNeeded();

      expect(
        upgraded.characterPrompts,
        equals([
          '1girl, rabbit girl, target#holding hands',
          '1boy, suit, source#holding hands',
        ]),
      );
      expect(
        upgraded.characterNegativePrompts,
        equals(['lowres', 'bad anatomy']),
      );
    });

    test('local gallery detail should upgrade rawJson character prompts',
        () async {
      final rawJson = jsonEncode({
        'prompt': '1girl, 1boy, indoor',
        'uc': 'bad hands',
        'v4_prompt': {
          'caption': {
            'base_caption': '1girl, 1boy, indoor',
            'char_captions': [
              {
                'char_caption': '1girl, rabbit girl, target#holding hands',
                'position': 'A',
              },
              {
                'char_caption': '1boy, suit, source#holding hands',
                'position': 'B',
              },
            ],
          },
        },
        'v4_negative_prompt': {
          'caption': {
            'base_caption': 'bad hands',
            'char_captions': [
              {'char_caption': 'lowres'},
              {'char_caption': 'bad anatomy'},
            ],
          },
        },
      });
      final stale = NaiImageMetadata(
        prompt: '1girl, 1boy, indoor',
        negativePrompt: 'bad hands',
        rawJson: rawJson,
        software: 'NovelAI',
        source: 'NovelAI Diffusion V4.5 4BDE2A90',
      );
      final record = LocalImageRecord(
        path: r'G:\test\image.png',
        size: 1,
        modifiedAt: DateTime(2026, 5, 4),
        metadata: stale,
        metadataStatus: MetadataStatus.success,
      );

      final metadata = await LocalImageDetailData(record).getMetadataAsync();

      expect(
        metadata?.characterPrompts,
        equals([
          '1girl, rabbit girl, target#holding hands',
          '1boy, suit, source#holding hands',
        ]),
      );
      expect(metadata?.characterInfos, hasLength(2));
      expect(metadata?.characterInfos.first.position, 'A');
      expect(metadata?.characterInfos.last.negativePrompt, 'bad anatomy');
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

    test('fromNaiComment should parse structured negative fixed tags', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'prompt': '1girl',
          'uc': 'bad anatomy, bad hands, text',
          'fixed_negative_prefix': ['bad anatomy'],
          'fixed_negative_suffix': ['text'],
        },
      );

      expect(metadata.fixedNegativePrefixTags, equals(['bad anatomy']));
      expect(metadata.fixedNegativeSuffixTags, equals(['text']));
      expect(metadata.displayNegativePrompt, equals('bad anatomy, bad hands, text'));
    });

    test('fromNaiComment should parse Variety Plus flag', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'prompt': '1girl',
          'uc': 'bad hands',
          'skip_cfg_above_sigma': 19,
        },
      );

      expect(metadata.varietyPlus, isTrue);
    });

    test('fromNaiComment should parse string-list Vibe metadata', () {
      final metadata = NaiImageMetadata.fromNaiComment(
        {
          'prompt': '1girl',
          'uc': 'bad hands',
          'reference_image_multiple': ['encoded-a', 'encoded-b'],
          'reference_strength_multiple': [0.25, 0.75],
          'reference_information_extracted_multiple': [0.4, 0.8],
        },
      );

      expect(metadata.vibeReferences, hasLength(2));
      expect(metadata.vibeReferences.first.vibeEncoding, equals('encoded-a'));
      expect(metadata.vibeReferences.first.strength, equals(0.25));
      expect(metadata.vibeReferences.last.infoExtracted, equals(0.8));
    });
  });
}
