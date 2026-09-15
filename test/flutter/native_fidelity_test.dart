import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final offset in [2, 3]) {
    for (final rich in [false, true]) {
      testWidgets(
        'I1 offset $offset rich=$rich agrees with painted whitespace',
        (tester) async {
          final recognizer = TapGestureRecognizer();
          addTearDown(recognizer.dispose);
          final leaf = TextSpan(
            text: ' bb',
            recognizer: recognizer,
            semanticsLabel: 'space and two letters',
            semanticsIdentifier: 'tail',
            locale: const Locale('en'),
            spellOut: true,
          );
          final source = TextSpan(
            text: 'aa',
            children: [
              TextSpan(text: ' ', children: [leaf]),
            ],
          );
          await tester.pumpWidget(
            wrapHost(
              rich
                  ? TextAutoWrap.rich(source, model: offsetModel([offset]))
                  : TextAutoWrap('aa  bb', model: offsetModel([offset])),
              width: 20,
            ),
          );
          final render = wrapRender(tester);
          final result = render.result!;
          expect(_widths(render), result.widths);
          expect(result.lineCount, 2);
          expect(result.widths, [20, 20]);
          expect(result.ranges.map((range) => (range.start, range.end)), [
            (0, 4),
            (4, 6),
          ]);
          expect(result.lines, ['aa  ', 'bb']);
          // Rejected transformations must retain all whitespace and metadata.
          if (!result.applied) {
            expect(render.effectiveText, same(render.sourceText));
            if (rich) {
              final root = render.effectiveText as TextSpan;
              expect(root.children!.single, same(source));
            }
          }
        },
      );
    }
  }

  for (final width in [20.0, 60.0]) {
    for (final rich in [false, true]) {
      testWidgets(
        'I1 run-end width=$width rich=$rich checks ranges when widths agree',
        (tester) async {
          final recognizer = TapGestureRecognizer();
          addTearDown(recognizer.dispose);
          final source = TextSpan(
            children: [
              TextSpan(
                children: [
                  TextSpan(
                    text: 'aa  bb',
                    recognizer: recognizer,
                    semanticsLabel: 'two words',
                    locale: const Locale('en'),
                    spellOut: true,
                  ),
                ],
              ),
            ],
          );
          await tester.pumpWidget(
            wrapHost(
              rich
                  ? TextAutoWrap.rich(
                      source,
                      model: offsetModel([4]),
                      strategy: offsetStrategy([4]),
                    )
                  : TextAutoWrap(
                      'aa  bb',
                      model: offsetModel([4]),
                      strategy: offsetStrategy([4]),
                    ),
              width: width,
            ),
          );
          final render = wrapRender(tester);
          final result = render.result!;
          // These already agree before the fix; geometry alone misses the defect.
          expect(_widths(render), result.widths);
          expect(result.lineCount, _widths(render).length);
          final effective = render.effectiveText.toPlainText(
            includeSemanticsLabels: false,
          );
          final actualLines = effective.contains('\n')
              ? effective.split('\n')
              : width == 20
              ? ['aa  ', 'bb']
              : ['aa  bb'];
          expect(result.lines, actualLines);
          expect(
            result.ranges.map((range) => (range.start, range.end)),
            width == 20 ? [(0, 4), (4, 6)] : [(0, 6)],
          );
          expect(result.widths, width == 20 ? [20, 20] : [60]);
          expect(result.applied, isFalse);
          expect(result.reason, 'invalidRuntimeMeasurement');
          expect(result.source, TextWrapSelectionSource.native);
          expect(
            result.diagnostics!.selection.source,
            TextWrapSelectionSource.native,
          );
          expect(
            result.diagnostics!.selection.reason,
            'invalidRuntimeMeasurement',
          );
          expect(result.diagnostics!.calculatedLayouts.single.lines, [
            'aa',
            'bb',
          ]);
          expect(render.effectiveText, same(render.sourceText));
          if (rich) {
            expect(
              (render.effectiveText as TextSpan).children!.single,
              same(source),
            );
          }
        },
      );
    }
  }

  testWidgets('I2 intrinsic parent uses updated text and style', (
    tester,
  ) async {
    Widget frame(String text, double fontSize) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: IntrinsicWidth(
          child: TextAutoWrap(text, style: TextStyle(fontSize: fontSize)),
        ),
      ),
    );
    await tester.pumpWidget(frame('ab', 10));
    final render = wrapRender(tester);
    expect(render.size, const Size(20, 10));
    await tester.pumpWidget(frame('abcdefghij', 10));
    expect(wrapRender(tester), same(render));
    expect(render.size, const Size(100, 10));
    await tester.pumpWidget(frame('abcdefghij', 20));
    expect(render.size, const Size(200, 20));
  });

  testWidgets('I2 dry and intrinsic measurements restore updated rich source', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          const TextSpan(text: 'abcd'),
          model: offsetModel([2]),
          strategy: offsetStrategy([2]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.effectiveText.toPlainText(), contains('\n'));
    render.sourceText = const TextSpan(
      style: TextStyle(fontSize: 20),
      text: 'abcdefghij',
    );
    expect(render.getMaxIntrinsicWidth(double.infinity), 200);
    expect(
      render.getDryLayout(const BoxConstraints(maxWidth: 200)),
      const Size(200, 20),
    );
    expect(render.getMinIntrinsicHeight(200), 20);
  });

  testWidgets('I2 intrinsic parent uses a style-only update', (tester) async {
    Widget frame(double fontSize) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: IntrinsicWidth(
          child: TextAutoWrap('ab', style: TextStyle(fontSize: fontSize)),
        ),
      ),
    );
    await tester.pumpWidget(frame(10));
    final render = wrapRender(tester);
    await tester.pumpWidget(frame(20));
    expect(wrapRender(tester), same(render));
    expect(render.size, const Size(40, 20));
  });

  for (final (name, width, softWrap) in [
    ('softWrap disabled', 15.0, false),
    ('zero width', 0.0, true),
    ('unbounded width', double.infinity, true),
  ]) {
    testWidgets('I3 $name publishes native hard newline geometry', (
      tester,
    ) async {
      final source = width == 0 ? 'a\nb' : 'a\n\nb\n';
      final child = TextAutoWrap(source, softWrap: softWrap);
      await tester.pumpWidget(
        width.isInfinite
            ? wrapHost(UnconstrainedBox(child: child))
            : wrapHost(child, width: width),
      );
      final render = wrapRender(tester);
      expect(render.result!.widths, _widths(render));
      expect(
        render.result!.lines,
        width == 0 ? ['a', 'b'] : ['a', '', 'b', ''],
      );
      expect(render.result!.widths, width == 0 ? [10, 10] : [10, 0, 10, 0]);
      expect(render.result!.overflow, width == 0);
      expect(
        render.result!.reason,
        softWrap ? 'unusableWidth' : 'softWrapDisabled',
      );
    });
  }

  testWidgets('I3 early placeholder fallback retains native measured widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapHost(
        const TextAutoWrap.rich(
          TextSpan(
            text: 'ab',
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: SizedBox(width: 20, height: 18),
              ),
              TextSpan(text: '\ncd'),
            ],
          ),
        ),
      ),
    );
    final result = wrapRender(tester).result!;
    expect(result.reason, 'unmeasurablePlaceholder');
    expect(result.lines, ['ab\uFFFC', 'cd']);
    expect(result.widths, [40, 20]);
    expect(result.overflow, isFalse);
  });

  for (final (name, arguments, expectedWidth, expectedHeight) in [
    (
      'height',
      <Symbol, dynamic>{#lineHeightScaleFactorOverride: 3.0},
      30.0,
      60.0,
    ),
    ('letters', <Symbol, dynamic>{#letterSpacingOverride: 2.0}, 36.0, 20.0),
    ('words', <Symbol, dynamic>{#wordSpacingOverride: 4.0}, 34.0, 20.0),
  ]) {
    final data = _spacingData(arguments);
    for (final rich in [false, true]) {
      testWidgets('I4 ambient $name rich=$rich matches native and updates', (
        tester,
      ) async {
        const source = TextSpan(
          text: 'a ',
          style: TextStyle(height: 1, letterSpacing: 0, wordSpacing: 0),
          children: [
            TextSpan(
              text: 'b\nc ',
              children: [TextSpan(text: 'd')],
            ),
          ],
        );
        Widget frame(MediaQueryData ambient) => wrapHost(
          MediaQuery(
            data: ambient,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                rich
                    ? const TextAutoWrap.rich(source, softWrap: false)
                    : const TextAutoWrap('a b\nc d', softWrap: false),
                rich
                    ? const Text.rich(source, softWrap: false)
                    : const Text('a b\nc d', softWrap: false),
              ],
            ),
          ),
        );
        await tester.pumpWidget(frame(const MediaQueryData()));
        final render = wrapRender(tester);
        await tester.pumpWidget(frame(data!));
        expect(wrapRender(tester), same(render));
        final native = tester.allRenderObjects
            .whereType<RenderParagraph>()
            .where((r) => r is! RenderTextAutoWrap)
            .toSet()
            .single;
        expect(render.size, native.size);
        expect(_widths(render), _widths(native));
        expect(render.size.height, expectedHeight);
        expect(_widths(render), [expectedWidth, expectedWidth]);
        await tester.pumpWidget(frame(const MediaQueryData()));
        expect(render.size.height, 20);
        expect(_widths(render), [30, 30]);
      }, skip: data == null);
    }
  }

  testWidgets(
    'M1 renderer emits canonical invalid runtime measurement reason',
    (tester) async {
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            'a\nb',
            model: offsetModel([]),
            strategy: const LineBreakStrategy(
              calculator: _UnavailableMeasurement(),
            ),
          ),
        ),
      );
      final result = wrapRender(tester).result!;
      expect(result.reason, 'invalidRuntimeMeasurement');
      expect(result.applied, isFalse);
      expect(result.lines, ['a', 'b']);
      expect(result.widths, [10, 10]);
    },
  );
}

