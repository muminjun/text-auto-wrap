import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/measure.dart';

BreakCandidate candidate(int offset, [double penalty = 0]) => BreakCandidate(
  offset: offset,
  penalty: penalty,
  levelName: 'test',
  consensusCount: 1,
  isFallback: false,
);

List<LineBreakLayout> calculate(
  String text,
  List<BreakCandidate> candidates,
  double maxWidth, {
  LayoutCalculator? calculator,
  TextRangeMeasurer? measureRange,
  LineBreakLayout? baseline,
}) =>
    ((calculator ?? optimalLayouts()).calculate(
              text: text,
              candidates: candidates,
              maxWidth: maxWidth,
              measureRange: measureRange ?? FixedRangeMeasurer(text).call,
              baseline: baseline,
            )
            as LayoutCalculationSuccess)
        .layouts;

void main() {
  test(
    'native measured ranges derive metrics and freeze caller-owned lists',
    () {
      final ranges = [const TextLineRange(0, 2), const TextLineRange(2, 4)];
      final widths = [15.0, 30.0];
      final layout = LineBreakLayout(
        sourceText: 'abcd',
        ranges: ranges,
        widths: widths,
        maxWidth: 20,
        selectedCandidates: [candidate(2, 3)],
      );
      ranges.clear();
      widths.clear();
      expect(layout.lines, ['ab', 'cd']);
      expect(layout.widths, [15.0, 30.0]);
      expect(layout.lineCount, 2);
      expect(layout.maxLineWidth, 30);
      expect(layout.imbalance, .5);
      expect(layout.totalModelCost, 3);
      expect(layout.overflow, isTrue);
    },
  );

  test('native measured ranges reject inconsistent or invalid inputs', () {
    for (final ranges in [
      [const TextLineRange(-1, 2)],
      [const TextLineRange(2, 1)],
      [const TextLineRange(0, 5)],
      [const TextLineRange(0, 2), const TextLineRange(1, 4)],
    ]) {
      expect(
        () => LineBreakLayout(
          sourceText: 'abcd',
          ranges: ranges,
          widths: List.filled(ranges.length, 10),
          maxWidth: 20,
        ),
        throwsA(isA<InvalidBoundaryException>()),
      );
    }
    expect(
      () => LineBreakLayout(
        sourceText: '😀z',
        ranges: [const TextLineRange(0, 1)],
        widths: [10],
        maxWidth: 20,
      ),
      throwsA(isA<InvalidBoundaryException>()),
    );
    expect(
      () => LineBreakLayout(
        sourceText: 'a',
        ranges: [],
        widths: [],
        maxWidth: 20,
      ),
      throwsA(isA<InvalidModelConfigurationException>()),
    );
    expect(
      () => LineBreakLayout(
        sourceText: 'a',
        ranges: [const TextLineRange(0, 1)],
        widths: [],
        maxWidth: 20,
      ),
      throwsA(isA<InvalidModelConfigurationException>()),
    );
    expect(
      () => LineBreakLayout(
        sourceText: 'a',
        ranges: [const TextLineRange(0, 1)],
        widths: [double.nan],
        maxWidth: 20,
      ),
      throwsA(isA<TextRangeMeasurementException>()),
    );
  });

  test('boundary trimming never removes part of a whitespace grapheme', () {
    const text = 'a \u0301b';
    final layout = calculate(text, [candidate(1)], 20).single;
    expect(layout.lines, ['a', ' \u0301b']);
    expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 1), (1, 4)]);
  });

  test(
    'preserves prefixes whose balance improves after a wider final line',
    () {
      final widths = <(int, int), double>{
        (0, 1): 1,
        (1, 3): 1,
        (0, 2): 5,
        (2, 3): 5,
        (3, 4): 10,
      };
      final layout = calculate(
        'abcd',
        [candidate(1), candidate(2), candidate(3)],
        10,
        measureRange: (start, end) => widths[(start, end)] ?? 100,
      ).single;
      expect(layout.breakOffsets, [2, 3]);
      expect(layout.widths, [5.0, 5.0, 10.0]);
      expect(layout.imbalance, .5);
    },
  );

  test('accepts exactly the candidate ceiling when the paragraph fits', () {
    final text = 'a' * 4097;
    final result = optimalLayouts().calculate(
      text: text,
      candidates: List.generate(4096, (i) => candidate(i + 1)),
      maxWidth: 4097,
      measureRange: (start, end) => (end - start).toDouble(),
    );
    expect(result, isA<LayoutCalculationSuccess>());
    expect((result as LayoutCalculationSuccess).layouts.single.lineCount, 1);
  });

  test('nearby work ceiling includes every emitted line across paragraphs', () {
    final text = '${'a' * 102}${'\nb' * 180}';
    final baseline =
        LineBreakLayoutCandidate(
          sourceText: text,
          selectedCandidates: [candidate(51)],
        ).measure(
          maxWidth: 1000,
          measureRange: (start, end) => (end - start).toDouble(),
        );
    final result = nearbyLayouts(radius: 100).calculate(
      text: text,
      candidates: List.generate(101, (i) => candidate(i + 1)),
      maxWidth: 1000,
      measureRange: (start, end) => (end - start).toDouble(),
      baseline: baseline,
    );
    expect(result, isA<LayoutCalculationLimit>());
  });

  test('exact fits trim selected boundary spaces and keep source offsets', () {
    const text = 'abcd efg';
    final measure = FixedRangeMeasurer(text);
    final layout = calculate(
      text,
      [candidate(5, 2)],
      40,
      measureRange: measure.call,
    ).single;
    expect(layout.sourceText, text);
    expect(layout.lines, ['abcd', 'efg']);
    expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 4), (5, 8)]);
    expect(layout.breakOffsets, [5]);
    expect(layout.widths, [40.0, 30.0]);
    expect(layout.overflow, isFalse);
    expect(layout.lineCount, 2);
    expect(layout.maxLineWidth, 40);
    expect(layout.imbalance, .25);
    expect(layout.totalModelCost, 2);
  });

  test('preserves outer whitespace and whitespace at unused boundaries', () {
    final layout = calculate(' a b ', [candidate(3)], 50).single;
    expect(layout.lines, [' a b ']);
    expect(layout.widths, [50.0]);
    expect(layout.breakOffsets, isEmpty);
  });

  test('trims only whitespace adjoining a selected character boundary', () {
    final layout = calculate('aa  bb', [candidate(2)], 20).single;
    expect(layout.lines, ['aa', 'bb']);
    expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 2), (4, 6)]);
  });

  test(
    'measures whole graphemes and placeholders in half-open UTF-16 ranges',
    () {
      const text = '👩‍💻e\u0301\uFFFCz';
      final measure = FixedRangeMeasurer(text, placeholderWidth: 25);
      final layout = calculate(
        text,
        [candidate(7)],
        35,
        measureRange: measure.call,
      ).single;
      expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 7), (7, 9)]);
      expect(layout.widths, [20.0, 35.0]);
    },
  );

  test('reports indivisible content overflow without inventing breaks', () {
    final layout = calculate('abcdef', [], 20).single;
    expect(layout.lines, ['abcdef']);
    expect(layout.overflow, isTrue);
  });

  test('prefers fewer lines even when extra breaks have lower cost', () {
    final layouts = calculate('abcdefgh', [
      candidate(2),
      candidate(4, 10),
      candidate(6),
    ], 40);
    expect(layouts.single.breakOffsets, [4]);
    expect(layouts.single.totalModelCost, 10);
  });

  test('removes layouts dominated in both model cost and balance', () {
    final layouts = calculate('abcdefgh', [
      candidate(3, 2),
      candidate(4, 1),
      candidate(5, 3),
    ], 50);
    expect(layouts.single.breakOffsets, [4]);
    expect(layouts.single.imbalance, 0);
  });

  test('retains the tradeoff between model cost and visual imbalance', () {
    final layouts = calculate('abcdefgh', [candidate(3), candidate(4, 2)], 50);
    expect(layouts.map((l) => l.breakOffsets), [
      [3],
      [4],
    ]);
    expect(layouts.map((l) => l.imbalance), [.4, 0]);
  });

  test('empty text is one empty measured line with zero imbalance', () {
    final layout = calculate('', [], 0).single;
    expect(layout.lines, ['']);
    expect(layout.ranges.map((r) => (r.start, r.end)), [(0, 0)]);
    expect(layout.widths, [0.0]);
    expect(layout.imbalance, 0);
    expect(layout.overflow, isFalse);
  });

  test('hard LF CRLF and trailing newlines preserve empty paragraphs', () {
    const text = 'ab cd\n\r\nef\n';
    final measure = FixedRangeMeasurer(text);
    final layout = calculate(
      text,
      [candidate(3), candidate(6), candidate(8)],
      20,
      measureRange: measure.call,
    ).single;
    expect(layout.lines, ['ab', 'cd', '', 'ef', '']);
    expect(layout.ranges.map((r) => (r.start, r.end)), [
      (0, 2),
      (3, 5),
      (6, 6),
      (8, 10),
      (11, 11),
    ]);
    expect(layout.breakOffsets, [3]);
    expect(
      measure.calls.every(
        (r) => !text.substring(r.$1, r.$2).contains(RegExp('[\r\n]')),
      ),
      isTrue,
    );
  });

  test('greedy chooses the furthest fitting candidate', () {
    final layout = calculate(
      'abcdefg',
      [candidate(2), candidate(3), candidate(4)],
      40,
      calculator: greedy(),
    ).single;
    expect(layout.breakOffsets, [4]);
    expect(layout.widths, [40.0, 30.0]);
  });

  test('range widths need not grow monotonically with the end offset', () {
    for (final calculator in [optimalLayouts(), greedy()]) {
      final layout = calculate(
        'abcd',
        [candidate(1), candidate(2)],
        40,
        calculator: calculator,
        measureRange: (start, end) => start == 0 && end == 1 ? 100 : 20,
      ).single;
      expect(layout.lines, ['abcd']);
      expect(layout.overflow, isFalse);
    }
  });

  test(
    'nearby layouts enumerate candidate-index neighbors around a baseline',
    () {
      final candidates = [
        candidate(2),
        candidate(3),
        candidate(4),
        candidate(5),
      ];
      final baseline = calculate(
        'abcdefgh',
        candidates,
        40,
        calculator: greedy(),
      ).single;
      final layouts = calculate(
        'abcdefgh',
        candidates,
        60,
        calculator: nearbyLayouts(radius: 1),
        baseline: baseline,
      );
      expect(layouts.map((l) => l.breakOffsets), [
        [3],
        [4],
        [5],
      ]);
    },
  );

  test('nearby radius zero retains only the baseline and can derive it', () {
    final layouts = calculate(
      'abcdefg',
      [candidate(3), candidate(4)],
      40,
      calculator: nearbyLayouts(radius: 0),
    );
    expect(layouts.single.breakOffsets, [4]);
    expect(
      () => nearbyLayouts(radius: -1),
      throwsA(isA<InvalidModelConfigurationException>()),
    );
  });

  test('freezes all layout and candidate result collections', () {
    final input = [candidate(3)];
    final unmeasured = LineBreakLayoutCandidate(
      sourceText: 'ab cd',
      selectedCandidates: input,
    );
    input.clear();
    final layout = unmeasured.measure(
      maxWidth: 20,
      measureRange: FixedRangeMeasurer('ab cd').call,
    );
    expect(layout.lines, ['ab', 'cd']);
    expect(() => unmeasured.selectedCandidates.clear(), throwsUnsupportedError);
    expect(() => layout.ranges.clear(), throwsUnsupportedError);
    expect(() => layout.lines.clear(), throwsUnsupportedError);
    expect(() => layout.widths.clear(), throwsUnsupportedError);
    expect(() => layout.breakOffsets.clear(), throwsUnsupportedError);
    expect(() => layout.selectedCandidates.clear(), throwsUnsupportedError);
    expect(() => calculate('a', [], 10).clear(), throwsUnsupportedError);
  });

  test('rejects negative or non-finite range widths with typed errors', () {
    for (final width in [-1.0, double.nan, double.infinity]) {
      expect(
        () => calculate('a', [], 10, measureRange: (_, _) => width),
        throwsA(isA<TextRangeMeasurementException>()),
      );
    }
  });

  test('rejects invalid available widths and candidate penalties', () {
    for (final width in [-1.0, double.nan, double.infinity]) {
      expect(
        () => calculate('ab', [], width),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
      expect(
        () => calculate('ab', [candidate(1, width)], 20),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    }
  });

  test(
    'rejects unordered, duplicate, exterior or split-grapheme candidates',
    () {
      for (final offsets in [
        [2, 1],
        [1, 1],
        [0],
        [3],
        [4],
      ]) {
        expect(
          () => calculate('abc', offsets.map(candidate).toList(), 20),
          throwsA(isA<InvalidBoundaryException>()),
        );
      }
      expect(
        () => calculate('😀z', [candidate(1)], 20),
        throwsA(isA<InvalidBoundaryException>()),
      );
    },
  );

  test(
    'candidate ceiling returns a typed fallback without any measurement',
    () {
      final text = 'a' * 4098;
      final measure = FixedRangeMeasurer(text);
      for (final calculator in [optimalLayouts(), greedy(), nearbyLayouts()]) {
        final result = calculator.calculate(
          text: text,
          candidates: List.generate(4097, (i) => candidate(i + 1)),
          maxWidth: 20,
          measureRange: measure.call,
        );
        expect(result, isA<LayoutCalculationLimit>());
        final limit = result as LayoutCalculationLimit;
        expect(limit.kind, LayoutCalculationLimitKind.candidates);
        expect(limit.limit, 4096);
        expect(limit.observedCount, 4097);
      }
      expect(measure.calls, isEmpty);
    },
  );

  test('state ceiling returns a typed outcome instead of partial layouts', () {
    const length = 220;
    final text = 'a' * length;
    final result = optimalLayouts().calculate(
      text: text,
      candidates: List.generate(length - 1, (i) => candidate(i + 1)),
      maxWidth: 30,
      measureRange: (start, end) => (end - start) * 10.0,
    );
    expect(result, isA<LayoutCalculationLimit>());
    final limit = result as LayoutCalculationLimit;
    expect(limit.kind, LayoutCalculationLimitKind.states);
    expect(limit.limit, 16384);
    expect(limit.observedCount, 16385);
  });
}
