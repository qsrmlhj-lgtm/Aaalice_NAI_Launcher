import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/app.dart';
import 'package:nai_launcher/core/comfyui/builtin_workflows.dart';
import 'package:nai_launcher/core/comfyui/comfyui_url_utils.dart';
import 'package:nai_launcher/core/comfyui/workflow_node_validator.dart';
import 'package:nai_launcher/core/comfyui/workflow_template_manager.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/shortcuts/default_shortcuts.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_config.dart';
import 'package:nai_launcher/core/utils/file_explorer_utils.dart';
import 'package:nai_launcher/core/utils/nai_resolution_adapter.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/gallery/gallery_statistics.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';
import 'package:nai_launcher/data/services/local_onnx_tagger_service.dart';
import 'package:nai_launcher/data/services/statistics_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_provider.dart';
import 'package:nai_launcher/presentation/providers/generation/image_workflow_controller.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';
import 'package:nai_launcher/presentation/providers/selection_mode_provider.dart';
import 'package:nai_launcher/presentation/providers/share_image_settings_provider.dart';
import 'package:nai_launcher/presentation/providers/shortcuts_provider.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/prompt_assistant_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/prompt_assistant_history_provider.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/prompt_assistant_api_client.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/prompt_assistant_service.dart';
import 'package:nai_launcher/presentation/screens/statistics/widgets/dashboard/aspect_ratio_card.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/tag_library_toolbar.dart';
import 'package:nai_launcher/presentation/screens/vibe_library/widgets/vibe_export_dialog.dart';
import 'package:nai_launcher/presentation/screens/vibe_library/widgets/vibe_export_dialog_advanced.dart';
import 'package:nai_launcher/presentation/utils/dropped_file_reader.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_gallery_toolbar.dart';
import 'package:nai_launcher/presentation/widgets/shortcuts/shortcut_aware_widget.dart';

class _MockDio extends Mock implements Dio {}

