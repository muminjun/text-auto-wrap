import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

BreakCandidate _candidate(int offset, double penalty) => BreakCandidate(
  offset: offset,
  penalty: penalty,
  levelName: 'test',
  consensusCount: 1,
  isFallback: false,
);

final class _Case {
  _Case(this.text, this.candidates, this.maxWidth);
  final String text;
  final List<BreakCandidate> candidates;
  final double maxWidth;
}

// Width grows with every added code unit, as for ordinary horizontal text.
double _monotonicWidth(String text, int start, int end) {
  var width = 0.0;
  for (var index = start; index < end; index++) {
    width += 4 + text.codeUnitAt(index) % 5;
  }
  return width;
}

List<_Case> _randomCases(int seed, int count) {
  final random = Random(seed);
  const penalties = [0.0, 0.35, 0.7, 1.0];
  return [
    for (var i = 0; i < count; i++)
      () {
        final words = [
          for (var w = 0; w < 2 + random.nextInt(13); w++)
            String.fromCharCodes([
              for (var c = 0; c < 1 + random.nextInt(8); c++)
                0x61 + random.nextInt(26),
            ]),
        ];
        final text = words.join(' ');
        final candidates = <BreakCandidate>[];
        var offset = 0;
        for (var w = 0; w < words.length - 1; w++) {
          offset += words[w].length + 1;
          candidates.add(
            _candidate(offset, penalties[random.nextInt(penalties.length)]),
          );
        }
        return _Case(text, candidates, 12.0 + random.nextInt(140));
      }(),
  ];
}

({List<LineBreakLayout> layouts, int measurements}) _run(
  LayoutCalculator calculator,
  _Case value,
) {
  var measurements = 0;
  final result =
      calculator.calculate(
            text: value.text,
            candidates: value.candidates,
            maxWidth: value.maxWidth,
            measureRange: (start, end) {
              measurements++;
              return _monotonicWidth(value.text, start, end);
            },
          )
          as LayoutCalculationSuccess;
  return (layouts: result.layouts, measurements: measurements);
}

void _expectSameLayouts(
  List<LineBreakLayout> actual,
  List<LineBreakLayout> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].breakOffsets, expected[i].breakOffsets);
    expect(
      [for (final r in actual[i].ranges) (r.start, r.end)],
      [for (final r in expected[i].ranges) (r.start, r.end)],
    );
    expect(actual[i].widths, expected[i].widths);
    expect(actual[i].totalModelCost, expected[i].totalModelCost);
  }
}

void main() {
  test('assumeMonotonicWidths is part of calculator equality', () {
    expect(optimalLayouts(), optimalLayouts());
    expect(
      optimalLayouts(assumeMonotonicWidths: true),
      optimalLayouts(assumeMonotonicWidths: true),
    );
    expect(
      optimalLayouts(assumeMonotonicWidths: true),
      isNot(optimalLayouts()),
    );
    expect(greedy(assumeMonotonicWidths: true), isNot(greedy()));
    expect(
      optimalLayouts(assumeMonotonicWidths: true).hashCode,
      optimalLayouts(assumeMonotonicWidths: true).hashCode,
    );
  });

  for (final (name, exact, fast) in [
    ('optimal', optimalLayouts(), optimalLayouts(assumeMonotonicWidths: true)),
    ('greedy', greedy(), greedy(assumeMonotonicWidths: true)),
  ]) {
    test('$name layouts are unchanged when widths grow with the range', () {
      var exactTotal = 0;
      var fastTotal = 0;
      for (final value in _randomCases(name.length * 31, 400)) {
        final expected = _run(exact, value);
        final actual = _run(fast, value);
        _expectSameLayouts(actual.layouts, expected.layouts);
        expect(actual.measurements, lessThanOrEqualTo(expected.measurements));
        exactTotal += expected.measurements;
        fastTotal += actual.measurements;
      }
      expect(fastTotal, lessThan(exactTotal));
    });
  }

  test('monotonic mode is bounded by the line length, not the paragraph', () {
    final text = List.filled(24, 'abc').join(' ');
    final candidates = [
      for (var i = 1; i < 24; i++) _candidate(i * 4, i.isEven ? 0.35 : 0.7),
    ];
    final value = _Case(text, candidates, 60);
    final exact = _run(optimalLayouts(), value);
    final fast = _run(optimalLayouts(assumeMonotonicWidths: true), value);
    _expectSameLayouts(fast.layouts, exact.layouts);
    expect(exact.measurements, greaterThan(250));
    expect(fast.measurements, lessThan(exact.measurements ~/ 2));
  });

  test(
    'a measurer that shrinks when a range grows is why the mode is opt-in',
    () {
      const text = 'aa bb cc';
      final candidates = [_candidate(3, 0), _candidate(6, 0)];
      // The two-word range [0, 5) is wider than the width, but the longer
      // [0, 8) is reported narrower, as with a cluster-forming script.
      double measure(int start, int end) => switch ((start, end)) {
        (0, 8) => 10,
        (0, 5) => 90,
        _ => (end - start) * 10.0,
      };
      List<int> breaks(LayoutCalculator calculator) =>
          (calculator.calculate(
                    text: text,
                    candidates: candidates,
                    maxWidth: 50,
                    measureRange: measure,
                  )
                  as LayoutCalculationSuccess)
              .layouts
              .first
              .breakOffsets;
      expect(breaks(greedy()), isEmpty);
      expect(breaks(greedy(assumeMonotonicWidths: true)), isNotEmpty);
    },
  );
}
