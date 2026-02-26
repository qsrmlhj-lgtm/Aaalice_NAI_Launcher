import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/models/image/image_params.dart';
import '../../data/services/metadata/unified_metadata_parser.dart';
import '../enums/precise_ref_type.dart';
import 'app_logger.dart';

/// 统一图像保存工具类
/// 
/// 整合所有图像保存路径，确保元数据完整嵌入
/// 替代分散在各处的图像保存逻辑
class ImageSaveUtils {
  ImageSaveUtils._();

  /// 构建完整的元数据 Comment JSON
  /// 
  /// [params] - 图像生成参数
  /// [actualSeed] - 实际使用的种子
  /// [fixedPrefixTags] - 固定前缀标签列表
  /// [fixedSuffixTags] - 固定后缀标签列表
  /// [charCaptions] - 角色提示词列表（V4多角色）
  /// [charNegCaptions] - 角色负面提示词列表
  /// [useCoords] - 是否使用坐标模式
  static Map<String, dynamic> buildCommentJson({
    required ImageParams params,
    required int actualSeed,
    List<String>? fixedPrefixTags,
    List<String>? fixedSuffixTags,
    List<Map<String, dynamic>>? charCaptions,
    List<Map<String, dynamic>>? charNegCaptions,
    bool useCoords = false,
  }) {
    final commentJson = <String, dynamic>{
      'prompt': params.prompt,
      'uc': params.negativePrompt,
      'seed': actualSeed,
      'steps': params.steps,
      'width': params.width,
      'height': params.height,
      'scale': params.scale,
      'uncond_scale': 0.0,
      'cfg_rescale': params.cfgRescale,
      'n_samples': 1,
      'noise_schedule': params.noiseSchedule,
      'sampler': params.sampler,
      'sm': params.smea,
      'sm_dyn': params.smeaDyn,
      // NAI官方格式字段
      'version': params.isV4Model ? 'v4' : 'v3',
      'legacy_v3_extend': false,
      // 模型信息
      'model': params.model,
      // UC预设和质量标签
      'uc_preset': params.ucPreset,
      'quality_toggle': params.qualityToggle,
      // 生成动作类型
      'action': params.action.value,
      // img2img参数
      if (params.isImg2Img) ...{
        'strength': params.strength,
        'noise': params.noise,
      },
      // 应用专属字段
      'fixed_prefix': fixedPrefixTags ?? [],
      'fixed_suffix': fixedSuffixTags ?? [],
    };

    // V4多角色提示词
    if (charCaptions != null && charCaptions.isNotEmpty) {
      commentJson['v4_prompt'] = {
        'caption': {
          'base_caption': params.prompt,
          'char_captions': charCaptions,
        },
        'use_coords': useCoords,
        'use_order': true,
      };
      if (charNegCaptions != null && charNegCaptions.isNotEmpty) {
        commentJson['v4_negative_prompt'] = {
          'caption': {
            'base_caption': params.negativePrompt,
            'char_captions': charNegCaptions,
          },
          'use_coords': false,
          'use_order': false,
        };
      }
    }

    // Vibe Transfer 数据（关键！之前缺失）
    if (params.vibeReferencesV4.isNotEmpty) {
      final validVibes = params.vibeReferencesV4
          .where((v) => v.vibeEncoding.isNotEmpty)
          .toList();
      
      if (validVibes.isNotEmpty) {
        commentJson['reference_image_multiple'] = validVibes
            .map((v) => v.vibeEncoding)
            .toList();
        commentJson['reference_strength_multiple'] = validVibes
            .map((v) => v.strength)
            .toList();
        commentJson['reference_information_extracted_multiple'] = validVibes
            .map((v) => v.infoExtracted)
            .toList();
      }
    }

    // Precise Reference 数据
    if (params.preciseReferences.isNotEmpty) {
      commentJson['use_precise_ref'] = true;
      commentJson['precise_ref_type'] = params.preciseReferences.first.type.toApiString();
      // 注意：Precise Reference 的图像数据不直接存入元数据，
      // 因为可能很大。这里只记录配置信息
    }

    // V4.5 参数
    if (params.isV45Model) {
      commentJson['variety_plus'] = params.varietyPlus;
    }

    return commentJson;
  }

  /// 构建完整的元数据 Map
  /// 
  /// [commentJson] - Comment字段的JSON对象
  /// [params] - 图像生成参数（用于获取模型信息）
  static Map<String, dynamic> buildMetadata({
    required Map<String, dynamic> commentJson,
    required ImageParams params,
  }) {
    return {
      'Description': params.prompt,
      'Software': 'NovelAI',
      'Source': _getModelSourceName(params.model),
      'Comment': jsonEncode(commentJson),
    };
  }

