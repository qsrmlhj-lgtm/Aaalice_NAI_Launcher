import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../core/constants/api_constants.dart';
import '../../../data/models/image/image_params.dart';
import 'generation_params_notifier.dart';

enum ImageWorkflowMode {
  base,
  inpaint,
  enhance,
}

class EnhanceWorkflowSettings {
  const EnhanceWorkflowSettings({
    this.magnitude = 0.5,
    this.showIndividualSettings = false,
    this.upscaleFactor = 1.0,
    this.strength = 0.5,
    this.noise = 0.175,
  });

  final double magnitude;
  final bool showIndividualSettings;
  final double upscaleFactor;
  final double strength;
  final double noise;

  EnhanceWorkflowSettings copyWith({
    double? magnitude,
    bool? showIndividualSettings,
    double? upscaleFactor,
    double? strength,
    double? noise,
  }) {
    return EnhanceWorkflowSettings(
      magnitude: magnitude ?? this.magnitude,
      showIndividualSettings:
          showIndividualSettings ?? this.showIndividualSettings,
      upscaleFactor: upscaleFactor ?? this.upscaleFactor,
      strength: strength ?? this.strength,
      noise: noise ?? this.noise,
    );
  }
}

class ImageWorkflowState {
  const ImageWorkflowState({
    this.mode = ImageWorkflowMode.base,
    this.sourceWidth,
    this.sourceHeight,
    this.baseWidth,
    this.baseHeight,
    this.baseStrength,
    this.baseNoise,
    this.baseModel,
    this.enhance = const EnhanceWorkflowSettings(),
    this.isPanelExpanded = false,
    this.showDirectorTools = false,
    this.isVariationPrepared = false,
    this.focusedInpaintEnabled = false,
    this.minimumContextMegaPixels = 88.0,
    this.focusedSelectionRect,
  });

  final ImageWorkflowMode mode;
  final int? sourceWidth;
  final int? sourceHeight;
  final int? baseWidth;
  final int? baseHeight;
  final double? baseStrength;
  final double? baseNoise;
  final String? baseModel;
  final EnhanceWorkflowSettings enhance;
  final bool isPanelExpanded;
  final bool showDirectorTools;
  final bool isVariationPrepared;
  final bool focusedInpaintEnabled;
  final double minimumContextMegaPixels;
  final Rect? focusedSelectionRect;

  bool get isEnhance => mode == ImageWorkflowMode.enhance;
  bool get isInpaint => mode == ImageWorkflowMode.inpaint;

  ImageWorkflowState copyWith({
    ImageWorkflowMode? mode,
    int? sourceWidth,
    int? sourceHeight,
    int? baseWidth,
    int? baseHeight,
    double? baseStrength,
    double? baseNoise,
    String? baseModel,
    EnhanceWorkflowSettings? enhance,
    bool? isPanelExpanded,
    bool? showDirectorTools,
    bool? isVariationPrepared,
    bool? focusedInpaintEnabled,
    double? minimumContextMegaPixels,
    Rect? focusedSelectionRect,
    bool clearSourceSize = false,
    bool clearBaseSnapshot = false,
    bool clearFocusedSelectionRect = false,
  }) {
    return ImageWorkflowState(
      mode: mode ?? this.mode,
      sourceWidth: clearSourceSize ? null : (sourceWidth ?? this.sourceWidth),
      sourceHeight:
          clearSourceSize ? null : (sourceHeight ?? this.sourceHeight),
      baseWidth: clearBaseSnapshot ? null : (baseWidth ?? this.baseWidth),
      baseHeight: clearBaseSnapshot ? null : (baseHeight ?? this.baseHeight),
      baseStrength:
          clearBaseSnapshot ? null : (baseStrength ?? this.baseStrength),
      baseNoise: clearBaseSnapshot ? null : (baseNoise ?? this.baseNoise),
      baseModel: clearBaseSnapshot ? null : (baseModel ?? this.baseModel),
      enhance: enhance ?? this.enhance,
      isPanelExpanded: isPanelExpanded ?? this.isPanelExpanded,
      showDirectorTools: showDirectorTools ?? this.showDirectorTools,
      isVariationPrepared: isVariationPrepared ?? this.isVariationPrepared,
      focusedInpaintEnabled:
          focusedInpaintEnabled ?? this.focusedInpaintEnabled,
      minimumContextMegaPixels:
          minimumContextMegaPixels ?? this.minimumContextMegaPixels,
      focusedSelectionRect: clearFocusedSelectionRect
          ? null
          : (focusedSelectionRect ?? this.focusedSelectionRect),
    );
  }
}

