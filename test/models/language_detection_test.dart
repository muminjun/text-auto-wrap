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

    test('selects English at the exact 70 percent dominance threshold', () {
      final result = detectTextWrapLanguage('가가가abcdefg', null);

      expect(result.hangulCount, 3);
      expect(result.latinCount, 7);
      expect(result.hangulRatio, .3);
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

    test('uses English locale at its exact 60 percent assistance boundary', () {
      final result = detectTextWrapLanguage('가가가가abcdef', const Locale('en'));

      expect(result.model, same(TextAutoWrapModels.english));
      expect(result.localeResolved, isTrue);
    });

    for (final fixture in [
      (
        name: 'Korean at 60 percent',
        text: '가가가가가가abcd',
        locale: const Locale('ko'),
        model: TextAutoWrapModels.korean,
      ),
      (
        name: 'English at 40 percent',
        text: '가가가가가가abcd',
        locale: const Locale('en'),
        model: TextAutoWrapModels.english,
      ),
    ]) {
      test('uses a matching locale for ${fixture.name}', () {
        final result = detectTextWrapLanguage(fixture.text, fixture.locale);

        expect(result.model, same(fixture.model));
        expect(result.localeResolved, isTrue);
        expect(result.fallbackReason, isNull);
      });
    }

    test('falls back for an unresolved mix above 60 and below 70 percent', () {
      final result = detectTextWrapLanguage('가가가가가가가가가가가가가abcdefg', null);

      expect(result.hangulCount, 13);
      expect(result.latinCount, 7);
      expect(result.hangulRatio, .65);
      expect(result.model, isNull);
      expect(result.localeResolved, isFalse);
      expect(result.fallbackReason, 'ambiguousLanguage');
    });

    for (final fixture in [
      (
        name: 'Korean 65 percent with Korean locale',
        text: '가가가가가가가가가가가가가abcdefg',
        locale: const Locale('ko'),
        model: TextAutoWrapModels.korean,
      ),
      (
        name: 'English 65 percent with English locale',
        text: '가가가가가가가abcdefghijklm',
        locale: const Locale('en'),
        model: TextAutoWrapModels.english,
      ),
      (
        name: 'Korean 65 percent with English locale',
        text: '가가가가가가가가가가가가가abcdefg',
        locale: const Locale('en'),
        model: null,
      ),
      (
        name: 'English 65 percent with Korean locale',
        text: '가가가가가가가abcdefghijklm',
        locale: const Locale('ko'),
        model: null,
      ),
    ]) {
      test('handles ${fixture.name}', () {
        final result = detectTextWrapLanguage(fixture.text, fixture.locale);

        expect(
          result.model,
          fixture.model == null ? isNull : same(fixture.model),
        );
        expect(result.localeResolved, fixture.model != null);
        expect(
          result.fallbackReason,
          fixture.model == null ? 'ambiguousLanguage' : isNull,
        );
      });
    }

    for (final fixture in [
      (
        name: 'Korean language with Hang script and Korean region',
        locale: const Locale.fromSubtags(
          languageCode: 'KO',
          scriptCode: 'Hang',
          countryCode: 'KR',
        ),
        model: TextAutoWrapModels.korean,
      ),
      (
        name: 'English language with Latn script and US region',
        locale: const Locale.fromSubtags(
          languageCode: 'EN',
          scriptCode: 'Latn',
          countryCode: 'US',
        ),
        model: TextAutoWrapModels.english,
      ),
    ]) {
      test('normalizes ${fixture.name}', () {
        final result = detectTextWrapLanguage('가가가가abcdef', fixture.locale);

        expect(result.model, same(fixture.model));
        expect(result.localeResolved, isTrue);
      });
    }

    test('counts Hangul syllables and jamo but not combining marks', () {
      final result = detectTextWrapLanguage('ᄀ가e\u0301', null);

      expect(result.hangulCount, 2);
      expect(result.latinCount, 1);
      expect(result.hangulRatio, closeTo(2 / 3, 0.000001));
      expect(result.model, isNull);
      expect(result.fallbackReason, 'ambiguousLanguage');
    });

    for (final text in ['', 'こんにちは', 'مرحبا', '😀✨', '123 456']) {
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

    test('does not count unassigned Hangul-block code points as evidence', () {
      final result = detectTextWrapLanguage('\u3130\uA97D\uD7C7', null);

      expect(result.hangulCount, 0);
      expect(result.latinCount, 0);
      expect(result.model, isNull);
      expect(result.fallbackReason, 'unsupportedLanguage');
    });

    test('counts assigned Hangul jamo at their block boundaries', () {
      final result = detectTextWrapLanguage('\u3131\uA97C\uD7C6', null);

      expect(result.hangulCount, 3);
      expect(result.latinCount, 0);
      expect(result.model, same(TextAutoWrapModels.korean));
    });

    test('counts fullwidth and Extended-F/G Latin letters', () {
      final result = detectTextWrapLanguage(
        '\uFF21\uFF41\u{10780}\u{1DF00}',
        null,
      );

      expect(result.hangulCount, 0);
      expect(result.latinCount, 4);
      expect(result.model, same(TextAutoWrapModels.english));
    });

    test('ignores unsupported scripts among supported-letter evidence', () {
      final result = detectTextWrapLanguage('가가가가가가가가가日本abc', null);

      expect(result.hangulCount, 9);
      expect(result.latinCount, 3);
      expect(result.model, same(TextAutoWrapModels.korean));
    });
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
