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

/// Encodes nested [TextSpan] and [WidgetSpan] instances without losing metadata.
EncodedInlineSpan encodeInlineSpan(InlineSpan span) {
  final buffer = StringBuffer();

  _SourceSpan visit(InlineSpan span) {
    final start = buffer.length;
    if (span is WidgetSpan) {
      buffer.write('\uFFFC');
      return _SourceSpan(span, start, buffer.length, buffer.length, const []);
    }
    if (span is! TextSpan) {
      throw ArgumentError.value(span, 'span', 'Unsupported InlineSpan type.');
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
/// Grapheme interiors and positions adjacent to existing CR/LF newlines throw
/// [InvalidBoundaryException]. Only changed text and its ancestors are cloned;
/// untouched spans and all widget children retain their identity. Every split
/// text run retains its original metadata, including semantic labels and IDs.
/// Flutter does not provide a mapping for splitting those labels by text offset.
InlineSpan insertLineBreaks(EncodedInlineSpan encoded, List<int> offsets) {
  validateOffsets(encoded.text, offsets);
  for (final offset in offsets) {
    bool isNewline(int unit) => unit == 0x0a || unit == 0x0d;
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

final class _BreakInserter {
  _BreakInserter(this.offsets);

  final List<int> offsets;
  int next = 0;

  InlineSpan rebuild(_SourceSpan source) {
    final span = source.span;
    if (span is! TextSpan) return span;
    final children = <InlineSpan>[];
    var text = span.text;
    var changed = false;
    var previous = source.start;

    while (next < offsets.length && offsets[next] < source.textEnd) {
      final offset = offsets[next++];
      final fragment = span.text!.substring(
        previous - source.start,
        offset - source.start,
      );
      if (!changed) {
        text = fragment;
      } else {
        children.add(_copyTextSpan(span, fragment, null));
      }
      children.add(const TextSpan(text: '\n'));
      changed = true;
      previous = offset;
    }
    if (changed) {
      children.add(
        _copyTextSpan(
          span,
          span.text!.substring(previous - source.start),
          null,
        ),
      );
    }

    void insertAt(int offset) {
      if (next < offsets.length &&
          offsets[next] == offset &&
          offset < source.end) {
        children.add(const TextSpan(text: '\n'));
        next++;
        changed = true;
      }
    }

    insertAt(source.textEnd);
    for (final child in source.children) {
      final rebuilt = rebuild(child);
      children.add(rebuilt);
      if (!identical(rebuilt, child.span)) changed = true;
      insertAt(child.end);
    }
    if (!changed) return span;
    return _copyTextSpan(span, text, List<InlineSpan>.unmodifiable(children));
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
