import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/diagnostics.dart';
import '../core/exceptions.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/plan.dart';
import '../core/selection.dart';
import '../core/strategy.dart';
import '../models/language_detection.dart';
import 'controller.dart';
import 'span_codec.dart';

/// A [RenderParagraph] that chooses semantic line breaks before final layout.
///
/// The inherited paragraph remains responsible for final positioning, paint,
/// hit testing, selection, and semantics. This adapter restores source text
/// when inputs change and commits the selected span during [performLayout],
/// before any intermediate paragraph can be painted.
class RenderTextAutoWrap extends RenderParagraph {
  RenderTextAutoWrap({
    required InlineSpan sourceText,
    required TextWrapModel model,
    required LineBreakStrategy strategy,
    TextAutoWrapController? controller,
    TextAlign textAlign = TextAlign.start,
    required TextDirection textDirection,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    TextScaler textScaler = TextScaler.noScaling,
    int? maxLines,
    Locale? locale,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    TextHeightBehavior? textHeightBehavior,
    List<RenderBox>? children,
    Color? selectionColor,
    SelectionRegistrar? registrar,
    double devicePixelRatio = 1.0,
  }) : _sourceText = sourceText,
       _model = model,
       _strategy = strategy,
       _controller = controller,
       _devicePixelRatio = devicePixelRatio,
       _effectiveTextKey = _InlineSpanCacheKey(sourceText),
       super(
         sourceText,
         textAlign: textAlign,
         textDirection: textDirection,
         softWrap: softWrap,
         overflow: overflow,
         textScaler: textScaler,
         maxLines: maxLines,
         locale: locale,
         strutStyle: strutStyle,
         textWidthBasis: textWidthBasis,
         textHeightBehavior: textHeightBehavior,
         children: children,
         selectionColor: selectionColor,
         registrar: registrar,
       );

  InlineSpan _sourceText;
  TextWrapModel _model;
  LineBreakStrategy _strategy;
  TextAutoWrapController? _controller;
  TextWrapResult? _lastResult;
  TextWrapPlan? _cachedPlan;
  _RendererPlanKey? _cachedPlanKey;
  _RendererSelectionKey? _cachedSelectionKey;
  TextWrapResult? _cachedSelection;
  _InlineSpanCacheKey _effectiveTextKey;
  double _devicePixelRatio;
  var _planHits = 0;
  var _planMisses = 0;
  var _selectionCacheHits = 0;
  var _selectionCacheMisses = 0;

  // ignore: annotate_overrides
  double get devicePixelRatio => _devicePixelRatio;

