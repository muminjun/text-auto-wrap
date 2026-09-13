import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets(
    'unchanged layouts reuse the final selection while width changes reuse only the immutable plan',
    (tester) async {
      final predictor = _CountingPredictor();
      final calculator = _CountingCalculator();
      final model = _model(predictor);
      final strategy = _strategy(calculator);

      await tester.pumpWidget(
        _host(model: model, strategy: strategy, width: 100),
      );
      final render = wrapRender(tester);
      final initialMeasurements = calculator.measurements;
      expect(predictor.calls, 1);
      expect(initialMeasurements, greaterThan(0));
      expect(render.result!.diagnostics!.cache.planMisses, 1);
      expect(render.result!.diagnostics!.cache.selectionCacheMisses, 1);

      await tester.pumpWidget(
        _host(model: model, strategy: strategy, width: 100),
      );
      expect(wrapRender(tester), same(render));
      expect(predictor.calls, 1);
      expect(calculator.calls, 1);
      expect(calculator.measurements, initialMeasurements);
      expect(render.result!.diagnostics!.cache.selectionCacheHits, 1);

      await tester.pumpWidget(
        _host(model: model, strategy: strategy, width: 80),
      );
      expect(predictor.calls, 1);
      expect(calculator.calls, 2);
      expect(calculator.measurements, greaterThan(initialMeasurements));
      expect(render.result!.diagnostics!.cache.planHits, 1);
      expect(render.result!.diagnostics!.cache.selectionCacheMisses, 2);
    },
  );

  testWidgets('value-equivalent model and strategy retain cached work', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator();
    await tester.pumpWidget(
      _host(
        model: _model(predictor),
        strategy: _strategy(calculator),
        width: 100,
      ),
    );
    final render = wrapRender(tester);

    await tester.pumpWidget(
      _host(
        model: _model(predictor),
        strategy: _strategy(calculator),
        width: 100,
      ),
    );

    expect(predictor.calls, 1);
    expect(calculator.calls, 1);
    expect(render.result!.diagnostics!.cache.planMisses, 1);
    expect(render.result!.diagnostics!.cache.selectionCacheHits, 1);
  });

  testWidgets('render inputs invalidate only the cache layers they affect', (
    tester,
  ) async {
    Future<void> expectInvalidation(
      String name,
      _CacheCase Function(_CacheCase base) change, {
      required bool invalidatesPlan,
    }) async {
      final predictor = _CountingPredictor();
      final calculator = _CountingCalculator();
      final base = _CacheCase(
        model: _model(predictor),
        strategy: _strategy(calculator),
      );
      await tester.pumpWidget(_hostCase(base));
      final render = wrapRender(tester);
      final before = render.result!.diagnostics!.cache;
      final initialMeasurements = calculator.measurements;

      await tester.pumpWidget(_hostCase(change(base)));

      final cache = render.result!.diagnostics!.cache;
      expect(
        cache.selectionCacheMisses,
        before.selectionCacheMisses + 1,
        reason: name,
      );
      expect(
        cache.planMisses,
        before.planMisses + (invalidatesPlan ? 1 : 0),
        reason: name,
      );
      expect(
        predictor.calls,
        name == 'model' ? 1 : (invalidatesPlan ? 2 : 1),
        reason: name,
      );
      if (name == 'maximum lines') {
        expect(cache.measurementRuns, before.measurementRuns, reason: name);
      } else {
        expect(
          calculator.measurements,
          greaterThan(initialMeasurements),
          reason: name,
        );
      }
    }

    await expectInvalidation(
      'text',
      (base) => base.copyWith(text: 'aa bb cd'),
      invalidatesPlan: true,
    );
    await expectInvalidation(
      'span metadata',
      (base) => base.copyWith(semanticsLabel: 'changed label'),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'style',
      (base) => base.copyWith(style: const TextStyle(fontSize: 13)),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'direction',
      (base) => base.copyWith(direction: TextDirection.rtl),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'locale',
      (base) => base.copyWith(locale: const Locale('en')),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'scaler',
      (base) => base.copyWith(scaler: TextScaler.linear(1.4)),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'strut',
      (base) => base.copyWith(
        strutStyle: const StrutStyle(fontSize: 12, forceStrutHeight: true),
      ),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'width basis',
      (base) => base.copyWith(widthBasis: TextWidthBasis.longestLine),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'height behavior',
      (base) => base.copyWith(
        heightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
        ),
      ),
      invalidatesPlan: false,
    );
    await expectInvalidation(
      'model',
      (base) => base.copyWith(model: _model(_CountingPredictor())),
      invalidatesPlan: true,
    );
    await expectInvalidation(
      'strategy',
      (base) => base.copyWith(
        strategy: LineBreakStrategy(
          calculator: base.strategy.calculator,
          selector: const _ChangedSelector(),
        ),
      ),
      invalidatesPlan: true,
    );
    await expectInvalidation(
      'maximum lines',
      (base) => base.copyWith(maxLines: 1),
      invalidatesPlan: false,
    );
  });

  testWidgets('placeholder dimensions invalidate cached range widths', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator();
    final model = _model(predictor);
    final strategy = _strategy(calculator);

    await tester.pumpWidget(
      _placeholderHost(model: model, strategy: strategy, placeholderWidth: 12),
    );
    final render = wrapRender(tester);
    final measurements = calculator.measurements;

    await tester.pumpWidget(
      _placeholderHost(model: model, strategy: strategy, placeholderWidth: 36),
    );

    expect(predictor.calls, 1);
    expect(calculator.measurements, greaterThan(measurements));
    expect(render.result!.diagnostics!.cache.planHits, 1);
    expect(render.result!.diagnostics!.cache.selectionCacheMisses, 2);
  });
}

