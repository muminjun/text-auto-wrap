import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/boundaries.dart';
import '../core/exceptions.dart';

/// Source text and an occurrence-based map back to an [InlineSpan] tree.
///
/// Offsets count UTF-16 code units, with one U+FFFC per [WidgetSpan]. Semantics
/// labels do not replace source text. The original tree must not be mutated.
final class EncodedInlineSpan {
  EncodedInlineSpan._(this.text, this._source);

  final String text;
  final _SourceSpan _source;
}

/// A range-specific span and the source widget-placeholder indices it retains.
///
/// This is an internal renderer bridge. The retained span is only for
/// measurement: it preserves the original text styling but never changes the
/// source tree.
final class InlineSpanMeasurementSlice {
  const InlineSpanMeasurementSlice(this.span, this.placeholderIndices);

  final InlineSpan span;
  final List<int> placeholderIndices;
}

/// Encodes nested [TextSpan] and [WidgetSpan] instances without losing metadata.
/// Custom spans are recorded as opaque ranges and can be reused unchanged.
EncodedInlineSpan encodeInlineSpan(InlineSpan span) {
  final buffer = StringBuffer();

  _SourceSpan visit(InlineSpan span) {
    final start = buffer.length;
    if (span is WidgetSpan) {
      buffer.write('\uFFFC');
      return _SourceSpan(span, start, buffer.length, buffer.length, const []);
    }
    if (span is! TextSpan || span.runtimeType != TextSpan) {
      buffer.write(span.toPlainText(includeSemanticsLabels: false));
      return _SourceSpan(span, start, buffer.length, buffer.length, const []);
    }
    buffer.write(span.text ?? '');
    final textEnd = buffer.length;
    final children = [
      for (final child in span.children ?? const <InlineSpan>[]) visit(child),
    ];
    return _SourceSpan(span, start, textEnd, buffer.length, children);
  }

  final source = visit(span);
  return EncodedInlineSpan._(buffer.toString(), source);
}

/// Adds newline leaves at strictly ascending interior UTF-16 [offsets].
///
/// Grapheme interiors and positions adjacent to existing CR, LF, U+2028, or
/// U+2029 newlines throw [InvalidBoundaryException]. Only changed text and its
/// ancestors are cloned; untouched spans and all widget children retain their
/// identity. Breaks inside a span's own text are inserted into that string to
/// keep its semantics and gesture target intact. Boundaries between spans use
/// newline leaves. Changing a custom span or TextSpan subclass throws
/// [UnsupportedSpanTransformationException] so callers can fall back to native
/// rendering without discarding custom state.
InlineSpan insertLineBreaks(EncodedInlineSpan encoded, List<int> offsets) {
  validateOffsets(encoded.text, offsets);
  for (final offset in offsets) {
    bool isNewline(int unit) =>
        unit == 0x0a || unit == 0x0d || unit == 0x2028 || unit == 0x2029;
    if (isNewline(encoded.text.codeUnitAt(offset - 1)) ||
        isNewline(encoded.text.codeUnitAt(offset))) {
      throw InvalidBoundaryException(
        'Offset $offset is adjacent to an existing newline.',
      );
    }
  }
  if (offsets.isEmpty) return encoded._source.span;
  return _BreakInserter(offsets).rebuild(encoded._source);
}

/// Clones the styled portion of [encoded] in `[start, end)` for measurement.
///
/// Text is sliced at UTF-16 offsets. A [WidgetSpan] is retained only when its
/// single U+FFFC source unit is wholly selected; [placeholderIndices] maps the
/// retained widgets back to the public [RenderParagraph.layoutInlineChildren]
/// dimensions. Partial opaque custom spans cannot safely retain their shaping
/// or metadata and therefore use the caller's native-layout fallback.
InlineSpanMeasurementSlice sliceInlineSpanForMeasurement(
  EncodedInlineSpan encoded,
  int start,
  int end,
) {
  if (start < 0 || start >= end || end > encoded.text.length) {
    throw TextRangeMeasurementException(
      'Measurement range [$start, $end) is outside the source text.',
    );
  }
  return _MeasurementSliceBuilder(start, end).build(encoded._source);
}

// Each occurrence has its own half-open ranges and children, so shared span
// instances in different tree paths still map to distinct source positions.
final class _SourceSpan {
  const _SourceSpan(
    this.span,
    this.start,
    this.textEnd,
    this.end,
    this.children,
  );

