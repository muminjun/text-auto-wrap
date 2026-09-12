import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  group('detectTextWrapLanguage', () {
    test('selects the Korean preset at the exact dominance threshold', () {
      final result = detectTextWrapLanguage('가가가가가가가abc', null);

      expect(result.hangulCount, 7);
      expect(result.latinCount, 3);
      expect(result.hangulRatio, .7);
      expect(result.model, same(TextAutoWrapModels.korean));
      expect(result.localeResolved, isFalse);
      expect(result.fallbackReason, isNull);
    });

    test('selects the English preset for Latin text', () {
      final result = detectTextWrapLanguage('English display title', null);

      expect(result.hangulCount, 0);
      expect(result.latinCount, 19);
      expect(result.hangulRatio, 0);
      expect(result.model, same(TextAutoWrapModels.english));
      expect(result.localeResolved, isFalse);
      expect(result.fallbackReason, isNull);
    });

    test('uses a matching locale for a 40 to 60 percent product-name mix', () {
      final result = detectTextWrapLanguage(
        '가가가가abcdef',
        const Locale('ko', 'KR'),
      );

      expect(result.hangulCount, 4);
      expect(result.latinCount, 6);
      expect(result.hangulRatio, .4);
      expect(result.model, same(TextAutoWrapModels.korean));
      expect(result.localeResolved, isTrue);
      expect(result.fallbackReason, isNull);
    });

    test('does not use a non-matching locale for mixed product-name text', () {
      final result = detectTextWrapLanguage('가가가가abcdef', const Locale('en'));

      expect(result.model, same(TextAutoWrapModels.english));
      expect(result.localeResolved, isTrue);
    });

    test('falls back for an unresolved mix above 60 and below 70 percent', () {
      final result = detectTextWrapLanguage('가가가가가가가가가가가가가abcdefg', null);

      expect(result.hangulCount, 13);
      expect(result.latinCount, 7);
      expect(result.hangulRatio, .65);
      expect(result.model, isNull);
      expect(result.localeResolved, isFalse);
      expect(result.fallbackReason, 'ambiguousLanguage');
    });

    test('counts Hangul syllables and jamo but not combining marks', () {
      final result = detectTextWrapLanguage('ᄀ가e\u0301', null);

      expect(result.hangulCount, 2);
      expect(result.latinCount, 1);
      expect(result.hangulRatio, closeTo(2 / 3, 0.000001));
      expect(result.model, isNull);
      expect(result.fallbackReason, 'ambiguousLanguage');
    });

    for (final text in ['こんにちは', 'مرحبا', '😀✨', '123 456']) {
      test('falls back for text without supported letters: $text', () {
        final result = detectTextWrapLanguage(text, null);

        expect(result.hangulCount, 0);
        expect(result.latinCount, 0);
        expect(result.hangulRatio, 0);
        expect(result.model, isNull);
        expect(result.localeResolved, isFalse);
        expect(result.fallbackReason, 'unsupportedLanguage');
      });
    }

    test(
      'ignores object-replacement characters with punctuation and whitespace',
      () {
        final result = detectTextWrapLanguage(
          '가가가가\uFFFC, a b c d e f!',
          const Locale('ko'),
        );

        expect(result.hangulCount, 4);
        expect(result.latinCount, 6);
        expect(result.model, same(TextAutoWrapModels.korean));
        expect(result.localeResolved, isTrue);
      },
    );
  });

  test(
    'the automatic model resolves while explicit presets remain direct models',
    () {
      final automatic = TextAutoWrapModels.auto;

      expect(automatic, isA<AutoTextWrapModel>());
      expect(
        automatic.resolve('English display title', const Locale('ko')).model,
        same(TextAutoWrapModels.english),
      );
      expect(TextAutoWrapModels.korean, isA<PhraseModel>());
      expect(TextAutoWrapModels.english, isA<PhraseModel>());
      expect(TextAutoWrapModels.korean, isNot(same(automatic)));
    },
  );
}
