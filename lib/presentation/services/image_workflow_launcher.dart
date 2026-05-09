import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/inpaint_mask_utils.dart';
import '../../core/utils/localization_extension.dart';
import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/services/image_metadata_service.dart';
import '../providers/generation/image_workflow_controller.dart';
import '../providers/image_generation_provider.dart';
import '../screens/director_tools/director_tools_screen.dart';
import '../utils/prompt_preset_import_utils.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/image_editor/image_editor_screen.dart';

class ImageWorkflowLauncher {
  const ImageWorkflowLauncher._();

  static void openImageToImage(
    WidgetRef ref,
    Uint8List imageBytes,
  ) {
    final workflowNotifier = ref.read(imageWorkflowControllerProvider.notifier);
    workflowNotifier.replaceSourceImage(imageBytes);
    workflowNotifier.enterBaseMode(clearMask: true);
    workflowNotifier.setPanelExpanded(true);
  }

  static Future<void> openEditor(
    BuildContext context,
    WidgetRef ref,
    Uint8List imageBytes, {
    required ImageEditorMode mode,
  }) async {
    final workflowNotifier = ref.read(imageWorkflowControllerProvider.notifier);
    final workflow = ref.read(imageWorkflowControllerProvider);

    if (mode == ImageEditorMode.edit) {
      workflowNotifier.enterBaseMode(clearMask: true);
    } else if (ref.read(imageWorkflowControllerProvider).isEnhance) {
      workflowNotifier.enterBaseMode(clearMask: false);
    }

    final params = ref.read(generationParamsNotifierProvider);
    final result = await ImageEditorScreen.show(
      context,
      initialImage: imageBytes,
      existingMask: mode == ImageEditorMode.inpaint ? params.maskImage : null,
      existingFocusRect: mode == ImageEditorMode.inpaint
          ? workflow.focusedSelectionRect
          : null,
      initialMinimumContextMegaPixels: mode == ImageEditorMode.inpaint
          ? workflow.minimumContextMegaPixels
          : 88.0,
      initialFocusedInpaintEnabled: mode == ImageEditorMode.inpaint
          ? workflow.focusedInpaintEnabled
          : false,
      showMaskExport: mode == ImageEditorMode.inpaint,
      mode: mode,
      title: mode == ImageEditorMode.edit
          ? context.l10n.img2img_editImage
          : context.l10n.img2img_inpaint,
    );

    if (result == null || !context.mounted) {
      return;
    }

    AppLogger.d(
      'Editor returned: mode=$mode, hasImageChanges=${result.hasImageChanges}, '
          'hasMaskChanges=${result.hasMaskChanges}, '
          'modifiedBytes=${result.modifiedImage?.length ?? 0}, '
          'maskBytes=${result.maskImage?.length ?? 0}, '
          'focusRect=${result.focusAreaRect}, '
          'minContext=${result.minimumContextMegaPixels.toStringAsFixed(2)}, '
          'focusedEnabled=${result.focusedInpaintEnabled}',
      'ImageWorkflow',
    );

    if (mode == ImageEditorMode.edit) {
      if (result.hasImageChanges && result.modifiedImage != null) {
        workflowNotifier.replaceSourceImage(result.modifiedImage!);
        workflowNotifier.setPanelExpanded(true);
        AppToast.success(context, context.l10n.img2img_editApplied);
      }
      return;
    }

    final effectiveMask = result.maskImage != null &&
            InpaintMaskUtils.hasMaskedPixels(result.maskImage!)
        ? result.maskImage
        : null;
    workflowNotifier.applyInpaintEditorResult(
      maskImage: effectiveMask,
      focusedInpaintEnabled: result.focusedInpaintEnabled,
      focusedSelectionRect: result.focusAreaRect,
      minimumContextMegaPixels: result.minimumContextMegaPixels,
    );
    if (effectiveMask != null) {
      AppToast.success(context, context.l10n.img2img_inpaintMaskReady);
    } else if (result.maskImage != null) {
      AppToast.warning(context, '没有检测到有效蒙版，保存结果已忽略。');
    }
  }

  static void openEnhance(
    WidgetRef ref,
    Uint8List imageBytes,
  ) {
    final workflowNotifier = ref.read(imageWorkflowControllerProvider.notifier);
    workflowNotifier.replaceSourceImage(imageBytes);
    workflowNotifier.enterEnhanceMode();
    workflowNotifier.setPanelExpanded(true);
  }

  static Future<void> openInpaint(
    BuildContext context,
    WidgetRef ref,
    Uint8List imageBytes,
  ) async {
    final workflowNotifier = ref.read(imageWorkflowControllerProvider.notifier);
    workflowNotifier.replaceSourceImage(imageBytes);
    workflowNotifier.setPanelExpanded(true);
    await openEditor(
      context,
      ref,
      imageBytes,
      mode: ImageEditorMode.inpaint,
    );
  }

