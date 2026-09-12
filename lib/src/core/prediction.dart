import 'boundaries.dart';
import 'models.dart';

/// The raw, validated offsets produced by one named phrase-model level.
final class BreakPrediction {
  /// Creates an immutable prediction record for a model level.
  BreakPrediction({
    required this.levelName,
    required this.penalty,
    required List<int> offsets,
  }) : offsets = List<int>.unmodifiable(offsets);

  /// The name of the model level that made this prediction.
  final String levelName;

  /// The model-level penalty associated with the predicted offsets.
  final double penalty;

  /// The validated UTF-16 offsets proposed by [levelName].
  final List<int> offsets;
}

/// One ordered candidate boundary selected for layout.
final class BreakCandidate {
  /// Creates a selected candidate boundary.
  const BreakCandidate({
    required this.offset,
    required this.penalty,
    required this.levelName,
    required this.consensusCount,
    required this.isFallback,
  });

  /// The candidate's interior UTF-16 text offset.
  final int offset;

  /// The layout cost associated with using this boundary.
  final double penalty;

  /// The selected source level, or null for a fallback candidate.
  final String? levelName;

  /// The number of distinct model levels that predicted this offset.
  final int consensusCount;

  /// Whether this candidate was supplied because no retained level predicted it.
  final bool isFallback;
}

/// The immutable prediction diagnostics and ordered candidates for one phrase.
final class PredictionSnapshot {
  /// Creates a snapshot with defensive immutable list copies.
  PredictionSnapshot({
    required List<BreakPrediction> predictions,
    required List<BreakCandidate> candidates,
  }) : predictions = List<BreakPrediction>.unmodifiable(predictions),
       candidates = List<BreakCandidate>.unmodifiable(candidates);

  /// Raw predictor output, one record for every phrase-model level.
  final List<BreakPrediction> predictions;

  /// Selected candidates in ascending UTF-16 offset order.
  final List<BreakCandidate> candidates;
}

/// Input required to produce validated predictions for a phrase.
final class PredictionContext {
  /// Creates a context for applying [model] to [text].
  const PredictionContext({required this.text, required this.model});

  /// The plain-text representation that predictors operate on.
  final String text;

  /// The configured predictor levels and boundary rules.
  final PhraseModel model;

  List<BreakPrediction> _predict() {
    return List<BreakPrediction>.unmodifiable([
      for (final level in model.levels)
        () {
          final offsets = level.predictor.predict(text);
          validateOffsets(text, offsets, mode: model.boundaryMode);
          return BreakPrediction(
            levelName: level.name,
            penalty: level.penalty,
            offsets: offsets,
          );
        }(),
    ]);
  }
}

/// A strategy that turns model predictions into layout candidates.
final class CandidateAggregator {
  const CandidateAggregator._(this._minimumModels);

  final int _minimumModels;

  /// Evaluates each model level and returns an immutable diagnostic snapshot.
  PredictionSnapshot aggregate(PredictionContext context) {
    final predictions = context._predict();
    final candidatesByOffset = <int, BreakCandidate>{};
    final countsByOffset = <int, int>{};

    for (final prediction in predictions) {
      for (final offset in prediction.offsets) {
        countsByOffset[offset] = (countsByOffset[offset] ?? 0) + 1;
      }
    }

    for (final prediction in predictions) {
      for (final offset in prediction.offsets) {
        if ((countsByOffset[offset] ?? 0) < _minimumModels) {
          continue;
        }
        final candidate = candidatesByOffset[offset];
        if (candidate == null || prediction.penalty < candidate.penalty) {
          candidatesByOffset[offset] = BreakCandidate(
            offset: offset,
            penalty: prediction.penalty,
            levelName: prediction.levelName,
            consensusCount: countsByOffset[offset]!,
            isFallback: false,
          );
        }
      }
    }

    for (final offset in allowedBoundaries(
      context.text,
      context.model.boundaryMode,
    )) {
      candidatesByOffset.putIfAbsent(
        offset,
        () => BreakCandidate(
          offset: offset,
          penalty: context.model.fallbackPenalty,
          levelName: null,
          consensusCount: 0,
          isFallback: true,
        ),
      );
    }

    final candidates = candidatesByOffset.values.toList()
      ..sort((left, right) => left.offset.compareTo(right.offset));
    return PredictionSnapshot(predictions: predictions, candidates: candidates);
  }
}

/// Keeps the lowest-penalty model candidate at every predicted offset.
CandidateAggregator lowestPenalty() => const CandidateAggregator._(1);

/// Keeps candidates predicted by at least [minimumModels] distinct levels.
CandidateAggregator consensus({required int minimumModels}) {
  if (minimumModels < 1) {
    throw ArgumentError.value(
      minimumModels,
      'minimumModels',
      'must be at least one.',
    );
  }
  return CandidateAggregator._(minimumModels);
}
