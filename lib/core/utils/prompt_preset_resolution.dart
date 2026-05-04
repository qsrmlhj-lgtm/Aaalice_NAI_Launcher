import '../../data/models/prompt/prompt_preset_mode.dart';
import '../constants/api_constants.dart';

class PromptPresetResolution {
  const PromptPresetResolution({
    required this.prompt,
    required this.negativePrompt,
    required this.qualityToggle,
    required this.ucPreset,
  });

  final String prompt;
  final String negativePrompt;
  final bool qualityToggle;
  final int ucPreset;
}

PromptPresetResolution resolvePromptPresetSettings({
  required String prompt,
  required String negativePrompt,
  required PromptPresetMode qualityMode,
  String? qualityContent,
  required UcPresetType ucPresetType,
  String? ucPresetContent,
  required bool useCustomUcPreset,
}) {
  var resolvedPrompt = prompt.trim();
  var resolvedNegativePrompt = negativePrompt.trim();
  var qualityToggle = false;
  var ucPreset = UcPresets.noneApiValue;

  switch (qualityMode) {
    case PromptPresetMode.naiDefault:
      qualityToggle = true;
    case PromptPresetMode.none:
      qualityToggle = false;
    case PromptPresetMode.custom:
      resolvedPrompt = _appendPromptPart(resolvedPrompt, qualityContent);
      qualityToggle = false;
  }

  if (useCustomUcPreset) {
    resolvedNegativePrompt =
        _prependPromptPart(resolvedNegativePrompt, ucPresetContent);
  } else if (UcPresets.hasNativeApiValue(ucPresetType)) {
    ucPreset = UcPresets.toApiValue(ucPresetType);
  } else {
    resolvedNegativePrompt =
        _prependPromptPart(resolvedNegativePrompt, ucPresetContent);
  }

  return PromptPresetResolution(
    prompt: resolvedPrompt,
    negativePrompt: resolvedNegativePrompt,
    qualityToggle: qualityToggle,
    ucPreset: ucPreset,
  );
}

String _appendPromptPart(String base, String? addition) {
  final trimmedBase = base.trim();
  final trimmedAddition = addition?.trim() ?? '';
  if (trimmedAddition.isEmpty) return trimmedBase;
  if (trimmedBase.isEmpty) return trimmedAddition;
  if (trimmedBase.endsWith(',')) return '$trimmedBase $trimmedAddition';
  return '$trimmedBase, $trimmedAddition';
}

String _prependPromptPart(String base, String? prefix) {
  final trimmedBase = base.trim();
  final trimmedPrefix = prefix?.trim() ?? '';
  if (trimmedPrefix.isEmpty) return trimmedBase;
  if (trimmedBase.isEmpty) return trimmedPrefix;
  if (trimmedPrefix.endsWith(',')) return '$trimmedPrefix $trimmedBase';
  return '$trimmedPrefix, $trimmedBase';
}
