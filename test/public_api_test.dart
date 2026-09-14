import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  testWidgets(
    'documented widget and engine APIs compile from the package entrypoint',
    (tester) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      final customModel = PhraseModel(
        levels: [
          PhraseModelLevel(
            name: 'custom',
            predictor: const _WhitespacePredictor(),
            penalty: 0,
          ),
        ],
        fallbackPenalty: 1,
      );
      final customStrategy = LineBreakStrategy(
        aggregator: consensus(minimumModels: 1),
        calculator: nearbyLayouts(radius: 1),
        selector: const BalanceStrategy(tolerance: .2),
      );

      final widgets = <Widget>[
        const TextAutoWrap('Automatic Korean wrapping example'),
        TextAutoWrap('Explicit Korean model', model: TextAutoWrapModels.korean),
        TextAutoWrap(
          'Explicit English model',
          model: TextAutoWrapModels.english,
        ),
        TextAutoWrap(
          'Custom model and strategy',
          model: customModel,
          strategy: customStrategy,
          controller: controller,
        ),
        TextAutoWrap.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Styled ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(width: 12, height: 12, color: Colors.blue),
              ),
              const TextSpan(text: ' rich text'),
            ],
          ),
          model: TextAutoWrapModels.auto,
        ),
      ];

      await tester.pumpWidget(MaterialApp(home: Column(children: widgets)));

      const source = 'aa bb';
      final plan = createTextWrapPlan(text: source, model: customModel);
      final result = plan.select(
        maxWidth: 3,
        measureRange: (start, end) => (end - start).toDouble(),
        diagnostics: true,
      );
      final oneShot = selectTextWrap(
        TextWrapInput(
          text: source,
          model: customModel,
          maxWidth: 3,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
        strategy: customStrategy,
        diagnostics: true,
      );
      final diagnostics = TextWrapDiagnostics(
        selection: const LayoutSelectionDecision.native(
          reason: 'publicApiExample',
        ),
        cache: const TextWrapCacheDiagnostics(),
      );

      expect(widgets, hasLength(5));
      expect(plan, isA<TextWrapPlan>());
      expect(result, isA<TextWrapResult>());
      expect(result.diagnostics, isA<TextWrapDiagnostics>());
      expect(oneShot, isA<TextWrapResult>());
      expect(diagnostics.selection.source, TextWrapSelectionSource.native);
      expect(RenderTextAutoWrap, isA<Type>());
      expect(
        detectTextWrapLanguage('한국어', null).selectedModel,
        same(TextAutoWrapModels.korean),
      );
      expect(
        detectTextWrapLanguage('English', null).selectedModel,
        same(TextAutoWrapModels.english),
      );
    },
  );
}

final class _WhitespacePredictor implements BoundaryPredictor {
  const _WhitespacePredictor();

  @override
  List<int> predict(String text) => [
    for (var index = 0; index < text.length; index++)
      if (text.codeUnitAt(index) == 0x20) index + 1,
  ];
}
