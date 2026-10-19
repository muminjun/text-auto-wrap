import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

/// Forwards to [BalanceStrategy] so the engine cannot take its single-line
/// shortcut and always calculates.
final class _OpaqueBalance implements LayoutSelector {
  const _OpaqueBalance();

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) =>
      const BalanceStrategy().select(context);
}

final class _CountingPredictor implements BoundaryPredictor {
  int calls = 0;

  @override
  List<int> predict(String text) {
    calls++;
    return [for (var i = 3; i < text.length; i += 3) i];
  }
}

final class _CountingCalculator implements LayoutCalculator {
  _CountingCalculator(this._inner);

  final LayoutCalculator _inner;
  int calls = 0;
  final requestedRanges = <(int, int)>{};

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    calls++;
    return _inner.calculate(
      text: text,
      candidates: candidates,
      maxWidth: maxWidth,
      measureRange: (start, end) {
        requestedRanges.add((start, end));
        return measureRange(start, end);
      },
      baseline: baseline,
    );
  }
}

PhraseModel _model(_CountingPredictor predictor) => PhraseModel(
  levels: [PhraseModelLevel(name: 'steps', predictor: predictor, penalty: 0)],
  fallbackPenalty: 100,
  boundaryMode: BoundaryMode.characters,
);

LineBreakStrategy _strategy(_CountingCalculator calculator) =>
    LineBreakStrategy(calculator: calculator);

Widget _host(
  PhraseModel model,
  LineBreakStrategy strategy, {
  String text = 'abcdefghijkl',
  double width = 50,
  Key? key,
  InlineSpan? span,
}) => wrapHost(
  KeyedSubtree(
    key: key,
    child: span == null
        ? TextAutoWrap(text, model: model, strategy: strategy)
        : TextAutoWrap.rich(span, model: model, strategy: strategy),
  ),
  width: width,
);

