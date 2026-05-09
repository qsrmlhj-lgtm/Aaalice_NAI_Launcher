import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/data/services/vibe_library_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/parameter_panel.dart';
import 'package:nai_launcher/presentation/widgets/common/themed_slider.dart';

void main() {
  group('resolveManualSizeFieldSyncText', () {
    test('keeps focused field text untouched while user is typing', () {
      final result = resolveManualSizeFieldSyncText(
        currentText: '83',
        targetValue: 8,
        hasFocus: true,
      );

      expect(result, isNull);
    });

    test('syncs unfocused field to latest widget value', () {
      final result = resolveManualSizeFieldSyncText(
        currentText: '832',
        targetValue: 1216,
        hasFocus: false,
      );

      expect(result, equals('1216'));
    });
  });

  group('resolveSeedFieldSyncText', () {
    test('keeps focused seed text untouched while user is typing', () {
      final result = resolveSeedFieldSyncText(
        currentText: '',
        seed: 123456,
        hasFocus: true,
      );

      expect(result, isNull);
    });

    test('syncs unfocused field to external seed value', () {
      final result = resolveSeedFieldSyncText(
        currentText: '',
        seed: 123456,
        hasFocus: false,
      );

      expect(result, equals('123456'));
    });

    test('syncs random seed state to empty field text', () {
      final result = resolveSeedFieldSyncText(
        currentText: '123456',
        seed: -1,
        hasFocus: false,
      );

      expect(result, equals(''));
    });
  });

  group('ParameterPanel', () {
    testWidgets('CFG scale slider uses 0.1 increments', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWith(
              (ref) => _TestLocalStorageService(),
            ),
            vibeLibraryStorageServiceProvider.overrideWithValue(
              _TestVibeLibraryStorageService(),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: SizedBox(
                width: 960,
                height: 1200,
                child: ParameterPanel(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final cfgSliders = tester
          .widgetList<ThemedSlider>(find.byType(ThemedSlider))
          .where(
            (slider) =>
                slider.min == 1 && slider.max == 20 && slider.value == 5.0,
          )
          .toList();

      expect(cfgSliders, hasLength(1));
      expect(cfgSliders.single.divisions, equals(190));
    });
  });
}

class _TestLocalStorageService extends LocalStorageService {
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
  bool getLastVarietyPlus() => false;

  @override
  bool getSeedLocked() => false;

  @override
  int? getLockedSeedValue() => null;
}

class _TestVibeLibraryStorageService extends VibeLibraryStorageService {
  @override
  Future<List<VibeLibraryEntry>> getRecentDisplayEntries({
    int limit = 20,
  }) async {
    return const [];
  }
}
