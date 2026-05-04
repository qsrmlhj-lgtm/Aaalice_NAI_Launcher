import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/prompt_assistant_models.dart';

class PromptAssistantRequest {
  const PromptAssistantRequest({
    required this.sessionId,
    required this.provider,
    required this.model,
    required this.systemPrompt,
    required this.userParts,
    required this.apiKey,
  });

  final String sessionId;
  final ProviderConfig provider;
  final String model;
  final String systemPrompt;
  final List<PromptAssistantContentPart> userParts;
  final String? apiKey;
}

abstract class PromptAssistantContentPart {
  const PromptAssistantContentPart();

  factory PromptAssistantContentPart.text(String text) =
      PromptAssistantTextPart;

  factory PromptAssistantContentPart.image({
    required Uint8List bytes,
    required String mimeType,
  }) = PromptAssistantImagePart;
}

class PromptAssistantTextPart extends PromptAssistantContentPart {
  const PromptAssistantTextPart(this.text);

  final String text;
}

class PromptAssistantImagePart extends PromptAssistantContentPart {
  const PromptAssistantImagePart({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

class PromptAssistantImageInput {
  const PromptAssistantImageInput({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

abstract class PromptAssistantProviderAdapter {
  const PromptAssistantProviderAdapter();

  Future<List<String>> fetchModels({
    required Dio dio,
    required ProviderConfig provider,
    required String? apiKey,
  });

  Future<String> complete({
    required Dio dio,
    required PromptAssistantRequest request,
    required CancelToken cancelToken,
  });
}

String normalizedBaseUrl(String baseUrl) {
  return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
}

String imageDataUri(PromptAssistantImagePart part) {
  return 'data:${part.mimeType};base64,${base64Encode(part.bytes)}';
}

String contentToText(dynamic content) {
  if (content is String) {
    return content;
  }
  if (content is List) {
    return content.map(contentToText).where((e) => e.isNotEmpty).join();
  }
  if (content is Map) {
    return contentToText(
      content['text'] ??
          content['content'] ??
          content['value'] ??
          content['output_text'],
    );
  }
  return '';
}

String? extractErrorMessage(Map<String, dynamic> obj) {
  final error = obj['error'];
  if (error is String && error.trim().isNotEmpty) {
    return error.trim();
  }
  if (error is Map<String, dynamic>) {
    final message = error['message'] ?? error['error'] ?? error['type'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  }
  return null;
}

List<String> extractModelNames(dynamic raw) {
  final names = <String>[];

  void addName(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      names.add(
        trimmed.startsWith('models/')
            ? trimmed.substring('models/'.length)
            : trimmed,
      );
    }
  }

  if (raw is Map<String, dynamic>) {
    final data = raw['data'];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          addName(item['id'] ?? item['name'] ?? item['model']);
        } else {
          addName(item);
        }
      }
    }
    final models = raw['models'];
    if (models is List) {
      for (final item in models) {
        if (item is Map<String, dynamic>) {
          final methods = item['supportedGenerationMethods'];
          if (methods is List &&
              methods.isNotEmpty &&
              !methods.contains('generateContent')) {
            continue;
          }
          addName(item['name'] ?? item['model'] ?? item['id']);
        } else {
          addName(item);
        }
      }
    }
  } else if (raw is List) {
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        addName(item['id'] ?? item['name'] ?? item['model']);
      } else {
        addName(item);
      }
    }
  }

  final dedup = <String>{};
  return names.where((name) => dedup.add(name)).toList();
}

String? detectImageMime(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'image/gif';
  }
  return null;
}

({Uint8List bytes, String mimeType})? parseDataUriImage(String value) {
  final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(value);
  if (match == null) return null;
  return (
    bytes: base64Decode(match.group(2)!),
    mimeType: match.group(1)!,
  );
}
