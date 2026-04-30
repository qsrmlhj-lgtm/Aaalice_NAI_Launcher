import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// NovelAI 分辨率适配器
///
/// 将任意尺寸图像缩放到最接近的 NovelAI 兼容分辨率（64 的倍数），
/// 使用双三次（Cubic/Lanczos-like）插值，保证最小程度的缩放变形。
class NaiResolutionAdapter {
  NaiResolutionAdapter._();

  /// 检查尺寸是否已经兼容 NAI（宽高均为 64 的倍数）
  static bool isCompatible(int width, int height) {
    return width % 64 == 0 && height % 64 == 0 && width >= 64 && height >= 64;
  }

  /// 找到最接近的 NAI 兼容分辨率
  ///
  /// 策略：
  ///   1. 先检查是否已经是 64 倍数 → 直接返回
  ///   2. 将宽高分别舍入到最近的 64 倍数
  ///   3. 在 4 种组合（floor/ceil × floor/ceil）中选面积变化和宽高比偏移最小的
  ///   4. 保证结果 >= 64 且 <= 4096
  static ({int width, int height, double scaleFactor}) findClosestResolution(
    int sourceWidth,
    int sourceHeight,
  ) {
    if (isCompatible(sourceWidth, sourceHeight)) {
      return (width: sourceWidth, height: sourceHeight, scaleFactor: 1.0);
    }

    // 对宽高分别做 floor/ceil 到 64 倍数，取最优组合
    final wFloor = _floorTo64(sourceWidth);
    final wCeil = _ceilTo64(sourceWidth);
    final hFloor = _floorTo64(sourceHeight);
    final hCeil = _ceilTo64(sourceHeight);

    final candidates = [
      (wFloor, hFloor),
      (wFloor, hCeil),
      (wCeil, hFloor),
      (wCeil, hCeil),
    ];

    var bestW = wFloor;
    var bestH = hFloor;
    var bestScore = double.infinity;

    for (final (cw, ch) in candidates) {
      if (cw < 64 || ch < 64 || cw > 4096 || ch > 4096) continue;

      // 评分 = 面积变化比 + 宽高比偏移（加权）
      final areaRatio = (cw * ch) / (sourceWidth * sourceHeight);
      final arSource = sourceWidth / sourceHeight;
      final arCandidate = cw / ch;
      final arDiff = (arSource - arCandidate).abs() / arSource;
      final score = (areaRatio - 1.0).abs() + arDiff * 2.0;

      if (score < bestScore) {
        bestScore = score;
        bestW = cw;
        bestH = ch;
      }
    }

    final scale = _combinedScale(sourceWidth, sourceHeight, bestW, bestH);
    return (width: bestW, height: bestH, scaleFactor: scale);
  }

  /// 将图像字节数据适配到最近的 NAI 兼容分辨率
  ///
  /// 如果图像已经兼容，直接返回原数据，不做任何处理。
  /// 使用 Cubic（双三次，最接近 Lanczos）插值以保证质量。
  ///
  /// 返回 null 表示解码失败。
  static NaiAdaptedImage? adaptImage(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final srcW = decoded.width;
    final srcH = decoded.height;

    if (isCompatible(srcW, srcH)) {
      return NaiAdaptedImage(
        bytes: imageBytes,
        width: srcW,
        height: srcH,
        wasResized: false,
        originalWidth: srcW,
        originalHeight: srcH,
      );
    }

    final target = findClosestResolution(srcW, srcH);

    final resized = img.copyResize(
      decoded,
      width: target.width,
      height: target.height,
      interpolation: img.Interpolation.cubic,
    );

    final encoded = img.encodePng(resized);

    return NaiAdaptedImage(
      bytes: Uint8List.fromList(encoded),
      width: target.width,
      height: target.height,
      wasResized: true,
      originalWidth: srcW,
      originalHeight: srcH,
    );
  }

  /// 异步版本，适合大图在 isolate 中处理
  static Future<NaiAdaptedImage?> adaptImageAsync(Uint8List imageBytes) async {
    return adaptImage(imageBytes);
  }

  // ==================== 内部方法 ====================

  static int _floorTo64(int value) {
    final result = (value ~/ 64) * 64;
    return result.clamp(64, 4096);
  }

  static int _ceilTo64(int value) {
    final result = ((value + 63) ~/ 64) * 64;
    return result.clamp(64, 4096);
  }

  static double _combinedScale(
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final scaleW = dstW / srcW;
    final scaleH = dstH / srcH;
    return (scaleW + scaleH) / 2.0;
  }
}

/// 适配后的图像数据
class NaiAdaptedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  /// 是否经过了缩放
  final bool wasResized;

  /// 原始宽度
  final int originalWidth;

  /// 原始高度
  final int originalHeight;

  const NaiAdaptedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.wasResized,
    required this.originalWidth,
    required this.originalHeight,
  });

  String get resizeDescription {
    if (!wasResized) return '无需调整';
    return '$originalWidth×$originalHeight → $width×$height';
  }
}
