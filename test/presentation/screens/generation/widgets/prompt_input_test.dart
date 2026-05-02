import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/core/services/prompt_token_counter_service.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/prompt_token_counter_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_input.dart';

void main() {
  test('Windows 下提示词切换按钮不使用富文本 Tooltip', () {
    expect(
      usesRichPromptTypeTooltip(TargetPlatform.windows),
      isFalse,
    );
    expect(
      usesRichPromptTypeTooltip(TargetPlatform.macOS),
      isTrue,
    );
  });

  testWidgets('冷启动时切换到负面提示词不会抛出异常', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) {
            return _TestLocalStorageService();
          }),
          characterPromptNotifierProvider.overrideWith(
            _TestCharacterPromptNotifier.new,
          ),
          promptTokenUsageProvider(PromptTokenCountTarget.positive)
              .overrideWith(
            (ref) async => const PromptTokenUsage(
              usedTokens: 0,
              limit: 512,
            ),
          ),
          promptTokenUsageProvider(PromptTokenCountTarget.negative)
              .overrideWith(
            (ref) async => const PromptTokenUsage(
              usedTokens: 0,
              limit: 512,
            ),
          ),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(
            body: SizedBox(
              width: 960,
              height: 420,
              child: PromptInputWidget(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.block).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('generation_prompt_negative_input')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestLocalStorageService extends LocalStorageService {
  @override
  bool getEnableAutocomplete() => false;

  @override
  bool getAutoFormatPrompt() => false;

  @override
  bool getHighlightEmphasis() => false;

  @override
  bool getSdSyntaxAutoConvert() => false;

  @override
  bool getEnableCooccurrenceRecommendation() => false;

  @override
  String getLastPrompt() => '';

  @override
  String getLastNegativePrompt() => '';

  @override
  String getDefaultModel() => 'nai-diffusion-4-5-full';

  @override
  String getDefaultSampler() => 'k_euler_ancestral';

  @override
  int getDefaultSteps() => 28;

  @override
  double getDefaultScale() => 5.0;

  @override
  int getDefaultWidth() => 832;

  @override
  int getDefaultHeight() => 1216;

  @override
  bool getLastSmea() => false;

  @override
  bool getLastSmeaDyn() => false;

  @override
  double getLastCfgRescale() => 0.0;

  @override
  String getLastNoiseSchedule() => 'native';

  @override
  bool getSeedLocked() => false;

  @override
  int? getLockedSeedValue() => null;
}

class _TestCharacterPromptNotifier extends CharacterPromptNotifier {
  @override
  CharacterPromptConfig build() => const CharacterPromptConfig();
}
