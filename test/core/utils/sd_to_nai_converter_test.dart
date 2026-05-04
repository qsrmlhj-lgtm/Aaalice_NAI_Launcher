import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/sd_to_nai_converter.dart';

void main() {
  group('SdToNaiConverter', () {
    test(
        'should not treat tag names with trailing parenthetical qualifiers as SD weights',
        () {
      expect(
        SdToNaiConverter.convert('summer dress (blue_archive)'),
        equals('summer dress (blue_archive)'),
      );
    });

    test('should preserve inline parenthetical qualifiers with spaces', () {
      expect(
        SdToNaiConverter.convert('summer dress (blue archive)'),
        equals('summer dress (blue archive)'),
      );
      expect(
        SdToNaiConverter.convert('artist name (fate grand order)'),
        equals('artist name (fate grand order)'),
      );
      expect(
        SdToNaiConverter.convert('preset tag (1.2)'),
        equals('preset tag (1.2)'),
      );
    });

    test('should preserve tag qualifiers while converting standalone emphasis',
        () {
      expect(
        SdToNaiConverter.convert(
          'summer dress (blue archive), (cinematic lighting)',
        ),
        equals('summer dress (blue archive), 1.1::cinematic lighting::'),
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

    test('should unescape SD escaped parentheses in prompts', () {
      expect(
        SdToNaiConverter.convert(r'\(literal parentheses\)'),
        equals('(literal parentheses)'),
      );
      expect(
        SdToNaiConverter.convert(r'\(literal\), (cinematic lighting)'),
        equals('(literal), 1.1::cinematic lighting::'),
      );
      expect(
        SdToNaiConverter.convert(r'1.2::tag::, \(literal\)'),
        equals('1.2::tag::, (literal)'),
      );
    });
  });
}
