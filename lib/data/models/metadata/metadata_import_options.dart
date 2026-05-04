import 'package:freezed_annotation/freezed_annotation.dart';

import '../gallery/nai_image_metadata.dart';

part 'metadata_import_options.freezed.dart';

/// 元数据导入选项模型
///
/// 用于选择性地套用图片元数据中的参数
@freezed
class MetadataImportOptions with _$MetadataImportOptions {
  const factory MetadataImportOptions({
    // ========== 提示词相关 ==========
    @Default(true) bool importPrompt, // 主提示词
    @Default(true) bool importNegativePrompt, // 负向提示词

    // 固定词（新增细分）
    @Default(true) bool importFixedTags, // 固定词总开关
    @Default(true) bool importFixedPrefix, // 固定前缀词
    @Default(true) bool importFixedSuffix, // 固定后缀词

    // 质量词（新增细分）
    @Default(true) bool importQualityTags, // 质量词总开关
    @Default([]) List<String> selectedQualityTags, // 选择的具体质量词

    // 角色提示词（新增细分）
    @Default(true) bool importCharacterPrompts, // 角色提示词总开关
    @Default([]) List<int> selectedCharacterIndices, // 选择的角色索引

    // Vibe数据（新增）
    @Default(true) bool importVibeReferences, // Vibe数据总开关
    @Default([]) List<int> selectedVibeIndices, // 选择的Vibe索引

    // Precise Reference 数据
    @Default(true) bool importPreciseReferences, // 精准参考总开关
    @Default([]) List<int> selectedPreciseReferenceIndices, // 选择的精准参考索引

    // ========== 生成参数 ==========
    @Default(false) bool importSeed, // 种子
    @Default(false) bool importSteps, // 步数
    @Default(false) bool importScale, // CFG Scale
    @Default(false) bool importSize, // 尺寸
    @Default(false) bool importSampler, // 采样器
    @Default(false) bool importModel, // 模型
    @Default(false) bool importSmea, // SMEA
    @Default(false) bool importSmeaDyn, // SMEA Dyn
    @Default(false) bool importNoiseSchedule, // 噪声计划
    @Default(false) bool importCfgRescale, // CFG Rescale
    @Default(false) bool importQualityToggle, // 质量标签
    @Default(false) bool importUcPreset, // UC 预设
    @Default(false) bool importVarietyPlus, // Variety+
  }) = _MetadataImportOptions;

  const MetadataImportOptions._();

  /// 快速预设：全部选中
  factory MetadataImportOptions.all() => const MetadataImportOptions(
        importSeed: true,
        importSteps: true,
        importScale: true,
        importSize: true,
        importSampler: true,
        importModel: true,
        importSmea: true,
        importSmeaDyn: true,
        importNoiseSchedule: true,
        importCfgRescale: true,
        importQualityToggle: true,
        importUcPreset: true,
        importVarietyPlus: true,
      );

  /// 快速预设：仅提示词相关
  factory MetadataImportOptions.promptsOnly() => const MetadataImportOptions(
        importPrompt: true,
        importNegativePrompt: true,
        importFixedTags: true,
        importFixedPrefix: true,
        importFixedSuffix: true,
        importQualityTags: true,
        importCharacterPrompts: true,
        importVibeReferences: false,
        importPreciseReferences: false,
        importSeed: false,
        importSteps: false,
        importScale: false,
        importSize: false,
        importSampler: false,
        importModel: false,
        importSmea: false,
        importSmeaDyn: false,
        importNoiseSchedule: false,
        importCfgRescale: false,
        importQualityToggle: false,
        importUcPreset: false,
        importVarietyPlus: false,
      );

  /// 快速预设：仅生成参数（不包含提示词）
  factory MetadataImportOptions.generationOnly() => const MetadataImportOptions(
        importPrompt: false,
        importNegativePrompt: false,
        importFixedTags: false,
        importFixedPrefix: false,
        importFixedSuffix: false,
        importQualityTags: false,
        importCharacterPrompts: false,
        importVibeReferences: true,
        importPreciseReferences: true,
        importSeed: true,
        importSteps: true,
        importScale: true,
        importSize: true,
        importSampler: true,
        importModel: true,
        importSmea: true,
        importSmeaDyn: true,
        importNoiseSchedule: true,
        importCfgRescale: true,
        importQualityToggle: true,
        importUcPreset: true,
        importVarietyPlus: true,
      );

