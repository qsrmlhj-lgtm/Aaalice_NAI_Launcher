import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/services/prompt_token_counter_service.dart';
import '../../core/utils/prompt_semantics_utils.dart';
import '../../core/utils/prompt_preset_resolution.dart';
import '../../data/models/character/character_prompt.dart' as ui_character;
import '../../data/models/prompt/prompt_preset_mode.dart';
import '../../data/services/alias_resolver_service.dart';
import 'character_prompt_provider.dart';
import 'fixed_tags_provider.dart';
import 'generation/generation_params_notifier.dart';
import 'quality_preset_provider.dart';
import 'tag_library_page_provider.dart';
import 'uc_preset_provider.dart';

enum PromptTokenCountTarget {
  positive,
  negative,
}

class PromptTokenCountPayload {
  const PromptTokenCountPayload({
    required this.mainText,
    this.extraTexts = const [],
    this.breakdown = const [],
  });

  final String mainText;
  final List<String> extraTexts;
  final List<PromptTokenCountBreakdownGroup> breakdown;
}

class PromptTokenCountBreakdownGroup {
  const PromptTokenCountBreakdownGroup({
    required this.label,
    required this.texts,
  });

  final String label;
  final List<String> texts;
}

final promptTokenCounterServiceProvider =
    FutureProvider<PromptTokenCounterService>((ref) async {
  return PromptTokenCounterService.createDefault();
});

final promptTokenUsageProvider =
    FutureProvider.family<PromptTokenUsage?, PromptTokenCountTarget>(
  (ref, target) async {
    final promptState = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => (
          prompt: params.prompt,
          negativePrompt: params.negativePrompt,
          model: params.model,
        ),
      ),
    );
    final characterConfig = ref.watch(characterPromptNotifierProvider);
    final fixedTagsState = ref.watch(fixedTagsNotifierProvider);
    final qualityState = ref.watch(qualityPresetNotifierProvider);
    final ucState = ref.watch(ucPresetNotifierProvider);
    ref.watch(tagLibraryPageNotifierProvider);
    final aliasResolver = ref.read(aliasResolverServiceProvider.notifier);
    final service = await ref.watch(promptTokenCounterServiceProvider.future);
    final qualityContent = ref
        .read(qualityPresetNotifierProvider.notifier)
        .getEffectiveContent(promptState.model);
    final ucPresetContent = ref
        .read(ucPresetNotifierProvider.notifier)
        .getEffectiveContent(promptState.model);

    final payload = buildPromptTokenCountPayload(
      target: target,
      prompt: promptState.prompt,
      negativePrompt: promptState.negativePrompt,
      model: promptState.model,
      fixedTagsState: fixedTagsState,
      qualityToggle: qualityState.mode == PromptPresetMode.naiDefault,
      ucPreset: UcPresets.toApiValue(ucState.presetType),
      qualityMode: qualityState.mode,
      qualityContent: qualityContent,
      ucPresetType: ucState.presetType,
      ucPresetContent: ucPresetContent,
      useCustomUcPreset: ucState.isCustom,
      characters: characterConfig.characters,
      resolveAliases: aliasResolver.resolveAliases,
    );

    final breakdown = <PromptTokenBreakdownEntry>[];
    for (final group in payload.breakdown) {
      final tokens = await service.countTokensForTexts(group.texts);
      if (tokens <= 0) {
        continue;
      }
      breakdown.add(
        PromptTokenBreakdownEntry(
          label: group.label,
          tokens: tokens,
        ),
      );
    }
    if (breakdown.isNotEmpty) {
      breakdown.add(
        const PromptTokenBreakdownEntry(
          label: '网页端校准',
          tokens: 1,
        ),
      );
    }

    return service.countUsageFromTexts(
      model: promptState.model,
      mainText: payload.mainText,
      extraTexts: payload.extraTexts,
      breakdown: breakdown,
    );
  },
);

