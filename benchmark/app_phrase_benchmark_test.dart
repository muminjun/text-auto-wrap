// Opt-in benchmark: all scales, widths, rounds, and repetitions run in one VM.
// flutter test benchmark/app_phrase_benchmark_test.dart \
//   --dart-define=TAW_BENCH=true --dart-define=TAW_REPS=5 \
//   --dart-define=TAW_ROUNDS=3 --dart-define=TAW_FONT=/path/Font.ttf
// TAW_ORACLE=true records unbounded-calculator layouts outside timed samples.
// TAW_REFERENCE=/path/log asserts against a previous TAW_ORACLE run:
// completed calculations match its exactLayout; remaining limits match layout.
// TAWROW JSON contains per-condition timing statistics and source geometry.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';

import '../test/support/app_phrase_samples.dart';
import '../test/support/app_phrase_benchmark_support.dart';

const _enabled = bool.fromEnvironment('TAW_BENCH');
const _scales = [1.0, 1.3, 1.5, 2.0];
const _rounds = int.fromEnvironment('TAW_ROUNDS', defaultValue: 3);
const _reps = int.fromEnvironment('TAW_REPS', defaultValue: 5);
const _fontPath = String.fromEnvironment('TAW_FONT');
const _widths = [120.0, 200.0, 320.0];

/// Counts calls made through the calculator and limit results. Copy of the
/// FNB app's `_AppAutoWrapLayout` (24-candidate optimal / greedy above, with
/// a 256-measurement ceiling) plus counters.
final class BenchAppCalculator implements LayoutCalculator {
  const BenchAppCalculator();
  static final _newlines = RegExp(r'\r\n|[\r\n  ]');
  static const _measurementLimit = 256;
  static bool unlimited = false;
  static int calls = 0;
  static int limits = 0;
  static int optimalRuns = 0;
  static int greedyRuns = 0;
  static int lastMeasurements = 0;

  static void reset() {
    calls = 0;
    limits = 0;
    optimalRuns = 0;
    greedyRuns = 0;
    lastMeasurements = 0;
  }

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    calls++;
    var measurements = 0;
    double measure(int start, int end) {
      if (++measurements > _measurementLimit && !unlimited) {
        throw const _Limit();
      }
      return measureRange(start, end);
    }

    try {
      if (candidates.length <= 24) {
        optimalRuns++;
        final result = optimalLayouts().calculate(
          text: text,
          candidates: candidates,
          maxWidth: maxWidth,
          measureRange: measure,
          baseline: baseline,
        );
        lastMeasurements = measurements;
        return result;
      }
      greedyRuns++;
      final selected = <BreakCandidate>[];
      var paragraphStart = 0;
      var candidateIndex = 0;
      for (final paragraphEnd in [
        ..._newlines.allMatches(text).map((match) => (match.start, match.end)),
        (text.length, text.length),
      ]) {
        final boundaries = <BreakCandidate>[];
        while (candidateIndex < candidates.length &&
            candidates[candidateIndex].offset < paragraphEnd.$1) {
          final candidate = candidates[candidateIndex++];
          if (candidate.offset > paragraphStart) boundaries.add(candidate);
        }
        var start = paragraphStart;
        var index = 0;
        while (start < paragraphEnd.$1) {
          BreakCandidate? fitting;
          int? overflowOffset;
          while (index < boundaries.length) {
            final candidate = boundaries[index++];
            if (candidate.offset <= start || candidate.isFallback) continue;
            final end =
                start +
                text.substring(start, candidate.offset).trimRight().length;
            if (end <= start) continue;
            if (measure(start, end) > maxWidth) {
              overflowOffset = candidate.offset;
              index--;
              break;
            }
            fitting = candidate;
          }
          if (overflowOffset == null &&
              measure(start, paragraphEnd.$1) <= maxWidth) {
            break;
          }
          if (fitting == null) {
            for (final candidate in boundaries) {
              if (candidate.offset <= start) continue;
              if (candidate.offset > (overflowOffset ?? paragraphEnd.$1)) break;
              final end =
                  start +
                  text.substring(start, candidate.offset).trimRight().length;
              if (end <= start) continue;
              if (measure(start, end) > maxWidth) break;
              fitting = candidate;
            }
          }
          if (fitting == null) break;
          selected.add(fitting);
          final remainder = text.substring(fitting.offset, paragraphEnd.$1);
          start =
              fitting.offset + remainder.length - remainder.trimLeft().length;
          while (index < boundaries.length &&
              boundaries[index].offset <= start) {
            index++;
          }
        }
        paragraphStart = paragraphEnd.$2;
      }
      final result = LayoutCalculationSuccess([
        LineBreakLayoutCandidate(
          sourceText: text,
          selectedCandidates: selected,
        ).measure(maxWidth: maxWidth, measureRange: measure),
      ]);
      lastMeasurements = measurements;
      return result;
    } on _Limit {
      limits++;
      lastMeasurements = _measurementLimit + 1;
      return const LayoutCalculationLimit(
        kind: LayoutCalculationLimitKind.states,
        limit: _measurementLimit,
        observedCount: _measurementLimit + 1,
      );
    }
  }
}

