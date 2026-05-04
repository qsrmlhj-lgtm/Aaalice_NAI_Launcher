import 'dart:convert';

enum AssistantTaskType { llm, translate, reverse, characterReplace, custom }

extension AssistantTaskTypeLabel on AssistantTaskType {
  String get label {
    switch (this) {
      case AssistantTaskType.llm:
        return '优化';
      case AssistantTaskType.translate:
        return '翻译';
      case AssistantTaskType.reverse:
        return '反推';
      case AssistantTaskType.characterReplace:
        return '角色替换';
      case AssistantTaskType.custom:
        return '自定义';
    }
  }
}

// Legacy storage/UI type. New code should prefer ProviderProtocol and
// ProviderPreset, but this remains to decode existing saved configs.
enum ProviderType { pollinations, openaiCompatible, ollama }

enum ProviderProtocol {
  openaiChatCompletions,
  openaiResponses,
  anthropicMessages,
  geminiGenerateContent,
  ollamaChatCompletions,
}

extension ProviderProtocolLabel on ProviderProtocol {
  String get label {
    switch (this) {
      case ProviderProtocol.openaiChatCompletions:
        return 'OpenAI Chat Completions';
      case ProviderProtocol.openaiResponses:
        return 'OpenAI Responses';
      case ProviderProtocol.anthropicMessages:
        return 'Anthropic Messages';
      case ProviderProtocol.geminiGenerateContent:
        return 'Gemini generateContent';
      case ProviderProtocol.ollamaChatCompletions:
        return 'Ollama Chat Completions';
    }
  }

  bool get supportsModelList => true;

  bool get supportsImagePayload {
    switch (this) {
      case ProviderProtocol.openaiChatCompletions:
      case ProviderProtocol.openaiResponses:
      case ProviderProtocol.anthropicMessages:
      case ProviderProtocol.geminiGenerateContent:
        return true;
      case ProviderProtocol.ollamaChatCompletions:
        return false;
    }
  }
}

enum ProviderPreset {
  openaiChat,
  openaiResponses,
  openaiCompatibleChat,
  openaiCompatibleResponses,
  anthropic,
  gemini,
  deepseek,
  lmStudioChat,
  lmStudioResponses,
  ollama,
  pollinations,
}

extension ProviderPresetDefaults on ProviderPreset {
  String get label {
    switch (this) {
      case ProviderPreset.openaiChat:
        return 'OpenAI Chat Completions';
      case ProviderPreset.openaiResponses:
        return 'OpenAI Responses';
      case ProviderPreset.openaiCompatibleChat:
        return 'OpenAI-compatible Chat';
      case ProviderPreset.openaiCompatibleResponses:
        return 'OpenAI-compatible Responses';
      case ProviderPreset.anthropic:
        return 'Anthropic';
      case ProviderPreset.gemini:
        return 'Gemini';
      case ProviderPreset.deepseek:
        return 'DeepSeek';
      case ProviderPreset.lmStudioChat:
        return 'LM Studio Chat';
      case ProviderPreset.lmStudioResponses:
        return 'LM Studio Responses';
      case ProviderPreset.ollama:
        return 'Ollama';
      case ProviderPreset.pollinations:
        return 'Pollinations';
    }
  }

  String get defaultId {
    switch (this) {
      case ProviderPreset.openaiChat:
        return 'openai_chat';
      case ProviderPreset.openaiResponses:
        return 'openai_responses';
      case ProviderPreset.openaiCompatibleChat:
        return 'openai_compatible_chat';
      case ProviderPreset.openaiCompatibleResponses:
        return 'openai_compatible_responses';
      case ProviderPreset.anthropic:
        return 'anthropic';
      case ProviderPreset.gemini:
        return 'gemini';
      case ProviderPreset.deepseek:
        return 'deepseek';
      case ProviderPreset.lmStudioChat:
        return 'lmstudio_chat';
      case ProviderPreset.lmStudioResponses:
        return 'lmstudio_responses';
      case ProviderPreset.ollama:
        return 'ollama';
      case ProviderPreset.pollinations:
        return 'pollinations';
    }
  }

