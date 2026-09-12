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
  if (languageCode == 'ko' && hangulRatio >= _localeAssistanceMinimum) {
    return _selected(
      hangulCount: hangulCount,
      latinCount: latinCount,
      hangulRatio: hangulRatio,
      model: TextAutoWrapModels.korean,
      localeResolved: true,
    );
  }
  final latinRatio = 1 - hangulRatio;
  if (languageCode == 'en' && latinRatio >= _localeAssistanceMinimum) {
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

// Frozen Unicode 16.0.0 intersections of Scripts.txt's Hangul/Latin entries
// with UnicodeData.txt's assigned General_Category Letter entries. Source:
// https://www.unicode.org/Public/16.0.0/ucd/{Scripts,UnicodeData}.txt
// SHA-256: Scripts.txt 9e88f0a677df47311106340be8ede2ecdacd9c1c931831218d2be6d5508e0039;
// UnicodeData.txt ff58e5823bd095166564a006e47d111130813dcf8bf234ef79fa51a870edb48f.
const _hangulLetterRanges = <(int, int)>[
  (0x1100, 0x11FF),
  (0x3131, 0x318E),
  (0xA960, 0xA97C),
  (0xAC00, 0xD7A3),
  (0xD7B0, 0xD7C6),
  (0xD7CB, 0xD7FB),
  (0xFFA0, 0xFFBE),
  (0xFFC2, 0xFFC7),
  (0xFFCA, 0xFFCF),
  (0xFFD2, 0xFFD7),
  (0xFFDA, 0xFFDC),
];

const _latinLetterRanges = <(int, int)>[
  (0x41, 0x5A),
  (0x61, 0x7A),
  (0xAA, 0xAA),
  (0xBA, 0xBA),
  (0xC0, 0xD6),
  (0xD8, 0xF6),
  (0xF8, 0x2B8),
  (0x2E0, 0x2E4),
  (0x1D00, 0x1D25),
  (0x1D2C, 0x1D5C),
  (0x1D62, 0x1D65),
  (0x1D6B, 0x1D77),
  (0x1D79, 0x1DBE),
  (0x1E00, 0x1EFF),
  (0x2071, 0x2071),
  (0x207F, 0x207F),
  (0x2090, 0x209C),
  (0x212A, 0x212B),
  (0x2132, 0x2132),
  (0x214E, 0x214E),
  (0x2183, 0x2184),
  (0x2C60, 0x2C7F),
  (0xA722, 0xA787),
  (0xA78B, 0xA7CD),
  (0xA7D0, 0xA7D1),
  (0xA7D3, 0xA7D3),
  (0xA7D5, 0xA7DC),
  (0xA7F2, 0xA7FF),
  (0xAB30, 0xAB5A),
  (0xAB5C, 0xAB64),
  (0xAB66, 0xAB69),
  (0xFB00, 0xFB06),
  (0xFF21, 0xFF3A),
  (0xFF41, 0xFF5A),
  (0x10780, 0x10785),
  (0x10787, 0x107B0),
  (0x107B2, 0x107BA),
  (0x1DF00, 0x1DF1E),
  (0x1DF25, 0x1DF2A),
];

bool _isHangul(int codePoint) =>
    _containsCodePoint(codePoint, _hangulLetterRanges);

bool _isLatinLetter(int codePoint) =>
    _containsCodePoint(codePoint, _latinLetterRanges);

bool _containsCodePoint(int codePoint, List<(int, int)> ranges) {
  for (final range in ranges) {
    if (codePoint < range.$1) return false;
    if (codePoint <= range.$2) return true;
  }
  return false;
}

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