class _Limit implements Exception {
  const _Limit();
}

const _strategy = LineBreakStrategy(calculator: BenchAppCalculator());

const _style = TextStyle(
  fontFamily: 'Pretendard-Variable',
  fontSize: 14,
  height: 1.5,
  letterSpacing: -0.2,
  color: Color(0xff000000),
);

Widget _host(double width, Widget child, {Key? key}) => Directionality(
  key: key,
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: child),
  ),
);

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

Map<String, Object?> _stats(List<double> micros) {
  if (micros.isEmpty) return {'n': 0};
  final mean = micros.reduce((a, b) => a + b) / micros.length;
  final variance =
      micros.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      micros.length;
  final sorted = [...micros]..sort();
  return {
    'n': micros.length,
    'medianUs': _median(micros).round(),
    'meanUs': mean.round(),
    'stdUs': variance <= 0 ? 0 : math.sqrt(variance).round(),
    'minUs': sorted.first.round(),
    'p90Us': sorted[((sorted.length - 1) * .9).round()].round(),
  };
}

void _clearCaches() {
  // Each cold sample intentionally clears package caches before timing starts.
  // ignore: invalid_use_of_visible_for_testing_member
  RenderTextAutoWrap.clearSharedCaches();
}

void main() {
  testWidgets(
    'app phrase benchmark',
    (tester) async {
      validateBenchmarkConfiguration(repetitions: _reps, rounds: _rounds);
      if (_fontPath.isNotEmpty) {
        await tester.runAsync(() async {
          final loader = FontLoader('Pretendard-Variable')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(_fontPath).readAsBytes()),
              ),
            );
          await loader.load();
        });
      }
      var seed = 0;
      var scale = 1.0;
      TextAutoWrap wrap(String text, TextAutoWrapController controller) =>
          TextAutoWrap(
            text,
            style: _style,
            textScaler: TextScaler.linear(scale),
            strategy: _strategy,
            controller: controller,
          );
      Future<double> pump(
        String text,
        double width,
        TextAutoWrapController c,
        Key key,
      ) async {
        final watch = Stopwatch()..start();
        await tester.pumpWidget(_host(width, wrap(text, c), key: key));
        watch.stop();
        expect(tester.takeException(), isNull);
        expect(c.failures, isEmpty);
        expect(c.result, isNotNull);
        return watch.elapsedMicroseconds.toDouble();
      }

      Map<String, Object?> snapshot(TextAutoWrapController c) {
        final r = c.result!;
        return {
          'breaks': r.breakOffsets,
          'lines': r.lines,
          'widths': r.widths,
          'ranges': [
            for (final range in r.ranges) [range.start, range.end],
          ],
          'applied': r.applied,
          'overflow': r.overflow,
        };
      }

      final referencePath = const String.fromEnvironment('TAW_REFERENCE');
      final expectedIds = <String>{
        for (final entry in appPhraseSamples.entries)
          for (var index = 0; index < entry.value.length; index++)
            for (final scale in _scales)
              for (final width in _widths) '${entry.key}:$index:$scale:$width',
      };
      final references = referencePath.isEmpty
          ? <String, Object?>{}
          : parseBenchmarkReferences(
              File(referencePath).readAsLinesSync(),
              expectedIds,
            );
      for (var pass = 0; pass < 2; pass++) {
        for (final phrases in appPhraseSamples.values) {
          for (final text in phrases) {
            final c = TextAutoWrapController();
            await pump('$text 워밍업$pass', 200, c, ValueKey(seed++));
            c.dispose();
          }
        }
      }
      for (var round = 0; round < _rounds; round++) {
        for (final textScale in _scales) {
          scale = textScale;
          for (final entry in appPhraseSamples.entries) {
            for (
              var phraseIndex = 0;
              phraseIndex < entry.value.length;
              phraseIndex++
            ) {
              final text = entry.value[phraseIndex];
              for (final width in _widths) {
                final cold = <double>[],
                    recreate = <double>[],
                    resize = <double>[],
                    newWidth = <double>[];
                Map<String, Object?>? layout;
                var limited = false;
                var measurements = 0, requests = 0, limits = 0;
                for (var rep = 0; rep < _reps; rep++) {
                  _clearCaches();
                  final c = TextAutoWrapController();
                  final key = ValueKey(seed++);
                  BenchAppCalculator.reset();
                  cold.add(await pump(text, width, c, key));
                  final current = snapshot(c);
                  limited = c.result!.reason == 'calculationLimit';
                  layout ??= current;
                  expect(current, layout);
                  measurements += c.result!.diagnostics!.cache.measurementRuns;
                  requests += BenchAppCalculator.lastMeasurements;
                  limits += BenchAppCalculator.limits;
                  c.dispose();
                  final warm = TextAutoWrapController();
                  final warmKey = ValueKey(seed++);
                  recreate.add(await pump(text, width, warm, warmKey));
                  expect(snapshot(warm), layout);
                  newWidth.add(await pump(text, width + 40, warm, warmKey));
                  resize.add(await pump(text, width, warm, warmKey));
                  expect(snapshot(warm), layout);
                  warm.dispose();
                }
                final id = '${entry.key}:$phraseIndex:$scale:$width';
                Map<String, Object?>? exactLayout;
                if (const bool.fromEnvironment('TAW_ORACLE')) {
                  _clearCaches();
                  BenchAppCalculator.unlimited = true;
                  final c = TextAutoWrapController();
                  try {
                    await pump(text, width, c, ValueKey(seed++));
                    exactLayout = snapshot(c);
                  } finally {
                    c.dispose();
                    BenchAppCalculator.unlimited = false;
                  }
                }
                if (references.isNotEmpty) {
                  final reference = references[id] as Map<String, dynamic>;
                  expect(
                    layout,
                    limited ? reference['layout'] : reference['exactLayout'],
                    reason: id,
                  );
                }
                // ignore: avoid_print
                print(
                  'TAWROW ${jsonEncode({'id': id, 'round': round, 'class': entry.key, 'scale': scale, 'width': width, 'layout': layout, 'exactLayout': exactLayout, 'cold': _stats(cold), 'recreate': _stats(recreate), 'newWidth': _stats(newWidth), 'resizeBack': _stats(resize), 'measureRuns': measurements / _reps, 'calcMeasurements': requests / _reps, 'limits': limits, 'reps': _reps})}',
                );
              }
            }
          }
        }
      }
    },
    skip: !_enabled,
    timeout: Timeout.none,
  );
}
