import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'boundaries.dart';
import 'exceptions.dart';
import 'prediction.dart';

/// Measures the half-open UTF-16 source range [start, end).
///
/// Results must be finite and non-negative. Widths need not be additive or
/// monotonic; shaping, styles, and placeholders may affect each range.
typedef TextRangeMeasurer = double Function(int start, int end);

const int _maxCandidateCount = 4096;
const int _maxStateCount = 16384;

/// An immutable half-open UTF-16 range in the original source text.
final class TextLineRange {
  const TextLineRange(this.start, this.end);

  final int start;
  final int end;
}

/// A selection of soft boundaries, ready for range measurement.
final class LineBreakLayoutCandidate {
  LineBreakLayoutCandidate({
    required this.sourceText,
    required List<BreakCandidate> selectedCandidates,
  }) : selectedCandidates = List.unmodifiable(selectedCandidates) {
    _validateCandidates(sourceText, this.selectedCandidates);
  }

  final String sourceText;
  final List<BreakCandidate> selectedCandidates;

  /// Preserves outer whitespace and trims only selected boundary whitespace.
  /// Hard newlines delimit paragraphs and never reach [measureRange].
  LineBreakLayout measure({
    required double maxWidth,
    required TextRangeMeasurer measureRange,
  }) {
    _validateWidth(maxWidth);
    final cache = _Measurements(measureRange);
    final ranges = <TextLineRange>[];
    final selected = <BreakCandidate>[];
    for (final paragraph in _paragraphs(sourceText, selectedCandidates)) {
      var start = paragraph.start;
      for (final boundary in paragraph.boundaries) {
        if (boundary.lineEnd < start) {
          throw const InvalidBoundaryException(
            'Selected boundary whitespace overlaps a preceding line.',
          );
        }
        ranges.add(TextLineRange(start, boundary.lineEnd));
        selected.add(boundary.candidate);
        start = boundary.nextStart;
      }
      ranges.add(TextLineRange(start, paragraph.end));
    }
    return LineBreakLayout._(
      sourceText: sourceText,
      ranges: ranges,
      widths: [for (final range in ranges) cache.measure(range)],
      selectedCandidates: selected,
      maxWidth: maxWidth,
    );
  }
}

/// A measured layout whose collections and derived metrics are immutable.
final class LineBreakLayout {
  /// Accepts already measured ranges, including native adapter line ranges.
  factory LineBreakLayout({
    required String sourceText,
    required List<TextLineRange> ranges,
    required List<double> widths,
    required double maxWidth,
    List<BreakCandidate> selectedCandidates = const [],
  }) {
    _validateWidth(maxWidth);
    _validateCandidates(sourceText, selectedCandidates);
    if (ranges.isEmpty || ranges.length != widths.length) {
      throw const InvalidModelConfigurationException(
        'A layout needs at least one line and a width for each line.',
      );
    }
    final boundaries = {
      0,
      sourceText.length,
      ...allowedBoundaries(sourceText, BoundaryMode.characters),
    };
    var previousEnd = 0;
    for (final range in ranges) {
      if (range.start < previousEnd ||
          range.end < range.start ||
          !boundaries.contains(range.start) ||
          !boundaries.contains(range.end)) {
        throw const InvalidBoundaryException(
          'Measured ranges must be ordered, non-overlapping grapheme ranges.',
        );
      }
      previousEnd = range.end;
    }
    for (final width in widths) {
      _validateMeasurement(width);
    }
    return LineBreakLayout._(
      sourceText: sourceText,
      ranges: ranges,
      widths: widths,
      selectedCandidates: selectedCandidates,
      maxWidth: maxWidth,
    );
  }

  LineBreakLayout._({
    required this.sourceText,
    required List<TextLineRange> ranges,
    required List<double> widths,
    required List<BreakCandidate> selectedCandidates,
    required double maxWidth,
  }) : ranges = List.unmodifiable(ranges),
       widths = List.unmodifiable(widths),
       selectedCandidates = List.unmodifiable(selectedCandidates),
       lines = List.unmodifiable([
         for (final range in ranges)
           sourceText.substring(range.start, range.end),
       ]),
       breakOffsets = List.unmodifiable([
         for (final candidate in selectedCandidates) candidate.offset,
       ]),
       lineCount = ranges.length,
       maxLineWidth = widths.fold(0, math.max),
       imbalance = _imbalance(widths),
       totalModelCost = selectedCandidates.fold(0, (sum, c) => sum + c.penalty),
       overflow = widths.any((width) => width > maxWidth);

