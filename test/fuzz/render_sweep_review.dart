// Opt-in; not part of the default suite (name does not end in _test.dart).
// flutter test test/fuzz/render_sweep_review.dart --dart-define=TAW_BUDGET_SECONDS=60
// Investigation harness for the S9 (InvalidBoundaryException) crash.
//
// Sweeps text x scale x width x letterSpacing x softWrap x maxLines through the
// real widget and records every exception that escapes layout. It uses only
// public API so the same file runs against 0.1.1 and 0.1.2+ trees.
//
// Bounded by a wall-clock budget (TAW_BUDGET_SECONDS, default 80).
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import 'fuzz_corpus.dart';

const _scales = [1.0, 1.3, 1.5, 1.94, 2.0, 3.0];
const _spacings = <double?>[null, -0.2, -1.0, 0.5];
const _fontSize = 10.0;

List<double> _widths(double scale) {
  final glyph = _fontSize * scale;
  return [
    0,
    1e-9,
    0.01,
    glyph - 0.01,
    glyph,
    glyph + 0.01,
    glyph * 2 - 0.01,
    glyph * 2,
    glyph * 2 + 0.01,
    glyph * 5,
    glyph * 13.5,
    300,
    double.infinity,
  ];
}

Widget _host(
  String text,
  double width,
  double scale,
  double? spacing,
  bool softWrap,
  int? maxLines,
  TextOverflow overflow,
) {
  final style = TextStyle(
    fontSize: _fontSize,
    letterSpacing: spacing,
    color: const Color(0xFF000000),
  );
  final child = TextAutoWrap(
    text,
    style: style,
    softWrap: softWrap,
    maxLines: maxLines,
    overflow: overflow,
    textScaler: TextScaler.linear(scale),
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: width.isInfinite
          ? OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              alignment: Alignment.topLeft,
              child: child,
            )
          : SizedBox(width: width, child: child),
    ),
  );
}

String _topFrames(StackTrace? stack) => (stack?.toString() ?? '')
    .split('\n')
    .where((l) => l.contains('text_auto_wrap'))
    .take(3)
    .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
    .join(' <- ');

String _units(String text) =>
    text.codeUnits.map((u) => '0x${u.toRadixString(16)}').join(',');

void main() {
  testWidgets('render sweep: no exception escapes layout', (tester) async {
    const budgetSeconds = int.fromEnvironment(
      'TAW_BUDGET_SECONDS',
      defaultValue: 80,
    );
    final watch = Stopwatch()..start();
    final caught = <Object>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => caught.add(
      '${details.exception.runtimeType}: ${details.exception}'
      ' @ ${_topFrames(details.stack)}',
    );
    addTearDown(() => FlutterError.onError = previousOnError);
    final corpus = buildCorpus();
    final random = Random(0x1234);
    var cases = 0;
    var thrown = 0;
    final byMessage = <String, List<String>>{};
    final byWidthClass = <String, int>{};

    void record(Object error, String replay, double width, bool softWrap) {
      thrown++;
      final key = error.toString().split('\n').first;
      (byMessage[key] ??= []).add(replay);
      final cls =
          '${width <= 0
              ? 'width<=0'
              : width.isInfinite
              ? 'unbounded'
              : 'bounded'}/softWrap=$softWrap';
      byWidthClass[cls] = (byWidthClass[cls] ?? 0) + 1;
    }

    final failureReasons = <String, int>{};
    var withFailures = 0;
    var round = 0;
    outer:
    while (watch.elapsed.inSeconds < budgetSeconds) {
      final shuffled = [...corpus]..shuffle(random);
      for (final text in shuffled) {
        if (watch.elapsed.inSeconds >= budgetSeconds) break outer;
        final scale = _scales[random.nextInt(_scales.length)];
        final widths = _widths(scale);
        final width = widths[random.nextInt(widths.length)];
        final spacing = _spacings[random.nextInt(_spacings.length)];
        final softWrap = random.nextInt(5) != 0;
        final maxLines = const [null, null, 1, 2][random.nextInt(4)];
        final overflow = random.nextBool()
            ? TextOverflow.clip
            : TextOverflow.ellipsis;
        await tester.pumpWidget(
          _host(text, width, scale, spacing, softWrap, maxLines, overflow),
        );
        cases++;
        tester.takeException();
        final renderers = tester.allRenderObjects
            .whereType<RenderTextAutoWrap>()
            .toSet();
        if (renderers.length == 1) {
          final failures = renderers.single.failures;
          if (failures.isNotEmpty) withFailures++;
          for (final failure in failures) {
            final key = '${failure.stage}/${failure.reason}';
            failureReasons[key] = (failureReasons[key] ?? 0) + 1;
          }
        } else if (caught.isEmpty) {
          caught.add('Expected one renderer, found ${renderers.length}');
        }
        final error = caught.isEmpty ? null : caught.first;
        caught.clear();
        if (error != null) {
          record(
            error,
            'UTF-16=[${_units(text)}] scale=$scale width=$width '
            'spacing=$spacing softWrap=$softWrap maxLines=$maxLines '
            'overflow=$overflow',
            width,
            softWrap,
          );
        }
      }
      round++;
    }
    // ignore: avoid_print
    print(
      'SWEEP cases=$cases rounds=$round exceptions=$thrown '
      'elapsed=${watch.elapsed.inSeconds}s',
    );
    print(
      '  layouts with failure records: $withFailures',
    ); // ignore: avoid_print
    failureReasons.forEach(
      (k, v) => print('    $k -> $v'),
    ); // ignore: avoid_print
    byWidthClass.forEach(
      (k, v) => print('  class $k -> $v'),
    ); // ignore: avoid_print
    byMessage.forEach((message, replays) {
      print('  [${replays.length}x] $message'); // ignore: avoid_print
      for (final replay in replays.take(3)) {
        print('      $replay'); // ignore: avoid_print
      }
    });
    expect(thrown, 0);
  }, timeout: const Timeout(Duration(seconds: 110)));
}
