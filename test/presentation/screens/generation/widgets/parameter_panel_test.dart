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
}
