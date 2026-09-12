import 'layout.dart';
import 'prediction.dart';
import 'selection.dart';

/// Cumulative plan counters, frozen at the time a result is selected.
final class TextWrapCacheDiagnostics {
  const TextWrapCacheDiagnostics({
    this.predictionRuns = 0,
    this.predictionHits = 0,
    this.aggregationRuns = 0,
    this.aggregationHits = 0,
    this.calculationRuns = 0,
    this.selectionRuns = 0,
    this.measurementRuns = 0,
    this.measurementHits = 0,
  });
  final int predictionRuns;
  final int predictionHits;
  final int aggregationRuns;
  final int aggregationHits;
  final int calculationRuns;
  final int selectionRuns;
  final int measurementRuns;
  final int measurementHits;
}

/// Immutable snapshots from every stage, including fallback and cache evidence.
final class TextWrapDiagnostics {
  TextWrapDiagnostics({
    List<BreakPrediction> predictions = const [],
    List<BreakCandidate> candidates = const [],
    List<LineBreakLayout> calculatedLayouts = const [],
    this.nativeLayout,
    required this.selection,
    this.cache = const TextWrapCacheDiagnostics(),
    this.calculationLimit,
  }) : predictions = List.unmodifiable(predictions),
       candidates = List.unmodifiable(candidates),
       calculatedLayouts = List.unmodifiable(calculatedLayouts);
  final List<BreakPrediction> predictions;
  final List<BreakCandidate> candidates;
  final List<LineBreakLayout> calculatedLayouts;
  final LineBreakLayout? nativeLayout;
  final LayoutSelectionDecision selection;
  final TextWrapCacheDiagnostics cache;
  final LayoutCalculationLimit? calculationLimit;
}

/// Immutable selected source ranges, measurements, and selection explanation.
final class TextWrapResult {
  const TextWrapResult({
    required this.layout,
    required this.applied,
    required this.reason,
    required this.source,
    this.diagnostics,
  });

  /// Explicit adapter fallback. Direct engine measurement errors still throw.
  factory TextWrapResult.native(
    LineBreakLayout layout, {
    String reason = 'nativeSelected',
    bool diagnostics = false,
  }) => TextWrapResult(
    layout: layout,
    applied: false,
    reason: reason,
    source: TextWrapSelectionSource.native,
    diagnostics: diagnostics
        ? TextWrapDiagnostics(
            nativeLayout: layout,
            selection: LayoutSelectionDecision.native(reason: reason),
          )
        : null,
  );

  final LineBreakLayout layout;
  final bool applied;
  final String reason;
  final TextWrapSelectionSource source;
  final TextWrapDiagnostics? diagnostics;
  String get sourceText => layout.sourceText;
  List<TextLineRange> get ranges => layout.ranges;
  List<String> get lines => layout.lines;
  List<int> get breakOffsets => layout.breakOffsets;
  List<double> get widths => layout.widths;
  List<BreakCandidate> get selectedCandidates => layout.selectedCandidates;
  int get lineCount => layout.lineCount;
  bool get overflow => layout.overflow;
}
