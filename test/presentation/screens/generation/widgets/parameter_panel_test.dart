import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/parameter_panel.dart';

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
}
