import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/utils/app_logger.dart';
import '../models/prompt_assistant_models.dart';

class PromptAssistantApiClient {
  PromptAssistantApiClient({required Dio dio}) : _dio = dio;

  final Dio _dio;
  final Map<String, CancelToken> _cancelTokens = {};

  void cancelCurrentRequest({String? sessionId}) {
    if (sessionId == null || sessionId.isEmpty) {
      for (final token in _cancelTokens.values) {
        token.cancel('cancelled by user');
      }
      _cancelTokens.clear();
      return;
    }

    final token = _cancelTokens.remove(sessionId);
    token?.cancel('cancelled by user');
  }

  Future<List<String>> fetchModels({
    required ProviderConfig provider,
    required String? apiKey,
  }) async {
    if (provider.type == ProviderType.pollinations) {
      return const ['openai-large'];
    }

    final headers = <String, dynamic>{};
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    final endpoints = <String>[
      _resolveModelsEndpoint(provider),
      if (provider.type == ProviderType.ollama)
        _resolveOllamaTagsEndpoint(provider),
    ];

    DioException? lastError;
    for (final endpoint in endpoints.toSet()) {
      try {
        final response = await _dio.get<dynamic>(
          endpoint,
          options: Options(
            headers: headers,
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final names = _extractModelNames(response.data);
        if (names.isNotEmpty) {
          return names;
        }
      } on DioException catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return const [];
  }

  Stream<StreamingChunk> streamChat({
    required String sessionId,
    required ProviderConfig provider,
    required String model,
    required List<Map<String, dynamic>> messages,
    required String? apiKey,
  }) async* {
    _cancelTokens.remove(sessionId)?.cancel('replaced by new request');
    final cancelToken = CancelToken();
    _cancelTokens[sessionId] = cancelToken;

    final endpoint = _resolveEndpoint(provider);
    final payload = <String, dynamic>{
      'model': model,
      'stream': false,
      'messages': messages,
    };

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
    };
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    try {
      AppLogger.d(
        'request start provider=${provider.id} type=${provider.type.name} model=$model endpoint=$endpoint messages=${messages.length} stream=false',
        'PromptAssistant',
      );
      Response<dynamic> response;
      try {
        response = await _dio.post<dynamic>(
          endpoint,
          data: payload,
          options: Options(
            headers: headers,
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(minutes: 2),
          ),
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        // retry once with degraded payload
        if (e.response?.statusCode == 400) {
          final degradedPayload = {
            'model': model,
            'stream': false,
            'messages': messages,
          };
          response = await _dio.post<dynamic>(
            endpoint,
            data: degradedPayload,
            options: Options(
              headers: headers,
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 2),
            ),
            cancelToken: cancelToken,
          );
        } else {
          rethrow;
        }
      }

      final content = _extractResponseContent(response.data).trim();
      if (content.isEmpty) {
        AppLogger.w(
          'empty non-stream response provider=${provider.id} model=$model status=${response.statusCode} body=${_previewBody(response.data.toString())}',
          'PromptAssistant',
        );
        throw StateError(
          'LLM 服务返回空内容：provider=${provider.name}, model=$model, status=${response.statusCode}',
        );
      }

      AppLogger.d(
        'response done provider=${provider.id} model=$model outputLen=${content.length} output=${_previewBody(content)}',
        'PromptAssistant',
      );
      yield StreamingChunk(delta: content);
      yield const StreamingChunk(delta: '', done: true);
    } finally {
      if (identical(_cancelTokens[sessionId], cancelToken)) {
        _cancelTokens.remove(sessionId);
      }
    }
  }

  String _resolveEndpoint(ProviderConfig provider) {
    if (provider.type == ProviderType.pollinations) {
      return 'https://gen.pollinations.ai/v1/chat/completions';
    }

    final base = _normalizedBase(provider);
    if (base.endsWith('/chat/completions')) {
      return base;
    }
    if (base.endsWith('/v1')) {
      return '$base/chat/completions';
    }
    return '$base/v1/chat/completions';
  }

  String _extractDelta(String jsonLine) {
    try {
      final obj = jsonDecode(jsonLine) as Map<String, dynamic>;
      final error = _extractErrorMessage(obj);
      if (error != null) {
        throw StateError('LLM 服务返回错误：$error');
      }
      final choices = obj['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final delta = first['delta'];
          if (delta is Map<String, dynamic>) {
            return _contentToText(delta['content']);
          }
          final message = first['message'];
          if (message is Map<String, dynamic>) {
            return _contentToText(message['content']);
          }
          return _contentToText(first['text']);
        }
      }
      final message = obj['message'];
      if (message is Map<String, dynamic>) {
        return _contentToText(message['content']);
      }
      final text = obj['text'];
      final textContent = _contentToText(text);
      if (textContent.isNotEmpty) return textContent;
      final response = obj['response'];
      final responseContent = _contentToText(response);
      if (responseContent.isNotEmpty) return responseContent;
      final outputText = obj['output_text'];
      return _contentToText(outputText);
    } on StateError {
      rethrow;
    } catch (_) {
      // ignore parse errors in incomplete frames
    }
    return '';
  }

  ({String delta, bool done}) _parseStreamLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return (delta: '', done: false);
    }

    final data =
        trimmed.startsWith('data:') ? trimmed.substring(5).trim() : trimmed;
    if (data == '[DONE]') {
      return (delta: '', done: true);
    }
    if (data.isEmpty || !data.startsWith('{')) {
      return (delta: '', done: false);
    }

    return (delta: _extractDelta(data), done: false);
  }

  String _extractFullContent(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }

    final deltas = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      final parsed = _parseStreamLine(line);
      if (parsed.delta.isNotEmpty) {
        deltas.add(parsed.delta);
      }
    }
    if (deltas.isNotEmpty) {
      return deltas.join();
    }

    return _extractDelta(text);
  }

  String _extractResponseContent(dynamic raw) {
    if (raw is Map) {
      return _extractDelta(jsonEncode(raw));
    }
    if (raw is String) {
      return _extractFullContent(raw);
    }
    return _contentToText(raw);
  }

  String? _extractErrorMessage(Map<String, dynamic> obj) {
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

  String _contentToText(dynamic content) {
    if (content is String) {
      return content;
    }
    if (content is List) {
      return content.map(_contentToText).where((e) => e.isNotEmpty).join();
    }
    if (content is Map) {
      return _contentToText(
        content['text'] ?? content['content'] ?? content['value'],
      );
    }
    return '';
  }

  String _previewBody(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 300) {
      return normalized;
    }
    return '${normalized.substring(0, 300)}...';
  }

  String _normalizedBase(ProviderConfig provider) {
    return provider.baseUrl.trim().replaceAll(RegExp(r"/+$"), "");
  }

  String _resolveModelsEndpoint(ProviderConfig provider) {
    final base = _normalizedBase(provider);
    if (base.endsWith('/v1')) {
      return '$base/models';
    }
    return '$base/v1/models';
  }

  String _resolveOllamaTagsEndpoint(ProviderConfig provider) {
    final base = _normalizedBase(provider);
    if (base.endsWith('/v1')) {
      return '${base.substring(0, base.length - 3)}/api/tags';
    }
    return '$base/api/tags';
  }

  List<String> _extractModelNames(dynamic raw) {
    final names = <String>[];

    void addName(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        names.add(value.trim());
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
}
