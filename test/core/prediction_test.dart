import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  group('lowestPenalty', () {
    test('keeps the lowest-penalty named level for each repeated offset', () {
      final snapshot = lowestPenalty().aggregate(
        PredictionContext(
          text: 'foo bar baz',
          model: PhraseModel(
            levels: [
              PhraseModelLevel(
                name: 'precise',
                predictor: _StaticPredictor([8]),
                penalty: 1,
              ),
              PhraseModelLevel(
                name: 'preferred',
                predictor: _StaticPredictor([4]),
                penalty: 0,
              ),
              PhraseModelLevel(
                name: 'fallback-model',
                predictor: _StaticPredictor([4]),
                penalty: 2,
              ),
            ],
            fallbackPenalty: 3,
          ),
        ),
      );

      expect(snapshot.candidates.map((c) => (c.offset, c.penalty)), [
        (4, 0.0),
        (8, 1.0),
      ]);
      expect(snapshot.candidates.map((c) => c.levelName), [
        'preferred',
        'precise',
      ]);
    });

    test('adds fallback candidates for allowed offsets no level predicted', () {
      final snapshot = lowestPenalty().aggregate(
        PredictionContext(
          text: 'aa bb cc',
          model: PhraseModel(
            levels: [
              PhraseModelLevel(
                name: 'primary',
                predictor: _StaticPredictor([3]),
                penalty: 1,
              ),
            ],
            fallbackPenalty: 5,
          ),
        ),
      );

      expect(snapshot.candidates.map((c) => (c.offset, c.penalty)), [
        (3, 1.0),
        (6, 5.0),
      ]);
      expect(snapshot.candidates.last.levelName, isNull);
      expect(snapshot.candidates.last.isFallback, isTrue);
    });

    test(
      'rejects predictor offsets that violate the model boundary contract',
      () {
        final context = PredictionContext(
          text: 'aa bb',
          model: PhraseModel(
            levels: [
              PhraseModelLevel(
                name: 'invalid',
                predictor: _StaticPredictor([3, 3]),
                penalty: 1,
              ),
            ],
            fallbackPenalty: 2,
          ),
        );

        expect(
          () => lowestPenalty().aggregate(context),
          throwsA(isA<InvalidBoundaryException>()),
        );
      },
    );

    test('returns candidates in stable ascending offset order', () {
      final snapshot = lowestPenalty().aggregate(
        PredictionContext(
          text: 'aa bb cc dd',
          model: PhraseModel(
            levels: [
              PhraseModelLevel(
                name: 'later',
                predictor: _StaticPredictor([9]),
                penalty: 0,
              ),
              PhraseModelLevel(
                name: 'earlier',
                predictor: _StaticPredictor([3]),
                penalty: 2,
              ),
            ],
            fallbackPenalty: 4,
          ),
        ),
      );

      expect(snapshot.candidates.map((candidate) => candidate.offset), [
        3,
        6,
        9,
      ]);
    });
  });

  group('consensus', () {
    test(
      'retains offsets predicted by the required number of distinct levels',
      () {
        final snapshot = consensus(minimumModels: 2).aggregate(
          PredictionContext(
            text: 'aa bb cc dd',
            model: PhraseModel(
              levels: [
                PhraseModelLevel(
                  name: 'first',
                  predictor: _StaticPredictor([3, 6]),
                  penalty: 2,
                ),
                PhraseModelLevel(
                  name: 'second',
                  predictor: _StaticPredictor([3, 9]),
                  penalty: 1,
                ),
                PhraseModelLevel(
                  name: 'third',
                  predictor: _StaticPredictor([3]),
                  penalty: 0,
                ),
              ],
              fallbackPenalty: 5,
            ),
          ),
        );

        expect(snapshot.candidates.map((c) => (c.offset, c.penalty)), [
          (3, 0.0),
          (6, 5.0),
          (9, 5.0),
        ]);
        expect(snapshot.candidates.first.levelName, 'third');
        expect(snapshot.candidates.first.consensusCount, 3);
      },
    );
  });

  test('returns immutable diagnostic prediction and candidate lists', () {
    final snapshot = lowestPenalty().aggregate(
      PredictionContext(
        text: 'aa bb',
        model: PhraseModel(
          levels: [
            PhraseModelLevel(
              name: 'primary',
              predictor: _StaticPredictor([3]),
              penalty: 1,
            ),
          ],
          fallbackPenalty: 2,
        ),
      ),
    );

    expect(
      () => snapshot.candidates.add(snapshot.candidates.first),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.predictions.add(snapshot.predictions.first),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.predictions.first.offsets.add(1),
      throwsUnsupportedError,
    );
  });
}

final class _StaticPredictor implements BoundaryPredictor {
  _StaticPredictor(this._offsets);

  final List<int> _offsets;

  @override
  List<int> predict(String text) => _offsets;
}