@visibleForTesting
PromptTokenCountPayload buildPromptTokenCountPayload({
  required PromptTokenCountTarget target,
  required String prompt,
  required String negativePrompt,
  required String model,
  required FixedTagsState fixedTagsState,
  required bool qualityToggle,
  required int ucPreset,
  PromptPresetMode? qualityMode,
  String? qualityContent,
  UcPresetType? ucPresetType,
  String? ucPresetContent,
  bool useCustomUcPreset = false,
  required List<ui_character.CharacterPrompt> characters,
  required String Function(String text) resolveAliases,
}) {
  return switch (target) {
    PromptTokenCountTarget.positive => _buildPositiveTokenCountPayload(
        prompt: prompt,
        negativePrompt: negativePrompt,
        model: model,
        fixedTagsState: fixedTagsState,
        qualityToggle: qualityToggle,
        ucPreset: ucPreset,
        qualityMode: qualityMode,
        qualityContent: qualityContent,
        ucPresetType: ucPresetType,
        ucPresetContent: ucPresetContent,
        useCustomUcPreset: useCustomUcPreset,
        characters: characters,
        resolveAliases: resolveAliases,
      ),
    PromptTokenCountTarget.negative => _buildNegativeTokenCountPayload(
        prompt: prompt,
        negativePrompt: negativePrompt,
        model: model,
        fixedTagsState: fixedTagsState,
        qualityToggle: qualityToggle,
        ucPreset: ucPreset,
        qualityMode: qualityMode,
        qualityContent: qualityContent,
        ucPresetType: ucPresetType,
        ucPresetContent: ucPresetContent,
        useCustomUcPreset: useCustomUcPreset,
        characters: characters,
        resolveAliases: resolveAliases,
      ),
  };
}

PromptTokenCountPayload _buildPositiveTokenCountPayload({
  required String prompt,
  required String negativePrompt,
  required String model,
  required FixedTagsState fixedTagsState,
  required bool qualityToggle,
  required int ucPreset,
  PromptPresetMode? qualityMode,
  String? qualityContent,
  UcPresetType? ucPresetType,
  String? ucPresetContent,
  bool useCustomUcPreset = false,
  required List<ui_character.CharacterPrompt> characters,
  required String Function(String text) resolveAliases,
}) {
  final resolvedPrompt = resolveAliases(prompt).trim();
  final resolvedNegativePrompt = resolveAliases(negativePrompt).trim();
  final promptWithFixedTags =
      fixedTagsState.applyToPrompt(resolvedPrompt).trim();
  final resolvedQualityMode = qualityMode ??
      (qualityToggle ? PromptPresetMode.naiDefault : PromptPresetMode.none);
  final resolvedUcPresetType =
      ucPresetType ?? UcPresets.getPresetTypeFromInt(ucPreset);
  final presetResolution = resolvePromptPresetSettings(
    prompt: promptWithFixedTags,
    negativePrompt: resolvedNegativePrompt,
    qualityMode: resolvedQualityMode,
    qualityContent: qualityContent,
    ucPresetType: resolvedUcPresetType,
    ucPresetContent: ucPresetContent,
    useCustomUcPreset: useCustomUcPreset,
  );
  final promptSemantics = buildPromptSemanticsSnapshot(
    prompt: presetResolution.prompt,
    negativePrompt: presetResolution.negativePrompt,
    model: model,
    qualityToggle: presetResolution.qualityToggle,
    ucPreset: presetResolution.ucPreset,
  );

  final extraTexts = characters
      .where((character) => character.enabled)
      .map((character) {
        final resolvedCharacterPrompt = resolveAliases(character.prompt).trim();
        if (resolvedCharacterPrompt.isEmpty) {
          return null;
        }
        return resolvedCharacterPrompt;
      })
      .whereType<String>()
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
  final fixedTagTexts = [
    ...fixedTagsState.enabledPrefixes
        .map((entry) => entry.weightedContent.trim())
        .where((text) => text.isNotEmpty),
    ...fixedTagsState.enabledSuffixes
        .map((entry) => entry.weightedContent.trim())
        .where((text) => text.isNotEmpty),
  ];
  final qualityTags = switch (resolvedQualityMode) {
    PromptPresetMode.naiDefault =>
      QualityTags.getQualityTags(model)?.trim() ?? '',
    PromptPresetMode.none => '',
    PromptPresetMode.custom => qualityContent?.trim() ?? '',
  };

  return PromptTokenCountPayload(
    mainText: promptSemantics.effectivePrompt,
    extraTexts: extraTexts,
    breakdown: [
      PromptTokenCountBreakdownGroup(
        label: '提示词',
        texts: [resolvedPrompt],
      ),
      PromptTokenCountBreakdownGroup(
        label: '固定词',
        texts: fixedTagTexts,
      ),
      PromptTokenCountBreakdownGroup(
        label: '质量预设',
        texts: [qualityTags],
      ),
      PromptTokenCountBreakdownGroup(
        label: '角色',
        texts: extraTexts,
      ),
    ],
  );
}

