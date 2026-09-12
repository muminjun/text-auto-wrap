// Copyright 2021 Google LLC
// Copyright 2026 Woohyun Park
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Modified by Woohyun Park in 2026 for semantic-wrap's dependency-free
// BudouX model inference.
// Modified for text_auto_wrap in 2026: Dart BoundaryPredictor adaptation,
// typed model validation, immutable maps/results, and explicit substring clamps.
// Source: https://github.com/woohyun-park/semantic-wrap
// Commit: 54ed67688aa5292f14970cae10bbabd9a11f1b5d
// Files: packages/core/src/core/budoux-parser.ts
//        packages/core/src/core/predictors.ts

import '../core/exceptions.dart';
import '../core/models.dart';

/// Dependency-free inference using BudouX-format character-feature weights.
///
/// Feature windows and output offsets use UTF-16 code units, matching upstream.
/// This raw predictor can propose word-internal or non-grapheme boundaries;
/// phrase-model adapters must restrict them to their permitted boundaries.
final class BudouxPredictor implements BoundaryPredictor {
  /// Validates and snapshots a map of string groups to string/numeric weights.
  ///
  /// Empty and unknown groups retain upstream semantics. Malformed maps and
  /// non-finite weights throw [InvalidModelConfigurationException].
  factory BudouxPredictor(Object? weights) {
    if (weights is! Map) {
      throw const InvalidModelConfigurationException(
        'BudouX weights must be a map.',
      );
    }
    final model = <String, Map<String, num>>{};
    var sum = 0.0;
    for (final entry in weights.entries) {
      final group = entry.key;
      final values = entry.value;
      if (group is! String || values is! Map) {
        throw const InvalidModelConfigurationException(
          'BudouX weight groups must have string keys and map values.',
        );
      }
      final features = <String, num>{};
      for (final entry in values.entries) {
        final feature = entry.key;
        final weight = entry.value;
        if (feature is! String || weight is! num || !weight.isFinite) {
          throw const InvalidModelConfigurationException(
            'BudouX features must have string keys and finite numeric weights.',
          );
        }
        features[feature] = weight;
        sum += weight;
      }
      model[group] = Map.unmodifiable(features);
    }
    return BudouxPredictor._(Map.unmodifiable(model), -0.5 * sum);
  }

  BudouxPredictor._(this._model, this._baseScore);

  final Map<String, Map<String, num>> _model;
  final double _baseScore;

  @override
  List<int> predict(String text) {
    final result = <int>[];
    num score(String group, int start, int end) =>
        _model[group]?[text.substring(
          start.clamp(0, text.length),
          end.clamp(0, text.length),
        )] ??
        0;

    for (var offset = 1; offset < text.length; offset++) {
      var total = _baseScore;
      total += score('UW1', offset - 3, offset - 2);
      total += score('UW2', offset - 2, offset - 1);
      total += score('UW3', offset - 1, offset);
      total += score('UW4', offset, offset + 1);
      total += score('UW5', offset + 1, offset + 2);
      total += score('UW6', offset + 2, offset + 3);
      total += score('BW1', offset - 2, offset);
      total += score('BW2', offset - 1, offset + 1);
      total += score('BW3', offset, offset + 2);
      total += score('TW1', offset - 3, offset);
      total += score('TW2', offset - 2, offset + 1);
      total += score('TW3', offset - 1, offset + 2);
      total += score('TW4', offset, offset + 3);
      if (total > 0) result.add(offset);
    }
    return List.unmodifiable(result);
  }
}
