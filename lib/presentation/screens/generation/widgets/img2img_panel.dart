import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../../core/utils/focused_inpaint_utils.dart';
import '../../../../core/utils/inpaint_mask_utils.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/datasources/remote/nai_image_enhancement_api_service.dart';
import '../../../../data/models/image/image_params.dart';
import '../../../providers/generation/image_workflow_controller.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../services/image_workflow_launcher.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/collapsible_image_panel.dart';
import '../../../widgets/common/image_picker_card/image_picker_card.dart';
import '../../../widgets/common/themed_divider.dart';
import '../../../widgets/image_editor/painters/focused_overlay_painter.dart';
import '../../../widgets/image_editor/image_editor_screen.dart';

enum _DirectorToolType {
  removeBackground,
  extractLineArt,
  toSketch,
  colorize,
  fixEmotion,
  declutter,
}

/// Img2Img 面板组件
class Img2ImgPanel extends ConsumerStatefulWidget {
  const Img2ImgPanel({super.key});

  @override
  ConsumerState<Img2ImgPanel> createState() => _Img2ImgPanelState();
}

class _Img2ImgPanelState extends ConsumerState<Img2ImgPanel> {
  bool _isDirectorRunning = false;
  _DirectorToolType _selectedDirectorTool = _DirectorToolType.removeBackground;
  Uint8List? _directorResult;
  String? _directorError;
  late final TextEditingController _directorPromptController;

  @override
  void initState() {
    super.initState();
    _directorPromptController = TextEditingController();
  }