  // ignore: annotate_overrides
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    if (kIsWeb) markNeedsPaint();
  }

  /// The unmodified span supplied by the widget.
  InlineSpan get sourceText => _sourceText;

  /// The span committed before the current paragraph's final layout.
  @visibleForTesting
  InlineSpan get effectiveText => super.text;

  /// The most recent selection made by this renderer, including fallback.
  @visibleForTesting
  TextWrapResult? get result => _lastResult;

  set sourceText(InlineSpan value) {
    if (identical(_sourceText, value)) return;
    _sourceText = value;
    // Parents can request intrinsic/dry sizes before performLayout. Restore
    // the current source in Flutter's painters before they choose constraints.
    _replaceParagraphText(value);
    markNeedsLayout();
  }

  set model(TextWrapModel value) {
    if (identical(_model, value)) return;
    _model = value;
    markNeedsLayout();
  }

  set strategy(LineBreakStrategy value) {
    if (identical(_strategy, value)) return;
    _strategy = value;
    markNeedsLayout();
  }

  set controller(TextAutoWrapController? value) {
    if (identical(_controller, value)) return;
    _controller?.detachOwner(this);
    _controller = value;
    final result = _lastResult;
    if (result != null) _controller?.commitResult(this, result);
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    if (!constraints.hasBoundedWidth ||
        !constraints.maxWidth.isFinite ||
        constraints.maxWidth <= 0 ||
        !softWrap) {
      _commitFallback(reason: softWrap ? 'unusableWidth' : 'softWrapDisabled');
      super.performLayout();
      return;
    }

    TextPainter? sourcePainter;
    LineBreakLayout? nativeLayout;
    try {
      final encoded = encodeInlineSpan(_sourceText);
      late final List<PlaceholderDimensions> placeholders;
      try {
        placeholders = _layoutPlaceholders(
          encoded.placeholderSpans,
          constraints.maxWidth,
        );
      } on UnsupportedSpanTransformationException {
        // An opaque custom span with a widget descendant cannot be indexed for
        // candidate measurement. Preserve its real native source layout for
        // the fallback result, without entering the transform path.
        final nativePlaceholders = _layoutPlaceholdersForNativeFallback(
          constraints.maxWidth,
        );
        sourcePainter = _painter(_sourceText, nativePlaceholders)
          ..layout(
            minWidth: constraints.minWidth,
            maxWidth: _maxLayoutWidth(constraints.maxWidth),
          );
        nativeLayout = _nativeLayout(
          sourcePainter,
          encoded.text,
          constraints.maxWidth,
        );
        rethrow;
      }
      final model = _resolvedModel(encoded.text);
      final planKey = _RendererPlanKey(
        text: encoded.text,
        model: model,
        strategy: _strategy,
      );
      final measurementKey = _RendererMeasurementKey(
        source: _sourceText,
        maxWidth: constraints.maxWidth,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        placeholders: _PlaceholderCacheKey(placeholders),
      );
      final selectionKey = _RendererSelectionKey(
        plan: planKey,
        measurement: measurementKey,
        minWidth: constraints.minWidth,
        textAlign: textAlign,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
      );
      final cached = _cachedSelection;
      if (_cachedSelectionKey == selectionKey && cached != null) {
        _selectionCacheHits++;
        _commitSelection(encoded, _withRendererCache(cached), placeholders);
      } else {
        _selectionCacheMisses++;
        sourcePainter = _painter(_sourceText, placeholders)
          ..layout(
            minWidth: constraints.minWidth,
            maxWidth: _maxLayoutWidth(constraints.maxWidth),
          );
        nativeLayout = _nativeLayout(
          sourcePainter,
          encoded.text,
          constraints.maxWidth,
        );
        final result = _planFor(planKey).select(
          maxWidth: constraints.maxWidth,
          nativeLayout: nativeLayout,
          maxLines: maxLines,
          measureRange: (start, end) =>
              _measureRange(encoded, start, end, placeholders),
          measurementCacheKey: measurementKey,
          diagnostics: true,
        );
        _cachedSelectionKey = selectionKey;
        _cachedSelection = result;
        _commitSelection(encoded, _withRendererCache(result), placeholders);
      }
    } catch (error) {
      // Rendering valid content wins over a semantic-layout attempt. This also
      // covers invalid custom predictions, unavailable measurements, and span
      // transformations that would discard custom InlineSpan state.
      _commitFallback(
        reason: _fallbackReason(error),
        nativeLayout: nativeLayout,
      );
    } finally {
      sourcePainter?.dispose();
    }
    super.performLayout();
  }

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    // A plan owns shaped range widths, and a cached selection owns the
    // resulting native geometry. Neither remains valid after font metrics
    // change, even when every public render input is unchanged.
    _cachedPlan = null;
    _cachedPlanKey = null;
    _cachedSelection = null;
    _cachedSelectionKey = null;
  }

  @override
  void detach() {
    _controller?.detachOwner(this);
    super.detach();
  }

  @override
  void dispose() {
    _controller?.detachOwner(this);
    super.dispose();
  }

  PhraseModel? _resolvedModel(String text) {
    final model = _model;
    return switch (model) {
      PhraseModel() => model,
      AutoTextWrapModel() => model.resolve(text, locale).model,
      _ => null,
    };
  }

  List<PlaceholderDimensions> _layoutPlaceholders(
    List<WidgetSpan> spans,
    double maxWidth,
  ) {
    // Validate the encoded occurrences before Flutter dereferences a child's
    // parent-data span or its required baseline type inside the layout helper.
    if (spans.length != childCount) {
      throw const _UnmeasurablePlaceholder();
    }
    final children = <RenderBox>[];
    var child = firstChild;
    for (final span in spans) {
      final parentData = child?.parentData;
      final needsBaseline = switch (span.alignment) {
        PlaceholderAlignment.baseline ||
        PlaceholderAlignment.aboveBaseline ||
        PlaceholderAlignment.belowBaseline => true,
        _ => false,
      };
      if (child == null ||
          parentData is! TextParentData ||
          !identical(parentData.span, span) ||
          (needsBaseline && span.baseline == null)) {
        throw const _UnmeasurablePlaceholder();
      }
      children.add(child);
      child = childAfter(child);
    }

    // Flutter's helper measures the children in logical span order, including
    // WidgetSpan's native nonlinear scale and real baseline. Keep the complete
    // dimensions for the source painter and the codec's indexed range slices.
    final dimensions = layoutInlineChildren(
      maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    if (dimensions.length != children.length || childCount != children.length) {
      throw const _UnmeasurablePlaceholder();
    }
    child = firstChild;
    for (var index = 0; index < dimensions.length; index++) {
      final dimension = dimensions[index];
      final span = spans[index];
      final parentData = child?.parentData;
      final baselineOffset = dimension.baselineOffset;
      if (!identical(child, children[index]) ||
          parentData is! TextParentData ||
          !identical(parentData.span, span) ||
          dimension.alignment != span.alignment ||
          dimension.baseline != span.baseline ||
          !dimension.size.isFinite ||
          dimension.size.width < 0 ||
          dimension.size.height < 0 ||
          dimension.size != child!.size ||
          (dimension.alignment == PlaceholderAlignment.baseline &&
              (dimension.baseline == null || baselineOffset == null)) ||
          (baselineOffset != null && !baselineOffset.isFinite)) {
        throw const _UnmeasurablePlaceholder();
      }
      final nativeBaseline =
          dimension.alignment == PlaceholderAlignment.baseline
          ? ChildLayoutHelper.getBaseline(
              child,
              child.constraints,
              dimension.baseline!,
            )
          : null;
      if (baselineOffset != nativeBaseline) {
        throw const _UnmeasurablePlaceholder();
      }
      child = childAfter(child);
    }
    return dimensions;
  }

  List<PlaceholderDimensions> _layoutPlaceholdersForNativeFallback(
    double maxWidth,
  ) => layoutInlineChildren(
    maxWidth,
    ChildLayoutHelper.layoutChild,
    ChildLayoutHelper.getBaseline,
  );

  TextPainter _painter(
    InlineSpan span,
    List<PlaceholderDimensions> placeholders, {
    bool finalLayout = true,
  }) => TextPainter(
    text: span,
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: finalLayout ? maxLines : null,
    ellipsis: finalLayout && overflow == TextOverflow.ellipsis
        ? '\u2026'
        : null,
    locale: locale,
    strutStyle: strutStyle,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
  )..setPlaceholderDimensions(placeholders);

  LineBreakLayout _nativeLayout(
    TextPainter painter,
    String source,
    double maxWidth,
  ) {
    final ranges = <TextLineRange>[];
    final widths = <double>[];
    var offset = 0;
    for (final metrics in painter.computeLineMetrics()) {
      if (offset == source.length) {
        ranges.add(TextLineRange(offset, offset));
        widths.add(metrics.width);
        continue;
      }
      final boundary = painter.getLineBoundary(TextPosition(offset: offset));
      final delimiterStart = metrics.hardBreak
          ? _hardBreakStart(source, boundary.start, boundary.end)
          : null;
      ranges.add(TextLineRange(boundary.start, delimiterStart ?? boundary.end));
      widths.add(metrics.width);
      offset = delimiterStart == null
          ? boundary.end
          : _nextLineStart(source, delimiterStart);
    }
    if (ranges.isEmpty) {
      ranges.add(const TextLineRange(0, 0));
      widths.add(0);
    }
    return LineBreakLayout(
      sourceText: source,
      ranges: ranges,
      widths: widths,
      maxWidth: maxWidth,
    );
  }

  double _measureRange(
    EncodedInlineSpan encoded,
    int start,
    int end,
    List<PlaceholderDimensions> placeholders,
  ) {
    if (start == end) return 0;
    final slice = sliceInlineSpanForMeasurement(encoded, start, end);
    final dimensions = [
      for (final index in slice.placeholderIndices)
        if (index < placeholders.length)
          placeholders[index]
        else
          throw const TextRangeMeasurementException(
            'Missing WidgetSpan dimensions.',
          ),
    ];
    final painter = _painter(slice.span, dimensions, finalLayout: false);
    try {
      painter.layout(maxWidth: double.infinity);
      final width = painter.width;
      if (!width.isFinite || width < 0) {
        throw TextRangeMeasurementException(
          'TextPainter returned an invalid range width.',
        );
      }
      return width;
    } finally {
      painter.dispose();
    }
  }

  double _maxLayoutWidth(double maxWidth) =>
      softWrap || overflow == TextOverflow.ellipsis
      ? maxWidth
      : double.infinity;

  TextWrapPlan _planFor(_RendererPlanKey key) {
    final plan = _cachedPlan;
    if (_cachedPlanKey == key && plan != null) {
      _planHits++;
      return plan;
    }
    _planMisses++;
    final created = createTextWrapPlan(
      text: key.text,
      model: key.model,
      strategy: key.strategy,
    );
    _cachedPlanKey = key;
    _cachedPlan = created;
    return created;
  }

  void _commitSelection(
    EncodedInlineSpan encoded,
    TextWrapResult result,
    List<PlaceholderDimensions> placeholders,
  ) {
    final effective = result.applied
        ? insertLineBreaks(encoded, result.breakOffsets)
        : _sourceText;
    var matches = true;
    if (result.applied) {
      // Range measurement trims boundary whitespace, but the source-preserving
      // transformation retains it. Shaping that effective paragraph can create
      // extra lines or retain whitespace absent from selected source ranges.
      // Validate both source coverage and geometry before committing it.
      final painter = _painter(effective, placeholders, finalLayout: false);
      try {
        painter.layout(
          minWidth: constraints.minWidth,
          maxWidth: _maxLayoutWidth(constraints.maxWidth),
        );
        final lines = painter.computeLineMetrics();
        matches =
            _matchesSelectedLines(effective, result) &&
            lines.length == result.lineCount &&
            !List.generate(lines.length, (index) => index).any(
              (index) =>
                  (lines[index].width - result.widths[index]).abs() > 0.001,
            );
      } finally {
        painter.dispose();
      }
    } else if (result.source == TextWrapSelectionSource.calculated) {
      // A calculated selection may reuse native offsets without inserting any
      // breaks. Its trimmed ranges must still match the native text we paint.
      final native = result.diagnostics?.nativeLayout ?? _fallbackLayout();
      matches = native.lineCount == result.lineCount;
      for (var index = 0; matches && index < native.lineCount; index++) {
        matches =
            native.ranges[index].start == result.ranges[index].start &&
            native.ranges[index].end == result.ranges[index].end &&
            native.lines[index] == result.lines[index] &&
            (native.widths[index] - result.widths[index]).abs() <= 0.001;
      }
    }
    if (!matches) {
      _commitFallback(
        reason: 'invalidRuntimeMeasurement',
        nativeLayout: result.diagnostics?.nativeLayout,
        diagnostics: result.diagnostics,
      );
      return;
    }
    _setEffectiveText(effective);
    _commit(result);
  }

  bool _matchesSelectedLines(InlineSpan effective, TextWrapResult result) {
    final text = effective.toPlainText(includeSemanticsLabels: false);
    var inserted = 0;
    int sourceOffset(int effectiveOffset) {
      while (inserted < result.breakOffsets.length &&
          result.breakOffsets[inserted] + inserted < effectiveOffset) {
        inserted++;
      }
      return effectiveOffset - inserted;
    }

    // Each calculated line has an explicit separator in the effective tree.
    // Include trailing whitespace even when TextPainter's boundaries omit it.
    // The separate painted-line count check rejects extra native soft wraps.
    var line = 0;
    var start = 0;
    for (var end = 0; end <= text.length; end++) {
      if (end != text.length && !_isNewline(text.codeUnitAt(end))) continue;
      if (line >= result.lineCount) return false;
      final range = result.ranges[line];
      final sourceStart = sourceOffset(start);
      final sourceEnd = sourceOffset(end);
      if (sourceStart != range.start ||
          sourceEnd != range.end ||
          text.substring(start, end) != result.lines[line]) {
        return false;
      }
      line++;
      if (end == text.length) break;
      start = _nextLineStart(text, end);
      end = start - 1;
    }
    return line == result.lineCount;
  }

  TextWrapResult _withRendererCache(TextWrapResult result) {
    final diagnostics = result.diagnostics;
    if (diagnostics == null) return result;
    return TextWrapResult(
      layout: result.layout,
      applied: result.applied,
      reason: result.reason,
      source: result.source,
      diagnostics: TextWrapDiagnostics(
        predictions: diagnostics.predictions,
        candidates: diagnostics.candidates,
        calculatedLayouts: diagnostics.calculatedLayouts,
        nativeLayout: diagnostics.nativeLayout,
        selection: diagnostics.selection,
        calculationLimit: diagnostics.calculationLimit,
        cache: diagnostics.cache.copyWith(
          planHits: _planHits,
          planMisses: _planMisses,
          selectionCacheHits: _selectionCacheHits,
          selectionCacheMisses: _selectionCacheMisses,
        ),
      ),
    );
  }

  void _setEffectiveText(InlineSpan value) {
    final key = _InlineSpanCacheKey(value);
    if (_effectiveTextKey == key) return;
    // RenderParagraph's public setter correctly resets its private painter,
    // semantics, overflow, and selection caches. Flutter permits this
    // synchronous render-tree mutation through the documented layout callback;
    // the object is already dirty, and the final super.performLayout below
    // consumes the updated painter before this frame can paint it.
    invokeLayoutCallback<BoxConstraints>((_) {
      _replaceParagraphText(value);
    });
  }

  void _replaceParagraphText(InlineSpan value) {
    final key = _InlineSpanCacheKey(value);
    if (_effectiveTextKey == key) return;
    // TextSpan.compareTo omits locale/spellOut, which affect semantics and
    // shaping. Force an otherwise comparison-identical replacement through.
    if (super.text.compareTo(value) == RenderComparison.identical) {
      super.text = _metadataResetSpan(super.text);
    }
    super.text = value;
    _effectiveTextKey = key;
  }

  void _commitFallback({
    required String reason,
    LineBreakLayout? nativeLayout,
    TextWrapDiagnostics? diagnostics,
  }) {
    _setEffectiveText(_sourceText);
    final layout = nativeLayout ?? _fallbackLayout();
    _commit(
      TextWrapResult(
        layout: layout,
        applied: false,
        reason: reason,
        source: TextWrapSelectionSource.native,
        diagnostics: diagnostics == null
            ? null
            : TextWrapDiagnostics(
                predictions: diagnostics.predictions,
                candidates: diagnostics.candidates,
                calculatedLayouts: diagnostics.calculatedLayouts,
                nativeLayout: layout,
                selection: LayoutSelectionDecision.native(reason: reason),
                cache: diagnostics.cache,
                calculationLimit: diagnostics.calculationLimit,
              ),
      ),
    );
  }

  LineBreakLayout _fallbackLayout() {
    final source = encodeInlineSpan(_sourceText).text;
    // Semantic placeholder validation is intentionally stricter than Flutter's
    // native path (for example, native layout permits a missing real baseline).
    final placeholders = super.layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    final painter = _painter(_sourceText, placeholders);
    try {
      painter.layout(
        minWidth: constraints.minWidth,
        maxWidth: _maxLayoutWidth(constraints.maxWidth),
      );
      return _nativeLayout(
        painter,
        source,
        constraints.maxWidth.isFinite ? constraints.maxWidth : painter.width,
      );
    } finally {
      painter.dispose();
    }
  }

  void _commit(TextWrapResult result) {
    _lastResult = result;
    _controller?.commitResult(this, result);
  }
}

