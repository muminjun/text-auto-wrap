import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  for (final alignment in PlaceholderAlignment.values) {
    for (final baseline in TextBaseline.values) {
      testWidgets('$alignment / $baseline preserves native child boxes', (
        tester,
      ) async {
        final placeholder = WidgetSpan(
          alignment: alignment,
          baseline: baseline,
          child: const _BaselineBox(),
        );
        final source = TextSpan(
          text: 'ab',
          children: [
            placeholder,
            const TextSpan(text: 'cdef'),
          ],
        );
        await tester.pumpWidget(
          wrapHost(
            TextAutoWrap.rich(
              source,
              model: offsetModel([3]),
              strategy: offsetStrategy([3]),
            ),
          ),
        );
        final render = wrapRender(tester);
        expect(render.result!.applied, isTrue);
        expect(render.result!.widths, [40, 40]);
        expect(_plain(render.effectiveText), 'ab\uFFFC\ncdef');
        final widgets = <InlineSpan>[];
        render.effectiveText.visitChildren((span) {
          if (span is WidgetSpan) widgets.add(span);
          return true;
        });
        expect(widgets.single, same(placeholder));
        final actual = _geometry(render);
        final sourceWidths = render.result!.diagnostics!.nativeLayout!.widths;

        await tester.pumpWidget(
          wrapHost(
            Text.rich(
              TextSpan(
                text: 'ab',
                children: [
                  placeholder,
                  const TextSpan(text: '\ncdef'),
                ],
              ),
            ),
          ),
        );
        expect(_geometry(_native(tester)), actual);
        await tester.pumpWidget(wrapHost(Text.rich(source)));
        final nativePainter =
            TextPainter(
              text: TextSpan(style: wrapStyle, children: [source]),
              textDirection: TextDirection.ltr,
            )..setPlaceholderDimensions([
              PlaceholderDimensions(
                size: _native(tester).firstChild!.size,
                alignment: alignment,
                baseline: baseline,
                baselineOffset: alignment == PlaceholderAlignment.baseline
                    ? 13
                    : null,
              ),
            ]);
        addTearDown(nativePainter.dispose);
        nativePainter.layout(maxWidth: 100);
        expect(
          sourceWidths,
          nativePainter.computeLineMetrics().map((m) => m.width),
        );
      });
    }
  }

  testWidgets('multiple placeholders map sliced indices and adjacent breaks', (
    tester,
  ) async {
    const first = WidgetSpan(child: SizedBox(width: 12, height: 16));
    const second = WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(width: 27, height: 8),
    );
    const source = TextSpan(
      text: 'a',
      children: [
        first,
        TextSpan(text: 'b'),
        second,
        TextSpan(text: 'cd'),
      ],
    );
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          source,
          model: offsetModel([1, 2, 3, 4]),
          strategy: offsetStrategy([1, 2, 3, 4]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.result!.sourceText, 'a\uFFFCb\uFFFCcd');
    expect(render.result!.breakOffsets, [1, 2, 3, 4]);
    expect(render.result!.widths, [10, 12, 10, 27, 20]);
    expect(_plain(render.effectiveText), 'a\n\uFFFC\nb\n\uFFFC\ncd');
    final actual = _geometry(render);
    await tester.pumpWidget(
      wrapHost(
        const Text.rich(
          TextSpan(
            text: 'a\n',
            children: [
              first,
              TextSpan(text: '\nb\n'),
              second,
              TextSpan(text: '\ncd'),
            ],
          ),
        ),
      ),
    );
    expect(_geometry(_native(tester)), actual);
  });

  testWidgets('child-only size changes remeasure without replacing identity', (
    tester,
  ) async {
    final width = ValueNotifier<double>(12);
    addTearDown(width.dispose);
    final childKey = GlobalKey();
    final child = ValueListenableBuilder<double>(
      key: childKey,
      valueListenable: width,
      builder: (_, width, _) => SizedBox(width: width, height: 15),
    );
    final source = TextSpan(
      text: 'ab',
      children: [
        WidgetSpan(child: child),
        const TextSpan(text: 'cd'),
      ],
    );
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          source,
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
      ),
    );
    final render = wrapRender(tester);
    final element = childKey.currentContext;
    final box = render.firstChild;
    expect(render.result!.widths, [32, 20]);
    width.value = 36;
    await tester.pump();
    expect(wrapRender(tester), same(render));
    expect(childKey.currentContext, same(element));
    expect(render.firstChild, same(box));
    expect(render.result!.widths, [56, 20]);
    final actual = _geometry(render);
    await tester.pumpWidget(
      wrapHost(
        const Text.rich(
          TextSpan(
            text: 'ab',
            children: [
              WidgetSpan(child: SizedBox(width: 36, height: 15)),
              TextSpan(text: '\ncd'),
            ],
          ),
        ),
      ),
    );
    expect(_geometry(_native(tester)), actual);
  });

  testWidgets('overwide child uses native constrained placeholder dimensions', (
    tester,
  ) async {
    const source = TextSpan(
      text: 'a',
      children: [
        WidgetSpan(child: SizedBox(width: 250, height: 18)),
        TextSpan(text: 'b'),
      ],
    );
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          source,
          model: offsetModel([1, 2]),
          strategy: offsetStrategy([1, 2]),
        ),
        width: 50,
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.widths, [10, 50, 10]);
    expect(render.firstChild!.size, const Size(50, 18));
    final actual = _geometry(render);
    await tester.pumpWidget(
      wrapHost(
        const Text.rich(
          TextSpan(
            text: 'a\n',
            children: [
              WidgetSpan(child: SizedBox(width: 250, height: 18)),
              TextSpan(text: '\nb'),
            ],
          ),
        ),
        width: 50,
      ),
    );
    expect(_geometry(_native(tester)), actual);
  });

  testWidgets('ellipsis hides and restores the same inline child', (
    tester,
  ) async {
    const childKey = ValueKey('ellipsis child');
    const source = TextSpan(
      text: 'abcd',
      children: [
        WidgetSpan(child: SizedBox(key: childKey, width: 12, height: 15)),
        TextSpan(text: 'ef'),
      ],
    );
    Widget text(int? maxLines) => wrapHost(
      TextAutoWrap.rich(
        source,
        overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
        maxLines: maxLines,
        model: offsetModel([4, 5]),
        strategy: offsetStrategy([4, 5]),
      ),
      width: 40,
    );
    await tester.pumpWidget(text(1));
    final render = wrapRender(tester);
    final child = render.firstChild!;
    final element = tester.element(find.byKey(childKey));
    expect(render.didExceedMaxLines, isTrue);
    expect((child.parentData! as TextParentData).offset, isNull);
    await tester.pumpWidget(text(null));
    expect(render.result!.applied, isTrue);
    expect(render.firstChild, same(child));
    expect(tester.element(find.byKey(childKey)), same(element));
    expect((child.parentData! as TextParentData).offset, isNotNull);
    final actual = _geometry(render);
    await tester.pumpWidget(
      wrapHost(
        const Text.rich(
          TextSpan(
            text: 'abcd\n',
            children: [
              WidgetSpan(child: SizedBox(width: 12, height: 15)),
              TextSpan(text: '\nef'),
            ],
          ),
        ),
        width: 40,
      ),
    );
    expect(_geometry(_native(tester)), actual);
  });

  for (final direction in TextDirection.values) {
    testWidgets('$direction multiple bidi placeholders retain logical order', (
      tester,
    ) async {
      const first = WidgetSpan(child: SizedBox(width: 12, height: 16));
      const second = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(width: 27, height: 8),
      );
      const source = TextSpan(
        text: 'אב',
        children: [
          first,
          TextSpan(text: 'cd'),
          second,
          TextSpan(text: 'הו'),
        ],
      );
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
          direction: direction,
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      expect(render.result!.widths, [32, 67]);
      final actual = _geometry(render);
      await tester.pumpWidget(
        wrapHost(
          const Text.rich(
            TextSpan(
              text: 'אב',
              children: [
                first,
                TextSpan(text: '\ncd'),
                second,
                TextSpan(text: 'הו'),
              ],
            ),
          ),
          direction: direction,
        ),
      );
      expect(_geometry(_native(tester)), actual);
    });
  }

  testWidgets(
    'missing real baseline retains source with placeholder fallback',
    (tester) async {
      const source = TextSpan(
        text: 'ab',
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: SizedBox(width: 20, height: 18),
          ),
          TextSpan(text: 'cd'),
        ],
      );
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.reason, 'unmeasurablePlaceholder');
      expect(render.result!.applied, isFalse);
      expect(render.effectiveText, same(render.sourceText));
      final actual = _geometry(render);
      await tester.pumpWidget(wrapHost(const Text.rich(source)));
      expect(_geometry(_native(tester)), actual);
    },
  );

  for (final (name, dimensions) in <(String, PlaceholderDimensions)>[
    (
      'infinite width',
      const PlaceholderDimensions(
        size: Size(double.infinity, 18),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 13,
      ),
    ),
    (
      'NaN height',
      const PlaceholderDimensions(
        size: Size(20, double.nan),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 13,
      ),
    ),
    (
      'negative size',
      const PlaceholderDimensions(
        size: Size(-1, 18),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 13,
      ),
    ),
    (
      'infinite baseline',
      const PlaceholderDimensions(
        size: Size(20, 18),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: double.infinity,
      ),
    ),
    (
      'NaN baseline',
      const PlaceholderDimensions(
        size: Size(20, 18),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: double.nan,
      ),
    ),
    (
      'missing baseline type',
      const PlaceholderDimensions(
        size: Size(20, 18),
        alignment: PlaceholderAlignment.baseline,
        baselineOffset: 13,
      ),
    ),
    (
      'mismatched alignment',
      const PlaceholderDimensions(
        size: Size(20, 18),
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 13,
      ),
    ),
  ]) {
    testWidgets(
      '$name in placeholder measurement falls back before candidate layout',
      (tester) async {
        final render = _InvalidDimensionsParagraph(dimensions);
        await tester.pumpWidget(wrapHost(_ParagraphHost(render)));
        expect(render.result!.reason, 'unmeasurablePlaceholder');
        expect(render.result!.applied, isFalse);
        expect(render.effectiveText, same(render.sourceText));
        expect(render.firstChild!.size, const Size(20, 18));
        expect(
          (render.firstChild!.parentData! as TextParentData).offset,
          isNotNull,
        );
      },
    );
  }

  testWidgets('finite measurement helper control reaches candidate layout', (
    tester,
  ) async {
    final render = _InvalidDimensionsParagraph(
      const PlaceholderDimensions(
        size: Size(20, 18),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 13,
      ),
    );
    await tester.pumpWidget(wrapHost(_ParagraphHost(render)));
    expect(render.result!.applied, isTrue);
    expect(render.result!.widths, [40, 20]);
  });
}