  final String sourceText;
  final List<TextLineRange> ranges;
  final List<String> lines;
  final List<double> widths;

  /// Inserted soft breaks only; existing hard newlines remain in [sourceText].
  final List<int> breakOffsets;
  final List<BreakCandidate> selectedCandidates;
  final int lineCount;
  final double maxLineWidth;

  /// (Widest - narrowest) / widest, or zero when every width is zero.
  final double imbalance;
  final double totalModelCost;
  final bool overflow;
}

/// An all-or-nothing calculation result suitable for widget fallback.
sealed class LayoutCalculationResult {
  const LayoutCalculationResult();
}

final class LayoutCalculationSuccess extends LayoutCalculationResult {
  LayoutCalculationSuccess(List<LineBreakLayout> layouts)
    : layouts = List.unmodifiable(layouts);

  final List<LineBreakLayout> layouts;
}

enum LayoutCalculationLimitKind { candidates, states }

/// Signals exhausted work without exposing partially calculated layouts.
final class LayoutCalculationLimit extends LayoutCalculationResult {
  const LayoutCalculationLimit({
    required this.kind,
    required this.limit,
    required this.observedCount,
  });

  final LayoutCalculationLimitKind kind;
  final int limit;
  final int observedCount;
}

/// A strategy consuming ordered prediction candidates and a range measurer.
abstract interface class LayoutCalculator {
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  });
}

/// Minimum-line dynamic programming, then model-cost/balance Pareto selection.
LayoutCalculator optimalLayouts() => const _Calculator(_Mode.optimal);

/// Chooses the furthest fitting boundary, or the next indivisible range.
LayoutCalculator greedy() => const _Calculator(_Mode.greedy);

/// Enumerates all shifts of each baseline soft break by up to [radius] candidate
/// positions within its paragraph. Defaults to a freshly calculated greedy
/// baseline. Keeps the same number of soft breaks and includes the baseline.
LayoutCalculator nearbyLayouts({int radius = 1}) {
  if (radius < 0) {
    throw const InvalidModelConfigurationException(
      'Nearby radius must be non-negative.',
    );
  }
  return _Calculator(_Mode.nearby, radius: radius);
}

enum _Mode { optimal, greedy, nearby }

final class _Calculator implements LayoutCalculator {
  const _Calculator(this.mode, {this.radius = 0});

  final _Mode mode;
  final int radius;

  @override
  LayoutCalculationResult calculate({
    required String text,
    required List<BreakCandidate> candidates,
    required double maxWidth,
    required TextRangeMeasurer measureRange,
    LineBreakLayout? baseline,
  }) {
    _validateWidth(maxWidth);
    _validateCandidates(text, candidates);
    if (candidates.length > _maxCandidateCount) {
      return LayoutCalculationLimit(
        kind: LayoutCalculationLimitKind.candidates,
        limit: _maxCandidateCount,
        observedCount: candidates.length,
      );
    }
    final budget = _Budget();
    final measurements = _Measurements(measureRange);
    try {
      final paragraphs = <_Paragraph>[];
      for (final paragraph in _paragraphs(text, candidates)) {
        budget.take();
        paragraphs.add(paragraph);
      }
      if (mode == _Mode.nearby) {
        return _nearby(
          text,
          paragraphs,
          measurements,
          budget,
          maxWidth,
          baseline,
        );
      }
      var states = <_State>[_State.empty()];
      for (final paragraph in paragraphs) {
        states = mode == _Mode.greedy
            ? [
                _greedy(
                  paragraph,
                  states.single,
                  measurements,
                  budget,
                  maxWidth,
                ),
              ]
            : _optimal(paragraph, states, measurements, budget, maxWidth);
      }
      final layouts = [
        for (final state in states) _layout(text, state, maxWidth, budget),
      ];
      return LayoutCalculationSuccess(
        mode == _Mode.optimal ? _pareto(layouts) : layouts,
      );
    } on _LimitReached {
      return const LayoutCalculationLimit(
        kind: LayoutCalculationLimitKind.states,
        limit: _maxStateCount,
        observedCount: _maxStateCount + 1,
      );
    }
  }