String _fallbackReason(Object error) => switch (error) {
  _UnmeasurablePlaceholder() => 'unmeasurablePlaceholder',
  UnsupportedSpanTransformationException() => 'unsupportedSpanTransformation',
  TextRangeMeasurementException() => 'invalidRuntimeMeasurement',
  _ => 'rendererFallback',
};

final class _UnmeasurablePlaceholder implements Exception {
  const _UnmeasurablePlaceholder();
}

final class _RendererPlanKey {
  const _RendererPlanKey({
    required this.text,
    required this.model,
    required this.strategy,
  });

  final String text;
  final PhraseModel? model;
  final LineBreakStrategy strategy;

  @override
  bool operator ==(Object other) =>
      other is _RendererPlanKey &&
      text == other.text &&
      _sameModel(model, other.model) &&
      _sameStrategy(strategy, other.strategy);

  @override
  int get hashCode =>
      Object.hash(text, _modelHash(model), _strategyHash(strategy));
}

bool _sameModel(PhraseModel? left, PhraseModel? right) {
  if (identical(left, right)) return true;
  if (left == null ||
      right == null ||
      left.boundaryMode != right.boundaryMode ||
      left.fallbackPenalty != right.fallbackPenalty ||
      left.levels.length != right.levels.length) {
    return false;
  }
  for (var index = 0; index < left.levels.length; index++) {
    final leftLevel = left.levels[index];
    final rightLevel = right.levels[index];
    if (leftLevel.name != rightLevel.name ||
        leftLevel.penalty != rightLevel.penalty ||
        leftLevel.predictor != rightLevel.predictor) {
      return false;
    }
  }
  return true;
}

