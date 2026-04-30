import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/sd_to_nai_converter.dart';

void main() {
  group('SdToNaiConverter', () {
    test('should not treat tag names with trailing parenthetical qualifiers as SD weights', () {
      expect(
        SdToNaiConverter.convert('summer dress (blue_archive)'),
        equals('summer dress (blue_archive)'),
      );
    });

    test('should still convert standalone emphasis brackets', () {
      expect(
        SdToNaiConverter.convert('(masterpiece)'),
        equals('1.1::masterpiece::'),
      );
    });

    test('should preserve spaces when only converting SD syntax', () {
      expect(
        SdToNaiConverter.convert('(long hair)'),
        equals('1.1::long hair::'),
      );
      expect(
        SdToNaiConverter.convert('(cinematic lighting:1.3)'),
        equals('1.3::cinematic lighting::'),
      );
    });
  });
}
