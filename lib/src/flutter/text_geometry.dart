import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import '../core/exceptions.dart';
import '../core/boundaries.dart';
import '../core/layout.dart';

/// Validates engine geometry before using it as source ranges or indices.
LineBreakLayout measureNativeTextLayout(
  TextPainter painter,
  String source,
  double maxWidth,
) {
  final ranges = <TextLineRange>[];
  final widths = <double>[];
  var offset = 0;
  var terminalLineSeen = false;
  final lineMetrics = painter.computeLineMetrics();
  for (var index = 0; index < lineMetrics.length; index++) {
    final metrics = lineMetrics[index];
    if (offset == source.length) {
      if (terminalLineSeen ||
          (ranges.isNotEmpty &&
              (source.isEmpty ||
                  !isNewline(source.codeUnitAt(source.length - 1))))) {
        throw const TextRangeMeasurementException(
          'TextPainter returned extra lines beyond the source text.',
        );
      }
      terminalLineSeen = true;
      ranges.add(TextLineRange(offset, offset));
      widths.add(normalizedFlutterWidth(metrics.width));
      continue;
    }
    var boundary = _lineBoundaryAt(painter, offset);
    if (boundary.start != offset || boundary.end < boundary.start) {
      // A line that holds one glyph wider than the available width leaves the
      // spaces that follow it outside every reported line boundary (the engine
      // answers with the previous line or with -1). Those spaces hang past the
      // line edge, so they belong to the previous line, exactly where a
      // normal soft wrap puts trailing spaces. Newlines are not absorbed:
      // delimiters stay outside ranges and keep their own validation.
      final visible = _hangingSpaceEnd(source, offset);
      if (visible > offset && ranges.isNotEmpty && ranges.last.end == offset) {
        ranges[ranges.length - 1] = TextLineRange(ranges.last.start, visible);
        offset = visible;
        if (offset == source.length) break;
        boundary = _lineBoundaryAt(painter, offset);
      }
    }
    if (boundary.start != offset ||
        boundary.end < boundary.start ||
        boundary.end > source.length) {
      throw const TextRangeMeasurementException(
        'TextPainter returned an invalid source line boundary.',
      );
    }
    final delimiterStart = metrics.hardBreak
        ? _hardBreakStart(source, boundary.start, boundary.end)
        : null;
    // Some engines include CR but exclude LF from a CRLF line boundary.
    // Strip it before the layout factory validates all grapheme endpoints.
    final end = delimiterStart ?? boundary.end;
    final nextOffset = delimiterStart == null
        ? boundary.end
        : nextLineStart(source, delimiterStart);
    ranges.add(TextLineRange(boundary.start, end));
    widths.add(normalizedFlutterWidth(metrics.width));
    offset = nextOffset;
    final truncatedTerminalLine =
        index == lineMetrics.length - 1 &&
        painter.ellipsis != null &&
        painter.didExceedMaxLines;
    if (offset == boundary.start && !truncatedTerminalLine) {
      throw const TextRangeMeasurementException(
        'TextPainter returned a line boundary without advancing.',
      );
    }
  }
  if (ranges.isEmpty) {
    if (source.isNotEmpty) {
      throw const TextRangeMeasurementException(
        'TextPainter returned no line metrics for nonempty text.',
      );
    }
    ranges.add(const TextLineRange(0, 0));
    widths.add(0);
  }
  if (offset < source.length && !painter.didExceedMaxLines) {
    throw const TextRangeMeasurementException(
      'TextPainter line metrics did not cover the source text.',
    );
  }
  try {
    // Validate graphemes once at the authoritative factory before it creates
    // substrings. Raw bounds and progress were checked before engine indexing.
    return LineBreakLayout(
      sourceText: source,
      ranges: ranges,
      widths: widths,
      maxWidth: maxWidth,
    );
  } on InvalidBoundaryException catch (error) {
    throw TextRangeMeasurementException(
      'TextPainter returned invalid grapheme ranges: ${error.message}',
    );
  }
}

// Flutter reports signed glyph advances: negative letter spacing can make
// control-only lines (or even visible text) have negative widths. Our layout
// metrics describe occupied width, whose lower bound is zero. Normalize at
// every Flutter measurement boundary, including the native fallback path.
double normalizedFlutterWidth(double width) {
  if (!width.isFinite) {
    throw const TextRangeMeasurementException(
      'TextPainter returned a non-finite width.',
    );
  }
  return width < 0 ? 0 : width;
}

TextRange _lineBoundaryAt(TextPainter painter, int offset) {
  final boundary = painter.getLineBoundary(TextPosition(offset: offset));
  if (boundary.start >= 0 &&
      boundary.start < offset &&
      boundary.end == offset) {
    // CanvasKit before Flutter PR #192664 ignores affinity and includes both
    // ends of a soft line. Query one code unit into the current line instead.
    // Upstream affinity also selects this line on engines that honor it when
    // the line is a single code unit. This correction is attempted only once.
    return painter.getLineBoundary(
      TextPosition(offset: offset + 1, affinity: TextAffinity.upstream),
    );
  }
  return boundary;
}

/// The offset of the first character at or after [offset] that is not a
/// breakable space (or [offset] itself when it starts with another character).
int _hangingSpaceEnd(String source, int offset) {
  var end = offset;
  for (final grapheme in source.substring(offset).characters) {
    if (!isBreakableWhitespace(grapheme) || grapheme.codeUnits.any(isNewline)) {
      break;
    }
    end += grapheme.length;
  }
  return end;
}

int? _hardBreakStart(String source, int lineStart, int lineEnd) {
  var offset = lineEnd;
  if (offset > lineStart && isNewline(source.codeUnitAt(offset - 1))) {
    offset--;
  }
  if (offset >= source.length || !isNewline(source.codeUnitAt(offset))) {
    return null;
  }
  if (source.codeUnitAt(offset) == 0x0a &&
      offset > lineStart &&
      source.codeUnitAt(offset - 1) == 0x0d) {
    return offset - 1;
  }
  return offset;
}

int nextLineStart(String source, int lineEnd) {
  if (lineEnd >= source.length) return lineEnd;
  final codeUnit = source.codeUnitAt(lineEnd);
  if (codeUnit == 0x0d &&
      lineEnd + 1 < source.length &&
      source.codeUnitAt(lineEnd + 1) == 0x0a) {
    return lineEnd + 2;
  }
  return isNewline(codeUnit) ? lineEnd + 1 : lineEnd;
}

bool isNewline(int codeUnit) => isHardBreak(codeUnit);