int _modelHash(PhraseModel? model) => model == null
    ? 0
    : Object.hash(
        model.boundaryMode,
        model.fallbackPenalty,
        Object.hashAll([
          for (final level in model.levels)
            (level.name, level.penalty, level.predictor),
        ]),
      );

bool _sameStrategy(LineBreakStrategy left, LineBreakStrategy right) =>
    identical(left, right) ||
    (left.aggregator == right.aggregator &&
        left.calculator == right.calculator &&
        left.selector == right.selector);

int _strategyHash(LineBreakStrategy strategy) =>
    Object.hash(strategy.aggregator, strategy.calculator, strategy.selector);

final class _RendererMeasurementKey {
  _RendererMeasurementKey({
    required InlineSpan source,
    required this.maxWidth,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.strutStyle,
    required this.textWidthBasis,
    required this.textHeightBehavior,
    required this.placeholders,
  }) : source = _InlineSpanCacheKey(source);

  final _InlineSpanCacheKey source;
  final double maxWidth;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final _PlaceholderCacheKey placeholders;

  @override
  bool operator ==(Object other) =>
      other is _RendererMeasurementKey &&
      source == other.source &&
      maxWidth == other.maxWidth &&
      textDirection == other.textDirection &&
      textScaler == other.textScaler &&
      locale == other.locale &&
      strutStyle == other.strutStyle &&
      textWidthBasis == other.textWidthBasis &&
      textHeightBehavior == other.textHeightBehavior &&
      placeholders == other.placeholders;

