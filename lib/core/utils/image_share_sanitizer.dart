import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SanitizedShareImage {
  const SanitizedShareImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class ImageShareSanitizer {
  ImageShareSanitizer._();

  static const Set<String> _clipboardFriendlyExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.bmp',
    '.gif',
    '.webp',
  };

  static const Set<String> _stripChunkTypes = {
    'tEXt',
    'zTXt',
    'iTXt',
    'eXIf',
    'tIME',
  };

  static Future<SanitizedShareImage> sanitizeForShare(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final extension = p.extension(fileName).toLowerCase();
    if (extension == '.png') {
      return SanitizedShareImage(
        bytes: _sanitizePng(bytes),
        fileName: p.basenameWithoutExtension(fileName).isEmpty
            ? 'shared.png'
            : p.basename(fileName),
        mimeType: 'image/png',
      );
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return SanitizedShareImage(
        bytes: bytes,
        fileName: p.setExtension(p.basename(fileName), '.png'),
        mimeType: 'image/png',
      );
    }

    return SanitizedShareImage(
      bytes: Uint8List.fromList(img.encodePng(decoded)),
      fileName: p.setExtension(p.basename(fileName), '.png'),
      mimeType: 'image/png',
    );
  }

  static Future<SanitizedShareImage> prepareForCopyOrDrag(
    Uint8List bytes, {
    required String fileName,
    required bool stripMetadata,
  }) async {
    final normalizedFileName = _normalizeShareFileName(fileName);
    final extension = p.extension(normalizedFileName).toLowerCase();
    final shouldNormalize =
        stripMetadata || !_clipboardFriendlyExtensions.contains(extension);

    if (shouldNormalize) {
      return sanitizeForShare(bytes, fileName: normalizedFileName);
    }

    return SanitizedShareImage(
      bytes: bytes,
      fileName: normalizedFileName,
      mimeType: _mimeTypeForExtension(extension),
    );
  }

  static Future<File> writeTempShareFile(SanitizedShareImage image) async {
    final tempDir = await getTemporaryDirectory();
    final shareDir = Directory(p.join(tempDir.path, 'nai_launcher_share'));
    if (!await shareDir.exists()) {
      await shareDir.create(recursive: true);
    }

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${image.fileName}';
    final file = File(p.join(shareDir.path, fileName));
    await file.writeAsBytes(image.bytes, flush: true);
    return file;
  }

  static Uint8List _sanitizePng(Uint8List bytes) {
    if (!_looksLikePng(bytes)) {
      return bytes;
    }

    final decoded = img.decodePng(bytes);
    if (decoded != null) {
      return Uint8List.fromList(
        img.encodePng(_clearStealthAlphaLsb(decoded)),
      );
    }

    final output = BytesBuilder();
    output.add(bytes.sublist(0, 8));

    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length =
          ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
      final type = latin1.decode(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      final chunkEnd = dataEnd + 4;
      if (chunkEnd > bytes.length) {
        break;
      }

      final shouldKeep = !_stripChunkTypes.contains(type);
      if (shouldKeep) {
        output.add(bytes.sublist(offset, chunkEnd));
      }

      offset = chunkEnd;
    }

    return output.toBytes();
  }

  static String _normalizeShareFileName(String fileName) {
    final normalized = p.basename(fileName);
    if (normalized.isEmpty) {
      return 'shared.png';
    }
    return normalized;
  }

  static String _mimeTypeForExtension(String extension) {
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.bmp' => 'image/bmp',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      _ => 'image/png',
    };
  }

  static bool _looksLikePng(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  static img.Image _clearStealthAlphaLsb(img.Image image) {
    _clearFrameStealthAlphaLsb(image);
    for (final frame in image.frames) {
      _clearFrameStealthAlphaLsb(frame);
    }
    return image;
  }

  static void _clearFrameStealthAlphaLsb(img.Image frame) {
    frame.textData = null;
    for (var x = 0; x < frame.width; x++) {
      for (var y = 0; y < frame.height; y++) {
        final pixel = frame.getPixel(x, y);
        frame.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          pixel.a.toInt() & 0xFE,
        );
      }
    }
  }
}
