import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/utils/text_selection_utils.dart';

void main() {
  group('TextSelectionUtils.wrapSelection', () {
    test('should wrap selected text and preserve the wrapped selection', () {
      const value = TextEditingValue(
        text: 'masterpiece, 1girl, blue_eyes',
        selection: TextSelection(baseOffset: 13, extentOffset: 18),
      );

      final wrapped = TextSelectionUtils.wrapSelection(
        value,
        open: '{',
        close: '}',
      );

      expect(wrapped.text, equals('masterpiece, {1girl}, blue_eyes'));
      expect(
        wrapped.selection,
        const TextSelection(baseOffset: 13, extentOffset: 20),
      );
    });

    test('should keep value unchanged when there is no active selection', () {
      const value = TextEditingValue(
        text: 'solo',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(
        TextSelectionUtils.wrapSelection(value, open: '[', close: ']'),
        equals(value),
      );
    });
  });

  group('TextSelectionUtils.wrapSelectionOnBracketReplacement', () {
    test('should convert bracket replacement into wrapped selection', () {
      const oldValue = TextEditingValue(
        text: 'masterpiece, 1girl, blue_eyes',
        selection: TextSelection(baseOffset: 13, extentOffset: 18),
      );
      const newValue = TextEditingValue(
        text: 'masterpiece, [, blue_eyes',
        selection: TextSelection.collapsed(offset: 14),
      );

      final wrapped = TextSelectionUtils.wrapSelectionOnBracketReplacement(
        oldValue,
        newValue,
      );

      expect(wrapped.text, 'masterpiece, [1girl], blue_eyes');
      expect(
        wrapped.selection,
        const TextSelection(baseOffset: 13, extentOffset: 20),
      );
    });

    test('should convert brace replacement into wrapped selection', () {
      const oldValue = TextEditingValue(
        text: 'masterpiece, 1girl, blue_eyes',
        selection: TextSelection(baseOffset: 13, extentOffset: 18),
      );
      const newValue = TextEditingValue(
        text: 'masterpiece, {, blue_eyes',
        selection: TextSelection.collapsed(offset: 14),
      );

      final wrapped = TextSelectionUtils.wrapSelectionOnBracketReplacement(
        oldValue,
        newValue,
      );

      expect(wrapped.text, 'masterpiece, {1girl}, blue_eyes');
      expect(
        wrapped.selection,
        const TextSelection(baseOffset: 13, extentOffset: 20),
      );
    });

    test('should ignore non-bracket replacement', () {
      const oldValue = TextEditingValue(
        text: 'masterpiece, 1girl, blue_eyes',
        selection: TextSelection(baseOffset: 13, extentOffset: 18),
      );
      const newValue = TextEditingValue(
        text: 'masterpiece, x, blue_eyes',
        selection: TextSelection.collapsed(offset: 14),
      );

      expect(
        TextSelectionUtils.wrapSelectionOnBracketReplacement(
          oldValue,
          newValue,
        ),
        newValue,
      );
    });

    test('should ignore full-width bracket replacement', () {
      const oldValue = TextEditingValue(
        text: 'masterpiece, 1girl, blue_eyes',
        selection: TextSelection(baseOffset: 13, extentOffset: 18),
      );
      const newValue = TextEditingValue(
        text: 'masterpiece, （, blue_eyes',
        selection: TextSelection.collapsed(offset: 14),
      );

      expect(
        TextSelectionUtils.wrapSelectionOnBracketReplacement(
          oldValue,
          newValue,
        ),
        newValue,
      );
    });

    test('should ignore replacement while ime composing is active', () {
      const oldValue = TextEditingValue(
        text: 'masterpiece, 1girl, blue_eyes',
        selection: TextSelection(baseOffset: 13, extentOffset: 18),
        composing: TextRange(start: 13, end: 18),
      );
      const newValue = TextEditingValue(
        text: 'masterpiece, [, blue_eyes',
        selection: TextSelection.collapsed(offset: 14),
        composing: TextRange(start: 13, end: 14),
      );

      expect(
        TextSelectionUtils.wrapSelectionOnBracketReplacement(
          oldValue,
          newValue,
        ),
        newValue,
      );
    });
  });
}