  LayoutCalculationResult _nearby(
    String text,
    List<_Paragraph> paragraphs,
    _Measurements measurements,
    _Budget budget,
    double maxWidth,
    LineBreakLayout? baseline,
  ) {
    if (baseline != null && baseline.sourceText != text) {
      throw const InvalidModelConfigurationException(
        'The nearby baseline must use the same source text.',
      );
    }
    if (baseline == null) {
      var state = _State.empty();
      for (final paragraph in paragraphs) {
        state = _greedy(paragraph, state, measurements, budget, maxWidth);
      }
      baseline = _layout(text, state, maxWidth, budget);
    }
    final choices = <List<BreakCandidate>>[];
    final availableOffsets = <int>{};
    final baselineOffsets = baseline.breakOffsets.toSet();
    for (final paragraph in paragraphs) {
      for (var index = 0; index < paragraph.boundaries.length; index++) {
        final boundary = paragraph.boundaries[index];
        availableOffsets.add(boundary.candidate.offset);
        if (!baselineOffsets.contains(boundary.candidate.offset)) {
          continue;
        }
        final options = <BreakCandidate>[];
        for (
          var neighbor = math.max(0, index - radius);
          neighbor <= math.min(paragraph.boundaries.length - 1, index + radius);
          neighbor++
        ) {
          budget.take();
          options.add(paragraph.boundaries[neighbor].candidate);
        }
        choices.add(options);
      }
    }
    if (!availableOffsets.containsAll(baseline.breakOffsets)) {
      throw const InvalidBoundaryException(
        'The nearby baseline must use available soft boundaries.',
      );
    }
    // Iterative enumeration avoids recursion proportional to the break count.
    var selections = <_Selection?>[null];
    for (final options in choices) {
      final next = <_Selection>[];
      for (final selection in selections) {
        for (final option in options) {
          budget.take();
          if (selection != null &&
              selection.candidate.offset >= option.offset) {
            continue;
          }
          next.add(_Selection(selection, option));
        }
      }
      selections = next;
    }
    final layouts = <LineBreakLayout>[];
    for (final selection in selections) {
      budget.take();
      final selected = <BreakCandidate>[];
      for (var cursor = selection; cursor != null; cursor = cursor.previous) {
        selected.add(cursor.candidate);
      }
      final selectedOffsets = selected
          .map((candidate) => candidate.offset)
          .toSet();
      final ranges = <TextLineRange>[];
      var valid = true;
      for (final paragraph in paragraphs) {
        var start = paragraph.start;
        for (final boundary in paragraph.boundaries) {
          if (!selectedOffsets.contains(boundary.candidate.offset)) continue;
          if (boundary.lineEnd < start) {
            valid = false;
            break;
          }
          budget.take();
          ranges.add(TextLineRange(start, boundary.lineEnd));
          start = boundary.nextStart;
        }
        if (!valid) break;
        budget.take();
        ranges.add(TextLineRange(start, paragraph.end));
      }
      if (!valid) continue;
      layouts.add(
        LineBreakLayout._(
          sourceText: text,
          ranges: ranges,
          widths: [for (final range in ranges) measurements.measure(range)],
          selectedCandidates: selected.reversed.toList(),
          maxWidth: maxWidth,
        ),
      );
    }
    return LayoutCalculationSuccess(layouts);
  }
}

List<_State> _optimal(
  _Paragraph paragraph,
  List<_State> seeds,
  _Measurements measurements,
  _Budget budget,
  double maxWidth,
) {
  final whole = TextLineRange(paragraph.start, paragraph.end);
  budget.take();
  final wholeWidth = measurements.measure(whole);
  if (wholeWidth <= maxWidth) {
    return [
      for (final seed in seeds)
        () {
          budget.take();
          return _State.extend(seed, whole, wholeWidth, null);
        }(),
    ];
  }
  final count = paragraph.boundaries.length + 1;
  final states = List.generate(count + 1, (_) => <_State>[]);
  states[0] = seeds;
  for (var end = 1; end <= count; end++) {
    for (var start = 0; start < end; start++) {
      if (states[start].isEmpty) continue;
      final range = paragraph.range(start, end);
      if (range.end < range.start) continue;
      // Charge attempted transitions, including infeasible ones: the state
      // ceiling also bounds shaping work for non-monotonic custom measurers.
      for (final previous in states[start]) {
        budget.take();
        final width = measurements.measure(range);
        if (width > maxWidth) continue;
        final state = _State.extend(
          previous,
          range,
          width,
          paragraph.candidateAt(end),
        );
        _retain(states[end], state);
      }
    }
  }
  if (states.last.isNotEmpty) return states.last;
  // No fitting path exists. Preserve content in an explicit overflowing layout.
  return [
    for (final seed in seeds)
      _greedy(paragraph, seed, measurements, budget, maxWidth),
  ];
}

