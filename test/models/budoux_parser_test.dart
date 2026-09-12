import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  group('BudouxPredictor feature scoring', () {
    // A wrong feature-window position must move or remove this sole boundary.
    for (final (group, feature) in const [
      ('UW1', 'a'),
      ('UW2', 'b'),
      ('UW3', 'c'),
      ('UW4', 'd'),
      ('UW5', 'e'),
      ('UW6', 'f'),
      ('BW1', 'bc'),
      ('BW2', 'cd'),
      ('BW3', 'de'),
      ('TW1', 'abc'),
      ('TW2', 'bcd'),
      ('TW3', 'cde'),
      ('TW4', 'def'),
    ]) {
      test('$group scores the correct UTF-16 window', () {
        final predictor = BudouxPredictor({
          group: {feature: 2},
        });

        expect(predictor.predict('abcdef'), [3]);
      });
    }

    // JavaScript substring clamps both ends; Dart substring does not.
    for (final (group, feature, offsets) in const [
      ('UW1', '', [1, 2]),
      ('UW2', '', [1]),
      ('UW5', '', [2]),
      ('UW6', '', [1, 2]),
      ('BW1', 'a', [1]),
      ('BW3', 'c', [2]),
      ('TW1', 'a', [1]),
      ('TW2', 'ab', [1]),
      ('TW3', 'bc', [2]),
      ('TW4', 'c', [2]),
    ]) {
      test('$group clamps edge windows for feature "$feature"', () {
        final predictor = BudouxPredictor({
          group: {feature: 2},
        });

        expect(predictor.predict('abc'), offsets);
      });
    }

    test('uses strictly positive scores and sums every model weight', () {
      final predictor = BudouxPredictor({
        'UW3': {'a': 2, 'b': 1, 'c': 3},
        'UW4': {'x': 2},
      });

      // Base is -4: ax scores 0, bx scores -1, cx scores +1.
      expect(predictor.predict('ax'), isEmpty);
      expect(predictor.predict('bx'), isEmpty);
      expect(predictor.predict('cx'), [1]);
    });

    test('preserves fractional weights without rounding', () {
      final predictor = BudouxPredictor({
        'UW3': {'a': 0.25, 'b': 0.125},
      });

      expect(predictor.predict('ab'), [1]);
      expect(predictor.predict('ba'), isEmpty);
    });

    test('includes unknown feature groups in the base score like upstream', () {
      final predictor = BudouxPredictor({
        'UW3': {'a': 2},
        'unused': {'feature': 2},
      });

      expect(predictor.predict('ab'), isEmpty);
    });

    test('returns no boundaries for empty models or short strings', () {
      expect(BudouxPredictor({}).predict('abc'), isEmpty);
      expect(BudouxPredictor({'UW3': <String, num>{}}).predict('abc'), isEmpty);
      final predictor = BudouxPredictor({
        'UW3': {'a': 2},
      });
      expect(predictor.predict(''), isEmpty);
      expect(predictor.predict('a'), isEmpty);
      expect(predictor.predict('가'), isEmpty);
      expect(predictor.predict('😀'), isEmpty);
    });

    test('predicts Latin and Hangul boundaries using the upstream scorer', () {
      expect(
        BudouxPredictor({
          'UW3': {'e': 100},
        }).predict('one two'),
        [3],
      );
      expect(
        BudouxPredictor({
          'UW3': {'나': 100},
        }).predict('하나둘셋'),
        [2],
      );
    });

    test('reports ascending UTF-16 offsets next to emoji and Hangul', () {
      final predictor = BudouxPredictor({
        'UW3': {'a': 2, '가': 2},
        'UW4': {'\uD83D': 2},
      });

      expect(predictor.predict('a😀가😀a😀'), [1, 4, 7]);
    });

    test('scores surrogate-pair bigrams as two UTF-16 code units', () {
      final predictor = BudouxPredictor({
        'BW1': {'😀': 2},
      });

      expect(predictor.predict('😀a😀b'), [2, 5]);
    });

    test('defensively freezes both levels of caller-provided maps', () {
      final group = <String, num>{'a': 2};
      final model = <String, Map<String, num>>{'UW3': group};
      final predictor = BudouxPredictor(model);
      group['a'] = -100;
      model.clear();

      expect(predictor.predict('ab'), [1]);
    });

    test('returns immutable output without retaining a previous result', () {
      final predictor = BudouxPredictor({
        'UW3': {'a': 2},
      });
      final result = predictor.predict('ab');

      expect(() => result.add(2), throwsUnsupportedError);
      expect(predictor.predict('ba'), isEmpty);
      expect(result, [1]);
    });
  });

  group('BudouxPredictor model validation', () {
    for (final (name, model) in <(String, Object?)>[
      ('null model', null),
      ('list model', []),
      ('string model', 'weights'),
      ('non-string group key', {1: <String, num>{}}),
      ('null group', {'UW3': null}),
      ('list group', {'UW3': <Object?>[]}),
      (
        'non-string feature key',
        {
          'UW3': {1: 1},
        },
      ),
      (
        'null weight',
        {
          'UW3': {'a': null},
        },
      ),
      (
        'string weight',
        {
          'UW3': {'a': '1'},
        },
      ),
      (
        'boolean weight',
        {
          'UW3': {'a': true},
        },
      ),
      (
        'NaN weight',
        {
          'UW3': {'a': double.nan},
        },
      ),
      (
        'infinite weight',
        {
          'UW3': {'a': double.infinity},
        },
      ),
      (
        'negative infinite weight',
        {
          'UW3': {'a': double.negativeInfinity},
        },
      ),
    ]) {
      test('rejects $name with a typed package exception', () {
        expect(
          () => BudouxPredictor(model),
          throwsA(isA<InvalidModelConfigurationException>()),
        );
      });
    }
  });
}
