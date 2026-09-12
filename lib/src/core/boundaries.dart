import 'package:characters/characters.dart';

import 'exceptions.dart';

/// The boundary opportunities accepted from a phrase model.
enum BoundaryMode {
  /// Every Unicode grapheme boundary is an opportunity.
  characters,

  /// Only the end of a contiguous whitespace sequence is an opportunity.
  spaces,
}

/// Returns sorted, interior UTF-16 offsets permitted by [mode].
///
/// Grapheme segmentation prevents offsets inside surrogate pairs, combining
/// sequences, emoji ZWJ sequences, and U+FFFC widget placeholders.
List<int> allowedBoundaries(String text, BoundaryMode mode) {
  final boundaries = <int>[];
  var offset = 0;
  var inWhitespace = false;

  for (final grapheme in text.characters) {
    offset += grapheme.length;
    final isWhitespace = grapheme.trim().isEmpty;

    switch (mode) {
      case BoundaryMode.characters:
        if (offset < text.length) {
          boundaries.add(offset);
        }
      case BoundaryMode.spaces:
        if (inWhitespace && !isWhitespace && offset - grapheme.length > 0) {
          boundaries.add(offset - grapheme.length);
        }
    }

    inWhitespace = isWhitespace;
  }

  return List<int>.unmodifiable(boundaries);
}

/// Ensures [offsets] are strictly ascending, interior, and legal for [mode].
void validateOffsets(
  String text,
  List<int> offsets, {
  BoundaryMode mode = BoundaryMode.characters,
}) {
  final permitted = allowedBoundaries(text, mode).toSet();
  var previous = -1;

  for (final offset in offsets) {
    if (offset <= previous) {
      throw InvalidBoundaryException(
        'Offsets must be strictly ascending; received $offset after $previous.',
      );
    }
    if (offset <= 0 || offset >= text.length) {
      throw InvalidBoundaryException(
        'Offset $offset must be inside the UTF-16 text range.',
      );
    }
    if (!permitted.contains(offset)) {
      throw InvalidBoundaryException(
        'Offset $offset is not a permitted $mode boundary.',
      );
    }
    previous = offset;
  }
}