PromptTokenCountPayload _buildNegativeTokenCountPayload({
  required String prompt,
  required String negativePrompt,
  required String model,
  required FixedTagsState fixedTagsState,
  required bool qualityToggle,
  required int ucPreset,
  PromptPresetMode? qualityMode,
  String? qualityContent,
  UcPresetType? ucPresetType,
  String? ucPresetContent,
  bool useCustomUcPreset = false,
  required List<ui_character.CharacterPrompt> characters,
  required String Function(String text) resolveAliases,
}) {
  final resolvedPrompt = resolveAliases(prompt).trim();
  final resolvedNegativePrompt = resolveAliases(negativePrompt).trim();
  final promptWithFixedTags =
      fixedTagsState.applyToPrompt(resolvedPrompt).trim();
  final resolvedQualityMode = qualityMode ??
      (qualityToggle ? PromptPresetMode.naiDefault : PromptPresetMode.none);
  final resolvedUcPresetType =
      ucPresetType ?? UcPresets.getPresetTypeFromInt(ucPreset);
  final presetResolution = resolvePromptPresetSettings(
    prompt: promptWithFixedTags,
    negativePrompt: resolvedNegativePrompt,
    qualityMode: resolvedQualityMode,
    qualityContent: qualityContent,
    ucPresetType: resolvedUcPresetType,
    ucPresetContent: ucPresetContent,
    useCustomUcPreset: useCustomUcPreset,
  );
  final promptSemantics = buildPromptSemanticsSnapshot(
    prompt: presetResolution.prompt,
    negativePrompt: presetResolution.negativePrompt,
    model: model,
    qualityToggle: presetResolution.qualityToggle,
    ucPreset: presetResolution.ucPreset,
  );

  final extraTexts = characters
      .where((character) => character.enabled)
      .map((character) => resolveAliases(character.negativePrompt).trim())
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
  final resolvedUcPresetContent =
      (useCustomUcPreset || !UcPresets.hasNativeApiValue(resolvedUcPresetType))
          ? (ucPresetContent?.trim() ?? '')
          : UcPresets.getPresetContent(model, resolvedUcPresetType).trim();

  return PromptTokenCountPayload(
    mainText: promptSemantics.effectiveNegativePrompt,
    extraTexts: extraTexts,
    breakdown: [
      PromptTokenCountBreakdownGroup(
        label: '负面提示词',
        texts: [resolvedNegativePrompt],
      ),
      PromptTokenCountBreakdownGroup(
        label: '负面预设',
        texts: [resolvedUcPresetContent],
      ),
      PromptTokenCountBreakdownGroup(
        label: '角色负面',
        texts: extraTexts,
      ),
    ],
  );
}
