import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

/// Forwards to [BalanceStrategy] so the engine cannot recognize the selector
/// and must run prediction, aggregation, and calculation.
final class _OpaqueBalance implements LayoutSelector {
  const _OpaqueBalance();

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const BalanceStrategy().select(context);
}

final class _CountingCalculator implements LayoutCalculator {
  _CountingCalculator(this._inner);

  final LayoutCalculator _inner;
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
    return _inner.calculate(
      text: text,
      candidates: candidates,
      maxWidth: maxWidth,
      measureRange: measureRange,
      baseline: baseline,
    );
  }
}

const _unit = 10.0;

double _measure(String text, int start, int end) =>
    text.substring(start, end).characters.length * _unit;

/// Greedy native wrapping at grapheme level, the way a paragraph without
/// semantic breaks would flow.
LineBreakLayout _native(String text, double maxWidth) {
  final ranges = <TextLineRange>[];
  final widths = <double>[];
  var start = 0;
  var offset = 0;
  var lineWidth = 0.0;
  for (final grapheme in text.characters) {
    if (lineWidth + _unit > maxWidth && offset > start) {
      ranges.add(TextLineRange(start, offset));
      widths.add(lineWidth);
      start = offset;
      lineWidth = 0;
    }
    lineWidth += _unit;
    offset += grapheme.length;
  }
  ranges.add(TextLineRange(start, offset));
  widths.add(lineWidth);
  return LineBreakLayout(
    sourceText: text,
    ranges: ranges,
    widths: widths,
    maxWidth: maxWidth,
  );
}

TextWrapResult _select(
  String text,
  PhraseModel model,
  double maxWidth,
  LineBreakStrategy strategy, {
  int? maxLines,
}) => createTextWrapPlan(text: text, model: model, strategy: strategy).select(
  maxWidth: maxWidth,
  measureRange: (start, end) => _measure(text, start, end),
  nativeLayout: _native(text, maxWidth),
  maxLines: maxLines,
  diagnostics: true,
);

List<(int, int)> _ranges(TextWrapResult result) => [
  for (final range in result.ranges) (range.start, range.end),
];

void main() {
  const phrases = [
    '확인',
    '저장하고 닫기',
    '이미 연결된 사용자를 추가하면, 연결을 해제한 뒤 현재 사용자와 연결해요.',
    'Save changes',
    'Your session has expired. Please sign in again to continue.',
    '주문 order 123 확인 completed',
  ];

  test('a fitting single line keeps the native layout without calculating', () {
    final model = TextAutoWrapModels.korean;
    for (final text in phrases) {
      final width = text.characters.length * _unit + 5;
      final result = _select(text, model, width, const LineBreakStrategy());
      expect(result.lineCount, 1);
      expect(result.applied, isFalse);
      expect(result.reason, 'nativeNoModelImprovement');
      expect(result.source, TextWrapSelectionSource.native);
      expect(result.diagnostics!.cache.calculationRuns, 0);
    }
  });

  test('shortcut and full calculation select the same layout', () {
    final models = [TextAutoWrapModels.korean, TextAutoWrapModels.english];
    for (final model in models) {
      for (final text in phrases) {
        final length = text.characters.length * _unit;
        for (final width in [
          20.0,
          60.0,
          length / 2,
          length - 1,
          length,
          length + 1,
          length * 2,
        ]) {
          for (final maxLines in [null, 1, 2]) {
            final fast = _select(
              text,
              model,
              width,
              const LineBreakStrategy(),
              maxLines: maxLines,
            );
            final slow = _select(
              text,
              model,
              width,
              const LineBreakStrategy(selector: _OpaqueBalance()),
              maxLines: maxLines,
            );
            final label = '$text @ $width maxLines=$maxLines';
            expect(fast.breakOffsets, slow.breakOffsets, reason: label);
            expect(_ranges(fast), _ranges(slow), reason: label);
            expect(fast.widths, slow.widths, reason: label);
            expect(fast.applied, slow.applied, reason: label);
            expect(fast.reason, slow.reason, reason: label);
            expect(fast.source, slow.source, reason: label);
            expect(fast.overflow, slow.overflow, reason: label);
          }
        }
      }
    }
  });

  test('wrapped or overflowing native text still goes through calculation', () {
    final model = TextAutoWrapModels.korean;
    const text = '저장하고 닫기 확인 취소';
    final length = text.characters.length * _unit;
    for (final width in [length / 2, 15.0]) {
      final calculator = _CountingCalculator(optimalLayouts());
      _select(text, model, width, LineBreakStrategy(calculator: calculator));
      expect(calculator.calls, 1, reason: '$width');
    }
  });

  test('raw BudouX predictors still validate grapheme boundaries', () {
    final raw = BudouxPredictor({
      'UW3': {'': -1},
    });
    final model = PhraseModel(
      levels: [PhraseModelLevel(name: 'raw', predictor: raw, penalty: 0)],
      fallbackPenalty: 1,
      boundaryMode: BoundaryMode.characters,
    );
    // The raw predictor proposes offset 1 inside the surrogate pair. Merely
    // fitting on one native line must not hide that invalid model output.
    expect(
      () => _select('😀', model, 100, const LineBreakStrategy()),
      throwsA(isA<InvalidBoundaryException>()),
    );
  });

  for (final throwsDirectly in [false, true]) {
    test('custom calculator errors remain visible ($throwsDirectly)', () {
      expect(
        () => _select(
          '확인',
          TextAutoWrapModels.korean,
          100,
          LineBreakStrategy(calculator: _InvalidCalculator(throwsDirectly)),
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    });
  }

  test('caller-supplied predictors keep full validation', () {
    final model = PhraseModel(
      levels: [
        PhraseModelLevel(
          name: 'custom',
          predictor: const _OutOfRangePredictor(),
          penalty: 0,
        ),
      ],
      fallbackPenalty: 1,
      boundaryMode: BoundaryMode.characters,
    );
    expect(
      () => _select('abc', model, 100, const LineBreakStrategy()),
      throwsA(isA<TextWrapException>()),
    );
  });

  test('an invalid selector tolerance is still rejected for fitting text', () {
    expect(
      () => _select(
        '확인',
        TextAutoWrapModels.korean,
        100,
        const LineBreakStrategy(selector: BalanceStrategy(tolerance: 2)),
      ),
      throwsA(isA<InvalidModelConfigurationException>()),
    );
  });
}

final class _OutOfRangePredictor implements BoundaryPredictor {
  const _OutOfRangePredictor();

  @override
  List<int> predict(String text) => [text.length + 5];
}

final class _InvalidCalculator implements LayoutCalculator {
  const _InvalidCalculator(this.throwsDirectly);
  final bool throwsDirectly;
  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    if (throwsDirectly) {
      throw const InvalidModelConfigurationException(
        'custom calculator failed',
      );
    }
    return LayoutCalculationSuccess([]);
  }
}
