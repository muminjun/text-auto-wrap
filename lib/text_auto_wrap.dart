// Preset metadata: semantic-wrap, Copyright 2026 Woohyun Park, Apache-2.0.
// Source: packages/{en,ko}/MODEL_CARD.md at commit
// 54ed67688aa5292f14970cae10bbabd9a11f1b5d (see NOTICE and LICENSE).
// Modified for text_auto_wrap in 2026: lazy Dart presets and whitespace-boundary
// adapters for the immutable PhraseModel API.
library;

import 'src/core/boundaries.dart';
import 'src/core/models.dart';
import 'src/models/budoux_parser.dart';
import 'src/models/english_model.dart';
import 'src/models/korean_model.dart';

export 'src/core/boundaries.dart';
export 'src/core/exceptions.dart';
export 'src/core/layout.dart';
export 'src/core/models.dart';
export 'src/core/prediction.dart';
export 'src/core/selection.dart';
export 'src/core/strategy.dart';
export 'src/core/diagnostics.dart';
export 'src/core/plan.dart';
export 'src/core/select_text_wrap.dart';
export 'src/models/budoux_parser.dart';

const String textAutoWrapVersion = '0.1.0';

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