_State _greedy(
  _Paragraph paragraph,
  _State state,
  _Measurements measurements,
  _Budget budget,
  double maxWidth,
) {
  final last = paragraph.boundaries.length + 1;
  var start = 0;
  while (start < last) {
    int? first;
    int? fitting;
    for (var end = start + 1; end <= last; end++) {
      budget.take();
      final range = paragraph.range(start, end);
      if (range.end < range.start) continue;
      first ??= end;
      if (measurements.measure(range) <= maxWidth) fitting = end;
    }
    final end = fitting ?? first!;
    final range = paragraph.range(start, end);
    state = _State.extend(
      state,
      range,
      measurements.measure(range),
      paragraph.candidateAt(end),
    );
    start = end;
  }
  return state;
}

void _retain(List<_State> frontier, _State state) {
  if (frontier.isNotEmpty && frontier.first.lineCount < state.lineCount) return;
  if (frontier.isNotEmpty && frontier.first.lineCount > state.lineCount) {
    frontier.clear();
  }
  // Comparing a prefix's scalar imbalance is unsafe: a future wide line can
  // reverse the ordering. Interval containment remains valid under extension.
  bool dominates(_State a, _State b) =>
      a.cost <= b.cost && a.minimum >= b.minimum && a.maximum <= b.maximum;
  if (frontier.any((other) => dominates(other, state))) return;
  frontier.removeWhere((other) => dominates(state, other));
  frontier.add(state);
}

List<LineBreakLayout> _pareto(List<LineBreakLayout> layouts) {
  final result = <LineBreakLayout>[];
  for (final layout in layouts) {
    bool dominates(LineBreakLayout a, LineBreakLayout b) =>
        a.totalModelCost <= b.totalModelCost && a.imbalance <= b.imbalance;
    if (result.any((other) => dominates(other, layout))) continue;
    result.removeWhere((other) => dominates(layout, other));
    result.add(layout);
  }
  result.sort((a, b) {
    final cost = a.totalModelCost.compareTo(b.totalModelCost);
    return cost != 0 ? cost : a.imbalance.compareTo(b.imbalance);
  });
  return result;
}

LineBreakLayout _layout(
  String text,
  _State state,
  double maxWidth,
  _Budget budget,
) {
  final ranges = <TextLineRange>[];
  final widths = <double>[];
  final selected = <BreakCandidate>[];
  for (var cursor = state; cursor.previous != null; cursor = cursor.previous!) {
    budget.take();
    ranges.add(cursor.range!);
    widths.add(cursor.width);
    if (cursor.candidate != null) selected.add(cursor.candidate!);
  }
  return LineBreakLayout._(
    sourceText: text,
    ranges: ranges.reversed.toList(),
    widths: widths.reversed.toList(),
    selectedCandidates: selected.reversed.toList(),
    maxWidth: maxWidth,
  );
}

final class _State {
  _State.empty()
    : previous = null,
      range = null,
      width = 0,
      candidate = null,
      lineCount = 0,
      cost = 0,
      minimum = double.infinity,
      maximum = 0;

  _State.extend(
    _State prior,
    TextLineRange line,
    double measured,
    BreakCandidate? boundary,
  ) : previous = prior,
      range = line,
      width = measured,
      candidate = boundary,
      lineCount = prior.lineCount + 1,
      cost = prior.cost + (boundary?.penalty ?? 0),
      minimum = math.min(prior.minimum, measured),
      maximum = math.max(prior.maximum, measured);

  final _State? previous;
  final TextLineRange? range;
  final double width;
  final BreakCandidate? candidate;
  final int lineCount;
  final double cost;
  final double minimum;
  final double maximum;
}

final class _Boundary {
  const _Boundary(this.candidate, this.lineEnd, this.nextStart);