  String get defaultName {
    switch (this) {
      case ProviderPreset.openaiChat:
        return 'OpenAI Chat';
      case ProviderPreset.openaiResponses:
        return 'OpenAI Responses';
      case ProviderPreset.openaiCompatibleChat:
        return 'OpenAI Compatible Chat';
      case ProviderPreset.openaiCompatibleResponses:
        return 'OpenAI Compatible Responses';
      case ProviderPreset.anthropic:
        return 'Anthropic';
      case ProviderPreset.gemini:
        return 'Gemini';
      case ProviderPreset.deepseek:
        return 'DeepSeek';
      case ProviderPreset.lmStudioChat:
        return 'LM Studio Chat';
      case ProviderPreset.lmStudioResponses:
        return 'LM Studio Responses';
      case ProviderPreset.ollama:
        return 'Ollama';
      case ProviderPreset.pollinations:
        return 'pollinations.ai';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case ProviderPreset.openaiChat:
      case ProviderPreset.openaiResponses:
        return 'https://api.openai.com/v1';
      case ProviderPreset.openaiCompatibleChat:
      case ProviderPreset.openaiCompatibleResponses:
        return '';
      case ProviderPreset.anthropic:
        return 'https://api.anthropic.com';
      case ProviderPreset.gemini:
        return 'https://generativelanguage.googleapis.com';
      case ProviderPreset.deepseek:
        return 'https://api.deepseek.com';
      case ProviderPreset.lmStudioChat:
      case ProviderPreset.lmStudioResponses:
        return 'http://localhost:1234/v1';
      case ProviderPreset.ollama:
        return 'http://127.0.0.1:11434/v1';
      case ProviderPreset.pollinations:
        return 'https://gen.pollinations.ai';
    }
  }

  ProviderProtocol get defaultProtocol {
    switch (this) {
      case ProviderPreset.openaiChat:
      case ProviderPreset.openaiCompatibleChat:
      case ProviderPreset.deepseek:
      case ProviderPreset.lmStudioChat:
      case ProviderPreset.pollinations:
        return ProviderProtocol.openaiChatCompletions;
      case ProviderPreset.openaiResponses:
      case ProviderPreset.openaiCompatibleResponses:
      case ProviderPreset.lmStudioResponses:
        return ProviderProtocol.openaiResponses;
      case ProviderPreset.anthropic:
        return ProviderProtocol.anthropicMessages;
      case ProviderPreset.gemini:
        return ProviderProtocol.geminiGenerateContent;
      case ProviderPreset.ollama:
        return ProviderProtocol.ollamaChatCompletions;
    }
  }

  List<String> get defaultModelNames {
    switch (this) {
      case ProviderPreset.openaiChat:
      case ProviderPreset.openaiResponses:
        return const ['gpt-4.1-mini'];
      case ProviderPreset.anthropic:
        return const ['claude-sonnet-4-20250514'];
      case ProviderPreset.gemini:
        return const ['gemini-2.5-flash'];
      case ProviderPreset.deepseek:
        return const ['deepseek-v4-flash', 'deepseek-v4-pro'];
      case ProviderPreset.pollinations:
        return const ['openai-large'];
      case ProviderPreset.openaiCompatibleChat:
      case ProviderPreset.openaiCompatibleResponses:
      case ProviderPreset.lmStudioChat:
      case ProviderPreset.lmStudioResponses:
      case ProviderPreset.ollama:
        return const [];
    }
  }

  bool get requiresApiKey {
    switch (this) {
      case ProviderPreset.lmStudioChat:
      case ProviderPreset.lmStudioResponses:
      case ProviderPreset.ollama:
      case ProviderPreset.pollinations:
        return false;
      case ProviderPreset.openaiChat:
      case ProviderPreset.openaiResponses:
      case ProviderPreset.openaiCompatibleChat:
      case ProviderPreset.openaiCompatibleResponses:
      case ProviderPreset.anthropic:
      case ProviderPreset.gemini:
      case ProviderPreset.deepseek:
        return true;
    }
  }

  bool get defaultAllowImageInput {
    switch (this) {
      case ProviderPreset.openaiChat:
      case ProviderPreset.openaiResponses:
      case ProviderPreset.openaiCompatibleChat:
      case ProviderPreset.openaiCompatibleResponses:
      case ProviderPreset.anthropic:
      case ProviderPreset.gemini:
      case ProviderPreset.lmStudioChat:
      case ProviderPreset.lmStudioResponses:
        return true;
      case ProviderPreset.deepseek:
      case ProviderPreset.ollama:
      case ProviderPreset.pollinations:
        return false;
    }
  }

