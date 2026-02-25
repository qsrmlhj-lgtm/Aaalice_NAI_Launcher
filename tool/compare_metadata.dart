// NAI 元数据字段对比工具
// 用法: dart run tool/compare_metadata.dart <官方图片路径>

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// 我们应用支持的字段（来自 NaiImageMetadata）
final Set<String> ourSupportedFields = {
  'prompt',
  'uc', // negativePrompt
  'seed',
  'sampler',
  'steps',
  'scale', // CFG Scale
  'width',
  'height',
  'model',
  'sm', // smea
  'sm_dyn', // smeaDyn
  'noise_schedule',
  'cfg_rescale',
  'uc_preset',
  'quality_toggle',
  'strength', // img2img
  'noise', // img2img
  'v4_prompt', // 多角色
  'v4_negative_prompt', // 多角色负面
};

// 我们关心的官方字段（按重要性分组）
final Map<String, List<String>> officialFieldGroups = {
  '核心生成参数': [
    'prompt',
    'uc',
    'seed',
    'steps',
    'scale',
    'sampler',
    'width',
    'height',
  ],
  '高级参数': [
    'cfg_rescale',
    'noise_schedule',
    'sm',
    'sm_dyn',
    'uncond_scale',
    'n_samples',
  ],
  'V4 多角色': [
    'v4_prompt',
    'v4_negative_prompt',
    'legacy_v3_extend',
  ],
  'Vibe Transfer': [
    'reference_image_multiple',
    'reference_strength_multiple',
    'reference_information_extracted_multiple',
    'uncond_per_vibe',
    'wonky_vibe_correlation',
  ],
  'ControlNet': [
    'controlnet_strength',
    'controlnet_model',
  ],
  '动态阈值': [
    'dynamic_thresholding',
    'dynamic_thresholding_percentile',
    'dynamic_thresholding_mimic_scale',
  ],
  'CFG 相关': [
    'skip_cfg_above_sigma',
    'skip_cfg_below_sigma',
    'cfg_sched_eligibility',
  ],
  'LoRA': [
    'lora_unet_weights',
    'lora_clip_weights',
  ],
  '其他技术参数': [
    'deliberate_euler_ancestral_bug',
    'prefer_brownian',
    'explike_fine_detail',
    'minimize_sigma_inf',
    'stream',
    'version',
    'request_type',
    'signed_hash',
  ],
};

void main(List<String> args) async {
  if (args.isEmpty) {
    print('用法: dart run tool/compare_metadata.dart <官方图片路径>');
    exit(1);
  }

  final imagePath = args[0];
  final file = File(imagePath);

  if (!file.existsSync()) {
    print('错误: 文件不存在 - $imagePath');
    exit(1);
  }

  print('正在分析 NAI 官网图片元数据字段...\n');
  print('图片: $imagePath');
  print('');

  final bytes = await file.readAsBytes();
  final metadata = await _extractFromChunks(bytes);

  if (metadata == null) {
    print('未能提取元数据');
    exit(1);
  }

  print('=' * 80);
  print('字段对比报告');
  print('=' * 80);
  print('');

  // 统计
  final allOfficialFields = <String>{};
  for (final group in officialFieldGroups.values) {
    allOfficialFields.addAll(group);
  }

  final supportedInOfficial =
      allOfficialFields.where(ourSupportedFields.contains).toList();
  final notSupportedInOfficial =
      allOfficialFields.where((f) => !ourSupportedFields.contains(f)).toList();
  final extraSupported =
      ourSupportedFields.where((f) => !allOfficialFields.contains(f)).toList();

  print('📊 统计:');
  print('  官方字段总数: ${allOfficialFields.length}');
  print('  我们支持的字段: ${ourSupportedFields.length}');
  print('  ✅ 已支持: ${supportedInOfficial.length}');
  print('  ❌ 未支持: ${notSupportedInOfficial.length}');
  print('  ⚠️  我们额外支持的: ${extraSupported.length}');
  print('');

  // 详细对比
  print('=' * 80);
  print('详细字段对比');
  print('=' * 80);
  print('');

  for (final entry in officialFieldGroups.entries) {
    final groupName = entry.key;
    final fields = entry.value;

    print('📁 $groupName');
    print('-' * 40);

    for (final field in fields) {
      final isSupported = ourSupportedFields.contains(field);
      final value = metadata[field];
      final hasValue = value != null;

      final status = isSupported ? (hasValue ? '✅' : '⚠️') : '❌';

      final valueStr = hasValue
          ? (value is String && value.length > 40
              ? '${value.substring(0, 40)}...'
              : value.toString())
          : '(null)';

      print('  $status $field: $valueStr');
    }
    print('');
  }

  // 图片中实际存在但我们不支持的字段
  print('=' * 80);
  print('图片中存在但我们未列出的字段');
  print('=' * 80);
  print('');

  final unexpectedFields =
      metadata.keys.where((k) => !allOfficialFields.contains(k)).toList();
  if (unexpectedFields.isEmpty) {
    print('  (无)');
  } else {
    for (final field in unexpectedFields) {
      final value = metadata[field];
      final valueStr = value is String && value.length > 40
          ? '${value.substring(0, 40)}...'
          : value.toString();
      print('  ⚠️  $field: $valueStr');
    }
  }
  print('');

  // 我们支持但图片中没有的字段
  print('=' * 80);
  print('我们支持但此图片缺失的字段');
  print('=' * 80);
  print('');

  final missingInImage =
      ourSupportedFields.where((f) => !metadata.containsKey(f)).toList();
  if (missingInImage.isEmpty) {
    print('  (无，所有支持字段都存在)');
  } else {
    for (final field in missingInImage) {
      print('  ⚠️  $field');
    }
  }
  print('');

  // 建议
  print('=' * 80);
  print('建议添加的字段（较重要）');
  print('=' * 80);
  print('');
  print('1. uncond_scale - 无条件引导比例');
  print('2. reference_image_multiple - Vibe Transfer 参考图');
  print('3. reference_strength_multiple - Vibe Transfer 强度');
  print('4. controlnet_strength / controlnet_model - ControlNet 参数');
  print('5. dynamic_thresholding* - 动态阈值参数');
  print('');
}

/// 从 PNG chunks 提取元数据（使用 image 包）
Future<Map<String, dynamic>?> _extractFromChunks(Uint8List bytes) async {
  try {
    // 使用 image 包的 PngDecoder - 纯 Dart 实现
    final decoder = img.PngDecoder();
    final info = decoder.startDecode(bytes);

    if (info == null) {
      return null;
    }

    // 从 PngInfo 获取 textData
    final pngInfo = info as img.PngInfo;
    final textData = pngInfo.textData;
    if (textData.isEmpty) {
      return null;
    }

    // 查找 Comment 或 parameters
    for (final keyword in ['Comment', 'parameters']) {
      final text = textData[keyword];
      if (text != null) {
        try {
          final json = jsonDecode(text) as Map<String, dynamic>;
          // 检查是否是 NAI 元数据
          if (json.containsKey('prompt') ||
              json.containsKey('comment') ||
              json.containsKey('Comment')) {
            return json;
          }
        } catch (e) {
          // 不是 JSON，忽略
        }
      }
    }

    return null;
  } catch (e) {
    return null;
  }
}
