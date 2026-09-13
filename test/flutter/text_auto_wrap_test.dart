import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  testWidgets('controller commits immediately and notifies after the frame', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await tester.pumpWidget(_controllerText(controller));

    expect(controller.result, isNotNull);
    expect(notifications, 1);
  });

  testWidgets('controller ignores an equivalent committed result', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await tester.pumpWidget(_controllerText(controller));
    await tester.pumpWidget(_controllerText(controller));

    expect(notifications, 1);
  });

  testWidgets(
    'controller replaces equivalent diagnostic payload without another notification',
    (tester) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await tester.pumpWidget(_controllerText(controller));
      final first = controller.result!;
      final replacement = TextWrapResult(
        layout: first.layout,
        applied: first.applied,
        reason: first.reason,
        source: first.source,
        diagnostics: TextWrapDiagnostics(
          candidates: const [
            BreakCandidate(
              offset: 3,
              penalty: 99,
              levelName: 'replacement',
              consensusCount: 1,
              isFallback: false,
            ),
          ],
          selection: const LayoutSelectionDecision.native(
            reason: 'replacement payload reason',
          ),
        ),
      );

      controller.commitResult(Object(), replacement);

      expect(controller.result, same(replacement));
      await tester.pumpWidget(_controllerText(controller));
      expect(notifications, 1);
    },
  );

  testWidgets('controller notifies for material selection outcome changes', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await tester.pumpWidget(_controllerText(controller));
    final first = controller.result!;
    final reasonChanged = TextWrapResult(
      layout: first.layout,
      applied: first.applied,
      reason: 'rendererFallback',
      source: first.source,
    );

    controller.commitResult(Object(), reasonChanged);
    expect(controller.result, same(reasonChanged));
    await _flushPostFrame(tester);
    expect(notifications, 2);

    final sourceChanged = TextWrapResult(
      layout: first.layout,
      applied: first.applied,
      reason: reasonChanged.reason,
      source: TextWrapSelectionSource.native,
    );
    controller.commitResult(Object(), sourceChanged);
    expect(controller.result, same(sourceChanged));
    await _flushPostFrame(tester);
    expect(notifications, 3);

    final candidateChanged = LineBreakLayout(
      sourceText: first.sourceText,
      ranges: first.ranges,
      widths: first.widths,
      maxWidth: 60,
      selectedCandidates: const [
        BreakCandidate(
          offset: 3,
          penalty: 99,
          levelName: 'replacement',
          consensusCount: 1,
          isFallback: false,
        ),
      ],
    );
    final costChanged = TextWrapResult(
      layout: candidateChanged,
      applied: first.applied,
      reason: sourceChanged.reason,
      source: sourceChanged.source,
    );

    expect(costChanged.breakOffsets, first.breakOffsets);
    expect(
      costChanged.layout.totalModelCost,
      isNot(first.layout.totalModelCost),
    );
    controller.commitResult(Object(), costChanged);
    expect(controller.result, same(costChanged));
    await _flushPostFrame(tester);
    expect(notifications, 4);
  });

  testWidgets(
    'range measurement ignores final maxLines truncation after a hard newline',
    (tester) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              child: TextAutoWrap(
                'abc\ndef',
                style: const TextStyle(fontSize: 10),
                maxLines: 1,
                controller: controller,
                model: _characterModel([5]),
                strategy: const LineBreakStrategy(
                  calculator: _OffsetLayoutCalculator([5]),
                  selector: _FirstCalculated(),
                ),
              ),
            ),
          ),
        ),
      );

      final calculated =
          controller.result!.diagnostics!.calculatedLayouts.single;
      expect(calculated.widths, [30, 10, 20]);
    },
  );

  testWidgets('fallback keeps native empty lines after consecutive LFs', (
    tester,
  ) async {
    final result = await _pumpFallback(tester, 'a\n\nb');

    expect(_ranges(result), [(0, 1), (2, 2), (3, 4)]);
    expect(result.widths, [10, 0, 10]);
  });

  testWidgets('fallback keeps native empty lines after CRLF delimiters', (
    tester,
  ) async {
    final result = await _pumpFallback(tester, 'a\r\n\r\nb');

    expect(_ranges(result), [(0, 1), (3, 3), (5, 6)]);
    expect(result.widths, [10, 0, 10]);
  });

  testWidgets('fallback keeps leading and trailing empty native lines', (
    tester,
  ) async {
    final result = await _pumpFallback(tester, '\na\n');

    expect(_ranges(result), [(0, 0), (1, 2), (3, 3)]);
    expect(result.widths, [0, 10, 0]);
  });

  testWidgets('predictor failure keeps the measured native baseline', (
    tester,
  ) async {
    final result = await _pumpFallback(
      tester,
      'a\n\nb',
      model: PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'throws',
            predictor: const _ThrowingPredictor(),
            penalty: 0,
          ),
        ],
        fallbackPenalty: 100,
        boundaryMode: BoundaryMode.characters,
      ),
      strategy: const LineBreakStrategy(),
    );

    expect(result.reason, 'rendererFallback');
    expect(_ranges(result), [(0, 1), (2, 2), (3, 4)]);
    expect(result.widths, [10, 0, 10]);
  });

  testWidgets('styled bidi measurements use the isolated logical range', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            child: TextAutoWrap.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'a '),
                  TextSpan(
                    text: 'אב',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: ' b'),
                ],
              ),
              style: const TextStyle(fontSize: 10),
              controller: controller,
              model: _characterModel([3]),
              strategy: const LineBreakStrategy(
                calculator: _OffsetLayoutCalculator([3]),
                selector: _FirstCalculated(),
              ),
            ),
          ),
        ),
      ),
    );

    final calculated = controller.result!.diagnostics!.calculatedLayouts.single;
    // The source selection boxes for this range are discontiguous (0–20 and
    // 30–40). Its isolated styled span is only `a א`, or 30 logical pixels.
    expect(calculated.widths.first, 30);
  });

  testWidgets('unsupported span measurement preserves the native baseline', (
    tester,
  ) async {
    final controller = TextAutoWrapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            child: TextAutoWrap.rich(
              const _OpaqueTextSpan(text: 'ab'),
              style: const TextStyle(fontSize: 10),
              controller: controller,
              model: _characterModel([1]),
              strategy: const LineBreakStrategy(
                calculator: _OffsetLayoutCalculator([1]),
                selector: _FirstCalculated(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(controller.result!.reason, 'unsupportedSpanTransformation');
    expect(_ranges(controller.result!), [(0, 2)]);
    expect(controller.result!.widths, [20]);
  });

  testWidgets(
    'custom span widget descendants fall back without shifting placeholders',
    (tester) async {
      const nestedWidget = WidgetSpan(child: SizedBox(width: 7, height: 10));
      const followingWidget = WidgetSpan(
        child: SizedBox(width: 13, height: 10),
      );
      const custom = _OpaqueTextSpan(text: 'a', children: [nestedWidget]);
      const source = TextSpan(
        children: [
          custom,
          followingWidget,
          TextSpan(text: 'b'),
        ],
      );
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              child: TextAutoWrap.rich(
                source,
                style: const TextStyle(fontSize: 10),
                controller: controller,
                model: _characterModel([3]),
                strategy: const LineBreakStrategy(
                  calculator: _OffsetLayoutCalculator([3]),
                  selector: _FirstCalculated(),
                ),
              ),
            ),
          ),
        ),
      );

      final render = _render(tester, 'a\uFFFC\uFFFCb');
      expect(controller.result!.reason, 'unsupportedSpanTransformation');
      expect(_ranges(controller.result!), [(0, 4)]);
      expect(controller.result!.widths, [40]);
      expect(render.effectiveText, same(render.sourceText));
      final effectiveSource =
          (render.effectiveText as TextSpan).children!.single as TextSpan;
      expect(effectiveSource.children!.first, same(custom));
      expect(effectiveSource.children![1], same(followingWidget));
    },
  );

  testWidgets('plain constructor preserves Text layout parameters', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 13, color: Color(0xff123456));
    const strutStyle = StrutStyle(fontSize: 17, height: 1.4);
    const locale = Locale('en', 'US');
    const heightBehavior = TextHeightBehavior(applyHeightToFirstAscent: false);
    const selectionColor = Color(0x55224466);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: TextAutoWrap(
              'parameter parity',
              style: style,
              strutStyle: strutStyle,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              locale: locale,
              softWrap: false,
              overflow: TextOverflow.fade,
              textScaler: TextScaler.linear(1.25),
              maxLines: 2,
              semanticsLabel: 'spoken parameters',
              textWidthBasis: TextWidthBasis.longestLine,
              textHeightBehavior: heightBehavior,
              selectionColor: selectionColor,
            ),
          ),
        ),
      ),
    );

    final render = _render(tester, 'parameter parity');
    expect(render.text.style, style);
    expect(render.strutStyle, strutStyle);
    expect(render.textAlign, TextAlign.right);
    expect(render.textDirection, TextDirection.rtl);
    expect(render.locale, locale);
    expect(render.softWrap, isFalse);
    expect(render.overflow, TextOverflow.fade);
    expect(render.textScaler.scale(10), 12.5);
    expect(render.maxLines, 2);
    expect(render.textWidthBasis, TextWidthBasis.longestLine);
    expect(render.textHeightBehavior, heightBehavior);
    expect(render.selectionColor, selectionColor);
  });

  testWidgets(
    'plain and styled rich text commits semantic breaks on first pump',
    (tester) async {
      const rootStyle = TextStyle(fontSize: 10, color: Color(0xff345678));
      const childStyle = TextStyle(fontWeight: FontWeight.bold);
      final model = PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'preferred',
            predictor: const _Offsets([3]),
            penalty: 0,
          ),
        ],
        fallbackPenalty: 100,
        boundaryMode: BoundaryMode.characters,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 40,
              child: TextAutoWrap.rich(
                const TextSpan(
                  style: rootStyle,
                  children: [TextSpan(text: 'abcdef', style: childStyle)],
                ),
                model: model,
                strategy: const LineBreakStrategy(
                  calculator: _OffsetLayoutCalculator([3]),
                  selector: _FirstCalculated(),
                ),
              ),
            ),
          ),
        ),
      );

      final render = _render(tester, 'abcdef');
      expect(
        render.sourceText.toPlainText(includeSemanticsLabels: false),
        'abcdef',
      );
      expect(render.constraints.maxWidth, 40);
      expect(render.result?.breakOffsets, [3]);
      expect(render.result?.applied, isTrue);
      final effective = render.effectiveText as TextSpan;
      expect(effective.toPlainText(includeSemanticsLabels: false), 'abc\ndef');
      final styledChild =
          (effective.children!.single as TextSpan).children!.single as TextSpan;
      expect(styledChild.style, childStyle);
    },
  );
}