final imageWorkflowControllerProvider =
    NotifierProvider<ImageWorkflowController, ImageWorkflowState>(
  ImageWorkflowController.new,
);

class ImageWorkflowController extends Notifier<ImageWorkflowState> {
  @override
  ImageWorkflowState build() => const ImageWorkflowState();

  GenerationParamsNotifier get _paramsNotifier =>
      ref.read(generationParamsNotifierProvider.notifier);

  ImageParams get _params => ref.read(generationParamsNotifierProvider);

  void replaceSourceImage(
    Uint8List imageBytes, {
    int? sourceWidth,
    int? sourceHeight,
  }) {
    _paramsNotifier.setSourceImage(imageBytes);

    final resolvedSize =
        _resolveImageSize(imageBytes, width: sourceWidth, height: sourceHeight);
    state = state.copyWith(
      sourceWidth: resolvedSize?.$1,
      sourceHeight: resolvedSize?.$2,
      isVariationPrepared: false,
      clearFocusedSelectionRect: true,
    );

    switch (state.mode) {
      case ImageWorkflowMode.enhance:
        _ensureBaseSnapshot();
        _applyEnhanceToParams();
        break;
      case ImageWorkflowMode.inpaint:
        _restoreBaseParams();
        _applySourceSizeToParams();
        _paramsNotifier.setMaskImage(null);
        state = state.copyWith(
          mode: ImageWorkflowMode.base,
          clearBaseSnapshot: true,
          showDirectorTools: false,
          isVariationPrepared: false,
          clearFocusedSelectionRect: true,
        );
        _paramsNotifier.updateAction(ImageGenerationAction.img2img);
        break;
      case ImageWorkflowMode.base:
        _ensureBaseSnapshot();
        _applySourceSizeToParams();
        _paramsNotifier.updateAction(ImageGenerationAction.img2img);
        break;
    }
  }

  void clearSourceImage() {
    if (state.baseWidth != null ||
        state.baseHeight != null ||
        state.baseModel != null) {
      _restoreBaseParams();
    } else if (ImageModels.isInpaintingModel(_params.model)) {
      _paramsNotifier.updateModel(
        _resolveBaseModel(_params.model),
        persist: false,
      );
    }

    _paramsNotifier.clearImg2Img();
    _paramsNotifier.setMaskImage(null);
    state = const ImageWorkflowState();
  }

  void setPanelExpanded(bool value) {
    state = state.copyWith(isPanelExpanded: value);
  }

  void setSourceImageDimensions(int? width, int? height) {
    state = state.copyWith(sourceWidth: width, sourceHeight: height);
    if (state.mode == ImageWorkflowMode.enhance) {
      _applyEnhanceToParams();
    }
  }

  void setFocusedInpaintEnabled(bool value) {
    state = state.copyWith(
      focusedInpaintEnabled: value,
      clearFocusedSelectionRect: !value,
    );
  }

  void setMinimumContextMegaPixels(double value) {
    state = state.copyWith(
      minimumContextMegaPixels: value.clamp(0.0, 192.0),
    );
  }

  void setFocusedSelectionRect(Rect? rect) {
    state = state.copyWith(
      focusedSelectionRect: rect,
      clearFocusedSelectionRect: rect == null,
    );
  }

  void enterEnhanceMode() {
    if (_params.sourceImage == null) {
      return;
    }

    _ensureBaseSnapshot();
    state = state.copyWith(
      mode: ImageWorkflowMode.enhance,
      isPanelExpanded: true,
      showDirectorTools: false,
      isVariationPrepared: false,
    );
    _applyEnhanceToParams();
  }

  void exitEnhanceMode() {
    if (state.mode != ImageWorkflowMode.enhance) {
      return;
    }

    _restoreBaseParams();
    state = state.copyWith(
      mode: ImageWorkflowMode.base,
      clearBaseSnapshot: true,
      showDirectorTools: false,
      isVariationPrepared: false,
    );
    _paramsNotifier.updateAction(
      _params.sourceImage != null
          ? ImageGenerationAction.img2img
          : ImageGenerationAction.generate,
    );
  }

  void enterInpaintMode() {
    if (_params.sourceImage == null) {
      return;
    }

    if (state.mode == ImageWorkflowMode.enhance) {
      _restoreBaseParams();
    }

    _ensureBaseSnapshot();
    state = state.copyWith(
      mode: ImageWorkflowMode.inpaint,
      isPanelExpanded: true,
      showDirectorTools: false,
      isVariationPrepared: false,
    );

    _applySourceSizeToParams();
    _syncInpaintRequestState();
  }

