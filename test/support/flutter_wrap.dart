import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

const wrapStyle = TextStyle(fontSize: 10, color: Color(0xFF000000));

PhraseModel offsetModel(List<int> offsets) => PhraseModel(
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

LineBreakStrategy offsetStrategy(List<int> offsets) => LineBreakStrategy(
  calculator: _OffsetLayout(offsets),
  selector: const _Calculated(),
);

Widget wrapHost(
  Widget child, {
  double width = 100,
  TextDirection direction = TextDirection.ltr,
}) => Directionality(
  textDirection: direction,
  child: DefaultTextStyle(
    style: wrapStyle,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

RenderTextAutoWrap wrapRender(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderTextAutoWrap>().toSet().single;

final class _Offsets implements BoundaryPredictor {
  const _Offsets(this.offsets);
  final List<int> offsets;

  @override
  List<int> predict(String text) => offsets;
}

final class _Calculated implements LayoutSelector {
  const _Calculated();

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const LayoutSelectionDecision.calculated(0);
}

final class _OffsetLayout implements LayoutCalculator {
  const _OffsetLayout(this.offsets);
  final List<int> offsets;

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) => LayoutCalculationSuccess([
    LineBreakLayoutCandidate(
      sourceText: text,
      selectedCandidates: [
        for (final offset in offsets)
          candidates.singleWhere((candidate) => candidate.offset == offset),
      ],
    ).measure(maxWidth: maxWidth, measureRange: measureRange),
  ]);
}