  @override
  void dispose() {
    _directorPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = ref.watch(generationParamsNotifierProvider);
    final workflow = ref.watch(imageWorkflowControllerProvider);
    final hasSourceImage = params.sourceImage != null;
    final showBackground = hasSourceImage && !workflow.isPanelExpanded;

    ref.listen(generationParamsNotifierProvider, (previous, next) {
      if (previous?.sourceImage == next.sourceImage) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _directorResult = null;
          _directorError = null;
        });
      });
    });

    ref.listen(imageWorkflowControllerProvider, (previous, next) {
      if (previous?.showDirectorTools == next.showDirectorTools) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _directorResult = null;
          _directorError = null;
          if (next.showDirectorTools &&
              _directorPromptController.text.trim().isEmpty) {
            _directorPromptController.text =
                ref.read(generationParamsNotifierProvider).prompt;
          }
        });
      });
    });

    return CollapsibleImagePanel(
      title: context.l10n.img2img_title,
      icon: Icons.image,
      isExpanded: workflow.isPanelExpanded,
      onToggle: () => ref
          .read(imageWorkflowControllerProvider.notifier)
          .setPanelExpanded(!workflow.isPanelExpanded),
      hasData: hasSourceImage,
      backgroundImage: hasSourceImage
          ? Image.memory(
              params.sourceImage!,
              fit: BoxFit.cover,
            )
          : null,
      badge: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: showBackground
              ? Colors.white.withValues(alpha: 0.2)
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          context.l10n.img2img_enabled,
          style: theme.textTheme.labelSmall?.copyWith(
            color: showBackground
                ? Colors.white
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ThemedDivider(),
            _buildSourceImageSection(theme, params, workflow),
            if (hasSourceImage) ...[
              const SizedBox(height: 16),
              if (workflow.showDirectorTools)
                _buildDirectorToolsPanel(theme, params)
              else if (workflow.isEnhance)
                _buildEnhancePanel(theme, workflow)
              else if (workflow.isInpaint)
                _buildInpaintPanel(theme, params)
              else ...[
                if (workflow.isVariationPrepared) ...[
                  _buildVariationStatus(theme),
                  const SizedBox(height: 12),
                ],
                _buildStrengthSlider(theme, params),
                const SizedBox(height: 12),
                _buildNoiseSlider(theme, params),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _clearImg2Img,
                icon: const Icon(Icons.clear, size: 18),
                label: Text(context.l10n.img2img_clearSettings),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceImageSection(
    ThemeData theme,
    ImageParams params,
    ImageWorkflowState workflow,
  ) {
    final hasSourceImage = params.sourceImage != null;
    if (!hasSourceImage) {
      return _buildEmptySourceSection(theme);
    }

    final isInpaintReady = workflow.isInpaint && params.maskImage != null;
    final sourceDimensions =
        _resolveSourceDimensions(workflow, params.sourceImage!);
    final focusedFrame = workflow.isInpaint && workflow.focusedInpaintEnabled
        ? FocusedInpaintUtils.resolvePreviewFrame(
            sourceImage: params.sourceImage!,
            maskImage: params.maskImage,
            focusedSelectionRect: workflow.focusedSelectionRect,
            minContextMegaPixels: workflow.minimumContextMegaPixels,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              context.l10n.img2img_sourceImage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _IconButton(
              icon: Icons.refresh,
              onPressed: _pickImage,
              tooltip: context.l10n.img2img_changeImage,
            ),
            const SizedBox(width: 8),
            _IconButton(
              icon: Icons.close,
              onPressed: _removeSourceImage,
              tooltip: context.l10n.img2img_removeImage,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 280,
            child: _SourceImagePreview(
              sourceBytes: params.sourceImage!,
              maskOverlayBytes: params.maskImage == null
                  ? null
                  : InpaintMaskUtils.maskToEditorOverlay(params.maskImage!),
              focusedCrop: focusedFrame?.contextCrop,
              focusBounds: focusedFrame?.focusBounds,
              imageWidth: sourceDimensions.$1,
              imageHeight: sourceDimensions.$2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _OperationChip(
              icon: Icons.edit_outlined,
              label: context.l10n.img2img_editImage,
              onPressed: () => ImageWorkflowLauncher.openEditor(
                context,
                ref,
                params.sourceImage!,
                mode: ImageEditorMode.edit,
              ),
            ),
            _OperationChip(
              icon: isInpaintReady ? Icons.check_circle : Icons.draw_outlined,
              label: context.l10n.img2img_inpaint,
              selected: workflow.isInpaint,
              onPressed: () => ImageWorkflowLauncher.openEditor(
                context,
                ref,
                params.sourceImage!,
                mode: ImageEditorMode.inpaint,
              ),
            ),
            _OperationChip(
              icon: Icons.auto_awesome_motion_outlined,
              label: context.l10n.img2img_generateVariations,
              onPressed: () => ImageWorkflowLauncher.prepareVariations(
                context,
                ref,
                params.sourceImage!,
              ),
            ),
            _OperationChip(
              icon: Icons.auto_fix_high_outlined,
              label: context.l10n.img2img_directorTools,
              selected: workflow.showDirectorTools,
              onPressed: () => _toggleDirectorTools(workflow, params),
            ),
            _OperationChip(
              icon: workflow.isEnhance
                  ? Icons.auto_awesome
                  : Icons.auto_awesome_outlined,
              label: context.l10n.img2img_enhance,
              selected: workflow.isEnhance,
              onPressed: () => _toggleEnhance(workflow),
            ),
          ],
        ),
        if (workflow.isInpaint) ...[
          const SizedBox(height: 10),
          _buildInpaintStatus(theme, isInpaintReady),
        ],
      ],
    );
  }

  Widget _buildVariationStatus(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.lightGreenAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.lightGreenAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_motion,
            size: 16,
            color: Colors.lightGreenAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.img2img_variationsPreparedHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.lightGreenAccent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySourceSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.img2img_sourceImage,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ImagePickerCard(
                icon: Icons.upload_file,
                label: context.l10n.img2img_uploadImage,
                height: 80,
                onImageSelected: (bytes, fileName, path) {
                  ref
                      .read(imageWorkflowControllerProvider.notifier)
                      .replaceSourceImage(bytes);
                },
                onError: (error) {
                  AppToast.error(
                    context,
                    context.l10n.img2img_selectFailed(error),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ImagePickerCard(
                icon: Icons.brush,
                label: context.l10n.img2img_drawSketch,
                height: 80,
                enableDragDrop: false,
                onTap: _openBlankCanvas,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInpaintStatus(ThemeData theme, bool isReady) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isReady
                  ? context.l10n.img2img_inpaintReadyHint
                  : context.l10n.img2img_inpaintPendingHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orangeAccent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrengthSlider(ThemeData theme, ImageParams params) {
    return _buildSliderSection(
      theme,
      label: context.l10n.img2img_strength,
      value: params.strength,
      hint: context.l10n.img2img_strengthHint,
      onChanged: (value) {
        ref
            .read(generationParamsNotifierProvider.notifier)
            .updateStrength(value);
      },
    );
  }

  Widget _buildNoiseSlider(ThemeData theme, ImageParams params) {
    return _buildSliderSection(
      theme,
      label: context.l10n.img2img_noise,
      value: params.noise,
      hint: context.l10n.img2img_noiseHint,
      onChanged: (value) {
        ref.read(generationParamsNotifierProvider.notifier).updateNoise(value);
      },
    );
  }

  Widget _buildInpaintPanel(ThemeData theme, ImageParams params) {
    final workflow = ref.watch(imageWorkflowControllerProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSliderSection(
            theme,
            label: context.l10n.img2img_inpaintStrength,
            value: params.inpaintStrength,
            hint: context.l10n.img2img_inpaintStrengthHint,
            onChanged: (value) {
              ref
                  .read(generationParamsNotifierProvider.notifier)
                  .updateInpaintStrength(value);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Focused Inpainting（聚焦重绘）',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              workflow.focusedInpaintEnabled
                  ? '已启用。请在重绘编辑器左上角按钮里调整聚焦区域与 Minimum Context Area。'
                  : '默认是普通重绘；如需聚焦重绘，请在重绘编辑器左上角按钮中开启并框选区域。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: workflow.focusedInpaintEnabled
                    ? Colors.cyanAccent.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: workflow.focusedInpaintEnabled
                      ? Colors.cyanAccent.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                workflow.focusedInpaintEnabled ? '已启用' : '未启用',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: workflow.focusedInpaintEnabled
                      ? Colors.cyanAccent
                      : Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (int, int) _resolveSourceDimensions(
    ImageWorkflowState workflow,
    Uint8List sourceBytes,
  ) {
    final width = workflow.sourceWidth;
    final height = workflow.sourceHeight;
    if (width != null && height != null) {
      return (width, height);
    }

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return (1, 1);
    }
    return (decoded.width, decoded.height);
  }

  Widget _buildSliderSection(
    ThemeData theme, {
    required String label,
    required double value,
    ValueChanged<double>? onChanged,
    String? hint,
    double min = 0.0,
    double max = 1.0,
    int? divisions,
    String Function(double value)? valueLabelBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Text(
              valueLabelBuilder?.call(value) ?? value.toStringAsFixed(2),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions ?? ((max - min) * 100).round(),
            onChanged: onChanged,
          ),
        ),
        if (hint != null)
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
      ],
    );
  }

  Widget _buildEnhancePanel(
    ThemeData theme,
    ImageWorkflowState workflow,
  ) {
    final controller = ref.read(imageWorkflowControllerProvider.notifier);
    final enhance = workflow.enhance;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.img2img_enhance,
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.img2img_enhanceHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _buildSliderSection(
            theme,
            label: context.l10n.img2img_enhanceMagnitude,
            value: enhance.magnitude,
            onChanged: controller.updateEnhanceMagnitude,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.l10n.img2img_enhanceShowIndividualSettings,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            value: enhance.showIndividualSettings,
            onChanged: controller.toggleEnhanceIndividualSettings,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.img2img_enhanceUpscaleAmount,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [1.0, 1.5].map((factor) {
              final label = factor == 1.0 ? '1x' : '1.5x';
              return ChoiceChip(
                label: Text(label),
                selected: enhance.upscaleFactor == factor,
                onSelected: (_) =>
                    controller.updateEnhanceUpscaleFactor(factor),
              );
            }).toList(),
          ),
          if (enhance.showIndividualSettings) ...[
            const SizedBox(height: 12),
            _buildSliderSection(
              theme,
              label: context.l10n.img2img_strength,
              value: enhance.strength,
              onChanged: (value) => controller.updateEnhanceIndividualSettings(
                strength: value,
              ),
            ),
            const SizedBox(height: 12),
            _buildSliderSection(
              theme,
              label: context.l10n.img2img_noise,
              value: enhance.noise,
              onChanged: (value) => controller.updateEnhanceIndividualSettings(
                noise: value,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDirectorToolsPanel(
    ThemeData theme,
    ImageParams params,
  ) {
    final selectedToolLabel =
        _directorToolLabel(context, _selectedDirectorTool);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.img2img_directorTools,
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.img2img_directorToolsHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _DirectorToolType.values.map((tool) {
              return ChoiceChip(
                label: Text(_directorToolLabel(context, tool)),
                selected: _selectedDirectorTool == tool,
                onSelected: (_) {
                  setState(() {
                    _selectedDirectorTool = tool;
                    _directorError = null;
                  });
                },
              );
            }).toList(),
          ),
          if (_directorToolNeedsPrompt(_selectedDirectorTool)) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _directorPromptController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.l10n.img2img_directorPrompt,
                hintText: context.l10n.img2img_directorPromptHint,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isDirectorRunning || params.sourceImage == null
                ? null
                : () => _runDirectorTool(params.sourceImage!),
            icon: _isDirectorRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(
              _isDirectorRunning
                  ? context.l10n.img2img_directorRunning
                  : context.l10n.img2img_directorRun(selectedToolLabel),
            ),
          ),
          if (_directorError != null) ...[
            const SizedBox(height: 10),
            Text(
              _directorError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_directorResult != null) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.img2img_directorResult,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.memory(
                  _directorResult!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _applyDirectorResult,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: Text(context.l10n.common_apply),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _directorResult = null;
                        _directorError = null;
                      });
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(context.l10n.common_close),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes;

        if (file.bytes != null) {
          bytes = file.bytes;
        } else if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes != null) {
          ref
              .read(imageWorkflowControllerProvider.notifier)
              .replaceSourceImage(bytes);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(
          context,
          context.l10n.img2img_selectFailed(e.toString()),
        );
      }
    }
  }

  void _removeSourceImage() {
    _resetInlinePanels();
    ref.read(imageWorkflowControllerProvider.notifier).clearSourceImage();
  }

  void _clearImg2Img() {
    _removeSourceImage();
  }

  void _toggleEnhance(ImageWorkflowState workflow) {
    _resetInlinePanels();
    final controller = ref.read(imageWorkflowControllerProvider.notifier);
    if (workflow.isEnhance) {
      controller.exitEnhanceMode();
    } else {
      controller.enterEnhanceMode();
    }
  }

  void _toggleDirectorTools(
    ImageWorkflowState workflow,
    ImageParams params,
  ) {
    final controller = ref.read(imageWorkflowControllerProvider.notifier);
    if (workflow.showDirectorTools) {
      controller.hideDirectorToolsPanel();
      return;
    }

    _directorResult = null;
    _directorError = null;
    if (_directorPromptController.text.trim().isEmpty) {
      _directorPromptController.text = params.prompt;
    }
    controller.showDirectorToolsPanel();
  }

  Future<void> _openBlankCanvas() async {
    final params = ref.read(generationParamsNotifierProvider);
    final canvasSize = Size(
      params.width.toDouble(),
      params.height.toDouble(),
    );

    _resetInlinePanels();
    final result = await ImageEditorScreen.show(
      context,
      initialSize: canvasSize,
      mode: ImageEditorMode.edit,
      title: context.l10n.img2img_drawSketch,
    );

    if (result != null && result.modifiedImage != null && mounted) {
      ref
          .read(imageWorkflowControllerProvider.notifier)
          .replaceSourceImage(result.modifiedImage!);
      ref.read(imageWorkflowControllerProvider.notifier).setPanelExpanded(true);
    }
  }

  Future<void> _runDirectorTool(Uint8List imageBytes) async {
    setState(() {
      _isDirectorRunning = true;
      _directorError = null;
      _directorResult = null;
    });

    try {
      final service = ref.read(naiImageEnhancementApiServiceProvider);
      final prompt = _directorPromptController.text.trim();

      final Uint8List result;
      switch (_selectedDirectorTool) {
        case _DirectorToolType.removeBackground:
          result = await service.removeBackground(imageBytes);
        case _DirectorToolType.extractLineArt:
          result = await service.extractLineArt(imageBytes);
        case _DirectorToolType.toSketch:
          result = await service.toSketch(imageBytes);
        case _DirectorToolType.colorize:
          result = await service.colorize(
            imageBytes,
            prompt: prompt.isEmpty ? null : prompt,
          );
        case _DirectorToolType.fixEmotion:
          result = await service.fixEmotion(
            imageBytes,
            prompt: prompt.isEmpty
                ? ref.read(generationParamsNotifierProvider).prompt
                : prompt,
          );
        case _DirectorToolType.declutter:
          result = await service.declutter(imageBytes);
      }

      if (!mounted) {
        return;
      }

      var saveParams = ref.read(generationParamsNotifierProvider);
      if (_directorToolNeedsPrompt(_selectedDirectorTool) &&
          prompt.isNotEmpty) {
        saveParams = saveParams.copyWith(prompt: prompt);
      }

      await ref
          .read(imageGenerationNotifierProvider.notifier)
          .registerExternalImage(
            result,
            params: saveParams,
            saveToLocal: true,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _directorResult = result;
        _directorError = null;
      });

      AppToast.success(
        context,
        context.l10n.img2img_directorResultReady(
          _directorToolLabel(context, _selectedDirectorTool),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _directorError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDirectorRunning = false;
        });
      }
    }
  }

  void _applyDirectorResult() {
    if (_directorResult == null) {
      return;
    }

    final resultBytes = _directorResult!;
    _resetInlinePanels();
    ref
        .read(imageWorkflowControllerProvider.notifier)
        .replaceSourceImage(resultBytes);
    ref
        .read(imageWorkflowControllerProvider.notifier)
        .enterBaseMode(clearMask: true);
    ref.read(imageWorkflowControllerProvider.notifier).setPanelExpanded(true);

    if (mounted) {
      AppToast.success(context, context.l10n.img2img_directorApplied);
    }
  }

  void _resetInlinePanels() {
    ref.read(imageWorkflowControllerProvider.notifier).hideDirectorToolsPanel();
    ref.read(imageWorkflowControllerProvider.notifier).clearVariationPrepared();
    setState(() {
      _directorResult = null;
      _directorError = null;
    });
  }

  bool _directorToolNeedsPrompt(_DirectorToolType tool) {
    return tool == _DirectorToolType.colorize ||
        tool == _DirectorToolType.fixEmotion;
  }

  String _directorToolLabel(BuildContext context, _DirectorToolType tool) {
    switch (tool) {
      case _DirectorToolType.removeBackground:
        return context.l10n.img2img_directorRemoveBackground;
      case _DirectorToolType.extractLineArt:
        return context.l10n.img2img_directorLineArt;
      case _DirectorToolType.toSketch:
        return context.l10n.img2img_directorSketch;
      case _DirectorToolType.colorize:
        return context.l10n.img2img_directorColorize;
      case _DirectorToolType.fixEmotion:
        return context.l10n.img2img_directorEmotion;
      case _DirectorToolType.declutter:
        return context.l10n.img2img_directorDeclutter;
    }
  }
}

class _OperationChip extends StatelessWidget {
  const _OperationChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceImagePreview extends StatelessWidget {
  const _SourceImagePreview({
    required this.sourceBytes,
    required this.imageWidth,
    required this.imageHeight,
    this.maskOverlayBytes,
    this.focusedCrop,
    this.focusBounds,
  });

  final Uint8List sourceBytes;
  final Uint8List? maskOverlayBytes;
  final FocusedInpaintCrop? focusedCrop;
  final FocusedInpaintCrop? focusBounds;
  final int imageWidth;
  final int imageHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final containedSize = _resolveContainedSize(
            imageWidth: imageWidth.toDouble(),
            imageHeight: imageHeight.toDouble(),
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          );

          return Center(
            child: SizedBox(
              width: containedSize.width,
              height: containedSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    sourceBytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  if (maskOverlayBytes != null)
                    IgnorePointer(
                      child: Image.memory(
                        maskOverlayBytes!,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                  if (focusedCrop != null)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _FocusedCropOverlayPainter(
                          crop: focusedCrop!,
                          focusBounds: focusBounds,
                          imageWidth: imageWidth,
                          imageHeight: imageHeight,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Size _resolveContainedSize({
    required double imageWidth,
    required double imageHeight,
    required double maxWidth,
    required double maxHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      return Size(maxWidth, maxHeight);
    }

    final scale = math.min(maxWidth / imageWidth, maxHeight / imageHeight);
    return Size(imageWidth * scale, imageHeight * scale);
  }
}

class _FocusedCropOverlayPainter extends CustomPainter {
  const _FocusedCropOverlayPainter({
    required this.crop,
    required this.focusBounds,
    required this.imageWidth,
    required this.imageHeight,
  });

  final FocusedInpaintCrop crop;
  final FocusedInpaintCrop? focusBounds;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final contextRect = Rect.fromLTWH(
      crop.x / imageWidth * size.width,
      crop.y / imageHeight * size.height,
      crop.width / imageWidth * size.width,
      crop.height / imageHeight * size.height,
    );
    final contextPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(contextRect, const Radius.circular(2)),
      );

    if (focusBounds != null) {
      final selectionRect = Rect.fromLTWH(
        focusBounds!.x / imageWidth * size.width,
        focusBounds!.y / imageHeight * size.height,
        focusBounds!.width / imageWidth * size.width,
        focusBounds!.height / imageHeight * size.height,
      );
      final focusPath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(selectionRect, const Radius.circular(2)),
        );
      FocusedOverlayPainter(
        contextPath: contextPath,
        focusPath: focusPath,
      ).paint(canvas, size);
      return;
    }

    FocusedOverlayPainter(
      contextPath: contextPath,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _FocusedCropOverlayPainter oldDelegate) {
    return crop.x != oldDelegate.crop.x ||
        crop.y != oldDelegate.crop.y ||
        crop.width != oldDelegate.crop.width ||
        crop.height != oldDelegate.crop.height ||
        focusBounds?.x != oldDelegate.focusBounds?.x ||
        focusBounds?.y != oldDelegate.focusBounds?.y ||
        focusBounds?.width != oldDelegate.focusBounds?.width ||
        focusBounds?.height != oldDelegate.focusBounds?.height ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight;
  }
}

/// 小型图标按钮
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