  /// 保存图像并嵌入完整元数据
  /// 
  /// [imageBytes] - 图像字节数据
  /// [filePath] - 目标文件路径
  /// [params] - 图像生成参数
  /// [actualSeed] - 实际使用的种子
  /// [fixedPrefixTags] - 固定前缀标签
  /// [fixedSuffixTags] - 固定后缀标签
  /// [charCaptions] - 角色提示词列表
  /// [charNegCaptions] - 角色负面提示词列表
  /// [useStealth] - 是否使用stealth编码（默认false）
  /// 
  /// 返回保存后的文件
  static Future<File> saveImageWithMetadata({
    required Uint8List imageBytes,
    required String filePath,
    required ImageParams params,
    required int actualSeed,
    List<String>? fixedPrefixTags,
    List<String>? fixedSuffixTags,
    List<Map<String, dynamic>>? charCaptions,
    List<Map<String, dynamic>>? charNegCaptions,
    bool useCoords = false,
    bool useStealth = false,
  }) async {
    // 构建元数据
    final commentJson = buildCommentJson(
      params: params,
      actualSeed: actualSeed,
      fixedPrefixTags: fixedPrefixTags,
      fixedSuffixTags: fixedSuffixTags,
      charCaptions: charCaptions,
      charNegCaptions: charNegCaptions,
      useCoords: useCoords,
    );

    final metadata = buildMetadata(
      commentJson: commentJson,
      params: params,
    );

    AppLogger.d(
      'Embedding metadata: ${jsonEncode(metadata).substring(0, jsonEncode(metadata).length.clamp(0, 200))}...',
      'ImageSaveUtils',
    );

    // 嵌入元数据
    final embeddedBytes = await UnifiedMetadataParser.embedMetadata(
      imageBytes,
      jsonEncode(metadata),
      useStealth: useStealth,
    );

    // 确保目录存在
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 写入文件
    await file.writeAsBytes(embeddedBytes);

    AppLogger.i('Image saved with metadata: $filePath', 'ImageSaveUtils');

    return file;
  }

  /// 简化版保存（用于不需要完整参数的场景）
  /// 
  /// [imageBytes] - 图像字节数据
  /// [filePath] - 目标文件路径
  /// [metadata] - 预构建的元数据Map
  /// [useStealth] - 是否使用stealth编码
  static Future<File> saveWithPrebuiltMetadata({
    required Uint8List imageBytes,
    required String filePath,
    required Map<String, dynamic> metadata,
    bool useStealth = false,
  }) async {
    // 嵌入元数据
    final embeddedBytes = await UnifiedMetadataParser.embedMetadata(
      imageBytes,
      jsonEncode(metadata),
      useStealth: useStealth,
    );

    // 确保目录存在
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 写入文件
    await file.writeAsBytes(embeddedBytes);

    AppLogger.i('Image saved with prebuilt metadata: $filePath', 'ImageSaveUtils');

    return file;
  }

  /// 从元数据重新构建 ImageParams
  /// 
  /// 用于导入图像时恢复生成参数
  static ImageParams? rebuildParamsFromMetadata(NaiImageMetadata metadata) {
    try {
      var params = ImageParams(
        prompt: metadata.prompt,
        negativePrompt: metadata.negativePrompt,
        model: metadata.model ?? 'nai-diffusion-4-full',
        width: metadata.width ?? 832,
        height: metadata.height ?? 1216,
        steps: metadata.steps ?? 28,
        scale: metadata.scale ?? 5.0,
        sampler: metadata.sampler ?? 'k_euler_ancestral',
        seed: metadata.seed ?? -1,
        cfgRescale: metadata.cfgRescale ?? 0.0,
        noiseSchedule: metadata.noiseSchedule ?? 'karras',
        smea: metadata.smea ?? false,
        smeaDyn: metadata.smeaDyn ?? false,
      );

      // 恢复Vibe数据
      if (metadata.vibeReferences.isNotEmpty) {
        params = params.copyWith(
          vibeReferencesV4: metadata.vibeReferences,
        );
      }

      // 恢复多角色数据
      if (metadata.characterPrompts.isNotEmpty) {
        final characters = metadata.characterPrompts.map((prompt) {
          return CharacterPrompt(
            prompt: prompt,
            // 其他字段使用默认值，因为元数据中可能不完整
          );
        }).toList();
        params = params.copyWith(characters: characters);
      }

      return params;
    } catch (e, stack) {
      AppLogger.e('Failed to rebuild params from metadata', e, stack, 'ImageSaveUtils');
      return null;
    }
  }

  /// 获取模型显示名称
  static String _getModelSourceName(String model) {
    if (model.contains('diffusion-4-5')) {
      return 'NovelAI Diffusion V4.5';
    } else if (model.contains('diffusion-4')) {
      return 'NovelAI Diffusion V4';
    } else if (model.contains('diffusion-3')) {
      return 'NovelAI Diffusion V3';
    } else if (model.contains('diffusion-2')) {
      return 'NovelAI Diffusion V2';
    }
    return 'NovelAI';
  }
}