  void enterBaseMode({bool clearMask = true}) {
    final shouldRestoreBaseSnapshot = state.mode == ImageWorkflowMode.enhance ||
        state.mode == ImageWorkflowMode.inpaint;

    if (shouldRestoreBaseSnapshot) {
      _restoreBaseParams();
    }

    if (clearMask) {
      _paramsNotifier.setMaskImage(null);
    }

    state = state.copyWith(
      mode: ImageWorkflowMode.base,
      clearBaseSnapshot: shouldRestoreBaseSnapshot,
      showDirectorTools: false,
      isVariationPrepared: false,
      clearFocusedSelectionRect: clearMask,
    );
    _applySourceSizeToParams();
    _paramsNotifier.updateAction(
      _params.sourceImage != null
          ? ImageGenerationAction.img2img
          : ImageGenerationAction.generate,
    );
  }

  void onMaskChanged(Uint8List? mask) {
    _paramsNotifier.setMaskImage(mask);
    if (state.mode == ImageWorkflowMode.inpaint) {
      _syncInpaintRequestState();
    }
  }

  void showDirectorToolsPanel() {
    if (_params.sourceImage == null) {
      return;
    }

    if (state.mode == ImageWorkflowMode.enhance) {
      _restoreBaseParams();
    }

    state = state.copyWith(
      mode: ImageWorkflowMode.base,
      clearBaseSnapshot: state.mode == ImageWorkflowMode.enhance,
      isPanelExpanded: true,
      showDirectorTools: true,
      isVariationPrepared: false,
    );
    _paramsNotifier.updateAction(ImageGenerationAction.img2img);
  }

  void hideDirectorToolsPanel() {
    if (!state.showDirectorTools) {
      return;
    }

    state = state.copyWith(showDirectorTools: false);
  }

  void markVariationPrepared() {
    if (_params.sourceImage == null) {
      return;
    }

    state = state.copyWith(
      mode: ImageWorkflowMode.base,
      isPanelExpanded: true,
      showDirectorTools: false,
      isVariationPrepared: true,
    );
    _paramsNotifier.updateAction(ImageGenerationAction.img2img);
  }

  void clearVariationPrepared() {
    if (!state.isVariationPrepared) {
      return;
    }

    state = state.copyWith(isVariationPrepared: false);
  }

  void updateEnhanceMagnitude(double value) {
    final resolved = _resolveMagnitude(value);
    state = state.copyWith(
      enhance: state.enhance.copyWith(
        magnitude: value,
        strength: state.enhance.showIndividualSettings
            ? state.enhance.strength
            : resolved.$1,
        noise: state.enhance.showIndividualSettings
            ? state.enhance.noise
            : resolved.$2,
      ),
    );

    if (!state.enhance.showIndividualSettings) {
      _applyEnhanceToParams();
    }
  }

  void toggleEnhanceIndividualSettings(bool value) {
    final resolved = _resolveMagnitude(state.enhance.magnitude);
    state = state.copyWith(
      enhance: state.enhance.copyWith(
        showIndividualSettings: value,
        strength: value ? state.enhance.strength : resolved.$1,
        noise: value ? state.enhance.noise : resolved.$2,
      ),
    );
    _applyEnhanceToParams();
  }

  void updateEnhanceUpscaleFactor(double factor) {
    state = state.copyWith(
      enhance: state.enhance.copyWith(
        upscaleFactor: factor <= 1.0 ? 1.0 : 1.5,
      ),
    );
    _applyEnhanceToParams();
  }

  void updateEnhanceIndividualSettings({
    double? strength,
    double? noise,
  }) {
    state = state.copyWith(
      enhance: state.enhance.copyWith(
        showIndividualSettings: true,
        strength: strength ?? state.enhance.strength,
        noise: noise ?? state.enhance.noise,
      ),
    );
    _applyEnhanceToParams();
  }

  void _ensureBaseSnapshot() {
    if (state.baseWidth != null &&
        state.baseHeight != null &&
        state.baseStrength != null &&
        state.baseNoise != null) {
      return;
    }

    state = state.copyWith(
      baseWidth: _params.width,
      baseHeight: _params.height,
      baseStrength: _params.strength,
      baseNoise: _params.noise,
      baseModel: _resolveBaseModel(_params.model),
    );
  }

  void _restoreBaseParams() {
    if (state.baseWidth != null && state.baseHeight != null) {
      _paramsNotifier.updateSize(
        state.baseWidth!,
        state.baseHeight!,
        persist: false,
      );
    }
    if (state.baseStrength != null) {
      _paramsNotifier.updateStrength(state.baseStrength!);
    }
    if (state.baseNoise != null) {
      _paramsNotifier.updateNoise(state.baseNoise!);
    }
    if (state.baseModel != null) {
      _paramsNotifier.updateModel(state.baseModel!, persist: false);
    }
  }

