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
