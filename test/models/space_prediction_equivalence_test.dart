import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/core/boundaries.dart';
import 'package:text_auto_wrap/src/models/english_model.dart';
import 'package:text_auto_wrap/src/models/korean_model.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/app_phrase_samples.dart';

void main() {
  test('space-only scoring matches full BudouX inference and projection', () {
    for (final (model, weights) in [
      (
        TextAutoWrapModels.korean,
        [koreanTitleCoarseModel, koreanTitleMediumModel, koreanTitleFineModel],
      ),
      (
        TextAutoWrapModels.english,
        [
          englishTitleCoarseModel,
          englishTitleMediumModel,
          englishTitleFineModel,
        ],
      ),
    ]) {
      final raw = [for (final weight in weights) BudouxPredictor(weight)];
      for (final text in [
        ...appPhraseSamples.values.expand((v) => v),
        '',
        '  leading  and trailing  ',
        '한글\t\t영문 English\r\nnext line',
        '👩🏽‍🚀 hello e\u0301 world',
        'a\u00a0b c\u2060 d',
        '123,456.78 (test) [한글] next',
        'नमस्ते दुनिया hello',
      ]) {
        for (var level = 0; level < raw.length; level++) {
          final predicted = raw[level].predict(text).toSet();
          final expected = <int>[];
          for (final end in allowedBoundaries(text, BoundaryMode.spaces)) {
            var start = end;
            while (start > 0 &&
                isBreakableWhitespace(text.substring(start - 1, start))) {
              start--;
            }
            if (start > 0 && predicted.contains(start)) expected.add(end);
          }
          expect(
            model.levels[level].predictor.predict(text),
            expected,
            reason: '$text level $level',
          );
        }
      }
    }
  });
}