  @override
  int get hashCode => Object.hash(
    source,
    maxWidth,
    textDirection,
    textScaler,
    locale,
    strutStyle,
    textWidthBasis,
    textHeightBehavior,
    placeholders,
  );
}

/// Full span-tree equality for cache and committed-text decisions.
///
/// Flutter's [TextSpan] equality and [TextSpan.compareTo] intentionally omit
/// locale and spellOut. They are nevertheless part of this renderer's shaped
/// text and semantics contract, including when inherited by nested spans.
final class _InlineSpanCacheKey {
  const _InlineSpanCacheKey(this.span);

  final InlineSpan span;

  @override
  bool operator ==(Object other) =>
      other is _InlineSpanCacheKey && _sameInlineSpan(span, other.span);

  @override
  int get hashCode => _inlineSpanHash(span);
}

bool _sameInlineSpan(InlineSpan left, InlineSpan right) {
  if (identical(left, right)) return true;
  if (left.runtimeType != right.runtimeType || left != right) return false;
  if (left is! TextSpan || right is! TextSpan) return true;
  if (left.locale != right.locale || left.spellOut != right.spellOut) {
    return false;
  }
  final leftChildren = left.children ?? const <InlineSpan>[];
  final rightChildren = right.children ?? const <InlineSpan>[];
  if (leftChildren.length != rightChildren.length) return false;
  for (var index = 0; index < leftChildren.length; index++) {
    if (!_sameInlineSpan(leftChildren[index], rightChildren[index])) {
      return false;
    }
  }
  return true;
}