void main() {
  setUp(RenderTextAutoWrap.clearSharedCaches);
  tearDown(RenderTextAutoWrap.clearSharedCaches);

  testWidgets('a re-created renderer reuses the selection of an equal one', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);

    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(1)));
    final first = wrapRender(tester);
    final firstText = first.effectiveText.toPlainText();
    final firstOffsets = first.result!.breakOffsets;
    final firstSize = first.size;
    expect(predictor.calls, 1);
    expect(calculator.calls, 1);
    expect(firstOffsets, isNotEmpty);

    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(2)));
    final second = wrapRender(tester);
    expect(second, isNot(same(first)));
    expect(predictor.calls, 1);
    expect(calculator.calls, 1);
    final cache = second.result!.diagnostics!.cache;
    expect(cache.selectionCacheHits, 1);
    expect(cache.selectionCacheMisses, 0);
    expect(second.effectiveText.toPlainText(), firstText);
    expect(second.result!.breakOffsets, firstOffsets);
    expect(second.size, firstSize);
  });

  testWidgets('a shared selection is identical to a freshly calculated one', (
    tester,
  ) async {
    final model = _model(_CountingPredictor());
    final strategy = _strategy(_CountingCalculator(optimalLayouts()));
    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(1)));
    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(2)));
    final shared = wrapRender(tester);
    final sharedResult = shared.result!;
    final sharedText = shared.effectiveText.toPlainText();

    RenderTextAutoWrap.clearSharedCaches();
    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(3)));
    final fresh = wrapRender(tester);
    expect(fresh.result!.diagnostics!.cache.selectionCacheMisses, 1);
    expect(fresh.effectiveText.toPlainText(), sharedText);
    expect(fresh.result!.breakOffsets, sharedResult.breakOffsets);
    expect(fresh.result!.lines, sharedResult.lines);
    expect(fresh.result!.widths, sharedResult.widths);
    expect(fresh.result!.applied, sharedResult.applied);
    expect(fresh.result!.reason, sharedResult.reason);
  });

  testWidgets('different width, text, or model never share a selection', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);
    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(1)));
    expect(calculator.calls, 1);

    await tester.pumpWidget(
      _host(model, strategy, width: 70, key: const ValueKey(2)),
    );
    expect(calculator.calls, 2);

    await tester.pumpWidget(
      _host(model, strategy, text: 'abcdefghijklm', key: const ValueKey(3)),
    );
    expect(calculator.calls, 3);

    await tester.pumpWidget(
      _host(_model(_CountingPredictor()), strategy, key: const ValueKey(4)),
    );
    expect(calculator.calls, 4);
  });

  testWidgets('range widths survive a width change and are reused', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);

    await tester.pumpWidget(_host(model, strategy, width: 50));
    final render = wrapRender(tester);
    final narrow = render.result!.diagnostics!.cache;
    expect(narrow.measurementRuns, greaterThan(0));
    final narrowRanges = {...calculator.requestedRanges};
    calculator.requestedRanges.clear();

    await tester.pumpWidget(_host(model, strategy, width: 70));
    final wide = render.result!.diagnostics!.cache;
    expect(calculator.calls, 2);
    // Exact pruning can visit different ranges at different widths. Previously
    // shaped ranges must survive; only genuinely new ranges may be shaped.
    final newRanges = calculator.requestedRanges.difference(narrowRanges);
    expect(wide.measurementRuns, narrow.measurementRuns + newRanges.length);
    expect(wide.measurementHits, greaterThan(narrow.measurementHits));
    expect(calculator.requestedRanges.intersection(narrowRanges), isNotEmpty);
  });

  testWidgets('plans are shared by renderers that differ only by width', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);

    await tester.pumpWidget(
      _host(model, strategy, width: 50, key: const ValueKey(1)),
    );
    await tester.pumpWidget(
      _host(model, strategy, width: 70, key: const ValueKey(2)),
    );
    final render = wrapRender(tester);
    expect(predictor.calls, 1);
    expect(render.result!.diagnostics!.cache.planHits, 1);
    expect(render.result!.diagnostics!.cache.planMisses, 0);
  });

  testWidgets('a font change drops every shared entry', (tester) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);
    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(1)));
    expect(RenderTextAutoWrap.sharedCacheSizes.selections, 1);

    await tester.binding.handleSystemMessage(const {'type': 'fontsChange'});
    expect(RenderTextAutoWrap.sharedCacheSizes, (selections: 0, plans: 0));

    await tester.pumpWidget(_host(model, strategy, key: const ValueKey(2)));
    expect(predictor.calls, 2);
    expect(calculator.calls, 2);
  });

  testWidgets('a shared plan is isolated before an interactive source update', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);
    final recognizer = TapGestureRecognizer();
    addTearDown(recognizer.dispose);
    await tester.pumpWidget(_host(model, strategy));
    expect(predictor.calls, 1);
    await tester.pumpWidget(
      _host(
        model,
        strategy,
        span: TextSpan(text: 'abcdefghijkl', recognizer: recognizer),
      ),
    );
    expect(
      predictor.calls,
      2,
      reason:
          'interactive spans must not write their measurement key into a shared plan',
    );
    expect(wrapRender(tester).result!.diagnostics!.cache.planMisses, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spans with recognizers or WidgetSpans are not shared', (
    tester,
  ) async {
    final predictor = _CountingPredictor();
    final calculator = _CountingCalculator(optimalLayouts());
    final model = _model(predictor);
    final strategy = _strategy(calculator);
    final recognizer = TapGestureRecognizer();
    addTearDown(recognizer.dispose);

    await tester.pumpWidget(
      _host(
        model,
        strategy,
        span: TextSpan(text: 'abcdefghijkl', recognizer: recognizer),
      ),
    );
    expect(RenderTextAutoWrap.sharedCacheSizes, (selections: 0, plans: 0));

    await tester.pumpWidget(
      _host(
        model,
        strategy,
        span: const TextSpan(
          text: 'abcdef',
          children: [WidgetSpan(child: SizedBox(width: 10, height: 10))],
        ),
      ),
    );
    expect(RenderTextAutoWrap.sharedCacheSizes, (selections: 0, plans: 0));
  });

  testWidgets('shared caches are bounded', (tester) async {
    final model = _model(_CountingPredictor());
    final strategy = _strategy(_CountingCalculator(optimalLayouts()));
    for (var i = 0; i < 120; i++) {
      await tester.pumpWidget(
        _host(
          model,
          strategy,
          text: 'abcdefghijkl${'x' * (i % 40)}$i',
          key: ValueKey(i),
        ),
      );
    }
    final sizes = RenderTextAutoWrap.sharedCacheSizes;
    expect(sizes.selections, lessThanOrEqualTo(64));
    expect(sizes.plans, lessThanOrEqualTo(32));
    expect(sizes.selections, greaterThan(0));
  });

  testWidgets('bundled-model layouts match a strategy without shortcuts', (
    tester,
  ) async {
    const phrases = [
      '확인',
      '저장하고 닫기',
      '이미 연결된 사용자를 추가하면, 연결을 해제한 뒤 현재 사용자와 연결해요.',
      'Save your changes before leaving',
    ];
    const opaque = LineBreakStrategy(selector: _OpaqueBalance());
    for (final text in phrases) {
      for (final width in [30.0, 60.0, 100.0, 180.0, 400.0]) {
        Widget host(LineBreakStrategy strategy, int key) => wrapHost(
          KeyedSubtree(
            key: ValueKey(key),
            child: TextAutoWrap(text, strategy: strategy),
          ),
          width: width,
        );
        await tester.pumpWidget(host(const LineBreakStrategy(), 1));
        final fast = wrapRender(tester);
        final fastResult = fast.result!;
        final fastText = fast.effectiveText.toPlainText();
        final fastSize = fast.size;
        // The second pump is served from the shared cache.
        await tester.pumpWidget(host(const LineBreakStrategy(), 2));
        final again = wrapRender(tester);
        expect(again.result!.breakOffsets, fastResult.breakOffsets);
        expect(again.effectiveText.toPlainText(), fastText);

        await tester.pumpWidget(host(opaque, 3));
        final slow = wrapRender(tester);
        final label = '$text @ $width';
        expect(
          fastResult.breakOffsets,
          slow.result!.breakOffsets,
          reason: label,
        );
        expect(fastResult.lines, slow.result!.lines, reason: label);
        expect(fastResult.widths, slow.result!.widths, reason: label);
        expect(fastResult.applied, slow.result!.applied, reason: label);
        expect(fastResult.reason, slow.result!.reason, reason: label);
        expect(fastText, slow.effectiveText.toPlainText(), reason: label);
        expect(fastSize, slow.size, reason: label);
      }
    }
  });
}