// Runtime invocation keeps these regressions compilable on Flutter 3.38,
// which predates the ambient spacing overrides.
MediaQueryData? _spacingData(Map<Symbol, dynamic> arguments) {
  try {
    return Function.apply(MediaQueryData.new, const [], arguments)
        as MediaQueryData;
  } on NoSuchMethodError {
    return null;
  }
}

List<double> _widths(RenderParagraph render) {
  final painter =
      TextPainter(
        text: render.text,
        textDirection: render.textDirection,
        textAlign: render.textAlign,
        textScaler: render.textScaler,
        maxLines: render.maxLines,
        ellipsis: render.overflow == TextOverflow.ellipsis ? '\u2026' : null,
        locale: render.locale,
        strutStyle: render.strutStyle,
        textWidthBasis: render.textWidthBasis,
        textHeightBehavior: render.textHeightBehavior,
      )..layout(
        minWidth: render.constraints.minWidth,
        maxWidth: render.softWrap || render.overflow == TextOverflow.ellipsis
            ? render.constraints.maxWidth
            : double.infinity,
      );
  try {
    return painter.computeLineMetrics().map((line) => line.width).toList();
  } finally {
    painter.dispose();
  }
}

final class _UnavailableMeasurement implements LayoutCalculator {
  const _UnavailableMeasurement();

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => throw const TextRangeMeasurementException('Range shaping unavailable.');
}
