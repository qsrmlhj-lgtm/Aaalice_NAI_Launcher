import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/history_panel.dart';

void main() {
  group('resolveHistoryPreviewAspectRatio', () {
    test('preserves extreme aspect ratios without clamping', () {
      expect(resolveHistoryPreviewAspectRatio(4.8), equals(4.8));
      expect(resolveHistoryPreviewAspectRatio(0.18), equals(0.18));
    });

    test('falls back when aspect ratio is invalid', () {
      expect(
        resolveHistoryPreviewAspectRatio(double.nan, fallback: 1.5),
        equals(1.5),
      );
      expect(
        resolveHistoryPreviewAspectRatio(0, fallback: 0.75),
        equals(0.75),
      );
    });
  });
}
