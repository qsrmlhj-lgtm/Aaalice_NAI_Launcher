import '../constants/api_constants.dart';

/// 提示词语义快照
///
/// - basePrompt/baseNegativePrompt: 结构化元数据中保留的基础文本
/// - effectivePrompt/effectiveNegativePrompt: 当前实际送给模型时的等效文本
class PromptSemanticsSnapshot {
  const PromptSemanticsSnapshot({
    required this.basePrompt,
    required this.baseNegativePrompt,
    required this.effectivePrompt,
    required this.effectiveNegativePrompt,
  });

  final String basePrompt;
  final String baseNegativePrompt;
  final String effectivePrompt;
  final String effectiveNegativePrompt;
}

PromptSemanticsSnapshot buildPromptSemanticsSnapshot({
  required String prompt,
  required String negativePrompt,
  required String model,
  required bool qualityToggle,
  required int ucPreset,
}) {
  final effectivePrompt =
      qualityToggle ? QualityTags.applyQualityTags(prompt, model) : prompt;

  final effectiveNegativePrompt = UcPresets.applyPresetWithNsfwCheck(
    negativePrompt,
    prompt,
    model,
    ucPreset,
  );

  return PromptSemanticsSnapshot(
    basePrompt: prompt,
    baseNegativePrompt: negativePrompt,
    effectivePrompt: effectivePrompt,
    effectiveNegativePrompt: effectiveNegativePrompt,
  );
}