class _ParagraphHost extends LeafRenderObjectWidget {
  const _ParagraphHost(this.render);
  final RenderTextAutoWrap render;

  @override
  RenderTextAutoWrap createRenderObject(BuildContext context) => render;
}

class _BaselineBox extends LeafRenderObjectWidget {
  const _BaselineBox();

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderBaselineBox();
}

class _RenderBaselineBox extends RenderBox {
  @override
  void performLayout() => size = constraints.constrain(const Size(20, 18));

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) => 13;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(const Size(20, 18));

  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => 13;
}

// Invalid RenderBox sizes violate Flutter's own layout contract and cannot be
// painted even by native Text. Inject only the measurement helper's bad result;
// final native layout still receives a valid child, so fallback is observable.
class _InvalidDimensionsParagraph extends RenderTextAutoWrap {
  _InvalidDimensionsParagraph(this.dimensions)
    : super(
        sourceText: const TextSpan(
          style: wrapStyle,
          text: 'ab',
          children: [
            _placeholder,
            TextSpan(text: 'cd'),
          ],
        ),
        model: offsetModel([3]),
        strategy: offsetStrategy([3]),
        textDirection: TextDirection.ltr,
        children: [
          RenderConstrainedBox(
            additionalConstraints: const BoxConstraints.tightFor(
              width: 20,
              height: 18,
            ),
          ),
        ],
      ) {
    (firstChild!.parentData! as TextParentData).span = _placeholder;
  }

  static const _placeholder = WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: SizedBox(width: 20, height: 18),
  );
  final PlaceholderDimensions dimensions;
  var _firstMeasurement = true;

  @override
  List<PlaceholderDimensions> layoutInlineChildren(
    double maxWidth,
    ChildLayouter layoutChild,
    ChildBaselineGetter getChildBaseline,
  ) {
    final native = super.layoutInlineChildren(
      maxWidth,
      layoutChild,
      getChildBaseline,
    );
    if (!_firstMeasurement) return native;
    _firstMeasurement = false;
    return [dimensions];
  }
}

String _plain(InlineSpan span) =>
    span.toPlainText(includeSemanticsLabels: false);

RenderParagraph _native(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderParagraph>().toSet().single;

List<Object?> _geometry(RenderParagraph render) => [
  render.size,
  [
    for (
      var child = render.firstChild;
      child != null;
      child = render.childAfter(child)
    )
      switch ((child.parentData! as TextParentData).offset) {
        final Offset offset => offset & child.size,
        null => null,
      },
  ],
];
