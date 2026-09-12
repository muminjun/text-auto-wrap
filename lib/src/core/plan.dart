import 'boundaries.dart';
import 'diagnostics.dart';
import 'exceptions.dart';
import 'layout.dart';
import 'models.dart';
import 'prediction.dart';
import 'selection.dart';
import 'strategy.dart';

/// Creates a lazy synchronous plan with immutable text, model, and strategy.
TextWrapPlan createTextWrapPlan({
  required String text,
  required PhraseModel? model,
  LineBreakStrategy strategy = const LineBreakStrategy(),
}) => TextWrapPlan._(text, model, strategy);

/// Reusable prediction/aggregation snapshots with fresh calculation/selection.
///
/// A non-null measurement cache key opts into range reuse. It must change when
/// any measurement input changes (style, direction, scaling, placeholders, or
/// width if the callback depends on it). Omitting the key disables cross-call
/// reuse. Only the most recent key's bounded range cache is retained.
final class TextWrapPlan {
  TextWrapPlan._(this.text, this.model, this.strategy);
  final String text;
  final PhraseModel? model;
  final LineBreakStrategy strategy;
  List<BreakPrediction>? _predictions;
  List<BreakCandidate>? _candidates;
  Object? _measurementKey;
  Map<(int, int), double> _widths = {};
  int _predictionRuns = 0, _predictionHits = 0;
  int _aggregationRuns = 0, _aggregationHits = 0;
  int _calculationRuns = 0, _selectionRuns = 0;
  int _measurementRuns = 0, _measurementHits = 0;

  /// Runs predictors once, then returns the same immutable snapshot.
  List<BreakPrediction> predict() {
    if (_predictions != null) {
      _predictionHits++;
      return _predictions!;
    }
    final resolved = model;
    final result = resolved == null
        ? <BreakPrediction>[]
        : PredictionContext(text: text, model: resolved).predict();
    _predictionRuns++;
    return _predictions = List.unmodifiable(result);
  }

  /// Invokes prediction if needed, and caches validated aggregated candidates.
  List<BreakCandidate> aggregate() {
    if (_candidates != null) {
      _aggregationHits++;
      return _candidates!;
    }
    final predictions = predict();
    final resolved = model;
    final result = resolved == null
        ? <BreakCandidate>[]
        : strategy.aggregator
              .aggregate(
                PredictionContext(text: text, model: resolved),
                predictions: predictions,
              )
              .candidates;
    validateOffsets(text, [
      for (final candidate in result) candidate.offset,
    ], mode: resolved?.boundaryMode ?? BoundaryMode.characters);
    // Also validates penalties using the authoritative layout contract.
    LineBreakLayoutCandidate(sourceText: text, selectedCandidates: result);
    _aggregationRuns++;
    return _candidates = List.unmodifiable(result);
  }

  /// Always reruns calculation; prerequisite snapshots may be reused.
  LayoutCalculationResult calculate({
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? nativeLayout,
    Object? measurementCacheKey,
  }) {
    _validate(maxWidth, nativeLayout, null);
    final candidates = aggregate();
    final measure = _measurer(measureRange, measurementCacheKey);
    final native = nativeLayout == null
        ? null
        : _scoreNative(nativeLayout, maxWidth);
    return _calculate(maxWidth, measure, native, candidates);
  }

  LayoutCalculationResult _calculate(
    double maxWidth,
    TextRangeMeasurer measure,
    LineBreakLayout? native,
    List<BreakCandidate> candidates,
  ) {
    _calculationRuns++;
    final result = strategy.calculator.calculate(
      text: text,
      candidates: candidates,
      maxWidth: maxWidth,
      measureRange: measure,
      baseline: native,
    );
    if (result case LayoutCalculationSuccess(:final layouts)) {
      if (layouts.isEmpty) {
        throw const InvalidModelConfigurationException(
          'A calculator must return at least one layout.',
        );
      }
      final byOffset = {
        for (final candidate in candidates) candidate.offset: candidate,
      };
      final signatures = <String>{};
      for (final layout in layouts) {
        if (layout.sourceText != text) {
          throw const InvalidModelConfigurationException(
            'Calculated layouts must use the plan source text.',
          );
        }
        if (layout.breakOffsets.any(
          (offset) => !byOffset.containsKey(offset),
        )) {
          throw const InvalidBoundaryException(
            'Calculated breaks must reference aggregated candidates.',
          );
        }
        for (final selected in layout.selectedCandidates) {
          final candidate = byOffset[selected.offset]!;
          if (selected.penalty != candidate.penalty ||
              selected.levelName != candidate.levelName ||
              selected.consensusCount != candidate.consensusCount ||
              selected.isFallback != candidate.isFallback) {
            throw const InvalidModelConfigurationException(
              'Calculated candidate metadata must match aggregated candidates.',
            );
          }
        }
        if (layout.overflow != layout.widths.any((width) => width > maxWidth)) {
          throw const InvalidModelConfigurationException(
            'Calculated overflow must use the current maximum width.',
          );
        }
        if (!signatures.add(layout.breakOffsets.join(','))) {
          throw const InvalidModelConfigurationException(
            'Calculated layouts must not contain duplicate break sets.',
          );
        }
      }
    }
    return result;
  }

