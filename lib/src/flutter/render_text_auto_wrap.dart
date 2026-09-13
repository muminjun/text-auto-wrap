import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/diagnostics.dart';
import '../core/exceptions.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/select_text_wrap.dart';
import '../core/strategy.dart';
import '../models/language_detection.dart';
import 'controller.dart';
import 'span_codec.dart';

/// A [RenderParagraph] that chooses semantic line breaks before final layout.
///
/// The inherited paragraph remains responsible for final positioning, paint,
/// hit testing, selection, and semantics. This adapter only replaces its span
/// while it is already dirty in [performLayout], so no intermediate paragraph
/// can be painted.
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
         devicePixelRatio: devicePixelRatio,
       );

  InlineSpan _sourceText;
  TextWrapModel _model;
  LineBreakStrategy _strategy;
  TextAutoWrapController? _controller;
  TextWrapResult? _lastResult;

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
    try {
      // This is the same protected helper used by RenderParagraph. It produces
      // the dimensions required by both the source and candidate painters.
      final placeholders = layoutInlineChildren(
        constraints.maxWidth,
        ChildLayoutHelper.layoutChild,
        ChildLayoutHelper.getBaseline,
      );
      sourcePainter = _painter(_sourceText, placeholders)
        ..layout(
          minWidth: constraints.minWidth,
          maxWidth: _maxLayoutWidth(constraints.maxWidth),
        );
      final encoded = encodeInlineSpan(_sourceText);
      final nativeLayout = _nativeLayout(
        sourcePainter,
        encoded.text,
        placeholders,
        constraints.maxWidth,
      );
      final model = _resolvedModel(encoded.text);
      final result = selectTextWrap(
        TextWrapInput(
          text: encoded.text,
          model: model,
          maxWidth: constraints.maxWidth,
          nativeLayout: nativeLayout,
          maxLines: maxLines,
          measureRange: (start, end) => _measureRange(start, end, placeholders),
        ),
        strategy: _strategy,
        diagnostics: true,
      );
      final effective = result.applied
          ? insertLineBreaks(encoded, result.breakOffsets)
          : _sourceText;
      _setEffectiveText(effective);
      _commit(result);
    } catch (_) {
      // Rendering valid content wins over a semantic-layout attempt. This also
      // covers invalid custom predictions, unavailable measurements, and span
      // transformations that would discard custom InlineSpan state.
      _commitFallback(reason: 'rendererFallback');
    } finally {
      sourcePainter?.dispose();
    }
    super.performLayout();
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

  TextPainter _painter(
    InlineSpan span,
    List<PlaceholderDimensions> placeholders,
  ) => TextPainter(
    text: span,
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
    ellipsis: overflow == TextOverflow.ellipsis ? '\u2026' : null,
    locale: locale,
    strutStyle: strutStyle,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
  )..setPlaceholderDimensions(placeholders);

  LineBreakLayout _nativeLayout(
    TextPainter painter,
    String source,
    List<PlaceholderDimensions> placeholders,
    double maxWidth,
  ) {
    final ranges = <TextLineRange>[];
    var offset = 0;
    for (final _ in painter.computeLineMetrics()) {
      final range = painter.getLineBoundary(TextPosition(offset: offset));
      ranges.add(TextLineRange(range.start, range.end));
      offset = range.end;
      while (offset < source.length && _isNewline(source.codeUnitAt(offset))) {
        offset++;
      }
    }
    if (ranges.isEmpty) ranges.add(const TextLineRange(0, 0));
    return LineBreakLayout(
      sourceText: source,
      ranges: ranges,
      widths: [
        for (final range in ranges)
          _measureRange(range.start, range.end, placeholders),
      ],
      maxWidth: maxWidth,
    );
  }

  double _measureRange(
    int start,
    int end,
    List<PlaceholderDimensions> placeholders,
  ) {
    if (start == end) return 0;
    final painter = _painter(_sourceText, placeholders);
    try {
      painter.layout(maxWidth: double.infinity);
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      if (boxes.isEmpty) return 0;
      var left = double.infinity;
      var right = -double.infinity;
      for (final box in boxes) {
        left = math.min(left, box.left);
        right = math.max(right, box.right);
      }
      final width = right - left;
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

  void _setEffectiveText(InlineSpan value) {
    if (super.text.compareTo(value) == RenderComparison.identical) return;
    // RenderParagraph's public setter correctly resets its private painter,
    // semantics, overflow, and selection caches. Flutter permits this
    // synchronous render-tree mutation through the documented layout callback;
    // the object is already dirty, and the final super.performLayout below
    // consumes the updated painter before this frame can paint it.
    invokeLayoutCallback<BoxConstraints>((_) {
      super.text = value;
    });
  }

  void _commitFallback({required String reason}) {
    _setEffectiveText(_sourceText);
    final source = encodeInlineSpan(_sourceText).text;
    final width = constraints.hasBoundedWidth && constraints.maxWidth.isFinite
        ? math.max(0.0, constraints.maxWidth).toDouble()
        : 0.0;
    final layout = LineBreakLayout(
      sourceText: source,
      ranges: [TextLineRange(0, source.length)],
      widths: const [0],
      maxWidth: width,
    );
    _commit(TextWrapResult.native(layout, reason: reason));
  }

  void _commit(TextWrapResult result) {
    _lastResult = result;
    _controller?.commitResult(this, result);
  }
}

bool _isNewline(int codeUnit) =>
    codeUnit == 0x0a ||
    codeUnit == 0x0d ||
    codeUnit == 0x2028 ||
    codeUnit == 0x2029;