  ProviderConfig createConfig({String? id}) {
    final resolvedId =
        (id == null || id.trim().isEmpty) ? defaultId : id.trim();
    return ProviderConfig(
      id: resolvedId,
      name: defaultName,
      type: legacyType,
      protocol: defaultProtocol,
      preset: this,
      baseUrl: defaultBaseUrl,
      allowImageInput: defaultAllowImageInput,
      enabled: true,
    );
  }

  ProviderType get legacyType {
    switch (this) {
      case ProviderPreset.pollinations:
        return ProviderType.pollinations;
      case ProviderPreset.ollama:
        return ProviderType.ollama;
      case ProviderPreset.openaiChat:
      case ProviderPreset.openaiResponses:
      case ProviderPreset.openaiCompatibleChat:
      case ProviderPreset.openaiCompatibleResponses:
      case ProviderPreset.anthropic:
      case ProviderPreset.gemini:
      case ProviderPreset.deepseek:
      case ProviderPreset.lmStudioChat:
      case ProviderPreset.lmStudioResponses:
        return ProviderType.openaiCompatible;
    }
  }
}

class ProviderConfig {
  final String id;
  final String name;
  final ProviderType type;
  final ProviderProtocol protocol;
  final ProviderPreset? preset;
  final String baseUrl;
  final bool enabled;
  final bool allowImageInput;

  const ProviderConfig({
    required this.id,
    required this.name,
    this.type = ProviderType.openaiCompatible,
    this.protocol = ProviderProtocol.openaiChatCompletions,
    this.preset,
    required this.baseUrl,
    this.enabled = true,
    this.allowImageInput = false,
  });

  ProviderConfig copyWith({
    String? id,
    String? name,
    ProviderType? type,
    ProviderProtocol? protocol,
    ProviderPreset? preset,
    bool clearPreset = false,
    String? baseUrl,
    bool? enabled,
    bool? allowImageInput,
  }) {
    return ProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      protocol: protocol ?? this.protocol,
      preset: clearPreset ? null : preset ?? this.preset,
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
      allowImageInput: allowImageInput ?? this.allowImageInput,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'protocol': protocol.name,
        'preset': preset?.name,
        'baseUrl': baseUrl,
        'enabled': enabled,
        'allowImageInput': allowImageInput,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    final type = ProviderType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => ProviderType.openaiCompatible,
    );
    final preset = _decodePreset(json['preset'] as String?);
    final protocol = _decodeProtocol(
      json['protocol'] as String?,
      legacyType: type,
      preset: preset,
    );
    return ProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      type: type,
      protocol: protocol,
      preset: preset ?? _inferPreset(type, json['id'] as String?, protocol),
      baseUrl: json['baseUrl'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      allowImageInput: json['allowImageInput'] as bool? ??
          (preset?.defaultAllowImageInput ?? protocol.supportsImagePayload),
    );
  }

  static ProviderPreset? _decodePreset(String? value) {
    if (value == null || value.isEmpty) return null;
    return ProviderPreset.values.cast<ProviderPreset?>().firstWhere(
          (preset) => preset?.name == value,
          orElse: () => null,
        );
  }

  static ProviderProtocol _decodeProtocol(
    String? value, {
    required ProviderType legacyType,
    required ProviderPreset? preset,
  }) {
    if (value != null && value.isNotEmpty) {
      return ProviderProtocol.values.firstWhere(
        (protocol) => protocol.name == value,
        orElse: () => preset?.defaultProtocol ?? _protocolForLegacy(legacyType),
      );
    }
    return preset?.defaultProtocol ?? _protocolForLegacy(legacyType);
  }

  static ProviderProtocol _protocolForLegacy(ProviderType type) {
    switch (type) {
      case ProviderType.pollinations:
      case ProviderType.openaiCompatible:
        return ProviderProtocol.openaiChatCompletions;
      case ProviderType.ollama:
        return ProviderProtocol.ollamaChatCompletions;
    }
  }

  static ProviderPreset? _inferPreset(
    ProviderType type,
    String? id,
    ProviderProtocol protocol,
  ) {
    if (type == ProviderType.pollinations || id == 'pollinations') {
      return ProviderPreset.pollinations;
    }
    if (type == ProviderType.ollama || id == 'ollama') {
      return ProviderPreset.ollama;
    }
    if (id == 'lmstudio' || id == 'lmstudio_chat') {
      return ProviderPreset.lmStudioChat;
    }
    if (id == 'lmstudio_responses') {
      return ProviderPreset.lmStudioResponses;
    }
    if (id == 'deepseek') {
      return ProviderPreset.deepseek;
    }
    if (id == 'anthropic') {
      return ProviderPreset.anthropic;
    }
    if (id == 'gemini') {
      return ProviderPreset.gemini;
    }
    if (id == 'openai_responses') {
      return ProviderPreset.openaiResponses;
    }
    if (id == 'openai' || id == 'openai_chat') {
      return ProviderPreset.openaiChat;
    }
    if (protocol == ProviderProtocol.openaiResponses) {
      return ProviderPreset.openaiCompatibleResponses;
    }
    return ProviderPreset.openaiCompatibleChat;
  }
}