  final InlineSpan span;
  final int start;
  final int textEnd;
  final int end;
  final List<_SourceSpan> children;
}

final class _MeasurementSliceBuilder {
  _MeasurementSliceBuilder(this.start, this.end);

  final int start;
  final int end;
  final placeholderIndices = <int>[];
  var _nextPlaceholderIndex = 0;

  InlineSpanMeasurementSlice build(_SourceSpan source) {
    final span = _slice(source);
    if (span == null) {
      throw TextRangeMeasurementException(
        'Measurement range [$start, $end) did not retain source text.',
      );
    }
    return InlineSpanMeasurementSlice(
      span,
      List<int>.unmodifiable(placeholderIndices),
    );
  }

  InlineSpan? _slice(_SourceSpan source) {
    final span = source.span;
    if (span is WidgetSpan) {
      final placeholderIndex = _nextPlaceholderIndex++;
      if (!_intersects(source)) return null;
      if (!_contains(source)) {
        throw UnsupportedSpanTransformationException(
          'Measurement range [$start, $end) splits a WidgetSpan.',
        );
      }
      placeholderIndices.add(placeholderIndex);
      return span;
    }
    if (span is! TextSpan || span.runtimeType != TextSpan) {
      if (!_intersects(source)) return null;
      if (!_contains(source)) {
        throw UnsupportedSpanTransformationException(
          'Measurement range [$start, $end) splits ${span.runtimeType}.',
        );
      }
      return span;
    }

    final textStart = math.max(start, source.start);
    final textEnd = math.min(end, source.textEnd);
    final text = textStart < textEnd
        ? span.text!.substring(textStart - source.start, textEnd - source.start)
        : null;
    final children = <InlineSpan>[];
    for (final child in source.children) {
      final sliced = _slice(child);
      if (sliced != null) children.add(sliced);
    }
    if (text == null && children.isEmpty) return null;
    return _copyTextSpan(
      span,
      text,
      children.isEmpty ? null : List<InlineSpan>.unmodifiable(children),
    );
  }

  bool _intersects(_SourceSpan source) =>
      start < source.end && end > source.start;

  bool _contains(_SourceSpan source) =>
      start <= source.start && end >= source.end;
}

final class _BreakInserter {
  _BreakInserter(this.offsets);

  final List<int> offsets;
  int next = 0;

  InlineSpan rebuild(_SourceSpan source) {
    final span = source.span;
    if (span is! TextSpan || span.runtimeType != TextSpan) {
      if (next < offsets.length &&
          offsets[next] > source.start &&
          offsets[next] < source.end) {
        throw UnsupportedSpanTransformationException(
          'A break at ${offsets[next]} would change ${span.runtimeType}.',
        );
      }
      return span;
    }
    final children = <InlineSpan>[];
    var childrenChanged = false;
    StringBuffer? rewrittenText;
    var previous = source.start;

    while (next < offsets.length && offsets[next] < source.textEnd) {
      final offset = offsets[next++];
      rewrittenText ??= StringBuffer();
      rewrittenText
        ..write(
          span.text!.substring(previous - source.start, offset - source.start),
        )
        ..write('\n');
      previous = offset;
    }
    if (rewrittenText != null) {
      rewrittenText.write(span.text!.substring(previous - source.start));
    }

    void insertAt(int offset) {
      if (next < offsets.length &&
          offsets[next] == offset &&
          offset < source.end) {
        children.add(const TextSpan(text: '\n'));
        next++;
        childrenChanged = true;
      }
    }

    insertAt(source.textEnd);
    for (final child in source.children) {
      final rebuilt = rebuild(child);
      children.add(rebuilt);
      if (!identical(rebuilt, child.span)) childrenChanged = true;
      insertAt(child.end);
    }
    if (rewrittenText == null && !childrenChanged) return span;
    return _copyTextSpan(
      span,
      rewrittenText?.toString() ?? span.text,
      childrenChanged ? List<InlineSpan>.unmodifiable(children) : span.children,
    );
  }
}

TextSpan _copyTextSpan(
  TextSpan span,
  String? text,
  List<InlineSpan>? children,
) => TextSpan(
  text: text,
  children: children,
  style: span.style,
  recognizer: span.recognizer,
  mouseCursor: span.mouseCursor,
  onEnter: span.onEnter,
  onExit: span.onExit,
  semanticsLabel: span.semanticsLabel,
  semanticsIdentifier: span.semanticsIdentifier,
  locale: span.locale,
  spellOut: span.spellOut,
);
