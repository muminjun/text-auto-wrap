import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  for (final (name, ranges, widths)
      in <(String, List<TextLineRange>, List<double>)>[
        (
          'range does not split at selected break',
          [const TextLineRange(0, 5)],
          [5],
        ),
        (
          'omitted source prefix',
          [const TextLineRange(1, 2), const TextLineRange(3, 5)],
          [1, 2],
        ),
        (
          'omitted interior source content',
          [const TextLineRange(0, 1), const TextLineRange(3, 5)],
          [1, 2],
        ),
        (
          'omitted source suffix',
          [const TextLineRange(0, 2), const TextLineRange(3, 4)],
          [2, 1],
        ),
        (
          'forged finite widths',
          [const TextLineRange(0, 2), const TextLineRange(3, 5)],
          [0.1, 0.1],
        ),
      ]) {
    test('rejects custom calculated $name', () {
      final plan = createTextWrapPlan(
        text: 'aa bb',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'p',
              predictor: CountingPredictor(),
              penalty: 0,
            ),
          ],
          fallbackPenalty: 1,
        ),
        strategy: LineBreakStrategy(
          calculator: InconsistentCalculator(ranges, widths),
        ),
      );
      expect(
        () => plan.select(
          maxWidth: 10,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
        throwsA(isA<TextWrapException>()),
      );
    });
  }
  test(
    'custom calculator cannot forge candidate costs or stale width status',
    () {
      final plan = createTextWrapPlan(
        text: 'aa bb',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'p',
              predictor: CountingPredictor(),
              penalty: 0,
            ),
          ],
          fallbackPenalty: 1,
        ),
        strategy: LineBreakStrategy(calculator: ForgedCalculator()),
      );
      expect(
        () => plan.select(
          maxWidth: 2,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    },
  );
  test(
    'a measurement callback reentering with another key cannot contaminate cache',
    () {
      final plan = createTextWrapPlan(
        text: 'aa bb',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'p',
              predictor: CountingPredictor(),
              penalty: 0,
            ),
          ],
          fallbackPenalty: 1,
        ),
      );
      final firstKey = Object();
      final secondKey = Object();
      var reentered = false;
      plan.select(
        maxWidth: 5,
        measurementCacheKey: firstKey,
        measureRange: (start, end) {
          if (!reentered) {
            reentered = true;
            plan.select(
              maxWidth: 5,
              measurementCacheKey: secondKey,
              measureRange: (start, end) => (end - start) * 2.0,
            );
          }
          return (end - start).toDouble();
        },
      );
      final second = plan.select(
        maxWidth: 5,
        measurementCacheKey: secondKey,
        measureRange: (start, end) => (end - start) * 2.0,
      );
      expect(second.lines, ['aa', 'bb']);
      expect(second.widths, [4, 4]);
    },
  );
  test(
    'plan caches prediction and aggregation while recalculating each width',
    () {
      final predictor = CountingPredictor();
      final aggregator = CountingAggregator();
      final calculator = CountingCalculator();
      final selector = CountingSelector();
      final plan = createTextWrapPlan(
        text: 'aa bb cc',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'preferred',
              predictor: predictor,
              penalty: 0,
            ),
          ],
          fallbackPenalty: 1,
        ),
        strategy: LineBreakStrategy(
          aggregator: aggregator,
          calculator: calculator,
          selector: selector,
        ),
      );
      expect(predictor.calls, 0);
      final predictions = plan.predict();
      expect(identical(plan.predict(), predictions), isTrue);
      final candidates = plan.aggregate();
      expect(identical(plan.aggregate(), candidates), isTrue);
      var measured = 0;
      double measure(int start, int end) {
        measured++;
        return (end - start).toDouble();
      }

      final first = plan.select(
        maxWidth: 5,
        measureRange: measure,
        diagnostics: true,
      );
      final firstMeasurements = measured;
      final second = plan.select(
        maxWidth: 2,
        measureRange: measure,
        diagnostics: true,
      );
      expect(first.lines, ['aa', 'bb cc']);
      expect(second.lines, ['aa', 'bb', 'cc']);
      expect(predictor.calls, 1);
      expect(aggregator.calls, 1);
      expect(calculator.calls, 2);
      expect(selector.calls, 2);
      expect(measured, greaterThan(firstMeasurements));
      final diagnostics = second.diagnostics!;
      expect(diagnostics.predictions.single.offsets, [3]);
      expect(diagnostics.candidates.map((c) => c.offset), [3, 6]);
      expect(diagnostics.calculatedLayouts, isNotEmpty);
      expect(diagnostics.nativeLayout, isNull);
      expect(diagnostics.selection.source, TextWrapSelectionSource.calculated);
      expect(diagnostics.cache.predictionRuns, 1);
      expect(diagnostics.cache.aggregationRuns, 1);
      expect(diagnostics.cache.calculationRuns, 2);
      expect(diagnostics.cache.selectionRuns, 2);
      expect(diagnostics.cache.predictionHits, greaterThan(0));
      expect(diagnostics.cache.aggregationHits, greaterThan(0));
      expect(first.diagnostics!.cache.calculationRuns, 1);
      expect(() => diagnostics.predictions.clear(), throwsUnsupportedError);
      expect(() => diagnostics.candidates.clear(), throwsUnsupportedError);
      expect(
        () => diagnostics.calculatedLayouts.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'measurement reuse requires the same non-null key and changes never leak',
    () {
      final plan = createTextWrapPlan(
        text: 'aa bb',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'p',
              predictor: CountingPredictor(),
              penalty: 0,
            ),
          ],
          fallbackPenalty: 1,
        ),
      );
      var calls = 0;
      double measure(int start, int end) {
        calls++;
        return (end - start).toDouble();
      }

      final key = Object();
      plan.calculate(
        maxWidth: 5,
        measureRange: measure,
        measurementCacheKey: key,
      );
      final measured = calls;
      final cached = plan.select(
        maxWidth: 5,
        measureRange: measure,
        measurementCacheKey: key,
        diagnostics: true,
      );
      expect(calls, measured);
      expect(cached.diagnostics!.cache.measurementHits, greaterThan(0));
      final changed = plan.select(
        maxWidth: 5,
        measureRange: (start, end) {
          calls++;
          return (end - start) * 2.0;
        },
        measurementCacheKey: Object(),
      );
      expect(changed.lines, ['aa', 'bb']);
      expect(changed.widths, [4, 4]);
      expect(calls, greaterThan(measured));
      final noKey = plan.select(maxWidth: 5, measureRange: measure);
      expect(noKey.lines, ['aa bb']);
    },
  );
  test(
    'select invokes missing prerequisites and scores native soft breaks from model',
    () {
      final predictor = CountingPredictor();
      final plan = createTextWrapPlan(
        text: 'aa bb cc',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(name: 'p', predictor: predictor, penalty: 0),
          ],
          fallbackPenalty: 5,
        ),
      );
      final native = LineBreakLayout(
        sourceText: 'aa bb cc',
        ranges: [const TextLineRange(0, 5), const TextLineRange(6, 8)],
        widths: [5, 2],
        maxWidth: 5,
      );
      final result = plan.select(
        maxWidth: 5,
        nativeLayout: native,
        measureRange: (start, end) => (end - start).toDouble(),
        diagnostics: true,
      );
      expect(predictor.calls, 1);
      expect(result.reason, 'calculatedSelected');
      expect(result.diagnostics!.nativeLayout!.totalModelCost, 5);
      expect(result.diagnostics!.nativeLayout!.breakOffsets, [6]);
      expect(result.lines, ['aa', 'bb cc']);
    },
  );
}