  final BreakCandidate candidate;
  final int lineEnd;
  final int nextStart;
}

final class _Selection {
  const _Selection(this.previous, this.candidate);

  final _Selection? previous;
  final BreakCandidate candidate;
}

final class _Paragraph {
  const _Paragraph(this.start, this.end, this.boundaries);

  final int start;
  final int end;
  final List<_Boundary> boundaries;

  TextLineRange range(int from, int to) => TextLineRange(
    from == 0 ? start : boundaries[from - 1].nextStart,
    to == boundaries.length + 1 ? end : boundaries[to - 1].lineEnd,
  );

  BreakCandidate? candidateAt(int index) =>
      index == boundaries.length + 1 ? null : boundaries[index - 1].candidate;
}

Iterable<_Paragraph> _paragraphs(
  String text,
  List<BreakCandidate> candidates,
) sync* {
  var start = 0;
  var candidateIndex = 0;
  final newline = RegExp(r'\r\n|[\r\n\u2028\u2029]');
  final matches = newline.allMatches(text).iterator;
  while (true) {
    final match = matches.moveNext() ? matches.current : null;
    final end = match?.start ?? text.length;
    final selected = <BreakCandidate>[];
    while (candidateIndex < candidates.length &&
        candidates[candidateIndex].offset <= end) {
      final candidate = candidates[candidateIndex++];
      if (candidate.offset <= start || candidate.offset == end) continue;
      selected.add(candidate);
    }
    yield _Paragraph(start, end, _boundaries(text, start, end, selected));
    if (match == null) break;
    start = match.end;
  }
}

List<_Boundary> _boundaries(
  String text,
  int start,
  int end,
  List<BreakCandidate> candidates,
) {
  if (candidates.isEmpty) return const [];
  final whitespaceRuns = <(int, int)>[];
  int? runStart;
  var offset = start;
  for (final grapheme in text.substring(start, end).characters) {
    if (grapheme.trim().isEmpty) {
      runStart ??= offset;
    } else if (runStart != null) {
      whitespaceRuns.add((runStart, offset));
      runStart = null;
    }
    offset += grapheme.length;
  }
  if (runStart != null) whitespaceRuns.add((runStart, end));
  var runIndex = 0;
  final boundaries = <_Boundary>[];
  for (final candidate in candidates) {
    while (runIndex < whitespaceRuns.length &&
        whitespaceRuns[runIndex].$2 < candidate.offset) {
      runIndex++;
    }
    final run = runIndex < whitespaceRuns.length
        ? whitespaceRuns[runIndex]
        : null;
    final adjacent = run != null && run.$1 <= candidate.offset;
    boundaries.add(
      _Boundary(
        candidate,
        adjacent ? run.$1 : candidate.offset,
        adjacent ? run.$2 : candidate.offset,
      ),
    );
  }
  return boundaries;
}

final class _Measurements {
  _Measurements(this.callback);

  final TextRangeMeasurer callback;
  final Map<(int, int), double> cache = {};

  double measure(TextLineRange range) =>
      cache.putIfAbsent((range.start, range.end), () {
        final width = callback(range.start, range.end);
        _validateMeasurement(width);
        return width;
      });
}

final class _Budget {
  var count = 0;

  void take() {
    if (count == _maxStateCount) throw const _LimitReached();
    count++;
  }
}

final class _LimitReached implements Exception {
  const _LimitReached();
}

void _validateWidth(double width) {
  if (!width.isFinite || width < 0) {
    throw const InvalidModelConfigurationException(
      'Available width must be finite and non-negative.',
    );
  }
}

void _validateMeasurement(double width) {
  if (!width.isFinite || width < 0) {
    throw const TextRangeMeasurementException(
      'Measured widths must be finite and non-negative.',
    );
  }
}

void _validateCandidates(String text, List<BreakCandidate> candidates) {
  validateOffsets(text, [for (final candidate in candidates) candidate.offset]);
  for (final candidate in candidates) {
    if (!candidate.penalty.isFinite || candidate.penalty < 0) {
      throw const InvalidModelConfigurationException(
        'Candidate penalties must be finite and non-negative.',
      );
    }
  }
}

double _imbalance(List<double> widths) {
  final maximum = widths.fold<double>(0, math.max);
  if (maximum == 0) return 0;
  return (maximum - widths.reduce(math.min)) / maximum;
}