  void _applyEnhanceToParams() {
    if (_params.sourceImage == null) {
      return;
    }

    final baseWidth = state.sourceWidth ?? state.baseWidth ?? _params.width;
    final baseHeight = state.sourceHeight ?? state.baseHeight ?? _params.height;
    final requestWidth =
        _normalizeDimension((baseWidth * state.enhance.upscaleFactor).round());
    final requestHeight =
        _normalizeDimension((baseHeight * state.enhance.upscaleFactor).round());
    final resolved = state.enhance.showIndividualSettings
        ? (state.enhance.strength, state.enhance.noise)
        : _resolveMagnitude(state.enhance.magnitude);

    _paramsNotifier.updateSize(requestWidth, requestHeight, persist: false);
    _paramsNotifier.updateStrength(resolved.$1);
    _paramsNotifier.updateNoise(resolved.$2);
    _paramsNotifier.updateAction(ImageGenerationAction.img2img);
  }

  void _applySourceSizeToParams() {
    final width = state.sourceWidth;
    final height = state.sourceHeight;
    if (width == null || height == null) {
      return;
    }

    _paramsNotifier.updateSize(width, height, persist: false);
  }

  void _applyInpaintModel() {
    final sourceModel = state.baseModel ?? _params.model;
    _paramsNotifier.updateModel(
      _resolveInpaintModel(sourceModel),
      persist: false,
    );
  }

  void _restoreBaseModel() {
    final baseModel = state.baseModel ?? _resolveBaseModel(_params.model);
    _paramsNotifier.updateModel(baseModel, persist: false);
  }

  void _syncInpaintRequestState() {
    if (state.mode != ImageWorkflowMode.inpaint) {
      return;
    }

    if (_params.maskImage != null) {
      _applyInpaintModel();
      _paramsNotifier.updateAction(ImageGenerationAction.infill);
      return;
    }

    _restoreBaseModel();
    _paramsNotifier.updateAction(ImageGenerationAction.img2img);
  }

  String _resolveInpaintModel(String model) {
    if (ImageModels.isInpaintingModel(model)) {
      return model;
    }

    switch (model) {
      case ImageModels.animeDiffusionV45Full:
        return ImageModels.animeDiffusionV45FullInpainting;
      case ImageModels.animeDiffusionV45Curated:
        return ImageModels.animeDiffusionV45CuratedInpainting;
      case ImageModels.animeDiffusionV4Full:
        return ImageModels.animeDiffusionV4FullInpainting;
      case ImageModels.animeDiffusionV4Curated:
        return ImageModels.animeDiffusionV4CuratedInpainting;
      case ImageModels.furryDiffusion:
      case ImageModels.furryDiffusionV3:
        return ImageModels.furryDiffusionV3Inpainting;
      case ImageModels.animeDiffusionV3:
      default:
        return ImageModels.animeDiffusionV3Inpainting;
    }
  }

  String _resolveBaseModel(String model) {
    switch (model) {
      case ImageModels.animeDiffusionV45FullInpainting:
        return ImageModels.animeDiffusionV45Full;
      case ImageModels.animeDiffusionV45CuratedInpainting:
        return ImageModels.animeDiffusionV45Curated;
      case ImageModels.animeDiffusionV4FullInpainting:
        return ImageModels.animeDiffusionV4Full;
      case ImageModels.animeDiffusionV4CuratedInpainting:
        return ImageModels.animeDiffusionV4Curated;
      case ImageModels.furryDiffusionV3Inpainting:
        return ImageModels.furryDiffusionV3;
      case ImageModels.animeDiffusionV3Inpainting:
        return ImageModels.animeDiffusionV3;
      default:
        return model;
    }
  }

  (double, double) _resolveMagnitude(double magnitude) {
    final clamped = magnitude.clamp(0.0, 1.0);
    // Magnitude 在 UI 中作为 Strength/Noise 的快捷联动值使用。
    // 这里先采用保守映射，避免增强时默认噪声过高。
    return (clamped, clamped * 0.35);
  }

  int _normalizeDimension(int value) {
    final normalized = ((value + 32) ~/ 64) * 64;
    return normalized.clamp(64, 4096);
  }

  (int, int)? _resolveImageSize(
    Uint8List imageBytes, {
    int? width,
    int? height,
  }) {
    if (width != null && height != null) {
      return (width, height);
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return null;
    }
    return (decoded.width, decoded.height);
  }
}