final class CountingPredictor implements BoundaryPredictor {
  int calls = 0;
  @override
  List<int> predict(String text) {
    calls++;
    return [3];
  }
}

final class CountingAggregator implements PredictionAggregator {
  int calls = 0;
  @override
  PredictionSnapshot aggregate(
    PredictionContext context, {
    List<BreakPrediction>? predictions,
  }) {
    calls++;
    return lowestPenalty().aggregate(context, predictions: predictions);
  }
}

final class CountingCalculator implements LayoutCalculator {
  int calls = 0;
  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    calls++;
    return optimalLayouts().calculate(
      text: text,
      candidates: candidates,
      maxWidth: maxWidth,
      measureRange: measureRange,
      baseline: baseline,
    );
  }
}

final class CountingSelector implements LayoutSelector {
  int calls = 0;
  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) {
    calls++;
    return const BalanceStrategy().select(context);
  }
}

final class ForgedCalculator implements LayoutCalculator {
  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => LayoutCalculationSuccess([
    LineBreakLayout(
      sourceText: text,
      ranges: [const TextLineRange(0, 2), const TextLineRange(3, 5)],
      widths: [3, 3],
      maxWidth: 100,
      selectedCandidates: [
        const BreakCandidate(
          offset: 3,
          penalty: 99,
          levelName: null,
          consensusCount: 0,
          isFallback: true,
        ),
      ],
    ),
  ]);
}

final class InconsistentCalculator implements LayoutCalculator {
  InconsistentCalculator(this.ranges, this.widths);
  final List<TextLineRange> ranges;
  final List<double> widths;

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => LayoutCalculationSuccess([
    LineBreakLayout(
      sourceText: text,
      ranges: ranges,
      widths: widths,
      maxWidth: maxWidth,
      selectedCandidates: [candidates.single],
    ),
  ]);
}