  /// 打开图生图「超分」子面板（内嵌，非弹窗）
  static void openUpscale(WidgetRef ref, Uint8List imageBytes) {
    final workflowNotifier = ref.read(imageWorkflowControllerProvider.notifier);
    workflowNotifier.replaceSourceImage(imageBytes);
    workflowNotifier.enterUpscaleMode();
    workflowNotifier.setPanelExpanded(true);
  }

  static Future<void> openDirectorTools(
    BuildContext context,
    WidgetRef ref,
    Uint8List imageBytes,
  ) async {
    final result = await DirectorToolsScreen.show(
      context,
      sourceImage: imageBytes,
    );
    if (result != null && context.mounted) {
      final workflowNotifier =
          ref.read(imageWorkflowControllerProvider.notifier);
      workflowNotifier.replaceSourceImage(result);
      workflowNotifier.setPanelExpanded(true);
      AppToast.success(context, context.l10n.img2img_directorApplied);
    }
  }

  static Future<void> generateVariations(
    BuildContext context,
    WidgetRef ref,
    Uint8List imageBytes,
  ) async {
    final workflowNotifier = ref.read(imageWorkflowControllerProvider.notifier);
    final paramsNotifier = ref.read(generationParamsNotifierProvider.notifier);

    workflowNotifier.replaceSourceImage(imageBytes);
    workflowNotifier.enterBaseMode(clearMask: true);
    workflowNotifier.setPanelExpanded(true);

    final metadata =
        await ImageMetadataService().getMetadataFromBytes(imageBytes);
    if (!context.mounted) {
      return;
    }

    if (metadata != null && metadata.hasData) {
      _applyVariationMetadata(
        metadata,
        ref,
        paramsNotifier,
        fallbackModel: ref.read(generationParamsNotifierProvider).model,
      );
    } else {
      paramsNotifier.randomizeSeed();
      paramsNotifier.updateStrength(0.45);
      paramsNotifier.updateNoise(0.0);
    }

    if (!context.mounted) return;
    AppToast.info(context, context.l10n.img2img_variationsStarted);

    final currentParams = ref.read(generationParamsNotifierProvider);
    ref.read(imageGenerationNotifierProvider.notifier).generate(currentParams);
  }

  static void _applyVariationMetadata(
    NaiImageMetadata metadata,
    WidgetRef ref,
    GenerationParamsNotifier notifier, {
    required String fallbackModel,
  }) {
    if (metadata.prompt.isNotEmpty) {
      notifier.updatePrompt(metadata.prompt);
    }
    final importModel = metadata.model ?? fallbackModel;
    final importNegativePrompt = metadata.ucPreset != null
        ? UcPresets.stripPresetByInt(
            metadata.negativePrompt,
            importModel,
            metadata.ucPreset!,
          )
        : metadata.negativePrompt;
    if (metadata.negativePrompt.isNotEmpty || metadata.ucPreset != null) {
      notifier.updateNegativePrompt(importNegativePrompt);
    }
    if (metadata.model != null && metadata.model!.isNotEmpty) {
      notifier.updateModel(metadata.model!);
    }
    if (metadata.sampler != null && metadata.sampler!.isNotEmpty) {
      notifier.updateSampler(metadata.sampler!);
    }
    if (metadata.steps != null) {
      notifier.updateSteps(metadata.steps!);
    }
    if (metadata.scale != null) {
      notifier.updateScale(metadata.scale!);
    }
    if (metadata.width != null && metadata.height != null) {
      notifier.updateSize(metadata.width!, metadata.height!);
    }
    if (metadata.noiseSchedule != null && metadata.noiseSchedule!.isNotEmpty) {
      notifier.updateNoiseSchedule(metadata.noiseSchedule!);
    }
    if (metadata.cfgRescale != null) {
      notifier.updateCfgRescale(metadata.cfgRescale!);
    }
    if (metadata.ucPreset != null) {
      notifier.updateUcPreset(metadata.ucPreset!);
      applyImportedUcPreset(ref.read, metadata.ucPreset!);
    }
    if (metadata.qualityToggle != null) {
      notifier.updateQualityToggle(metadata.qualityToggle!);
      applyImportedQualityToggle(ref.read, metadata.qualityToggle!);
    }
    if (metadata.smea != null) {
      notifier.updateSmea(metadata.smea!);
    }
    if (metadata.smeaDyn != null) {
      notifier.updateSmeaDyn(metadata.smeaDyn!);
    }
    if (metadata.varietyPlus != null) {
      notifier.updateVarietyPlus(metadata.varietyPlus!);
    }

    notifier.randomizeSeed();
    notifier.updateStrength(metadata.strength ?? 0.45);
    notifier.updateNoise(metadata.noise ?? 0.0);
  }
}
