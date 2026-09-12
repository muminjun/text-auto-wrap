import 'boundaries.dart';
import 'exceptions.dart';

/// A configuration accepted by the text wrapping engine.
abstract interface class TextWrapModel {}

/// Predicts UTF-16 offsets at which a phrase may be broken.
abstract interface class BoundaryPredictor {
  /// Returns proposed, strictly ascending UTF-16 offsets for [text].
  List<int> predict(String text);
}

/// One named predictor priority within a [PhraseModel].
final class PhraseModelLevel {
  /// Creates an immutable predictor level with a non-negative finite penalty.
  PhraseModelLevel({
    required this.name,
    required this.predictor,
    required this.penalty,
  }) {
    if (name.isEmpty) {
      throw const InvalidModelConfigurationException(
        'Level names must not be empty.',
      );
    }
    if (!penalty.isFinite || penalty < 0) {
      throw const InvalidModelConfigurationException(
        'Level penalties must be finite and non-negative.',
      );
    }
  }

  /// A unique name for this priority level.
  final String name;

  /// The model used to produce candidate boundaries.
  final BoundaryPredictor predictor;

  /// The cost assigned to a break proposed by [predictor].
  final double penalty;
}

/// An immutable ordered set of phrase-boundary predictors.
final class PhraseModel implements TextWrapModel {
  /// Creates a phrase model and freezes its caller-provided levels.
  PhraseModel({
    required List<PhraseModelLevel> levels,
    required this.fallbackPenalty,
    this.boundaryMode = BoundaryMode.spaces,
  }) : levels = List<PhraseModelLevel>.unmodifiable(levels) {
    if (this.levels.isEmpty) {
      throw const InvalidModelConfigurationException(
        'Phrase models must contain at least one level.',
      );
    }
    if (!fallbackPenalty.isFinite || fallbackPenalty < 0) {
      throw const InvalidModelConfigurationException(
        'Fallback penalties must be finite and non-negative.',
      );
    }

    final names = <String>{};
    for (final level in this.levels) {
      if (!names.add(level.name)) {
        throw const InvalidModelConfigurationException(
          'Phrase model level names must be unique.',
        );
      }
    }
  }

  /// Ordered, immutable predictor levels.
  final List<PhraseModelLevel> levels;

  /// The penalty assigned to legal boundaries no level predicted.
  final double fallbackPenalty;

  /// The set of candidate boundaries that predictors may return.
  final BoundaryMode boundaryMode;
}
