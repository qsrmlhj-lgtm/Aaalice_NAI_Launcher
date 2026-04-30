import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/enums/uc_preset_type.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_provider.dart';
import 'package:nai_launcher/presentation/providers/prompt_token_counter_provider.dart';

void main() {
  group('buildPromptTokenCountPayload', () {
    test(
        'positive payload should include request-aligned quality tags and raw enabled character prompts only',
        () {
      final payload = buildPromptTokenCountPayload(
        target: PromptTokenCountTarget.positive,
        prompt: '<hero>',
        negativePrompt: '<bad>',
        model: 'nai-diffusion-4-5-full',
        fixedTagsState: FixedTagsState(
          entries: [
            FixedTagEntry.create(
              name: 'prefix',
              content: 'year 2025',
              position: FixedTagPosition.prefix,
              sortOrder: 0,
            ),
            FixedTagEntry.create(
              name: 'suffix',
              content: 'cinematic lighting',
              position: FixedTagPosition.suffix,
              sortOrder: 1,
            ),
          ],
        ),
        qualityToggle: true,
        ucPreset: UcPresetType.heavy.index,
        characters: [
          CharacterPrompt.create(
            name: 'A',
            prompt: '<dress>',
          ),
          CharacterPrompt.create(
            name: 'Positioned',
            prompt: '<cape>',
          ).copyWith(
            positionMode: CharacterPositionMode.custom,
            customPosition: const CharacterPosition(row: 0.0, column: 1.0),
          ),
          CharacterPrompt.create(
            name: 'B',
            prompt: 'ignored',
          ).copyWith(enabled: false),
          CharacterPrompt.create(
            name: 'C',
            prompt: '',
          ),
        ],
        resolveAliases: _resolveAliases,
      );

      expect(
        payload.mainText,
        equals(
          'year 2025, 1girl, cinematic lighting, very aesthetic, masterpiece, no text',
        ),
      );
      expect(
        payload.extraTexts,
        equals(['blue dress', 'red cape']),
      );
      expect(
        payload.breakdown.map((item) => item.label).toList(),
        equals(['提示词', '固定词', '质量预设', '角色']),
      );
    });

    test(
        'negative payload should include request-aligned uc preset, negative prompt and character negatives',
        () {
      final payload = buildPromptTokenCountPayload(
        target: PromptTokenCountTarget.negative,
        prompt: '<hero>',
        negativePrompt: '<bad>',
        model: 'nai-diffusion-4-5-full',
        fixedTagsState: const FixedTagsState(),
        qualityToggle: true,
        ucPreset: UcPresetType.light.index,
        characters: [
          CharacterPrompt.create(
            name: 'A',
            prompt: '1girl',
            negativePrompt: '<charBad>',
          ),
          CharacterPrompt.create(
            name: 'B',
            prompt: '1boy',
            negativePrompt: 'ignored',
          ).copyWith(enabled: false),
        ],
        resolveAliases: _resolveAliases,
      );

      expect(
        payload.mainText,
        equals(
          'nsfw, lowres, artistic error, scan artifacts, worst quality, bad quality, jpeg artifacts, multiple views, very displeasing, too many watermarks, negative space, blank page, bad hands',
        ),
      );
      expect(
        payload.extraTexts,
        equals(['extra fingers']),
      );
      expect(
        payload.breakdown.map((item) => item.label).toList(),
        equals(['负面提示词', '负面预设', '角色负面']),
      );
    });
  });
}

String _resolveAliases(String text) {
  return text
      .replaceAll('<hero>', '1girl')
      .replaceAll('<dress>', 'blue dress')
      .replaceAll('<cape>', 'red cape')
      .replaceAll('<bad>', 'bad hands')
      .replaceAll('<charBad>', 'extra fingers');
}