  /// Calculates and selects using the supplied current rendering inputs.
  TextWrapResult select({
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? nativeLayout,
    int? maxLines,
    Object? measurementCacheKey,
    bool diagnostics = false,
  }) {
    _validate(maxWidth, nativeLayout, maxLines);
    final candidates = aggregate();
    final measure = _measurer(measureRange, measurementCacheKey);
    var native = nativeLayout == null
        ? null
        : _scoreNative(nativeLayout, maxWidth);
    LayoutCalculationLimit? limit;
    List<LineBreakLayout> layouts = const [];
    LayoutSelectionDecision decision;
    if (model == null) {
      decision = const LayoutSelectionDecision.native(
        reason: 'unsupportedLanguage',
      );
    } else {
      final calculation = _calculate(maxWidth, measure, native, candidates);
      switch (calculation) {
        case LayoutCalculationLimit():
          limit = calculation;
          decision = const LayoutSelectionDecision.native(
            reason: 'calculationLimit',
          );
        case LayoutCalculationSuccess():
          layouts = calculation.layouts;
          decision = strategy.selector.select(
            LayoutSelectionContext(
              calculatedLayouts: layouts,
              nativeLayout: native,
              maxLines: maxLines,
            ),
          );
      }
    }
    if (model == null || limit != null) {
      native ??= LineBreakLayoutCandidate(
        sourceText: text,
        selectedCandidates: const [],
      ).measure(maxWidth: maxWidth, measureRange: measure);
    }
    final LineBreakLayout selected;
    switch (decision.source) {
      case TextWrapSelectionSource.native:
        if (native == null) {
          throw const InvalidModelConfigurationException(
            'A selector cannot select a missing native layout.',
          );
        }
        selected = native;
      case TextWrapSelectionSource.calculated:
        final index = decision.index;
        if (index == null || index < 0 || index >= layouts.length) {
          throw const InvalidModelConfigurationException(
            'A selector must select an existing calculated layout index.',
          );
        }
        selected = layouts[index];
    }
    _selectionRuns++;
    final applied =
        decision.source == TextWrapSelectionSource.calculated &&
        !selected.overflow &&
        (maxLines == null || selected.lineCount <= maxLines) &&
        selected.breakOffsets.isNotEmpty &&
        (native == null ||
            !_sameOffsets(selected.breakOffsets, native.breakOffsets));
    return TextWrapResult(
      layout: selected,
      applied: applied,
      reason: decision.reason,
      source: decision.source,
      diagnostics: diagnostics
          ? TextWrapDiagnostics(
              predictions: _predictions!,
              candidates: candidates,
              calculatedLayouts: layouts,
              nativeLayout: native,
              selection: decision,
              calculationLimit: limit,
              cache: TextWrapCacheDiagnostics(
                predictionRuns: _predictionRuns,
                predictionHits: _predictionHits,
                aggregationRuns: _aggregationRuns,
                aggregationHits: _aggregationHits,
                calculationRuns: _calculationRuns,
                selectionRuns: _selectionRuns,
                measurementRuns: _measurementRuns,
                measurementHits: _measurementHits,
              ),
            )
          : null,
    );
  }

  void _validate(double width, LineBreakLayout? native, int? maxLines) {
    if (!width.isFinite || width < 0) {
      throw const InvalidModelConfigurationException(
        'Available width must be finite and non-negative.',
      );
    }
    if (maxLines != null && maxLines < 1) {
      throw const InvalidModelConfigurationException(
        'maxLines must be positive.',
      );
    }
    if (native != null && native.sourceText != text) {
      throw const InvalidModelConfigurationException(
        'The native layout must use the plan source text.',
      );
    }
  }

  TextRangeMeasurer _measurer(TextRangeMeasurer callback, Object? key) {
    if (key == null || key != _measurementKey) _widths = {};
    _measurementKey = key;
    // Capture this generation: callbacks may synchronously reenter the plan.
    final widths = _widths;
    return (start, end) {
      final range = (start, end);
      final cached = key == null ? null : widths[range];
      if (cached != null) {
        _measurementHits++;
        return cached;
      }
      final width = callback(start, end);
      if (!width.isFinite || width < 0) {
        throw const TextRangeMeasurementException(
          'Measured widths must be finite and non-negative.',
        );
      }
      _measurementRuns++;
      if (key != null) {
        widths[range] = width;
        if (widths.length > 65536) widths.remove(widths.keys.first);
      }
      return width;
    };
  }

  LineBreakLayout _scoreNative(LineBreakLayout native, double maxWidth) {
    final byOffset = {
      for (final candidate in _candidates!) candidate.offset: candidate,
    };
    final breaks = <BreakCandidate>[];
    for (var index = 1; index < native.ranges.length; index++) {
      final previous = native.ranges[index - 1];
      final current = native.ranges[index];
      // Native ranges may include the newline or exclude it in their gap.
      if (RegExp(
        r'[\r\n]',
      ).hasMatch(text.substring(previous.start, current.start))) {
        continue;
      }
      final offset = current.start;
      if (offset <= 0 || offset >= text.length) continue;
      breaks.add(
        byOffset[offset] ??
            BreakCandidate(
              offset: offset,
              penalty: model?.fallbackPenalty ?? 0,
              levelName: null,
              consensusCount: 0,
              isFallback: true,
            ),
      );
    }
    return LineBreakLayout(
      sourceText: text,
      ranges: native.ranges,
      widths: native.widths,
      maxWidth: maxWidth,
      selectedCandidates: breaks,
    );
  }
}

bool _sameOffsets(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
