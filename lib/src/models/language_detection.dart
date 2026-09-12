import 'dart:ui' show Locale;

import '../core/boundaries.dart';
import '../core/models.dart';
import 'budoux_parser.dart';
import 'english_model.dart';
import 'korean_model.dart';

/// Resolves the bundled Korean or English model from supported script evidence.
final class AutoTextWrapModel implements TextWrapModel {
  /// Creates the stateless automatic model selector.
  const AutoTextWrapModel();

  /// Detects a bundled phrase model for [text], optionally using [locale].
  LanguageDetectionResult resolve(String text, [Locale? locale]) =>
      detectTextWrapLanguage(text, locale);
}

/// An immutable explanation of automatic bundled-model selection.
final class LanguageDetectionResult {
  const LanguageDetectionResult._({
    required this.hangulCount,
    required this.latinCount,
    required this.hangulRatio,
    required this.model,
    required this.localeResolved,
    required this.fallbackReason,
  });

  /// Number of Hangul syllable or jamo code points found in the source text.
  final int hangulCount;

  /// Number of Latin letter code points found in the source text.
  final int latinCount;

  /// Hangul's share of all supported-letter evidence, or zero when absent.
  final double hangulRatio;

  /// The selected bundled phrase model, or null when native wrapping is used.
  final PhraseModel? model;

  /// Whether the supplied Korean or English locale selected [model].
  final bool localeResolved;

  /// A stable native-wrapping reason when [model] is null.
  final String? fallbackReason;

  /// Alias for [hangulCount] using the bundled preset's language name.
  int get koreanCount => hangulCount;

  /// Alias for [latinCount] using the bundled preset's language name.
  int get englishCount => latinCount;

  /// Alias for [hangulRatio] using the bundled preset's language name.
  double get koreanRatio => hangulRatio;

  /// Alias for [model] that makes the selected preset explicit in diagnostics.
  PhraseModel? get selectedModel => model;

  /// Alias for [localeResolved] that describes locale influence in diagnostics.
  bool get localeInfluenced => localeResolved;
}

/// Detects whether [text] has enough Korean or English evidence for a preset.
///
/// Hangul syllables and jamo, and Latin letters, are counted by Unicode code
/// point. All other code points, including punctuation, whitespace, digits,
/// combining marks, and U+FFFC inline-widget placeholders, are not evidence.
LanguageDetectionResult detectTextWrapLanguage(String text, Locale? locale) {
  var hangulCount = 0;
  var latinCount = 0;
  for (final codePoint in text.runes) {
    if (_isHangul(codePoint)) {
      hangulCount++;
    } else if (_isLatinLetter(codePoint)) {
      latinCount++;
    }
  }

  final total = hangulCount + latinCount;
  if (total == 0) {
    return const LanguageDetectionResult._(
      hangulCount: 0,
      latinCount: 0,
      hangulRatio: 0,
      model: null,
      localeResolved: false,
      fallbackReason: 'unsupportedLanguage',
    );
  }

  final hangulRatio = hangulCount / total;
  if (hangulRatio >= _dominanceThreshold) {
    return _selected(
      hangulCount: hangulCount,
      latinCount: latinCount,
      hangulRatio: hangulRatio,
      model: TextAutoWrapModels.korean,
    );
  }
  if (1 - hangulRatio >= _dominanceThreshold) {
    return _selected(
      hangulCount: hangulCount,
      latinCount: latinCount,
      hangulRatio: hangulRatio,
      model: TextAutoWrapModels.english,
    );
  }

  final languageCode = locale?.languageCode.toLowerCase();
  if (languageCode == 'ko' &&
      hangulRatio >= _localeAssistanceMinimum &&
      hangulRatio <= _localeAssistanceMaximum) {
    return _selected(
      hangulCount: hangulCount,
      latinCount: latinCount,
      hangulRatio: hangulRatio,
      model: TextAutoWrapModels.korean,
      localeResolved: true,
    );
  }
  final latinRatio = 1 - hangulRatio;
  if (languageCode == 'en' &&
      latinRatio >= _localeAssistanceMinimum &&
      latinRatio <= _localeAssistanceMaximum) {
    return _selected(
      hangulCount: hangulCount,
      latinCount: latinCount,
      hangulRatio: hangulRatio,
      model: TextAutoWrapModels.english,
      localeResolved: true,
    );
  }
  return LanguageDetectionResult._(
    hangulCount: hangulCount,
    latinCount: latinCount,
    hangulRatio: hangulRatio,
    model: null,
    localeResolved: false,
    fallbackReason: 'ambiguousLanguage',
  );
}

