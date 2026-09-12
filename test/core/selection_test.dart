import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

LineBreakLayout fixture({
  double imbalance = 0,
  double cost = 1,
  bool overflow = false,
  int lines = 2,
  int offset = 2,
}) => LineBreakLayout(
  sourceText: 'abcd',
  ranges: lines == 1
      ? [const TextLineRange(0, 4)]
      : [TextLineRange(0, offset), TextLineRange(offset, 4)],
  widths: lines == 1 ? [100] : [100, 100 * (1 - imbalance)],
  maxWidth: overflow ? 90 : 100,
  selectedCandidates: lines == 1
      ? []
      : [
          BreakCandidate(
            offset: offset,
            penalty: cost,
            levelName: null,
            consensusCount: 0,
            isFallback: true,
          ),
        ],
);

final class EmptyPredictor implements BoundaryPredictor {
  @override
  List<int> predict(String text) => [];
}

PhraseModel model() => PhraseModel(
  levels: [
    PhraseModelLevel(name: 'empty', predictor: EmptyPredictor(), penalty: 0),
  ],
  fallbackPenalty: 1,
);

void main() {
  for (final separator in ['\u2028', '\u2029']) {
    test(
      'native hard separator U+${separator.codeUnitAt(0).toRadixString(16)} has no semantic cost',
      () {
        final text = 'aa${separator}bb';
        final native = LineBreakLayout(
          sourceText: text,
          ranges: [const TextLineRange(0, 2), const TextLineRange(3, 5)],
          widths: [2, 2],
          maxWidth: 10,
        );
        final result = selectTextWrap(
          TextWrapInput(
            text: text,
            model: model(),
            maxWidth: 10,
            nativeLayout: native,
            measureRange: (start, end) => (end - start).toDouble(),
          ),
          diagnostics: true,
        );
        expect(result.reason, 'nativeNoModelImprovement');
        expect(result.source, TextWrapSelectionSource.native);
        expect(result.lines, ['aa', 'bb']);
        expect(result.diagnostics!.nativeLayout!.totalModelCost, 0);
        expect(result.diagnostics!.nativeLayout!.selectedCandidates, isEmpty);
        expect(result.breakOffsets, isEmpty);
      },
    );
  }
  test('fitting native requires strictly lower cost and same line count', () {
    for (final calculated in [
      fixture(cost: 1),
      fixture(cost: 2),
      fixture(cost: 0, lines: 1),
      fixture(cost: 0, overflow: true),
    ]) {
      final result = const BalanceStrategy().select(
        LayoutSelectionContext(
          calculatedLayouts: [calculated],
          nativeLayout: fixture(),
        ),
      );
      expect(result.source, TextWrapSelectionSource.native);
      expect(result.reason, 'nativeNoModelImprovement');
    }
  });
  test('balance tolerance includes 0.12 but rejects a larger regression', () {
    for (final (imbalance, reason) in [
      (0.17, 'calculatedSelected'),
      (0.17001, 'nativeSelected'),
      (0.30, 'nativeSelected'),
    ]) {
      final result = const BalanceStrategy().select(
        LayoutSelectionContext(
          nativeLayout: fixture(imbalance: .05),
          calculatedLayouts: [fixture(cost: 0, imbalance: imbalance)],
        ),
      );
      expect(result.reason, reason);
    }
  });
  test(
    'overflowing native accepts fitting layout regardless of cost or count',
    () {
      final result = const BalanceStrategy().select(
        LayoutSelectionContext(
          nativeLayout: fixture(overflow: true, cost: 0),
          calculatedLayouts: [fixture(cost: 10, lines: 1)],
        ),
      );
      expect(result.reason, 'calculatedSelected');
      expect(
        const BalanceStrategy()
            .select(
              LayoutSelectionContext(
                nativeLayout: fixture(overflow: true),
                calculatedLayouts: [fixture(overflow: true)],
              ),
            )
            .reason,
        'nativeSelected',
      );
    },
  );
  test(
    'without native prioritizes fitting minimum lines then cost within tolerance',
    () {
      final result = const BalanceStrategy().select(
        LayoutSelectionContext(
          calculatedLayouts: [
            fixture(cost: 0, overflow: true),
            fixture(cost: 1),
            fixture(cost: 0, imbalance: .1),
          ],
        ),
      );
      expect(result.index, 2);
      expect(result.reason, 'calculatedSelected');
    },
  );
  test(
    'maximum lines keeps native if calculated would exceed rendering limit',
    () {
      final result = const BalanceStrategy().select(
        LayoutSelectionContext(
          nativeLayout: fixture(lines: 1, overflow: true),
          calculatedLayouts: [fixture(cost: 0)],
          maxLines: 1,
        ),
      );
      expect(result.source, TextWrapSelectionSource.native);
    },
  );
  test('invalid tolerance and empty selection throw typed errors', () {
    for (final tolerance in [-1.0, 1.1, double.nan, double.infinity]) {
      expect(
        () => BalanceStrategy(
          tolerance: tolerance,
        ).select(LayoutSelectionContext(calculatedLayouts: [fixture()])),
        throwsA(isA<TextWrapException>()),
      );
    }
    expect(
      () => const BalanceStrategy().select(
        LayoutSelectionContext(calculatedLayouts: []),
      ),
      throwsA(isA<TextWrapException>()),
    );
  });
  test(
    'one-shot preserves hard newlines and does not call them inserted breaks',
    () {
      final result = selectTextWrap(
        TextWrapInput(
          text: 'aa\nbb',
          model: model(),
          maxWidth: 10,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
      );
      expect(result.lines, ['aa', 'bb']);
      expect(result.breakOffsets, isEmpty);
      expect(result.applied, isFalse);
      expect(result.diagnostics, isNull);
      expect(() => result.lines.clear(), throwsUnsupportedError);
    },
  );
  test('custom selector reason survives and invalid index is rejected', () {
    final input = TextWrapInput(
      text: 'aa bb',
      model: model(),
      maxWidth: 2,
      measureRange: (start, end) => (end - start).toDouble(),
    );
    final result = selectTextWrap(
      input,
      strategy: LineBreakStrategy(selector: CustomSelector(0)),
    );
    expect(result.reason, 'product-rule');
    expect(result.lines, ['aa', 'bb']);
    expect(result.applied, isTrue);
    expect(
      () => selectTextWrap(
        input,
        strategy: LineBreakStrategy(selector: CustomSelector(99)),
      ),
      throwsA(isA<TextWrapException>()),
    );
  });
  test(
    'unsupported model and explicit runtime fallback have stable reasons',
    () {
      final native = fixture();
      final result = selectTextWrap(
        TextWrapInput(
          text: 'abcd',
          model: null,
          maxWidth: 100,
          nativeLayout: native,
          measureRange: (_, _) => 100,
        ),
        diagnostics: true,
      );
      expect(result.reason, 'unsupportedLanguage');
      expect(result.applied, isFalse);
      final fallback = TextWrapResult.native(
        native,
        reason: 'invalidRuntimeMeasurement',
      );
      expect(fallback.reason, 'invalidRuntimeMeasurement');
      expect(fallback.applied, isFalse);
    },
  );
  test('calculation safety limit falls back with exact limit diagnostics', () {
    final result = selectTextWrap(
      TextWrapInput(
        text: 'abcd',
        model: model(),
        maxWidth: 100,
        nativeLayout: fixture(),
        measureRange: (_, _) => 100,
      ),
      strategy: LineBreakStrategy(calculator: LimitCalculator()),
      diagnostics: true,
    );
    expect(result.reason, 'calculationLimit');
    expect(result.diagnostics!.calculationLimit!.observedCount, 4097);
    expect(result.diagnostics!.calculatedLayouts, isEmpty);
  });
  test(
    'direct invalid widths and runtime measurements remain typed failures',
    () {
      for (final width in [-1.0, double.nan, double.infinity]) {
        expect(
          () => selectTextWrap(
            TextWrapInput(
              text: 'a',
              model: model(),
              maxWidth: width,
              measureRange: (_, _) => 1,
            ),
          ),
          throwsA(isA<TextWrapException>()),
        );
        expect(
          () => selectTextWrap(
            TextWrapInput(
              text: 'a',
              model: model(),
              maxWidth: 10,
              measureRange: (_, _) => width,
            ),
          ),
          throwsA(isA<TextRangeMeasurementException>()),
        );
      }
      expect(
        () => selectTextWrap(
          TextWrapInput(
            text: 'a',
            model: model(),
            maxWidth: 1,
            maxLines: 0,
            measureRange: (_, _) => 1,
          ),
        ),
        throwsA(isA<TextWrapException>()),
      );
    },
  );
}

final class CustomSelector implements LayoutSelector {
  CustomSelector(this.index);
  final int index;
  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      LayoutSelectionDecision.calculated(index, reason: 'product-rule');
}

final class LimitCalculator implements LayoutCalculator {
  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => const LayoutCalculationLimit(
    kind: LayoutCalculationLimitKind.candidates,
    limit: 4096,
    observedCount: 4097,
  );
}