RenderTextAutoWrap _render(WidgetTester tester, String source) {
  final results = tester.allRenderObjects
      .whereType<RenderTextAutoWrap>()
      .where(
        (render) =>
            render.sourceText.toPlainText(includeSemanticsLabels: false) ==
            source,
      )
      .toList();
  return results.last;
}

final class _Offsets implements BoundaryPredictor {
  const _Offsets(this.offsets);

  final List<int> offsets;

  @override
  List<int> predict(String text) => offsets;
}

final class _FirstCalculated implements LayoutSelector {
  const _FirstCalculated();

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const LayoutSelectionDecision.calculated(0);
}

final class _OffsetLayoutCalculator implements LayoutCalculator {
  const _OffsetLayoutCalculator(this.offsets);

  final List<int> offsets;

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    final candidatesByOffset = {
      for (final candidate in candidates) candidate.offset: candidate,
    };
    final selected = [
      for (final offset in offsets) candidatesByOffset[offset]!,
    ];
    return LayoutCalculationSuccess([
      LineBreakLayoutCandidate(
        sourceText: text,
        selectedCandidates: selected,
      ).measure(maxWidth: maxWidth, measureRange: measureRange),
    ]);
  }
}

Widget _controllerText(TextAutoWrapController controller) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 60,
      child: TextAutoWrap(
        'abcdef',
        controller: controller,
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'preferred',
              predictor: const _Offsets([3]),
              penalty: 0,
            ),
          ],
          fallbackPenalty: 100,
          boundaryMode: BoundaryMode.characters,
        ),
        strategy: const LineBreakStrategy(
          calculator: _OffsetLayoutCalculator([3]),
          selector: _FirstCalculated(),
        ),
      ),
    ),
  ),
);