Widget _host({
  required PhraseModel model,
  required LineBreakStrategy strategy,
  required double width,
}) => _hostCase(_CacheCase(model: model, strategy: strategy, width: width));

Widget _hostCase(_CacheCase value) => wrapHost(
  TextAutoWrap.rich(
    TextSpan(text: value.text, semanticsLabel: value.semanticsLabel),
    style: value.style,
    textDirection: value.direction,
    locale: value.locale,
    textScaler: value.scaler,
    strutStyle: value.strutStyle,
    textWidthBasis: value.widthBasis,
    textHeightBehavior: value.heightBehavior,
    maxLines: value.maxLines,
    model: value.model,
    strategy: value.strategy,
  ),
  width: value.width,
  direction: value.direction,
);

Widget _placeholderHost({
  required PhraseModel model,
  required LineBreakStrategy strategy,
  required double placeholderWidth,
}) => wrapHost(
  TextAutoWrap.rich(
    TextSpan(
      text: 'ab',
      children: [
        WidgetSpan(child: SizedBox(width: placeholderWidth, height: 12)),
        const TextSpan(text: 'cd'),
      ],
    ),
    model: model,
    strategy: strategy,
  ),
);

PhraseModel _model(_CountingPredictor predictor) => PhraseModel(
  levels: [
    PhraseModelLevel(name: 'counting', predictor: predictor, penalty: 0),
  ],
  fallbackPenalty: 100,
  boundaryMode: BoundaryMode.characters,
);

LineBreakStrategy _strategy(_CountingCalculator calculator) =>
    LineBreakStrategy(
      calculator: calculator,
      selector: const _FirstCalculated(),
    );

final class _CacheCase {
  const _CacheCase({
    required this.model,
    required this.strategy,
    this.text = 'aa bb cc',
    this.width = 100,
    this.semanticsLabel,
    this.style,
    this.direction = TextDirection.ltr,
    this.locale,
    this.scaler = TextScaler.noScaling,
    this.strutStyle,
    this.widthBasis = TextWidthBasis.parent,
    this.heightBehavior,
    this.maxLines,
  });

  final PhraseModel model;
  final LineBreakStrategy strategy;
  final String text;
  final double width;
  final String? semanticsLabel;
  final TextStyle? style;
  final TextDirection direction;
  final Locale? locale;
  final TextScaler scaler;
  final StrutStyle? strutStyle;
  final TextWidthBasis widthBasis;
  final TextHeightBehavior? heightBehavior;
  final int? maxLines;

  _CacheCase copyWith({
    PhraseModel? model,
    LineBreakStrategy? strategy,
    String? text,
    String? semanticsLabel,
    TextStyle? style,
    TextDirection? direction,
    Locale? locale,
    TextScaler? scaler,
    StrutStyle? strutStyle,
    TextWidthBasis? widthBasis,
    TextHeightBehavior? heightBehavior,
    int? maxLines,
  }) => _CacheCase(
    model: model ?? this.model,
    strategy: strategy ?? this.strategy,
    text: text ?? this.text,
    width: width,
    semanticsLabel: semanticsLabel ?? this.semanticsLabel,
    style: style ?? this.style,
    direction: direction ?? this.direction,
    locale: locale ?? this.locale,
    scaler: scaler ?? this.scaler,
    strutStyle: strutStyle ?? this.strutStyle,
    widthBasis: widthBasis ?? this.widthBasis,
    heightBehavior: heightBehavior ?? this.heightBehavior,
    maxLines: maxLines ?? this.maxLines,
  );
}

final class _CountingPredictor implements BoundaryPredictor {
  var calls = 0;

  @override
  List<int> predict(String text) {
    calls++;
    return [
      for (final offset in [3, 6])
        if (offset < text.length) offset,
    ];
  }
}

final class _CountingCalculator implements LayoutCalculator {
  var calls = 0;
  var measurements = 0;

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    calls++;
    return optimalLayouts().calculate(
      text: text,
      candidates: candidates,
      maxWidth: maxWidth,
      measureRange: (start, end) {
        measurements++;
        return measureRange(start, end);
      },
      baseline: baseline,
    );
  }
}

final class _FirstCalculated implements LayoutSelector {
  const _FirstCalculated();

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const LayoutSelectionDecision.calculated(0);
}

final class _ChangedSelector implements LayoutSelector {
  const _ChangedSelector();

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const LayoutSelectionDecision.calculated(0);
}