int _inlineSpanHash(InlineSpan span) {
  if (span is! TextSpan) return Object.hash(span.runtimeType, span);
  return Object.hash(
    span.runtimeType,
    span,
    span.locale,
    span.spellOut,
    Object.hashAll([
      for (final child in span.children ?? const <InlineSpan>[])
        _inlineSpanHash(child),
    ]),
  );
}

InlineSpan _metadataResetSpan(InlineSpan current) {
  const first = TextSpan(text: '\u0000');
  const second = TextSpan(text: '\u0001');
  return current.compareTo(first) == RenderComparison.identical
      ? second
      : first;
}

final class _RendererSelectionKey {
  const _RendererSelectionKey({
    required this.plan,
    required this.measurement,
    required this.minWidth,
    required this.textAlign,
    required this.softWrap,
    required this.overflow,
    required this.maxLines,
  });

  final _RendererPlanKey plan;
  final _RendererMeasurementKey measurement;
  final double minWidth;
  final TextAlign textAlign;
  final bool softWrap;
  final TextOverflow overflow;
  final int? maxLines;

  @override
  bool operator ==(Object other) =>
      other is _RendererSelectionKey &&
      plan == other.plan &&
      measurement == other.measurement &&
      minWidth == other.minWidth &&
      textAlign == other.textAlign &&
      softWrap == other.softWrap &&
      overflow == other.overflow &&
      maxLines == other.maxLines;

