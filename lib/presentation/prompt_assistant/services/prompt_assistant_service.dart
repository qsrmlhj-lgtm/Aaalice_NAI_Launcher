import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/utils/app_logger.dart';
import '../models/prompt_assistant_models.dart';
import '../providers/prompt_assistant_config_provider.dart';
import 'prompt_assistant_api_client.dart';

final promptAssistantDioProvider = Provider<Dio>((ref) {
  // 使用独立 Dio，避免第三方服务的 401 触发全局登录态刷新/登出逻辑。
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 2),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
});

final promptAssistantServiceProvider = Provider<PromptAssistantService>((ref) {
  final dio = ref.watch(promptAssistantDioProvider);
  return PromptAssistantService(
    ref: ref,
    apiClient: PromptAssistantApiClient(dio: dio),
  );
});

class PromptAssistantService {
  PromptAssistantService({
    required Ref ref,
    required PromptAssistantApiClient apiClient,
  })  : _ref = ref,
        _apiClient = apiClient;

  final Ref _ref;
  final PromptAssistantApiClient _apiClient;

  Future<void> cancelCurrentTask({String? sessionId}) async {
    _apiClient.cancelCurrentRequest(sessionId: sessionId);
  }

  Future<List<String>> fetchAvailableModels(String providerId) async {
    final config = _ref.read(promptAssistantConfigProvider);
    final provider = config.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => throw StateError('未找到服务商: $providerId'),
    );
    final apiKey = await _ref
        .read(promptAssistantConfigProvider.notifier)
        .getProviderApiKey(provider.id);
    return _apiClient.fetchModels(provider: provider, apiKey: apiKey);
  }

  Stream<StreamingChunk> optimizePrompt(
    String input, {
    required String sessionId,
  }) async* {
    yield* _runTask(
      sessionId: sessionId,
      taskType: AssistantTaskType.llm,
      userContent: input,
      userInstruction: '请优化这段图像生成提示词，保留原意并增强细节，输出单行结果。',
    );
  }

  Stream<StreamingChunk> translatePrompt(
    String input, {
    required String sessionId,
    String? targetLanguage,
  }) async* {
    final instruction = targetLanguage == null || targetLanguage.isEmpty
        ? '请自动识别原文语言，在中文和英文之间互译，仅返回译文。'
        : '请将文本翻译为$targetLanguage，仅返回译文。';
    yield* _runTask(
      sessionId: sessionId,
      taskType: AssistantTaskType.translate,
      userContent: input,
      userInstruction: instruction,
    );
  }

  Stream<StreamingChunk> reverseImagePrompt(
    Uint8List imageBytes, {
    required String sessionId,
    String? taggerPrompt,
  }) async* {
    final text = StringBuffer(
      '请反推这张图片，输出 NovelAI 可直接使用的英文逗号分隔提示词。',
    );
    final trimmedTags = taggerPrompt?.trim();
    if (trimmedTags != null && trimmedTags.isNotEmpty) {
      text
        ..write('\n\n本地 ONNX tagger 初步结果如下，请结合图片判断取舍：\n')
        ..write(trimmedTags);
    }

    yield* _runTask(
      sessionId: sessionId,
      taskType: AssistantTaskType.reverse,
      userContent: [
        {'type': 'text', 'text': text.toString()},
        {
          'type': 'image_url',
          'image_url': {'url': _imageDataUri(imageBytes)},
        },
      ],
      userInstruction: '请严格输出单行英文提示词，不要 Markdown，不要解释。优先保留可见元素，避免编造不可见角色信息。',
    );
  }

  Stream<StreamingChunk> replaceCharacterPrompt(
    String input, {
    required String sessionId,
    required String characterName,
    required String characterPrompt,
  }) async* {
    final sourcePrompt = input.trim();
    final targetCharacterPrompt = characterPrompt.trim();
    AppLogger.d(
      'character replace input sourceLen=${sourcePrompt.length} targetLen=${targetCharacterPrompt.length} '
          'source="${_previewForLog(sourcePrompt)}" target="${_previewForLog(targetCharacterPrompt)}"',
      'PromptAssistant',
    );

    yield* _runTask(
      sessionId: sessionId,
      taskType: AssistantTaskType.characterReplace,
      userContent: buildCharacterReplacementUserContent(
        sourcePrompt: sourcePrompt,
        characterName: characterName,
        characterPrompt: targetCharacterPrompt,
      ),
      userInstruction: characterReplacementInstruction,
    );
  }

  static const String characterReplacementInstruction =
      '仅输出替换后的完整单行英文逗号分隔提示词，不要输出分析、解释、删除/保留清单或 Markdown。';

  static String buildCharacterReplacementUserContent({
    required String sourcePrompt,
    required String characterName,
    required String characterPrompt,
  }) {
    return [
      '待替换提示词（以这一段为主，保留非角色内容）：',
      sourcePrompt.trim(),
      '',
      '目标角色名称：',
      characterName.trim(),
      '',
      '目标角色提示词（只作为替换角色块）：',
      characterPrompt.trim(),
    ].join('\n');
  }

  static String _previewForLog(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 240) {
      return normalized;
    }
    return '${normalized.substring(0, 240)}...';
  }

  Stream<StreamingChunk> _runTask({
    required String sessionId,
    required AssistantTaskType taskType,
    required Object userContent,
    required String userInstruction,
  }) async* {
    final config = _ref.read(promptAssistantConfigProvider);

    final routingProviderId = config.routing.providerIdFor(taskType);
    final routingModel = config.routing.modelFor(taskType);

    final provider = config.providers.firstWhere(
      (p) => p.id == routingProviderId && p.enabled,
      orElse: () => config.providers.firstWhere(
        (p) => p.enabled,
        orElse: () => throw StateError('没有可用的已启用服务商'),
      ),
    );

    final taskModels = config.modelsForProviderTask(
      providerId: provider.id,
      taskType: taskType,
    );
    final hasRealModel = taskModels.any((m) => !m.isPlaceholder);
    final shouldIgnoreRoutedPlaceholder = (routingModel.trim().isEmpty ||
            routingModel.trim() == 'default-model') &&
        hasRealModel;
    final model = shouldIgnoreRoutedPlaceholder
        ? taskModels.firstWhere((m) => !m.isPlaceholder)
        : taskModels.firstWhere(
            (m) => m.name == routingModel,
            orElse: () => taskModels.isNotEmpty
                ? taskModels.first
                : ModelConfig(
                    providerId: provider.id,
                    name: routingModel,
                    displayName: routingModel,
                    forTask: taskType,
                    isDefault: true,
                  ),
          );

    final apiKey = await _ref
        .read(promptAssistantConfigProvider.notifier)
        .getProviderApiKey(provider.id);

    final activeRules = config.rules
        .where((r) => r.taskType == taskType && r.enabled)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final systemPrompt = [
      ...activeRules.map((e) => e.content.trim()).where((e) => e.isNotEmpty),
      userInstruction,
    ].join('\n\n');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userContent},
    ];

    yield* _apiClient.streamChat(
      sessionId: sessionId,
      provider: provider,
      model: model.name,
      messages: messages,
      apiKey: apiKey,
    );
  }

  String _imageDataUri(Uint8List imageBytes) {
    final mime = _detectImageMime(imageBytes);
    return 'data:$mime;base64,${base64Encode(imageBytes)}';
  }

  String _detectImageMime(Uint8List bytes) {
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
    return 'image/png';
  }
}
