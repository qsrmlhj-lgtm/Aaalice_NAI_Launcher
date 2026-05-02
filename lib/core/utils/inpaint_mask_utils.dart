import 'dart:collection';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Inpaint 蒙版处理工具
class InpaintMaskUtils {
  InpaintMaskUtils._();

  static const int _alphaThreshold = 8;
  static const int _colorThreshold = 32;

  /// 将任意输入蒙版归一化为 NovelAI 更稳定的黑白二值蒙版。
  static Uint8List normalizeMaskBytes(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return bytes;
    }
    if (decoded == null) {
      return bytes;
    }

    final binaryMask = _createBinaryMask(decoded);
    return _encodeBinaryMask(binaryMask, decoded.width, decoded.height);
  }

  static bool hasMaskedPixels(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return false;
    }
    if (decoded == null) {
      return false;
    }

    final binaryMask = _createBinaryMask(decoded);
    return binaryMask.any((value) => value == 1);
  }

  /// 将封闭轮廓内部的透明空洞补成白色蒙版。
  ///
  /// 仅填充与画布边界不连通的透明区域，保持开放轮廓不变。
  static Uint8List fillClosedMaskRegions(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return bytes;
    }
    if (decoded == null) {
      return bytes;
    }

    final width = decoded.width;
    final height = decoded.height;
    final binaryMask = _createBinaryMask(decoded);
    final outside = Uint8List(width * height);
    final queue = Queue<int>();

    void enqueueIfTransparent(int x, int y) {
      final index = y * width + x;
      if (binaryMask[index] == 0 && outside[index] == 0) {
        outside[index] = 1;
        queue.add(index);
      }
    }

    for (var x = 0; x < width; x++) {
      enqueueIfTransparent(x, 0);
      enqueueIfTransparent(x, height - 1);
    }
    for (var y = 1; y < height - 1; y++) {
      enqueueIfTransparent(0, y);
      enqueueIfTransparent(width - 1, y);
    }

    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      final x = index % width;
      final y = index ~/ width;

      if (x > 0) enqueueIfTransparent(x - 1, y);
      if (x + 1 < width) enqueueIfTransparent(x + 1, y);
      if (y > 0) enqueueIfTransparent(x, y - 1);
      if (y + 1 < height) enqueueIfTransparent(x, y + 1);
    }

    final filledMask = Uint8List.fromList(binaryMask);
    for (var index = 0; index < filledMask.length; index++) {
      if (filledMask[index] == 0 && outside[index] == 0) {
        filledMask[index] = 1;
      }
    }

    return _encodeBinaryMask(filledMask, width, height);
  }

  /// 模拟油漆桶：仅填充用户点击到的封闭透明区域。
  ///
  /// 如果点击位置超出范围、落在已有蒙版上，或该区域与边界连通，则保持原样。
  static Uint8List fillMaskRegionAtPoint(
    Uint8List bytes, {
    required int x,
    required int y,
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return bytes;
    }
    if (decoded == null) {
      return bytes;
    }

    final width = decoded.width;
    final height = decoded.height;
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return bytes;
    }

    final binaryMask = _createBinaryMask(decoded);
    final startIndex = y * width + x;
    if (binaryMask[startIndex] == 1) {
      return _encodeBinaryMask(binaryMask, width, height);
    }

    final visited = Uint8List(width * height);
    final queue = Queue<int>()..add(startIndex);
    final region = <int>[];
    visited[startIndex] = 1;
    var touchesBorder = false;

    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      region.add(index);
      final currentX = index % width;
      final currentY = index ~/ width;

      if (currentX == 0 ||
          currentX == width - 1 ||
          currentY == 0 ||
          currentY == height - 1) {
        touchesBorder = true;
      }

      void visit(int nextX, int nextY) {
        final nextIndex = nextY * width + nextX;
        if (visited[nextIndex] == 1 || binaryMask[nextIndex] == 1) {
          return;
        }
        visited[nextIndex] = 1;
        queue.add(nextIndex);
      }

      if (currentX > 0) visit(currentX - 1, currentY);
      if (currentX + 1 < width) visit(currentX + 1, currentY);
      if (currentY > 0) visit(currentX, currentY - 1);
      if (currentY + 1 < height) visit(currentX, currentY + 1);
    }

    if (touchesBorder) {
      return _encodeBinaryMask(binaryMask, width, height);
    }

    for (final index in region) {
      binaryMask[index] = 1;
    }
    return _encodeBinaryMask(binaryMask, width, height);
  }

  /// 提取填充操作新补出的区域，避免把原有蒙版重复叠进新图层。
  static Uint8List extractFilledMaskDelta(
    Uint8List originalBytes,
    Uint8List filledBytes,
  ) {
    img.Image? original;
    img.Image? filled;
    try {
      original = img.decodeImage(originalBytes);
      filled = img.decodeImage(filledBytes);
    } catch (_) {
      return filledBytes;
    }
    if (original == null ||
        filled == null ||
        original.width != filled.width ||
        original.height != filled.height) {
      return filledBytes;
    }

    final originalMask = _createBinaryMask(original);
    final filledMask = _createBinaryMask(filled);
    final deltaMask = Uint8List(original.width * original.height);
    for (var index = 0; index < deltaMask.length; index++) {
      if (filledMask[index] == 1 && originalMask[index] == 0) {
        deltaMask[index] = 1;
      }
    }

    return _encodeBinaryMask(deltaMask, original.width, original.height);
  }

  /// 将蒙版处理为更适合 NovelAI Inpaint 的版本：
  /// 默认仅做二值化；按需启用闭运算或扩边，避免平白放大蒙版边界。
  static Uint8List prepareInpaintMaskBytes(
    Uint8List bytes, {
    int closingIterations = 0,
    int expansionIterations = 0,
  }) {
    return prepareRequestMaskBytes(
      bytes,
      closingIterations: closingIterations,
      expansionIterations: expansionIterations,
    );
  }

  /// 构建真正发送给 NovelAI 的请求蒙版。
  ///
  /// `alignToLatentGrid` 会把 V4/V4.5 的 mask 对齐到 8px latent 网格，
  /// 避免 UI 里的软边/亚像素边界直接泄漏到请求层。
  static Uint8List prepareRequestMaskBytes(
    Uint8List bytes, {
    int closingIterations = 0,
    int expansionIterations = 0,
    bool alignToLatentGrid = false,
    int latentGridSize = 8,
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return bytes;
    }
    if (decoded == null) {
      return bytes;
    }

    var binaryMask = _createBinaryMask(decoded);
    if (closingIterations > 0) {
      binaryMask = _closeMask(
        binaryMask,
        decoded.width,
        decoded.height,
        closingIterations,
      );
    }
    if (expansionIterations > 0) {
      binaryMask = _dilateMask(
        binaryMask,
        decoded.width,
        decoded.height,
        expansionIterations,
      );
    }
    if (alignToLatentGrid) {
      binaryMask = _alignMaskToLatentGrid(
        binaryMask,
        decoded.width,
        decoded.height,
        latentGridSize,
      );
    }

    return _encodeBinaryMask(binaryMask, decoded.width, decoded.height);
  }

  /// 将已保存的黑白蒙版转换为编辑器可见的透明覆盖层。
  static Uint8List maskToEditorOverlay(
    Uint8List bytes, {
    int overlayAlpha = 140,
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return bytes;
    }
    if (decoded == null) {
      return bytes;
    }

    final overlay = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 4,
    );

    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (_isMaskedPixel(pixel)) {
          overlay.setPixelRgba(x, y, 96, 170, 255, overlayAlpha);
        } else {
          overlay.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(overlay));
  }

  static bool _isMaskedPixel(img.Pixel pixel) {
    final alpha = pixel.a.toInt();
    if (alpha <= _alphaThreshold) {
      return false;
    }

    final brightest = [
      pixel.r.toInt(),
      pixel.g.toInt(),
      pixel.b.toInt(),
    ].reduce((a, b) => a > b ? a : b);

    return brightest >= _colorThreshold;
  }

  static Uint8List _createBinaryMask(img.Image decoded) {
    final mask = Uint8List(decoded.width * decoded.height);
    var index = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        mask[index++] = _isMaskedPixel(pixel) ? 1 : 0;
      }
    }
    return mask;
  }

  static Uint8List _encodeBinaryMask(
    Uint8List binaryMask,
    int width,
    int height,
  ) {
    final normalized = img.Image(
      width: width,
      height: height,
      numChannels: 4,
    );

    var index = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final value = binaryMask[index++] == 1 ? 255 : 0;
        normalized.setPixelRgba(x, y, value, value, value, 255);
      }
    }

    return Uint8List.fromList(img.encodePng(normalized));
  }

  static Uint8List _closeMask(
    Uint8List source,
    int width,
    int height,
    int iterations,
  ) {
    final expanded = _dilateMask(source, width, height, iterations);
    return _erodeMask(expanded, width, height, iterations);
  }

  static Uint8List _dilateMask(
    Uint8List source,
    int width,
    int height,
    int iterations,
  ) {
    var current = Uint8List.fromList(source);
    for (var i = 0; i < iterations; i++) {
      final next = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          var masked = false;
          for (var dy = -1; dy <= 1 && !masked; dy++) {
            final ny = y + dy;
            if (ny < 0 || ny >= height) {
              continue;
            }
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              if (nx < 0 || nx >= width) {
                continue;
              }
              if (current[ny * width + nx] == 1) {
                masked = true;
                break;
              }
            }
          }
          next[y * width + x] = masked ? 1 : 0;
        }
      }
      current = next;
    }
    return current;
  }

  static Uint8List _erodeMask(
    Uint8List source,
    int width,
    int height,
    int iterations,
  ) {
    var current = Uint8List.fromList(source);
    for (var i = 0; i < iterations; i++) {
      final next = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          var masked = true;
          for (var dy = -1; dy <= 1 && masked; dy++) {
            final ny = y + dy;
            if (ny < 0 || ny >= height) {
              masked = false;
              break;
            }
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              if (nx < 0 || nx >= width || current[ny * width + nx] == 0) {
                masked = false;
                break;
              }
            }
          }
          next[y * width + x] = masked ? 1 : 0;
        }
      }
      current = next;
    }
    return current;
  }

  static Uint8List _alignMaskToLatentGrid(
    Uint8List source,
    int width,
    int height,
    int latentGridSize,
  ) {
    const minBlockCoverage = 0.25;
    final aligned = Uint8List(width * height);

    for (var blockY = 0; blockY < height; blockY += latentGridSize) {
      final blockBottom = (blockY + latentGridSize).clamp(0, height);
      for (var blockX = 0; blockX < width; blockX += latentGridSize) {
        final blockRight = (blockX + latentGridSize).clamp(0, width);
        final blockWidth = blockRight - blockX;
        final blockHeight = blockBottom - blockY;
        final blockArea = blockWidth * blockHeight;

        var maskedPixels = 0;
        for (var y = blockY; y < blockBottom; y++) {
          for (var x = blockX; x < blockRight; x++) {
            if (source[y * width + x] == 1) {
              maskedPixels++;
            }
          }
        }

        if (maskedPixels / blockArea < minBlockCoverage) {
          continue;
        }

        for (var y = blockY; y < blockBottom; y++) {
          for (var x = blockX; x < blockRight; x++) {
            aligned[y * width + x] = 1;
          }
        }
      }
    }

    return aligned;
  }
}