/// 简单的 Widget 测试示例
///
/// 运行: flutter test test/app_test.dart
void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('Widget Tests', () {
    testWidgets('MaterialApp 创建', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Hello'),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('按钮点击', (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () => pressed = true,
              child: const Text('Click'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('AppBootstrapEffects 监听 provider 变化时不重建子树', (tester) async {
      final anlasWatcherProvider = StateProvider<int>((ref) => 0);
      final backgroundRefreshProvider = StateProvider<int>((ref) => 0);
      var buildCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AppBootstrapEffects(
              anlasWatcher: anlasWatcherProvider,
              backgroundRefresh: backgroundRefreshProvider,
              child: Builder(
                builder: (context) {
                  buildCount++;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppBootstrapEffects)),
      );

      expect(container.exists(anlasWatcherProvider), isTrue);
      expect(container.exists(backgroundRefreshProvider), isTrue);
      expect(buildCount, 1);

      container.read(anlasWatcherProvider.notifier).state = 1;
      await tester.pump();
      container.read(backgroundRefreshProvider.notifier).state = 1;
      await tester.pump();

      expect(buildCount, 1);
    });

    testWidgets('本地画廊搜索框 Ctrl+A 应选择文本而不是进入多选', (tester) async {
      var enteredSelectionMode = false;
      const query = 'a';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localGalleryNotifierProvider.overrideWith(
              _FakeLocalGalleryNotifier.new,
            ),
            shortcutConfigNotifierProvider.overrideWith(
              _FakeShortcutConfigNotifier.new,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PageShortcuts(
                contextType: ShortcutContext.gallery,
                shortcuts: {
                  ShortcutIds.enterSelectionMode: () {
                    enteredSelectionMode = true;
                  },
                },
                child: const LocalGalleryToolbar(
                  enableSearchAutocomplete: false,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.enterText(textField, query);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.selection.baseOffset, 0);
      expect(editable.controller.selection.extentOffset, query.length);
      expect(enteredSelectionMode, isFalse);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LocalGalleryToolbar)),
      );
      expect(
        container.read(localGallerySelectionNotifierProvider).isActive,
        isFalse,
      );
    });

    testWidgets('词库工具栏重建时搜索框应显示当前搜索条件', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tagLibraryPageNotifierProvider.overrideWith(
              _FakeTagLibraryPageNotifier.new,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: TagLibraryToolbar(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, 'rabbit');
    });

    testWidgets('批量 Vibe 导出不显示嵌入 PNG 入口', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VibeExportDialogAdvanced(
                entries: [
                  _buildVibeEntry(id: 'first', displayName: 'First'),
                  _buildVibeEntry(id: 'second', displayName: 'Second'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Export as PNG'), findsNothing);
    });

    testWidgets('单个 Vibe 导出显示嵌入 PNG 入口', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VibeExportDialog(
                entries: [
                  _buildVibeEntry(id: 'single', displayName: 'Single'),
                ],
                categories: const [],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('嵌入到 PNG'), findsOneWidget);

      await tester.tap(find.text('嵌入到 PNG'));
      await tester.pumpAndSettle();

      expect(find.text('选择外部 PNG 图片...'), findsOneWidget);
    });
  });

  group('ComfyUI URL helpers', () {
    test('normalizes pasted server URLs without breaking scheme typing', () {
      expect(
        normalizeComfyUIBaseUrl('  http://127.0.0.1:8188/  '),
        'http://127.0.0.1:8188',
      );
      expect(
        normalizeComfyUIBaseUrl('https://example.test/comfyui///'),
        'https://example.test/comfyui',
      );
      expect(normalizeComfyUIBaseUrl('http://'), 'http://');
      expect(normalizeComfyUIBaseUrl('https://'), 'https://');
    });

    test('builds websocket URLs without double slashes', () {
      final rootUri = buildComfyUIWebSocketUri(
        baseUrl: 'http://127.0.0.1:8188/',
        clientId: 'client-1',
      );
      final proxiedUri = buildComfyUIWebSocketUri(
        baseUrl: 'https://example.test/comfyui/',
        clientId: 'client-1',
      );

      expect(rootUri.toString(), 'ws://127.0.0.1:8188/ws?clientId=client-1');
      expect(
        proxiedUri.toString(),
        'wss://example.test/comfyui/ws?clientId=client-1',
      );
    });
  });

  group('File explorer helpers', () {
    test('uses a separate Explorer select switch for paths with spaces', () {
      const filePath = r'C:\Users\alice\NAI Launcher\history image.png';

      expect(
        FileExplorerUtils.windowsRevealFileArguments(filePath),
        ['/select,', filePath],
      );
    });
  });

  group('ComfyUI upscale workflows', () {
    test('SeedVR2 workflow avoids optional helper nodes', () {
      final workflow = BuiltinWorkflows.all.firstWhere(
        (workflow) => workflow.id == comfySeedvr2UpscaleTemplateId,
      );
      final nodeTypes = extractWorkflowNodeTypes(workflow.workflowJson);

      expect(nodeTypes, isNot(contains('Float')));
      expect(nodeTypes, isNot(contains('easy imageSizeBySide')));
      expect(nodeTypes, isNot(contains('LayerUtility: NumberCalculatorV2')));
      expect(workflow.workflowJson['5']['inputs']['resolution'], isA<int>());
      expect(
        workflow.parameterSlots.map((slot) => slot.id),
        contains('target_resolution'),
      );
    });

    test('injects SeedVR2 target resolution into the upscaler node', () {
      final manager = WorkflowTemplateManager()..loadBuiltinTemplates();
      final workflow = manager.getById(comfySeedvr2UpscaleTemplateId)!;

      final executable = manager.buildExecutableWorkflow(
        template: workflow,
        paramValues: const {'target_resolution': 1536},
      );

      expect(executable['5']['inputs']['resolution'], 1536);
    });

    test('injects SeedVR2 VAE tile size into encode and decode fields', () {
      final manager = WorkflowTemplateManager()..loadBuiltinTemplates();
      final workflow = manager.getById(comfySeedvr2UpscaleTemplateId)!;

      final executable = manager.buildExecutableWorkflow(
        template: workflow,
        paramValues: const {
          'vae_encode_tile_size': 768,
          'vae_decode_tile_size': 768,
        },
      );

      expect(executable['7']['inputs']['encode_tile_size'], 768);
      expect(executable['7']['inputs']['decode_tile_size'], 768);
    });

    test('includes RTX upscale workflow using Nvidia RTX nodes', () {
      final manager = WorkflowTemplateManager()..loadBuiltinTemplates();
      final workflow = manager.getById('builtin_rtx_upscale')!;
      final nodeTypes = extractWorkflowNodeTypes(workflow.workflowJson);

      expect(nodeTypes, contains('RTXVideoSuperResolution'));
      expect(nodeTypes, isNot(contains('UpscaleModelLoader')));
      expect(
        workflow.parameterSlots.map((slot) => slot.id),
        contains('rtx_scale'),
      );
    });

    test('includes SeedVR2 tiled workflow with tile size controls', () {
      final manager = WorkflowTemplateManager()..loadBuiltinTemplates();
      final workflow = manager.getById('builtin_seedvr2_tiled_upscale')!;

      final executable = manager.buildExecutableWorkflow(
        template: workflow,
        paramValues: const {
          'tile_size': 1280,
          'tile_upscale_resolution': 1536,
        },
      );

      expect(executable['8']['class_type'], 'SeedVR2TilingUpscaler');
      expect(executable['8']['inputs']['tile_width'], 1280);
      expect(executable['8']['inputs']['tile_height'], 1280);
      expect(executable['8']['inputs']['tile_upscale_resolution'], 1536);
    });

    test('detects missing ComfyUI node types before queueing workflow', () {
      final missing = findMissingWorkflowNodeTypes(
        workflow: {
          '1': {
            'class_type': 'LoadImage',
            'inputs': <String, dynamic>{},
          },
          '18': {
            'class_type': 'Float',
            'inputs': <String, dynamic>{},
          },
        },
        objectInfo: {
          'LoadImage': <String, dynamic>{},
        },
      );

      expect(missing, ['Float']);
      expect(
        formatMissingWorkflowNodeTypesMessage(missing),
        contains('Float'),
      );
    });

    test('calculates SeedVR2 target resolution from source shortest side', () {
      expect(
        calculateComfySeedvr2TargetResolution(
          sourceWidth: 832,
          sourceHeight: 1216,
          scale: 1.5,
        ),
        1248,
      );
    });

    test('adapts img2img sources to 64-pixel grid without preset snapping', () {
      final adapted = NaiResolutionAdapter.findClosestResolution(1000, 1400);

      expect(adapted.width, 1024);
      expect(adapted.height, 1408);
      expect(
        NaiResolutionAdapter.isCompatible(adapted.width, adapted.height),
        isTrue,
      );
    });

    test('does not overwrite saved upscale model before server fetch', () {
      expect(
        shouldAutoPersistResolvedUpscaleModel(
          isComfyBackend: true,
          hasFetchedFromServer: false,
          availableModels: const ['seedvr2_ema_7b_fp16.safetensors'],
          currentModel: 'seedvr2_ema_3b-Q4_K_M.gguf',
          resolvedModel: 'seedvr2_ema_7b_fp16.safetensors',
        ),
        isFalse,
      );
      expect(
        shouldAutoPersistResolvedUpscaleModel(
          isComfyBackend: true,
          hasFetchedFromServer: true,
          availableModels: const ['seedvr2_ema_7b_fp16.safetensors'],
          currentModel: 'missing-model.safetensors',
          resolvedModel: 'seedvr2_ema_7b_fp16.safetensors',
        ),
        isTrue,
      );
    });

    test('includes regular model upscale workflow with Lanczos final resize',
        () {
      final workflow = BuiltinWorkflows.all.firstWhere(
        (workflow) => workflow.id == comfyModelUpscaleTemplateId,
      );

      expect(workflow.workflowJson['2']['class_type'], 'UpscaleModelLoader');
      expect(
        workflow.workflowJson['3']['class_type'],
        'ImageUpscaleWithModel',
      );
      expect(workflow.workflowJson['4']['class_type'], 'ImageScale');
      expect(
        workflow.workflowJson['4']['inputs']['upscale_method'],
        'lanczos',
      );
    });

    test('classifies SeedVR2 and regular ComfyUI upscale models', () {
      expect(
        isComfySeedvr2UpscaleModel('seedvr2_ema_7b_fp16.safetensors'),
        isTrue,
      );
      expect(
        isComfySeedvr2UpscaleModel('4x-UltraSharpV2.safetensors'),
        isFalse,
      );
      expect(
        isComfySeedvr2UpscaleModel('realesrganX4plusAnime_v1.pt'),
        isFalse,
      );
    });
  });

  group('Image workflow upscale persistence', () {
    late Directory hiveTempDir;

    setUpAll(() async {
      hiveTempDir = await Directory.systemTemp.createTemp(
        'nai_launcher_app_test_hive_',
      );
      Hive.init(hiveTempDir.path);
      await Hive.openBox(StorageKeys.settingsBox);
    });

    setUp(() async {
      await Hive.box(StorageKeys.settingsBox).clear();
    });

    tearDownAll(() async {
      if (Hive.isBoxOpen(StorageKeys.settingsBox)) {
        await Hive.box(StorageKeys.settingsBox).close();
      }
      if (await hiveTempDir.exists()) {
        await hiveTempDir.delete(recursive: true);
      }
    });

    test('keeps separate model choices across local upscale modules', () async {
      const seedvr2Model = 'seedvr2_ema_7b_fp16.safetensors';
      const regularModel = '4x-UltraSharpV2.pth';
      final firstContainer = ProviderContainer();

      try {
        final controller =
            firstContainer.read(imageWorkflowControllerProvider.notifier);

        controller.updateComfyUpscaleModule(ComfyUpscaleModule.seedvr2);
        controller.updateUpscaleComfyModel(seedvr2Model);
        controller.updateComfyUpscaleModule(ComfyUpscaleModule.regular);
        controller.updateUpscaleComfyModel(regularModel);
        controller.updateComfyUpscaleModule(ComfyUpscaleModule.rtx);
        controller.updateComfyUpscaleModule(ComfyUpscaleModule.seedvr2);

        expect(
          firstContainer
              .read(imageWorkflowControllerProvider)
              .upscale
              .comfyModel,
          seedvr2Model,
        );

        controller.updateComfyUpscaleModule(ComfyUpscaleModule.regular);

        expect(
          firstContainer
              .read(imageWorkflowControllerProvider)
              .upscale
              .comfyModel,
          regularModel,
        );

        await Future<void>.delayed(Duration.zero);
        await Hive.box(StorageKeys.settingsBox).flush();
      } finally {
        firstContainer.dispose();
      }

      final secondContainer = ProviderContainer();
      try {
        final workflow = secondContainer.read(imageWorkflowControllerProvider);

        expect(workflow.upscale.comfyModule, ComfyUpscaleModule.regular);
        expect(workflow.upscale.comfyModel, regularModel);
        expect(workflow.upscale.comfyRegularModel, regularModel);
        expect(workflow.upscale.comfySeedvr2Model, seedvr2Model);

        secondContainer
            .read(imageWorkflowControllerProvider.notifier)
            .updateComfyUpscaleModule(ComfyUpscaleModule.seedvr2);

        expect(
          secondContainer
              .read(imageWorkflowControllerProvider)
              .upscale
              .comfyModel,
          seedvr2Model,
        );
      } finally {
        secondContainer.dispose();
      }
    });
  });

  group('Statistics dashboard', () {
    test('ignores non-positive image dimensions in resolution statistics', () {
      final service = StatisticsService();
      final modifiedAt = DateTime(2026);

      final stats = service.calculateStatistics([
        LocalImageRecord(
          path: 'zero.png',
          size: 1024,
          modifiedAt: modifiedAt,
          metadata: const NaiImageMetadata(width: 0, height: 0),
        ),
        LocalImageRecord(
          path: 'valid.png',
          size: 1024,
          modifiedAt: modifiedAt,
          metadata: const NaiImageMetadata(width: 1024, height: 1024),
        ),
      ]);

      expect(stats.resolutionDistribution.map((r) => r.label), ['1024x1024']);
    });

    testWidgets('aspect ratio card skips invalid cached resolutions', (
      tester,
    ) async {
      final stats = GalleryStatistics(
        totalImages: 2,
        totalSizeBytes: 2048,
        averageFileSizeBytes: 1024,
        resolutionDistribution: const [
          ResolutionStatistics(label: '0x0', count: 1),
          ResolutionStatistics(label: '1024x1024', count: 1),
        ],
        calculatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AspectRatioCard(stats: stats)),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('宽高比分布'), findsOneWidget);
      expect(find.text('1:1'), findsOneWidget);
    });
  });

  group('Dropped file reader URL helpers', () {
    test('extracts Discord CDN image URLs from HTML payloads', () {
      final uri = DroppedFileReader.extractImageUriFromText(
        '<img src="https://media.discordapp.net/attachments/1/2/image.png?ex=abc&amp;is=def">',
      );

      expect(uri, isNotNull);
      expect(uri!.host, 'media.discordapp.net');
      expect(uri.path, '/attachments/1/2/image.png');
      expect(uri.queryParameters['ex'], 'abc');
      expect(uri.queryParameters['is'], 'def');
    });

    test('infers image file names from URL and response headers', () {
      expect(
        DroppedFileReader.inferFileNameFromUri(
          Uri.parse(
            'https://cdn.discordapp.com/attachments/a/b/sample.webp?ex=1',
          ),
        ),
        'sample.webp',
      );
      expect(
        DroppedFileReader.inferFileNameFromUri(
          Uri.parse('https://media.discordapp.net/attachments/a/b/image'),
          contentType: 'image/jpeg',
        ),
        'image.jpg',
      );
      expect(
        DroppedFileReader.inferFileNameFromUri(
          Uri.parse('https://example.test/download'),
          contentDisposition: 'attachment; filename="discord drop.png"',
          contentType: 'image/png',
        ),
        'discord drop.png',
      );
    });
  });

  group('Protection mode settings', () {
    test('gates individual protection features behind the master switch', () {
      const disabled = ShareImageSettings(
        protectionMode: false,
        stripMetadataForCopyAndDrag: true,
        confirmDangerousActions: true,
        warnExternalImageSend: true,
        preventOverwrite: true,
        warnHighAnlasCost: true,
        highAnlasCostThreshold: 50,
      );

      expect(disabled.effectiveStripMetadataForCopyAndDrag, isFalse);
      expect(disabled.effectiveConfirmDangerousActions, isFalse);
      expect(disabled.effectiveWarnExternalImageSend, isFalse);
      expect(disabled.effectivePreventOverwrite, isFalse);
      expect(disabled.effectiveWarnHighAnlasCost, isFalse);

      final enabled = disabled.copyWith(protectionMode: true);
      expect(enabled.effectiveStripMetadataForCopyAndDrag, isTrue);
      expect(enabled.effectiveConfirmDangerousActions, isTrue);
      expect(enabled.effectiveWarnExternalImageSend, isTrue);
      expect(enabled.effectivePreventOverwrite, isTrue);
      expect(enabled.effectiveWarnHighAnlasCost, isTrue);
    });

    test('allows each protection feature to be disabled independently', () {
      const settings = ShareImageSettings(
        protectionMode: true,
        stripMetadataForCopyAndDrag: false,
        confirmDangerousActions: false,
        warnExternalImageSend: false,
        preventOverwrite: false,
        warnHighAnlasCost: false,
        highAnlasCostThreshold: 50,
      );

      expect(settings.effectiveStripMetadataForCopyAndDrag, isFalse);
      expect(settings.effectiveConfirmDangerousActions, isFalse);
      expect(settings.effectiveWarnExternalImageSend, isFalse);
      expect(settings.effectivePreventOverwrite, isFalse);
      expect(settings.effectiveWarnHighAnlasCost, isFalse);
    });
  });

  group('Prompt assistant defaults', () {
    test('contains immutable defaults for all assistant task types', () {
      final defaults = PromptAssistantConfigState.defaults();
      expect(defaults.streamOutput, isFalse);

      for (final taskType in AssistantTaskType.values) {
        expect(
          defaults.models.any(
            (model) => model.forTask == taskType && model.isDefault,
          ),
          isTrue,
        );
        expect(
          defaults.rules.any(
            (rule) => rule.taskType == taskType && rule.isDefault,
          ),
          isTrue,
        );
        expect(defaults.routing.providerIdFor(taskType), isNotEmpty);
        expect(defaults.routing.modelFor(taskType), isNotEmpty);
      }
    });

    test(
      'hydrates reverse and character replacement routing from old config',
      () {
        final oldConfig = PromptAssistantConfigState.defaults()
            .copyWith(
              models: PromptAssistantConfigState.defaults()
                  .models
                  .where(
                    (model) =>
                        model.forTask == AssistantTaskType.llm ||
                        model.forTask == AssistantTaskType.translate,
                  )
                  .toList(),
              rules: PromptAssistantConfigState.defaults()
                  .rules
                  .where(
                    (rule) =>
                        rule.taskType == AssistantTaskType.llm ||
                        rule.taskType == AssistantTaskType.translate,
                  )
                  .toList(),
            )
            .toJson()
          ..['routing'] = const TaskRoutingConfig(
            llmProviderId: 'pollinations',
            llmModel: 'openai-large',
            translateProviderId: 'pollinations',
            translateModel: 'openai-large',
            reverseProviderId: '',
            reverseModel: '',
            characterReplaceProviderId: '',
            characterReplaceModel: '',
          ).toJson();

        final decoded = PromptAssistantConfigState.decode(
          PromptAssistantConfigState(
            enabled: oldConfig['enabled'] as bool,
            desktopOverlayEnabled: oldConfig['desktopOverlayEnabled'] as bool,
            streamOutput: oldConfig['streamOutput'] as bool,
            providers: (oldConfig['providers'] as List)
                .cast<Map<String, dynamic>>()
                .map(ProviderConfig.fromJson)
                .toList(),
            models: (oldConfig['models'] as List)
                .cast<Map<String, dynamic>>()
                .map(ModelConfig.fromJson)
                .toList(),
            routing: TaskRoutingConfig.fromJson(
              (oldConfig['routing'] as Map).cast<String, dynamic>(),
            ),
            rules: (oldConfig['rules'] as List)
                .cast<Map<String, dynamic>>()
                .map(PromptRuleTemplate.fromJson)
                .toList(),
            providerHasApiKey: const {},
          ).encode(),
        );

        expect(decoded.streamOutput, isFalse);
        expect(
          decoded.models.any(
            (model) => model.forTask == AssistantTaskType.reverse,
          ),
          isTrue,
        );
        expect(
          decoded.models.any(
            (model) => model.forTask == AssistantTaskType.characterReplace,
          ),
          isTrue,
        );
        expect(
          decoded.rules.any(
            (rule) => rule.taskType == AssistantTaskType.reverse,
          ),
          isTrue,
        );
        expect(
          decoded.rules.any(
            (rule) => rule.taskType == AssistantTaskType.characterReplace,
          ),
          isTrue,
        );
        expect(
          decoded.routing.providerIdFor(AssistantTaskType.reverse),
          isNotEmpty,
        );
        expect(
          decoded.routing.providerIdFor(AssistantTaskType.characterReplace),
          isNotEmpty,
        );
      },
    );

    test('reuses pulled provider models for reverse and character tasks', () {
      const providerId = 'openai_custom';
      const modelName = '[PAY]gemini-3.1-pro-preview';
      final defaults = PromptAssistantConfigState.defaults();
      final providers = defaults.providers
          .map(
            (provider) => provider.id == providerId
                ? provider.copyWith(enabled: true)
                : provider,
          )
          .toList();

      final decoded = PromptAssistantConfigState.decode(
        defaults
            .copyWith(
              providers: providers,
              models: const [
                ModelConfig(
                  providerId: providerId,
                  name: modelName,
                  displayName: modelName,
                  forTask: AssistantTaskType.llm,
                ),
                ModelConfig(
                  providerId: providerId,
                  name: modelName,
                  displayName: modelName,
                  forTask: AssistantTaskType.translate,
                ),
                ModelConfig(
                  providerId: providerId,
                  name: 'default-model',
                  displayName: 'default-model',
                  forTask: AssistantTaskType.reverse,
                  isDefault: true,
                ),
                ModelConfig(
                  providerId: providerId,
                  name: 'default-model',
                  displayName: 'default-model',
                  forTask: AssistantTaskType.characterReplace,
                  isDefault: true,
                ),
              ],
              routing: const TaskRoutingConfig(
                llmProviderId: providerId,
                llmModel: modelName,
                translateProviderId: providerId,
                translateModel: modelName,
                reverseProviderId: providerId,
                reverseModel: 'default-model',
                characterReplaceProviderId: providerId,
                characterReplaceModel: 'default-model',
              ),
            )
            .encode(),
      );

      for (final taskType in [
        AssistantTaskType.reverse,
        AssistantTaskType.characterReplace,
      ]) {
        final models = decoded.modelsForProviderTask(
          providerId: providerId,
          taskType: taskType,
        );
        expect(models.map((model) => model.name), contains(modelName));
        expect(models.first.name, modelName);
        expect(decoded.routing.modelFor(taskType), modelName);
      }
    });
  });

  group('Prompt assistant API client', () {
    test('character replacement payload keeps source prompt as primary input',
        () {
      final payload =
          PromptAssistantService.buildCharacterReplacementUserContent(
        sourcePrompt: '1girl, sitting, classroom, looking at viewer',
        characterName: 'target',
        characterPrompt: 'target girl, silver hair, blue dress',
      );

      expect(payload, contains('待替换提示词'));
      expect(payload, contains('1girl, sitting, classroom, looking at viewer'));
      expect(payload, isNot(contains('源语境标签')));
      expect(payload, contains('目标角色提示词'));
      expect(payload, contains('target girl, silver hair, blue dress'));
      expect(
        payload.indexOf('1girl, sitting, classroom'),
        lessThan(payload.indexOf('target girl, silver hair')),
      );
      expect(
        PromptAssistantService.characterReplacementInstruction,
        contains('不要输出分析'),
      );
    });

    test('sends chat requests as non-streaming JSON', () async {
      final dio = _MockDio();
      final client = PromptAssistantApiClient(dio: dio);

      when(
        () => dio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        final payload =
            Map<String, dynamic>.from(invocation.namedArguments[#data] as Map);
        final options = invocation.namedArguments[#options] as Options;
        expect(payload['stream'], isFalse);
        expect(payload.containsKey('temperature'), isFalse);
        expect(payload.containsKey('top_p'), isFalse);
        expect(payload.containsKey('max_tokens'), isFalse);
        expect(options.responseType, isNot(ResponseType.stream));
        return Response<dynamic>(
          data: const {
            'choices': [
              {
                'message': {'content': 'hello'},
              },
            ],
          },
          requestOptions: RequestOptions(path: '/v1/chat/completions'),
          statusCode: 200,
        );
      });

      final chunks = await client
          .streamChat(
            sessionId: 'test',
            provider: const ProviderConfig(
              id: 'openai_custom',
              name: 'OpenAI Compatible',
              type: ProviderType.openaiCompatible,
              baseUrl: 'https://example.invalid/v1',
            ),
            model: 'model-a',
            messages: const [
              {'role': 'user', 'content': 'test'},
            ],
            apiKey: 'key',
          )
          .toList();

      expect(
        chunks.where((chunk) => !chunk.done).map((chunk) => chunk.delta).join(),
        'hello',
      );
      expect(chunks.last.done, isTrue);
    });

    test('throws a visible error when the non-stream response has no content',
        () async {
      final dio = _MockDio();
      final client = PromptAssistantApiClient(dio: dio);

      when(
        () => dio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: const {'choices': <Object>[]},
          requestOptions: RequestOptions(path: '/v1/chat/completions'),
          statusCode: 200,
        ),
      );

      expect(
        () => client
            .streamChat(
              sessionId: 'test',
              provider: const ProviderConfig(
                id: 'openai_custom',
                name: 'OpenAI Compatible',
                type: ProviderType.openaiCompatible,
                baseUrl: 'https://example.invalid/v1',
              ),
              model: 'model-a',
              messages: const [
                {'role': 'user', 'content': 'test'},
              ],
              apiKey: 'key',
            )
            .drain<void>(),
        throwsA(isA<StateError>()),
      );
    });

    test('retries non-streaming on 400 without sampling params', () async {
      final dio = _MockDio();
      final client = PromptAssistantApiClient(dio: dio);
      var callCount = 0;

      when(
        () => dio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        callCount++;
        final payload =
            Map<String, dynamic>.from(invocation.namedArguments[#data] as Map);
        expect(payload['stream'], isFalse);
        if (callCount == 1) {
          expect(payload.containsKey('temperature'), isFalse);
          expect(payload.containsKey('top_p'), isFalse);
          expect(payload.containsKey('max_tokens'), isFalse);
          throw DioException(
            requestOptions: RequestOptions(path: '/v1/chat/completions'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/v1/chat/completions'),
              statusCode: 400,
            ),
          );
        }
        expect(payload.containsKey('temperature'), isFalse);
        expect(payload.containsKey('top_p'), isFalse);
        expect(payload.containsKey('max_tokens'), isFalse);
        return Response<dynamic>(
          data: const {
            'choices': [
              {
                'message': {'content': 'fallback result'},
              },
            ],
          },
          requestOptions: RequestOptions(path: '/v1/chat/completions'),
          statusCode: 200,
        );
      });

      final chunks = await client
          .streamChat(
            sessionId: 'test',
            provider: const ProviderConfig(
              id: 'openai_custom',
              name: 'OpenAI Compatible',
              type: ProviderType.openaiCompatible,
              baseUrl: 'https://example.invalid/v1',
            ),
            model: 'model-a',
            messages: const [
              {'role': 'user', 'content': 'test'},
            ],
            apiKey: 'key',
          )
          .toList();

      expect(
        chunks.where((chunk) => !chunk.done).map((chunk) => chunk.delta).join(),
        'fallback result',
      );
      expect(chunks.last.done, isTrue);
      expect(callCount, 2);
    });
  });

  group('Prompt assistant fixed tag scope', () {
    test('strips enabled fixed prefixes and suffixes before assistant tasks',
        () {
      final state = FixedTagsState(
        entries: [
          FixedTagEntry.create(
            name: 'quality',
            content: 'masterpiece, best quality',
            position: FixedTagPosition.prefix,
          ),
          FixedTagEntry.create(
            name: 'suffix',
            content: 'highres',
            position: FixedTagPosition.suffix,
          ),
          FixedTagEntry.create(
            name: 'disabled',
            content: 'keep_me',
            enabled: false,
            position: FixedTagPosition.prefix,
          ),
        ],
      );

      expect(
        state.stripFromPrompt(
          'masterpiece, best quality, 1girl, smile, highres',
        ),
        '1girl, smile',
      );
      expect(state.stripFromPrompt('1girl, smile'), '1girl, smile');
      expect(
        state.stripFromPrompt('keep_me, 1girl, highres'),
        'keep_me, 1girl',
      );
    });
  });

  group('ONNX tagger categories', () {
    test('keeps only general and character label categories by default', () {
      expect(
        const OnnxTaggerLabel(name: '1girl', category: 'General').isGeneral,
        isTrue,
      );
      expect(
        const OnnxTaggerLabel(name: 'hakurei_reimu', category: 'Character')
            .isCharacter,
        isTrue,
      );
      expect(
        const OnnxTaggerLabel(name: '1girl', category: '0').isGeneral,
        isTrue,
      );
      expect(
        const OnnxTaggerLabel(name: 'hakurei_reimu', category: '4').isCharacter,
        isTrue,
      );
      expect(
        const OnnxTaggerLabel(name: 'general', category: 'Rating').isRating,
        isTrue,
      );
      expect(
        const OnnxTaggerLabel(name: 'artist_name', category: 'Artist')
            .labelCategory,
        OnnxTaggerLabelCategory.other,
      );
    });
  });

  group('Prompt injected history', () {
    test('supports external undo and redo for injected prompts', () {
      final history = PromptAssistantHistoryNotifier();
      history.recordExternalChange(
        PromptHistorySessionIds.generationPrompt,
        before: 'old prompt',
        after: 'reverse prompt',
      );

      expect(
        history.undoExternal(
          PromptHistorySessionIds.generationPrompt,
          'reverse prompt',
        ),
        'old prompt',
      );
      expect(
        history.redoExternal(
          PromptHistorySessionIds.generationPrompt,
          'old prompt',
        ),
        'reverse prompt',
      );
      expect(
        history.undoExternal(
          PromptHistorySessionIds.generationPrompt,
          'manual edit after injection',
        ),
        isNull,
      );
    });
  });
}

class _FakeLocalGalleryNotifier extends LocalGalleryNotifier {
  @override
  LocalGalleryState build() => const LocalGalleryState(
        isInitialized: true,
        totalPages: 1,
      );

  @override
  Future<void> setSearchQuery(String query) async {}

  @override
  Future<void> clearAllFilters() async {}
}

class _FakeShortcutConfigNotifier extends ShortcutConfigNotifier {
  @override
  Future<ShortcutConfig> build() async => ShortcutConfig.createDefault();
}

class _FakeTagLibraryPageNotifier extends TagLibraryPageNotifier {
  @override
  TagLibraryPageState build() => const TagLibraryPageState(
        searchQuery: 'rabbit',
      );
}

VibeLibraryEntry _buildVibeEntry({
  required String id,
  required String displayName,
}) {
  return VibeLibraryEntry(
    id: id,
    name: displayName,
    vibeDisplayName: displayName,
    vibeEncoding: 'ZW5jb2RlZA==',
    strength: 0.6,
    infoExtracted: 0.7,
    sourceTypeIndex: VibeSourceType.naiv4vibe.index,
    createdAt: DateTime(2026, 5, 2),
  );
}