  /// 全不选
  factory MetadataImportOptions.none() => const MetadataImportOptions(
        importPrompt: false,
        importNegativePrompt: false,
        importFixedTags: false,
        importFixedPrefix: false,
        importFixedSuffix: false,
        importQualityTags: false,
        importCharacterPrompts: false,
        importVibeReferences: false,
        importPreciseReferences: false,
        importSeed: false,
        importSteps: false,
        importScale: false,
        importSize: false,
        importSampler: false,
        importModel: false,
        importSmea: false,
        importSmeaDyn: false,
        importNoiseSchedule: false,
        importCfgRescale: false,
        importQualityToggle: false,
        importUcPreset: false,
        importVarietyPlus: false,
      );

  /// 获取已选中的可用参数数量。
  ///
  /// 与 [selectedCount] 不同，这里只统计当前图片元数据里实际存在的数据，
  /// 避免“仅提示词”把空的固定词/质量词开关也计入数量。
  int selectedCountFor(NaiImageMetadata metadata) {
    var count = 0;
    if (importPrompt && metadata.prompt.isNotEmpty) count++;
    if (importNegativePrompt && metadata.negativePrompt.isNotEmpty) count++;
    if (importFixedTags &&
        ((importFixedPrefix && metadata.fixedPrefixTags.isNotEmpty) ||
            (importFixedSuffix && metadata.fixedSuffixTags.isNotEmpty))) {
      count++;
    }
    if (importQualityTags &&
        selectedQualityTags.any(metadata.qualityTags.contains)) {
      count++;
    }
    if (importCharacterPrompts &&
        (selectedCharacterIndices.any(
              (index) => index >= 0 && index < metadata.characterInfos.length,
            ) ||
            (metadata.characterInfos.isEmpty &&
                metadata.characterPrompts.isNotEmpty))) {
      count++;
    }
    if (importVibeReferences &&
        selectedVibeIndices.any(
          (index) => index >= 0 && index < metadata.vibeReferences.length,
        )) {
      count++;
    }
    if (importPreciseReferences &&
        selectedPreciseReferenceIndices.any(
          (index) => index >= 0 && index < metadata.preciseReferences.length,
        )) {
      count++;
    }
    if (importSeed && metadata.seed != null) count++;
    if (importSteps && metadata.steps != null) count++;
    if (importScale && metadata.scale != null) count++;
    if (importSize && metadata.width != null && metadata.height != null) {
      count++;
    }
    if (importSampler && metadata.sampler != null) count++;
    if (importModel && metadata.model != null) count++;
    if (importSmea && (metadata.smea == true || metadata.smeaDyn == true)) {
      count++;
    }
    if (importSmeaDyn && metadata.smeaDyn == true) count++;
    if (importNoiseSchedule && metadata.noiseSchedule != null) count++;
    if (importCfgRescale &&
        metadata.cfgRescale != null &&
        metadata.cfgRescale! > 0) {
      count++;
    }
    if (importQualityToggle && metadata.qualityToggle != null) count++;
    if (importUcPreset && metadata.ucPreset != null) count++;
    if (importVarietyPlus && metadata.varietyPlus != null) count++;
    return count;
  }

  /// 获取已选中的参数数量（按逻辑分组计数）
  int get selectedCount {
    var count = 0;
    // 主提示词
    if (importPrompt) count++;
    // 负向提示词
    if (importNegativePrompt) count++;
    // 固定词（作为一个整体计数）
    if (importFixedTags && (importFixedPrefix || importFixedSuffix)) count++;
    // 质量词
    if (importQualityTags && selectedQualityTags.isNotEmpty) count++;
    // 角色提示词
    if (importCharacterPrompts && selectedCharacterIndices.isNotEmpty) count++;
    // Vibe数据
    if (importVibeReferences && selectedVibeIndices.isNotEmpty) count++;
    // 精准参考
    if (importPreciseReferences && selectedPreciseReferenceIndices.isNotEmpty) {
      count++;
    }
    // 生成参数
    if (importSeed) count++;
    if (importSteps) count++;
    if (importScale) count++;
    if (importSize) count++;
    if (importSampler) count++;
    if (importModel) count++;
    if (importSmea) count++;
    if (importSmeaDyn) count++;
    if (importNoiseSchedule) count++;
    if (importCfgRescale) count++;
    if (importQualityToggle) count++;
    if (importUcPreset) count++;
    if (importVarietyPlus) count++;
    return count;
  }

  /// 是否全部选中
  bool get isAllSelected => selectedCount == 19;

  /// 是否全部未选中
  bool get isNoneSelected => selectedCount == 0;

  /// 是否导入任何提示词相关
  bool get isImportingAnyPrompt =>
      importPrompt ||
      importNegativePrompt ||
      (importFixedTags && (importFixedPrefix || importFixedSuffix)) ||
      (importQualityTags && selectedQualityTags.isNotEmpty) ||
      (importCharacterPrompts && selectedCharacterIndices.isNotEmpty);
}