class ModelConfig {
  final String providerId;
  final String name;
  final String displayName;
  final AssistantTaskType forTask;
  final bool isDefault;

  const ModelConfig({
    required this.providerId,
    required this.name,
    required this.displayName,
    required this.forTask,
    this.isDefault = false,
  });

  bool get isPlaceholder =>
      name.trim().isEmpty || name.trim() == 'default-model';

  ModelConfig copyWith({
    String? providerId,
    String? name,
    String? displayName,
    AssistantTaskType? forTask,
    bool? isDefault,
  }) {
    return ModelConfig(
      providerId: providerId ?? this.providerId,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      forTask: forTask ?? this.forTask,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'name': name,
        'displayName': displayName,
        'forTask': forTask.name,
        'isDefault': isDefault,
      };

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      providerId: json['providerId'] as String,
      name: json['name'] as String,
      displayName: json['displayName'] as String? ?? (json['name'] as String),
      forTask: AssistantTaskType.values.firstWhere(
        (t) => t.name == json['forTask'],
        orElse: () => AssistantTaskType.llm,
      ),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

class TaskRoutingConfig {
  final String llmProviderId;
  final String llmModel;
  final String translateProviderId;
  final String translateModel;
  final String reverseProviderId;
  final String reverseModel;
  final String characterReplaceProviderId;
  final String characterReplaceModel;
  final String customProviderId;
  final String customModel;

  const TaskRoutingConfig({
    required this.llmProviderId,
    required this.llmModel,
    required this.translateProviderId,
    required this.translateModel,
    required this.reverseProviderId,
    required this.reverseModel,
    required this.characterReplaceProviderId,
    required this.characterReplaceModel,
    this.customProviderId = '',
    this.customModel = '',
  });

  TaskRoutingConfig copyWith({
    String? llmProviderId,
    String? llmModel,
    String? translateProviderId,
    String? translateModel,
    String? reverseProviderId,
    String? reverseModel,
    String? characterReplaceProviderId,
    String? characterReplaceModel,
    String? customProviderId,
    String? customModel,
  }) {
    return TaskRoutingConfig(
      llmProviderId: llmProviderId ?? this.llmProviderId,
      llmModel: llmModel ?? this.llmModel,
      translateProviderId: translateProviderId ?? this.translateProviderId,
      translateModel: translateModel ?? this.translateModel,
      reverseProviderId: reverseProviderId ?? this.reverseProviderId,
      reverseModel: reverseModel ?? this.reverseModel,
      characterReplaceProviderId:
          characterReplaceProviderId ?? this.characterReplaceProviderId,
      characterReplaceModel:
          characterReplaceModel ?? this.characterReplaceModel,
      customProviderId: customProviderId ?? this.customProviderId,
      customModel: customModel ?? this.customModel,
    );
  }

  String providerIdFor(AssistantTaskType taskType) {
    switch (taskType) {
      case AssistantTaskType.llm:
        return llmProviderId;
      case AssistantTaskType.translate:
        return translateProviderId;
      case AssistantTaskType.reverse:
        return reverseProviderId;
      case AssistantTaskType.characterReplace:
        return characterReplaceProviderId;
      case AssistantTaskType.custom:
        return customProviderId;
    }
  }

  String modelFor(AssistantTaskType taskType) {
    switch (taskType) {
      case AssistantTaskType.llm:
        return llmModel;
      case AssistantTaskType.translate:
        return translateModel;
      case AssistantTaskType.reverse:
        return reverseModel;
      case AssistantTaskType.characterReplace:
        return characterReplaceModel;
      case AssistantTaskType.custom:
        return customModel;
    }
  }

  TaskRoutingConfig copyWithTask({
    required AssistantTaskType taskType,
    required String providerId,
    required String model,
  }) {
    switch (taskType) {
      case AssistantTaskType.llm:
        return copyWith(llmProviderId: providerId, llmModel: model);
      case AssistantTaskType.translate:
        return copyWith(
          translateProviderId: providerId,
          translateModel: model,
        );
      case AssistantTaskType.reverse:
        return copyWith(reverseProviderId: providerId, reverseModel: model);
      case AssistantTaskType.characterReplace:
        return copyWith(
          characterReplaceProviderId: providerId,
          characterReplaceModel: model,
        );
      case AssistantTaskType.custom:
        return copyWith(customProviderId: providerId, customModel: model);
    }
  }

  Map<String, dynamic> toJson() => {
        'llmProviderId': llmProviderId,
        'llmModel': llmModel,
        'translateProviderId': translateProviderId,
        'translateModel': translateModel,
        'reverseProviderId': reverseProviderId,
        'reverseModel': reverseModel,
        'characterReplaceProviderId': characterReplaceProviderId,
        'characterReplaceModel': characterReplaceModel,
        'customProviderId': customProviderId,
        'customModel': customModel,
      };

  factory TaskRoutingConfig.fromJson(Map<String, dynamic> json) {
    final llmProviderId = _routingString(json, 'llmProviderId');
    final llmModel = _routingString(json, 'llmModel');
    return TaskRoutingConfig(
      llmProviderId: llmProviderId,
      llmModel: llmModel,
      translateProviderId: _routingString(json, 'translateProviderId'),
      translateModel: _routingString(json, 'translateModel'),
      reverseProviderId: _routingString(
        json,
        'reverseProviderId',
        fallback: llmProviderId,
      ),
      reverseModel: _routingString(json, 'reverseModel', fallback: llmModel),
      characterReplaceProviderId: _routingString(
        json,
        'characterReplaceProviderId',
        fallback: llmProviderId,
      ),
      characterReplaceModel: _routingString(
        json,
        'characterReplaceModel',
        fallback: llmModel,
      ),
      customProviderId: _routingString(
        json,
        'customProviderId',
        fallback: llmProviderId,
      ),
      customModel: _routingString(json, 'customModel', fallback: llmModel),
    );
  }
}

String _routingString(
  Map<String, dynamic> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key] as String?;
  if (value == null) {
    return fallback;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

class PromptRuleTemplate {
  final String id;
  final String name;
  final AssistantTaskType taskType;
  final String content;
  final bool enabled;
  final bool isDefault;
  final int order;

  const PromptRuleTemplate({
    required this.id,
    required this.name,
    required this.taskType,
    required this.content,
    this.enabled = true,
    this.isDefault = false,
    this.order = 0,
  });

  PromptRuleTemplate copyWith({
    String? id,
    String? name,
    AssistantTaskType? taskType,
    String? content,
    bool? enabled,
    bool? isDefault,
    int? order,
  }) {
    return PromptRuleTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      taskType: taskType ?? this.taskType,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'taskType': taskType.name,
        'content': content,
        'enabled': enabled,
        'isDefault': isDefault,
        'order': order,
      };

  factory PromptRuleTemplate.fromJson(Map<String, dynamic> json) {
    return PromptRuleTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      taskType: AssistantTaskType.values.firstWhere(
        (t) => t.name == json['taskType'],
        orElse: () => AssistantTaskType.llm,
      ),
      content: json['content'] as String,
      enabled: json['enabled'] as bool? ?? true,
      isDefault: json['isDefault'] as bool? ?? false,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class StreamingChunk {
  final String delta;
  final bool done;

  const StreamingChunk({required this.delta, this.done = false});
}

class AssistantOperationResult {
  final bool success;
  final String content;
  final String? error;

  const AssistantOperationResult({
    required this.success,
    required this.content,
    this.error,
  });
}

class PromptAssistantConfigState {
  final bool enabled;
  final bool desktopOverlayEnabled;
  final bool streamOutput;
  final List<ProviderConfig> providers;
  final List<ModelConfig> models;
  final TaskRoutingConfig routing;
  final List<PromptRuleTemplate> rules;
  final Map<String, bool> providerHasApiKey;

  const PromptAssistantConfigState({
    required this.enabled,
    required this.desktopOverlayEnabled,
    required this.streamOutput,
    required this.providers,
    required this.models,
    required this.routing,
    required this.rules,
    required this.providerHasApiKey,
  });

  factory PromptAssistantConfigState.defaults() {
    return const PromptAssistantConfigState(
      enabled: true,
      desktopOverlayEnabled: true,
      streamOutput: false,
      providers: [],
      models: [],
      routing: TaskRoutingConfig(
        llmProviderId: '',
        llmModel: '',
        translateProviderId: '',
        translateModel: '',
        reverseProviderId: '',
        reverseModel: '',
        characterReplaceProviderId: '',
        characterReplaceModel: '',
        customProviderId: '',
        customModel: '',
      ),
      rules: [
        PromptRuleTemplate(
          id: 'opt_default',
          name: '默认优化规则',
          taskType: AssistantTaskType.llm,
          content: '你是提示词优化助手。保留用户核心意图，补充可执行细节，输出单行逗号分隔提示词。',
          isDefault: true,
        ),
        PromptRuleTemplate(
          id: 'translate_default',
          name: '默认翻译规则',
          taskType: AssistantTaskType.translate,
          content: '你是翻译助手。识别原文语言，自动在中英间互译，仅返回译文，不要解释。',
          isDefault: true,
        ),
        PromptRuleTemplate(
          id: 'reverse_default',
          name: '默认反推规则',
          taskType: AssistantTaskType.reverse,
          content:
              '你是图像反推助手。根据图片和可选 tagger 结果，输出适合 NovelAI 的英文逗号分隔提示词。保留主体、角色、画风、服装、动作、构图、光影和背景，不要解释。',
          isDefault: true,
        ),
        PromptRuleTemplate(
          id: 'character_replace_default',
          name: '默认角色替换规则',
          taskType: AssistantTaskType.characterReplace,
          content:
              '你是角色替换助手。将输入提示词中的原角色身份、发型、服装、外观替换为指定角色；保留动作、构图、背景、画风、镜头和质量词。仅输出替换后的单行提示词。',
          isDefault: true,
        ),
        PromptRuleTemplate(
          id: 'custom_default',
          name: '默认自定义规则',
          taskType: AssistantTaskType.custom,
          content:
              '你是提示词改写助手。根据当前提示词、用户的自由需求和可选参考图片修改提示词。只输出最终可直接使用的单行提示词，不要解释。',
          isDefault: true,
        ),
      ],
      providerHasApiKey: {},
    );
  }

  PromptAssistantConfigState copyWith({
    bool? enabled,
    bool? desktopOverlayEnabled,
    bool? streamOutput,
    List<ProviderConfig>? providers,
    List<ModelConfig>? models,
    TaskRoutingConfig? routing,
    List<PromptRuleTemplate>? rules,
    Map<String, bool>? providerHasApiKey,
  }) {
    return PromptAssistantConfigState(
      enabled: enabled ?? this.enabled,
      desktopOverlayEnabled:
          desktopOverlayEnabled ?? this.desktopOverlayEnabled,
      streamOutput: false,
      providers: providers ?? this.providers,
      models: models ?? this.models,
      routing: routing ?? this.routing,
      rules: rules ?? this.rules,
      providerHasApiKey: providerHasApiKey ?? this.providerHasApiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'enabled': enabled,
        'desktopOverlayEnabled': desktopOverlayEnabled,
        'streamOutput': false,
        'providers': providers.map((e) => e.toJson()).toList(),
        'models': models.map((e) => e.toJson()).toList(),
        'routing': routing.toJson(),
        'rules': rules.map((e) => e.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  List<ModelConfig> modelsForProviderTask({
    required String providerId,
    required AssistantTaskType taskType,
  }) {
    return _modelsForProviderTask(
      models,
      providerId: providerId,
      taskType: taskType,
    );
  }

  factory PromptAssistantConfigState.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final defaults = PromptAssistantConfigState.defaults();

    final providersRaw = json['providers'];
    var providers = providersRaw is List && providersRaw.isNotEmpty
        ? providersRaw
            .map((e) => ProviderConfig.fromJson(e as Map<String, dynamic>))
            .toList()
        : defaults.providers;

    final modelsRaw = json['models'];
    var decodedModels = modelsRaw is List && modelsRaw.isNotEmpty
        ? modelsRaw
            .map((e) => ModelConfig.fromJson(e as Map<String, dynamic>))
            .toList()
        : defaults.models;

    var routing = TaskRoutingConfig.fromJson(
      (json['routing'] as Map?)?.cast<String, dynamic>() ??
          defaults.routing.toJson(),
    );

    if (_isUntouchedLegacyPollinationsDefault(
      providers: providers,
      models: decodedModels,
      routing: routing,
      schemaVersion: json['schemaVersion'] as int?,
    )) {
      providers = const [];
      decodedModels = const [];
      routing = defaults.routing;
    }

    final models = _expandProviderModelsToAllTasks(
      _mergeDefaultModels(decodedModels, defaults.models),
    );

    for (final taskType in AssistantTaskType.values) {
      final providerId = routing.providerIdFor(taskType);
      if (providerId.isNotEmpty &&
          !providers.any((provider) => provider.id == providerId)) {
        routing = routing.copyWithTask(
          taskType: taskType,
          providerId: '',
          model: '',
        );
      }
    }
    routing = _normalizeRoutingModels(
      routing: routing,
      providers: providers,
      models: models,
    );

    final rulesRaw = json['rules'];
    final decodedRules = rulesRaw is List && rulesRaw.isNotEmpty
        ? rulesRaw
            .map((e) => PromptRuleTemplate.fromJson(e as Map<String, dynamic>))
            .toList()
        : defaults.rules;
    final rules = _mergeDefaultRules(decodedRules, defaults.rules);

    return PromptAssistantConfigState(
      enabled: json['enabled'] as bool? ?? true,
      desktopOverlayEnabled: json['desktopOverlayEnabled'] as bool? ?? true,
      streamOutput: false,
      providers: providers,
      models: models,
      routing: routing,
      rules: rules,
      providerHasApiKey: const {},
    );
  }

  static bool _isUntouchedLegacyPollinationsDefault({
    required List<ProviderConfig> providers,
    required List<ModelConfig> models,
    required TaskRoutingConfig routing,
    required int? schemaVersion,
  }) {
    if (schemaVersion != null) return false;
    final providerIds = providers.map((provider) => provider.id).toSet();
    final isSinglePollinationsDefault =
        providerIds.length == 1 && providerIds.contains('pollinations');
    final isOldThreeProviderDefault = providerIds.length == 3 &&
        providerIds.contains('pollinations') &&
        providerIds.contains('openai_custom') &&
        providerIds.contains('ollama');
    if (!isSinglePollinationsDefault && !isOldThreeProviderDefault) {
      return false;
    }
    final pollinations = providers.firstWhere(
      (provider) => provider.id == 'pollinations',
    );
    if (pollinations.enabled != true ||
        pollinations.baseUrl != 'https://gen.pollinations.ai') {
      return false;
    }
    if (isOldThreeProviderDefault) {
      final openai = providers.firstWhere(
        (provider) => provider.id == 'openai_custom',
      );
      final ollama = providers.firstWhere(
        (provider) => provider.id == 'ollama',
      );
      if (openai.enabled ||
          openai.baseUrl != 'https://api.openai.com/v1' ||
          ollama.enabled ||
          ollama.baseUrl != 'http://127.0.0.1:11434/v1') {
        return false;
      }
    }
    if (models.isEmpty) {
      return false;
    }
    for (final taskType in AssistantTaskType.values) {
      if (taskType == AssistantTaskType.custom) continue;
      if (routing.providerIdFor(taskType) != 'pollinations' ||
          routing.modelFor(taskType) != 'openai-large') {
        return false;
      }
    }
    return models.every(
      (model) =>
          model.providerId == 'pollinations' &&
          model.name == 'openai-large' &&
          model.isDefault,
    );
  }

  static List<ModelConfig> _mergeDefaultModels(
    List<ModelConfig> models,
    List<ModelConfig> defaults,
  ) {
    final result = [...models];
    for (final fallback in defaults) {
      final exists = result.any(
        (m) =>
            m.providerId == fallback.providerId &&
            m.name == fallback.name &&
            m.forTask == fallback.forTask,
      );
      if (!exists) {
        result.add(fallback);
      }
    }
    return result;
  }

  static List<ModelConfig> _expandProviderModelsToAllTasks(
    List<ModelConfig> models,
  ) {
    final result = [...models];
    final namesByProvider = <String, Map<String, ModelConfig>>{};

    for (final model in result) {
      namesByProvider.putIfAbsent(model.providerId, () => {})[model.name] =
          model;
    }

    for (final entry in namesByProvider.entries) {
      for (final model in entry.value.values) {
        for (final taskType in AssistantTaskType.values) {
          final exists = result.any(
            (candidate) =>
                candidate.providerId == model.providerId &&
                candidate.name == model.name &&
                candidate.forTask == taskType,
          );
          if (!exists) {
            result.add(model.copyWith(forTask: taskType));
          }
        }
      }
    }

    return result;
  }

  static TaskRoutingConfig _normalizeRoutingModels({
    required TaskRoutingConfig routing,
    required List<ProviderConfig> providers,
    required List<ModelConfig> models,
  }) {
    var next = routing;

    for (final taskType in AssistantTaskType.values) {
      final providerId = next.providerIdFor(taskType);
      if (providerId.isEmpty ||
          !providers.any((provider) => provider.id == providerId)) {
        continue;
      }

      final candidates = _modelsForProviderTask(
        models,
        providerId: providerId,
        taskType: taskType,
      );
      if (candidates.isEmpty) {
        continue;
      }

      final routedModel = next.modelFor(taskType);
      final hasRoutedModel =
          candidates.any((candidate) => candidate.name == routedModel);
      final isPlaceholderRoute =
          routedModel.trim().isEmpty || routedModel.trim() == 'default-model';
      final shouldReplacePlaceholder = isPlaceholderRoute &&
          candidates.any((candidate) => !candidate.isPlaceholder);

      if (!hasRoutedModel || shouldReplacePlaceholder) {
        next = next.copyWithTask(
          taskType: taskType,
          providerId: providerId,
          model: candidates.first.name,
        );
      }
    }

    return next;
  }

  static List<ModelConfig> _modelsForProviderTask(
    List<ModelConfig> source, {
    required String providerId,
    required AssistantTaskType taskType,
  }) {
    final candidates = <ModelConfig>[];
    final names = <String>{};

    void addCandidate(ModelConfig model) {
      if (!names.add(model.name)) {
        return;
      }
      candidates.add(model.copyWith(forTask: taskType));
    }

    for (final model in source) {
      if (model.providerId == providerId && model.forTask == taskType) {
        addCandidate(model);
      }
    }

    for (final model in source) {
      if (model.providerId == providerId) {
        addCandidate(model);
      }
    }

    candidates.sort((a, b) {
      final aPlaceholder = a.isPlaceholder;
      final bPlaceholder = b.isPlaceholder;
      if (aPlaceholder != bPlaceholder) {
        return aPlaceholder ? 1 : -1;
      }
      return a.displayName.compareTo(b.displayName);
    });

    return candidates;
  }

  static List<PromptRuleTemplate> _mergeDefaultRules(
    List<PromptRuleTemplate> rules,
    List<PromptRuleTemplate> defaults,
  ) {
    final result = [...rules];
    for (final fallback in defaults) {
      final index = result.indexWhere((r) => r.id == fallback.id);
      if (index >= 0) {
        result[index] = result[index].copyWith(isDefault: true);
      } else {
        result.add(fallback);
      }
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }
}
