import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_extract;

import '../../data/models/gallery/nai_image_metadata.dart';
import 'app_logger.dart';

/// NAI 元数据解析器
///
/// 从 NovelAI 生成的 PNG 图片中提取隐写元数据
/// 支持两种方式：
/// 1. tEXt/zTXt chunk 快速解析（推荐，性能更好）
/// 2. stealth_pngcomp 格式：元数据被 gzip 压缩后嵌入 alpha 通道的 LSB（fallback）
///
/// 推荐使用 [ImageMetadataService] 作为统一入口，它提供：
/// - 流式解析（只读前50KB）
/// - LRU 缓存
/// - 自动 fallback 机制
class NaiMetadataParser {
  static const String _magic = 'stealth_pngcomp';
  static const int _maxFileSize = 20 * 1024 * 1024;
  static const Duration _stealthParseTimeout = Duration(seconds: 3); // 缩短stealth超时，避免长时间等待

  /// 从 PNG 文件路径提取元数据（使用 Isolate 避免阻塞 UI）
  ///
  /// 这是完整的解析方法，会读取整个文件并使用双通道解析（tEXt + stealth）
  /// 用于 ImageMetadataService 的 fallback 场景
  static Future<NaiImageMetadata?> extractFromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await extractFromBytes(bytes);
    } catch (e, stack) {
      AppLogger.e('Failed to read file: ${file.path}', e, stack, 'NaiMetadataParser');
      return null;
    }
  }

  /// 从 PNG 文件字节提取元数据
  ///
  /// 注意：此方法会读取整个文件。对于大文件，推荐使用 [ImageMetadataService]
  /// 它使用流式解析（只读前50KB），性能更好。
  ///
  /// 优化策略：
  /// 1. chunks 解析直接在主线程执行（很快，无需 isolate 开销）
  /// 2. 只有当 chunks 没有分离字段时，才在 isolate 中尝试 stealth 解析
  static Future<NaiImageMetadata?> extractFromBytes(Uint8List bytes) async {
    if (bytes.length > _maxFileSize) {
      AppLogger.w(
        'PNG file too large (${bytes.length} bytes), skipping metadata extraction',
        'NaiMetadataParser',
      );
      return null;
    }

    final totalStopwatch = Stopwatch()..start();

    // Phase 1: 在主线程直接解析 chunks（无需 isolate，避免启动开销）
    NaiImageMetadata? fastResult;
    try {
      final fastStopwatch = Stopwatch()..start();
      // 关键优化：直接在主线程执行，避免 isolate 启动开销
      fastResult = _extractFromChunksSync(bytes);
      fastStopwatch.stop();
      AppLogger.d(
        '[NaiMetadataParser] Fast chunk: ${fastStopwatch.elapsedMilliseconds}ms, '
        'hasData=${fastResult != null}, hasSeparatedFields=${fastResult?.hasSeparatedFields ?? false}',
        'NaiMetadataParser',
      );

      // 优化：如果 fast 结果有分离字段，直接返回，不需要 stealth 解析
      if (fastResult?.hasSeparatedFields == true) {
        totalStopwatch.stop();
        AppLogger.d(
          '[NaiMetadataParser] Fast chunk has separated fields, skipping stealth (${totalStopwatch.elapsedMilliseconds}ms total)',
          'NaiMetadataParser',
        );
        return fastResult;
      }
    } catch (e) {
      AppLogger.w('[NaiMetadataParser] Fast chunk extraction error: $e', 'NaiMetadataParser');
    }

    // Phase 2: 只有当 fast 没有分离字段时，才尝试 stealth 解析
    // 注意：stealth 需要解码整个 PNG，所以在 isolate 中执行
    NaiImageMetadata? stealthResult;
    try {
      final stealthStopwatch = Stopwatch()..start();
      stealthResult = await compute(_extractMetadataIsolate, bytes)
          .timeout(_stealthParseTimeout);
      stealthStopwatch.stop();
      AppLogger.d(
        '[NaiMetadataParser] Stealth: ${stealthStopwatch.elapsedMilliseconds}ms, '
        'hasData=${stealthResult != null}, hasSeparatedFields=${stealthResult?.hasSeparatedFields ?? false}',
        'NaiMetadataParser',
      );

      // 如果 stealth 有分离字段，优先使用 stealth
      if (stealthResult?.hasSeparatedFields == true) {
        totalStopwatch.stop();
        AppLogger.d(
          '[NaiMetadataParser] Using stealth result with separated fields (${totalStopwatch.elapsedMilliseconds}ms total)',
          'NaiMetadataParser',
        );
        return stealthResult;
      }
    } on TimeoutException {
      AppLogger.w('[NaiMetadataParser] Stealth extraction timeout', 'NaiMetadataParser');
    } catch (e) {
      AppLogger.w('[NaiMetadataParser] Stealth extraction error: $e', 'NaiMetadataParser');
    }

    totalStopwatch.stop();

    // 合并策略：优先使用有分离字段的结果
    if (fastResult?.hasSeparatedFields == true) {
      AppLogger.d(
        '[NaiMetadataParser] Final: fast result with separated fields (${totalStopwatch.elapsedMilliseconds}ms total)',
        'NaiMetadataParser',
      );
      return fastResult;
    }
    if (stealthResult?.hasSeparatedFields == true) {
      AppLogger.d(
        '[NaiMetadataParser] Final: stealth result with separated fields (${totalStopwatch.elapsedMilliseconds}ms total)',
        'NaiMetadataParser',
      );
      return stealthResult;
    }

    // 没有分离字段，优先使用 chunks 结果（性能更好）
    if (fastResult != null && fastResult.hasData) {
      AppLogger.d(
        '[NaiMetadataParser] Final: fast result (${totalStopwatch.elapsedMilliseconds}ms total)',
        'NaiMetadataParser',
      );
      return fastResult;
    }

    // fallback 到 stealth
    if (stealthResult != null && stealthResult.hasData) {
      AppLogger.d(
        '[NaiMetadataParser] Final: stealth result (${totalStopwatch.elapsedMilliseconds}ms total)',
        'NaiMetadataParser',
      );
      return stealthResult;
    }

    AppLogger.d(
      '[NaiMetadataParser] Final: no metadata found (${totalStopwatch.elapsedMilliseconds}ms total)',
      'NaiMetadataParser',
    );
    return null;
  }

  /// 从 PNG chunks 提取标准元数据（无需完整解码 PNG）
  ///
  /// 优化：
  /// 1. 直接在主线程同步执行（无需 isolate，避免启动开销）
  /// 2. 只解析前15个chunks，NAI元数据通常位于文件前面
  static NaiImageMetadata? _extractFromChunksSync(Uint8List bytes) {
    try {
      final stopwatch = Stopwatch()..start();
      final chunks = png_extract.extractChunks(bytes);
      final maxChunks = chunks.length > 15 ? 15 : chunks.length;

      for (var i = 0; i < maxChunks; i++) {
        final chunk = chunks[i];
        final name = chunk['name'] as String?;
        if (name == null || !const {'tEXt', 'zTXt', 'iTXt'}.contains(name)) continue;

        final data = chunk['data'] as Uint8List?;
        if (data == null) continue;

        final textData = _parseTextChunk(data, name);
        if (textData == null) continue;

        final json = _tryParseNaiJson(textData);
        if (json != null) {
          stopwatch.stop();
          AppLogger.d(
            '[NaiMetadataParser] Found NAI metadata in $name chunk at index $i (${stopwatch.elapsedMilliseconds}ms)',
            'NaiMetadataParser',
          );
          return NaiImageMetadata.fromNaiComment(json, rawJson: textData);
        }
      }

      stopwatch.stop();
      // 优化：如果解析很快（<50ms）且没找到，只输出debug日志
      if (stopwatch.elapsedMilliseconds > 50) {
        AppLogger.w(
          '[NaiMetadataParser] Slow chunks parse: ${stopwatch.elapsedMilliseconds}ms for ${bytes.length ~/ 1024}KB, ${chunks.length} chunks',
          'NaiMetadataParser',
        );
      }
      return null;
    } catch (e, stack) {
      AppLogger.e('Error extracting from chunks', e, stack, 'NaiMetadataParser');
      return null;
    }
  }
  
  /// 解析 PNG text chunk（tEXt/zTXt/iTXt）
  static String? _parseTextChunk(Uint8List data, String chunkType) {
    try {
      return switch (chunkType) {
        'tEXt' => _parseTEXt(data),
        'zTXt' => _parseZTXt(data),
        'iTXt' => _parseITXt(data),
        _ => null,
      };
    } catch (e) {
      return null;
    }
  }

  /// 解析 tEXt chunk: keyword\0text (Latin-1)
  static String? _parseTEXt(Uint8List data) {
    final nullIndex = data.indexOf(0);
    if (nullIndex < 0) return null;
    return latin1.decode(data.sublist(nullIndex + 1));
  }

  /// 解析 zTXt chunk: keyword\0compressionMethod\0compressedText
  static String? _parseZTXt(Uint8List data) {
    final firstNull = data.indexOf(0);
    if (firstNull < 0 || firstNull + 1 >= data.length) return null;

    final compressionMethod = data[firstNull + 1];
    if (compressionMethod != 0) return null;

    return _inflateZlib(data.sublist(firstNull + 2));
  }

  /// 解析 iTXt chunk: keyword\0compressed\0method\0language\0translatedKeyword\0text
  static String? _parseITXt(Uint8List data) {
    var offset = 0;

    // 跳过 keyword
    final keywordEnd = data.indexOf(0, offset);
    if (keywordEnd < 0) return null;
    offset = keywordEnd + 1;

    if (offset + 1 >= data.length) return null;
    final compressed = data[offset++];
    final method = data[offset++];

    // 跳过 language tag
    final langEnd = data.indexOf(0, offset);
    if (langEnd < 0) return null;
    offset = langEnd + 1;

    // 跳过 translated keyword
    final transEnd = data.indexOf(0, offset);
    if (transEnd < 0) return null;
    offset = transEnd + 1;

    if (offset >= data.length) return null;
    final textData = data.sublist(offset);

    if (compressed == 1) {
      if (method != 0) return null;
      return _inflateZlib(textData);
    }
    return utf8.decode(textData);
  }

  /// 解压 zlib 压缩数据
  static String? _inflateZlib(Uint8List data) {
    try {
      final inflated = ZLibCodec().decode(data);
      return utf8.decode(inflated);
    } catch (e) {
      return null;
    }
  }

  /// 尝试解析 NAI JSON 数据
  ///
  /// 支持两种格式：
  /// 1. 官方格式：{"prompt": "...", "uc": "..."} - prompt在顶层
  /// 2. PNG标准格式：{"Description": "...", "Software": "...", "Source": "...", "Comment": "{...}"}
  ///    Comment字段包含实际元数据（JSON字符串）
  static Map<String, dynamic>? _tryParseNaiJson(String text) {
    try {
      final lowerText = text.toLowerCase();
      final hasNaiKeywords =
          lowerText.contains('prompt') ||
          lowerText.contains('sampler') ||
          lowerText.contains('steps');
      if (!hasNaiKeywords) return null;

      final json = jsonDecode(text) as Map<String, dynamic>;

      // 格式1: 直接格式 - prompt在顶层
      if (json.containsKey('prompt') || json.containsKey('comment')) {
        return json;
      }

      // 格式2: PNG标准格式 - Comment字段包含实际元数据
      if (json.containsKey('Comment')) {
        final comment = json['Comment'];
        if (comment is String) {
          try {
            final commentJson = jsonDecode(comment) as Map<String, dynamic>;
            if (commentJson.containsKey('prompt') || commentJson.containsKey('uc')) {
              return commentJson;
            }
          } catch (_) {
            // Comment不是有效的JSON，忽略
          }
        } else if (comment is Map<String, dynamic>) {
          if (comment.containsKey('prompt') || comment.containsKey('uc')) {
            return comment;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 在 Isolate 中执行元数据提取（stealth_pngcomp 方式）
  static Future<NaiImageMetadata?> _extractMetadataIsolate(Uint8List bytes) async {
    try {
      final image = img.decodePng(bytes);
      if (image == null) return null;

      final jsonString = await _extractStealthData(image);
      if (jsonString == null || jsonString.isEmpty) return null;

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final result = NaiImageMetadata.fromNaiComment(json, rawJson: jsonString);

      // Debug: 打印 stealth 提取的结果
      AppLogger.i(
        '[NaiMetadataParser] Stealth extraction result: hasSeparatedFields=${result.hasSeparatedFields}, '
        'fixedPrefix=${result.fixedPrefixTags.length}, fixedSuffix=${result.fixedSuffixTags.length}, '
        'prompt="${result.prompt.substring(0, result.prompt.length.clamp(0, 50))}..."',
        'NaiMetadataParser',
      );

      return result;
    } catch (e) {
      AppLogger.w('[NaiMetadataParser] Stealth extraction error: $e', 'NaiMetadataParser');
      return null;
    }
  }

  /// 从 Image 对象提取隐写数据（stealth_pngcomp 格式）
  static Future<String?> _extractStealthData(img.Image image) async {
    final magicBytes = utf8.encode(_magic);
    final extractedBytes = <int>[];
    var bitIndex = 0;
    var byteValue = 0;

    final headerLength = magicBytes.length + 4; // magic(15) + length(4)
    int? dataLength;

    // 按列优先顺序读取 alpha 通道 LSB
    outerLoop:
    for (var x = 0; x < image.width; x++) {
      for (var y = 0; y < image.height; y++) {
        final alpha = image.getPixel(x, y).a.toInt();
        byteValue = (byteValue << 1) | (alpha & 1);

        if (++bitIndex % 8 != 0) continue;
        extractedBytes.add(byteValue);
        byteValue = 0;

        // 解析 header
        if (extractedBytes.length == headerLength) {
          final extractedMagic = extractedBytes.take(magicBytes.length).toList();
          if (!listEquals(extractedMagic, magicBytes)) return null;

          final bitLength = ByteData.sublistView(
            Uint8List.fromList(extractedBytes.sublist(magicBytes.length, headerLength)),
          ).getInt32(0);
          dataLength = (bitLength / 8).ceil();

          if (dataLength <= 0 || dataLength > 10 * 1024 * 1024) return null;
        }

        // 数据读取完成，提前退出
        if (dataLength != null && extractedBytes.length >= headerLength + dataLength) {
          break outerLoop;
        }
      }
    }

    if (dataLength == null || extractedBytes.length < headerLength + dataLength) {
      return null;
    }

    try {
      final decoded = GZipCodec().decode(
        Uint8List.fromList(extractedBytes.sublist(headerLength, headerLength + dataLength)),
      );
      return utf8.decode(decoded);
    } catch (e) {
      return null;
    }
  }

  /// 将元数据嵌入 PNG 图片
  ///
  /// 支持两种模式：
  /// 1. 快速模式（默认）：仅添加 tEXt chunk，不重新编码 PNG（<5ms，性能提升50-100倍）
  /// 2. 完整模式：同时写入 stealth（alpha通道）和 tEXt chunk（500-800ms，兼容性更好）
  ///
  /// [useStealth] 是否嵌入 stealth 数据到 alpha 通道。默认 false，使用快速路径。
  static Future<Uint8List> embedMetadata(
    Uint8List imageBytes,
    String metadataJson, {
    bool useStealth = false,
  }) async {
    if (!useStealth) {
      // 快速路径：仅添加/更新 tEXt chunk（不重新编码PNG）
      return embedTextChunkOnly(imageBytes, 'Comment', metadataJson);
    }

    // 完整路径：stealth + tEXt（保持最大兼容性）
    final stealthBytes = await _embedStealthData(imageBytes, metadataJson);
    return _updateTextChunk(stealthBytes, metadataJson);
  }

  /// 仅嵌入 tEXt chunk（不重新编码 PNG，性能提升 50-100 倍）
  ///
  /// 直接操作 PNG chunks，避免调用 img.decodePng/img.encodePng，
  /// 保留所有原始 chunks，包括非标准 chunks。
  ///
  /// 时间对比（1024x1024 图片）：
  /// - 重新编码: 500-800ms
  /// - 此方法: 5-15ms
  static Uint8List embedTextChunkOnly(Uint8List originalPng, String keyword, String text) {
    try {
      final chunks = png_extract.extractChunks(originalPng);
      final output = BytesBuilder();

      // 写入 PNG 签名
      output.add(originalPng.sublist(0, 8));

      var textChunkAdded = false;
      var idatIndex = -1;

      // 找到第一个 IDAT 的位置（用于决定插入位置）
      for (var i = 0; i < chunks.length; i++) {
        if (chunks[i]['name'] == 'IDAT') {
          idatIndex = i;
          break;
        }
      }

      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final name = chunk['name'] as String;

        // 如果存在相同 keyword 的 chunk，替换它
        if (name == 'tEXt' && !textChunkAdded) {
          final data = chunk['data'] as Uint8List;
          final nullIndex = data.indexOf(0);
          if (nullIndex > 0) {
            final existingKeyword = latin1.decode(data.sublist(0, nullIndex));
            if (existingKeyword == keyword) {
              _writeTextChunk(output, keyword, text);
              textChunkAdded = true;
              continue; // 跳过原始 chunk
            }
          }
        }

        // 在第一个 IDAT 之前插入新 chunk（PNG 规范建议）
        if (i == idatIndex && !textChunkAdded) {
          _writeTextChunk(output, keyword, text);
          textChunkAdded = true;
        }

        // 写入原始 chunk
        _writeRawChunk(output, chunk);
      }

      // 如果还没添加（没有 IDAT 的情况），追加到末尾
      if (!textChunkAdded) {
        _writeTextChunk(output, keyword, text);
      }

      return output.toBytes();
    } catch (e, stack) {
      AppLogger.e('[NaiMetadataParser] Failed to embed text chunk', e, stack, 'NaiMetadataParser');
      // 失败时返回原始数据
      return originalPng;
    }
  }

  /// 写入原始 chunk 到 builder
  static void _writeRawChunk(BytesBuilder builder, Map<String, dynamic> chunk) {
    final name = chunk['name'] as String;
    final data = chunk['data'] as Uint8List;
    _writeChunk(builder, name, data);
  }

  /// 写入 tEXt chunk 到 builder
  static void _writeTextChunk(BytesBuilder builder, String keyword, String text) {
    final keywordBytes = latin1.encode(keyword);
    final textBytes = latin1.encode(text);

    final data = Uint8List(keywordBytes.length + 1 + textBytes.length);
    data.setAll(0, keywordBytes);
    data[keywordBytes.length] = 0; // null separator
    data.setAll(keywordBytes.length + 1, textBytes);

    _writeChunk(builder, 'tEXt', data);
  }

  /// 写入 PNG chunk（带 length + type + data + crc 结构）
  static void _writeChunk(BytesBuilder builder, String type, Uint8List data) {
    // Length (4 bytes, big-endian)
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    builder.add(lengthBytes.buffer.asUint8List());

    // Type (4 bytes)
    final typeBytes = latin1.encode(type);
    builder.add(typeBytes);

    // Data
    builder.add(data);

    // CRC32 (type + data)
    final crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setAll(0, typeBytes);
    crcInput.setAll(typeBytes.length, data);
    final crc = _crc32(crcInput);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    builder.add(crcBytes.buffer.asUint8List());
  }

  /// 更新 PNG 的 tEXt chunk 中的 Comment 字段
  static Future<Uint8List> _updateTextChunk(Uint8List bytes, String metadataJson) async {
    try {
      final chunks = png_extract.extractChunks(bytes);
      final output = BytesBuilder();

      // 写入 PNG 文件头
      output.add(bytes.sublist(0, 8));

      var commentUpdated = false;

      for (final chunk in chunks) {
        final name = chunk['name'] as String?;

        if (name == 'tEXt' && !commentUpdated) {
          // 解析现有的 tEXt chunk
          final data = chunk['data'] as Uint8List;
          final nullIndex = data.indexOf(0);

          if (nullIndex > 0) {
            final keyword = latin1.decode(data.sublist(0, nullIndex));

            if (keyword == 'Comment') {
              // 更新 Comment chunk
              final newComment = _createTextChunk('Comment', metadataJson);
              output.add(newComment);
              commentUpdated = true;
              continue; // 跳过原始 chunk
            }
          }
        }

        // 写入原始 chunk
        final chunkData = chunk['data'] as Uint8List;
        output.add(_createChunk(name!, chunkData));
      }

      // 如果没有找到 Comment chunk，添加一个新的
      if (!commentUpdated) {
        final newComment = _createTextChunk('Comment', metadataJson);
        // 在 IHDR 之后插入（通常是第二个位置）
        final ihdrEnd = _findChunkEnd(bytes, 'IHDR');
        if (ihdrEnd > 0) {
          final result = output.toBytes();
          final before = result.sublist(0, ihdrEnd);
          final after = result.sublist(ihdrEnd);
          return Uint8List.fromList([...before, ...newComment, ...after]);
        }
      }

      return output.toBytes();
    } catch (e) {
      AppLogger.w('[NaiMetadataParser] Failed to update tEXt chunk: $e', 'NaiMetadataParser');
      return bytes; // 失败时返回原始数据
    }
  }

  /// 创建 tEXt chunk
  static Uint8List _createTextChunk(String keyword, String text) {
    final keywordBytes = latin1.encode(keyword);
    final textBytes = latin1.encode(text);
    final data = Uint8List(keywordBytes.length + 1 + textBytes.length);

    data.setRange(0, keywordBytes.length, keywordBytes);
    data[keywordBytes.length] = 0; // null separator
    data.setRange(keywordBytes.length + 1, data.length, textBytes);

    return _createChunk('tEXt', data);
  }

  /// 创建 PNG chunk
  static Uint8List _createChunk(String type, Uint8List data) {
    final output = BytesBuilder();

    // Length (4 bytes, big-endian)
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    output.add(lengthBytes.buffer.asUint8List());

    // Type (4 bytes)
    final typeBytes = latin1.encode(type);
    output.add(typeBytes);

    // Data
    output.add(data);

    // CRC32 (type + data)
    final crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setRange(0, typeBytes.length, typeBytes);
    crcInput.setRange(typeBytes.length, crcInput.length, data);
    final crc = _crc32(crcInput);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    output.add(crcBytes.buffer.asUint8List());

    return output.toBytes();
  }

  /// 查找 chunk 的结束位置
  static int _findChunkEnd(Uint8List bytes, String chunkType) {
    var offset = 8; // 跳过 PNG 文件头

    while (offset < bytes.length) {
      if (offset + 8 > bytes.length) break;

      final length = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
      final type = latin1.decode(bytes.sublist(offset + 4, offset + 8));

      if (type == chunkType) {
        return offset + 12 + length; // length(4) + type(4) + data(length) + crc(4)
      }

      offset += 12 + length;
    }

    return 0;
  }

  /// CRC32 计算（PNG 标准）
  static int _crc32(Uint8List data) {
    const table = [
      0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
      0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
      0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
      0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
      0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
      0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
      0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
      0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
      0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
      0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
      0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
      0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
      0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
      0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
      0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
      0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
      0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
      0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
      0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
      0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
      0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
      0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
      0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
      0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
      0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
      0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
      0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
      0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
      0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
      0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
      0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
      0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
    ];

    var crc = 0xffffffff;
    for (final byte in data) {
      crc = (crc >>> 8) ^ table[(crc ^ byte) & 0xff];
    }
    return crc ^ 0xffffffff;
  }

  /// 嵌入 stealth 数据到 alpha 通道
  static Future<Uint8List> _embedStealthData(Uint8List imageBytes, String metadataJson) async {
    final image = img.decodePng(imageBytes);
    if (image == null) throw Exception('Failed to decode PNG image');

    final encodedData = GZipCodec().encode(utf8.encode(metadataJson));
    final bitLengthBytes = ByteData(4)..setInt32(0, encodedData.length * 8);

    final dataToEmbed = [
      ...utf8.encode(_magic),
      ...bitLengthBytes.buffer.asUint8List(),
      ...encodedData,
    ];

    var bitIndex = 0;
    for (var x = 0; x < image.width; x++) {
      for (var y = 0; y < image.height; y++) {
        final byteIndex = bitIndex ~/ 8;
        if (byteIndex >= dataToEmbed.length) break;

        final bit = (dataToEmbed[byteIndex] >> (7 - bitIndex % 8)) & 1;
        final pixel = image.getPixel(x, y);
        pixel.a = (pixel.a.toInt() & 0xFE) | bit;
        image.setPixel(x, y, pixel);

        bitIndex++;
      }
    }

    return img.encodePng(image);
  }

}