  @override
  int get hashCode => Object.hash(
    plan,
    measurement,
    minWidth,
    textAlign,
    softWrap,
    overflow,
    maxLines,
  );
}

final class _PlaceholderCacheKey {
  _PlaceholderCacheKey(List<PlaceholderDimensions> dimensions)
    : dimensions = List.unmodifiable([
        for (final dimension in dimensions)
          (
            dimension.size,
            dimension.alignment,
            dimension.baseline,
            dimension.baselineOffset,
          ),
      ]);

  final List<(Size, PlaceholderAlignment, TextBaseline?, double?)> dimensions;

  @override
  bool operator ==(Object other) {
    if (other is! _PlaceholderCacheKey ||
        dimensions.length != other.dimensions.length) {
      return false;
    }
    for (var index = 0; index < dimensions.length; index++) {
      if (dimensions[index] != other.dimensions[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(dimensions);
}

int? _hardBreakStart(String source, int lineStart, int lineEnd) {
  var offset = lineEnd;
  if (offset > lineStart && _isNewline(source.codeUnitAt(offset - 1))) {
    offset--;
  }
  if (offset >= source.length || !_isNewline(source.codeUnitAt(offset))) {
    return null;
  }
  if (source.codeUnitAt(offset) == 0x0a &&
      offset > lineStart &&
      source.codeUnitAt(offset - 1) == 0x0d) {
    return offset - 1;
  }
  return offset;
}

int _nextLineStart(String source, int lineEnd) {
  if (lineEnd >= source.length) return lineEnd;
  final codeUnit = source.codeUnitAt(lineEnd);
  if (codeUnit == 0x0d &&
      lineEnd + 1 < source.length &&
      source.codeUnitAt(lineEnd + 1) == 0x0a) {
    return lineEnd + 2;
  }
  return _isNewline(codeUnit) ? lineEnd + 1 : lineEnd;
}

bool _isNewline(int codeUnit) =>
    codeUnit == 0x0a ||
    codeUnit == 0x0d ||
    codeUnit == 0x2028 ||
    codeUnit == 0x2029;