PhraseModel _characterModel(List<int> offsets) => PhraseModel(
  levels: [
    PhraseModelLevel(
      name: 'preferred',
      predictor: _Offsets(offsets),
      penalty: 0,
    ),
  ],
  fallbackPenalty: 100,
  boundaryMode: BoundaryMode.characters,
);

Future<TextWrapResult> _pumpFallback(
  WidgetTester tester,
  String text, {
  TextWrapModel? model,
  LineBreakStrategy strategy = const LineBreakStrategy(
    calculator: _ThrowingCalculator(),
  ),
}) async {
  final controller = TextAutoWrapController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: TextAutoWrap(
            text,
            style: const TextStyle(fontSize: 10),
            controller: controller,
            model: model ?? _characterModel(const []),
            strategy: strategy,
          ),
        ),
      ),
    ),
  );
  return controller.result!;
}

List<(int, int)> _ranges(TextWrapResult result) => [
  for (final range in result.ranges) (range.start, range.end),
];

Future<void> _flushPostFrame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

final class _ThrowingCalculator implements LayoutCalculator {
  const _ThrowingCalculator();

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => throw StateError('strategy failure');
}

final class _ThrowingPredictor implements BoundaryPredictor {
  const _ThrowingPredictor();

  @override
  List<int> predict(String text) => throw StateError('predictor failure');
}

final class _OpaqueTextSpan extends TextSpan {
  const _OpaqueTextSpan({super.text, super.children});
}
