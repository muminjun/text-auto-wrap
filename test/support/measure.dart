import 'package:characters/characters.dart';

/// Deterministic grapheme measurement, including an explicit placeholder width.
final class FixedRangeMeasurer {
  FixedRangeMeasurer(
    this.text, {
    this.defaultWidth = 10,
    this.placeholderWidth = 20,
    this.graphemeWidths = const {},
  });

  final String text;
  final double defaultWidth;
  final double placeholderWidth;
  final Map<String, double> graphemeWidths;
  final List<(int, int)> calls = [];

  double call(int start, int end) {
    calls.add((start, end));
    return text
        .substring(start, end)
        .characters
        .fold<double>(
          0,
          (width, grapheme) =>
              width +
              (graphemeWidths[grapheme] ??
                  (grapheme == '\uFFFC' ? placeholderWidth : defaultWidth)),
        );
  }
}