LanguageDetectionResult _selected({
  required int hangulCount,
  required int latinCount,
  required double hangulRatio,
  required PhraseModel model,
  bool localeResolved = false,
}) => LanguageDetectionResult._(
  hangulCount: hangulCount,
  latinCount: latinCount,
  hangulRatio: hangulRatio,
  model: model,
  localeResolved: localeResolved,
  fallbackReason: null,
);

const _dominanceThreshold = .7;
const _localeAssistanceMinimum = .4;
const _localeAssistanceMaximum = .6;

bool _isHangul(int codePoint) =>
    (codePoint >= 0xAC00 && codePoint <= 0xD7A3) ||
    (codePoint >= 0x1100 && codePoint <= 0x11FF) ||
    (codePoint >= 0x3130 && codePoint <= 0x318F) ||
    (codePoint >= 0xA960 && codePoint <= 0xA97F) ||
    (codePoint >= 0xD7B0 && codePoint <= 0xD7FF);

bool _isLatinLetter(int codePoint) =>
    (codePoint >= 0x41 && codePoint <= 0x5A) ||
    (codePoint >= 0x61 && codePoint <= 0x7A) ||
    (codePoint >= 0xC0 && codePoint <= 0xD6) ||
    (codePoint >= 0xD8 && codePoint <= 0xF6) ||
    (codePoint >= 0xF8 && codePoint <= 0x2AF) ||
    (codePoint >= 0x1D00 && codePoint <= 0x1DBF) ||
    (codePoint >= 0x1E00 && codePoint <= 0x1EFF) ||
    (codePoint >= 0x2C60 && codePoint <= 0x2C7F) ||
    (codePoint >= 0xA720 && codePoint <= 0xA7FF) ||
    (codePoint >= 0xAB30 && codePoint <= 0xAB6F) ||
    (codePoint >= 0xFB00 && codePoint <= 0xFB06);

/// Bundled experimental title presets using immutable BudouX-format weights.
///
/// Both presets use the pinned semantic-wrap model cards' coarse, medium, and
/// fine penalties (0, 0.35, 0.7), with unpredicted whitespace breaks costing 1.
abstract final class TextAutoWrapModels {
  /// Experimental Korean display-title model, initialized once on first use.
  static final PhraseModel korean = _titleModel([
    koreanTitleCoarseModel,
    koreanTitleMediumModel,
    koreanTitleFineModel,
  ]);

  /// Experimental English display-title model, initialized once on first use.
  static final PhraseModel english = _titleModel([
    englishTitleCoarseModel,
    englishTitleMediumModel,
    englishTitleFineModel,
  ]);

  /// Stateless automatic resolver for the bundled Korean and English presets.
  static const AutoTextWrapModel auto = AutoTextWrapModel();
}

PhraseModel _titleModel(List<Map<String, Map<String, num>>> weights) =>
    PhraseModel(
      levels: [
        for (var index = 0; index < weights.length; index++)
          PhraseModelLevel(
            name: const ['coarse', 'medium', 'fine'][index],
            predictor: _SpaceBoundaryPredictor(BudouxPredictor(weights[index])),
            penalty: const [0.0, 0.35, 0.7][index],
          ),
      ],
      fallbackPenalty: 1,
    );

// Upstream models score the beginning of a whitespace run. This package's
// boundary contract uses the end of that run. Keep only those source-space
// predictions, preserving the score and a legal grapheme boundary at the end.
final class _SpaceBoundaryPredictor implements BoundaryPredictor {
  _SpaceBoundaryPredictor(this._raw);

  final BudouxPredictor _raw;

  @override
  List<int> predict(String text) {
    final predicted = _raw.predict(text).toSet();
    final result = <int>[];
    for (final end in allowedBoundaries(text, BoundaryMode.spaces)) {
      var start = end;
      while (start > 0 && text.substring(start - 1, start).trim().isEmpty) {
        start--;
      }
      if (start > 0 && predicted.contains(start)) result.add(end);
    }
    return List.unmodifiable(result);
  }
}
