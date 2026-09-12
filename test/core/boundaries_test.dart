import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  group('allowedBoundaries', () {
    test('keeps emoji ZWJ sequences and combining characters indivisible', () {
      expect(allowedBoundaries('가👨‍👩‍👧‍👦é 나', BoundaryMode.characters), [
        1,
        12,
        14,
        15,
      ]);
    });

    test('returns only the end of each whitespace opportunity', () {
      expect(allowedBoundaries('가  나', BoundaryMode.spaces), [3]);
    });

    test('treats a widget placeholder as one character token', () {
      expect(allowedBoundaries('a\uFFFCb', BoundaryMode.characters), [1, 2]);
    });
  });

  group('validateOffsets', () {
    test('rejects duplicate offsets', () {
      expect(
        () => validateOffsets('abc', [1, 1]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });

    test('rejects descending offsets', () {
      expect(
        () => validateOffsets('abc', [2, 1]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });

    test('rejects text endpoints', () {
      expect(
        () => validateOffsets('ab', [0]),
        throwsA(isA<InvalidBoundaryException>()),
      );
      expect(
        () => validateOffsets('ab', [2]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });

    test('rejects a UTF-16 offset inside a surrogate pair', () {
      expect(
        () => validateOffsets('😀', [1]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    });
  });

  group('PhraseModel', () {
    test('freezes copied levels and validates its penalties', () {
      final levels = <PhraseModelLevel>[
        PhraseModelLevel(
          name: 'primary',
          predictor: _NoOpPredictor(),
          penalty: 1,
        ),
      ];

      final model = PhraseModel(levels: levels, fallbackPenalty: 2);
      levels.clear();

      expect(model.levels, hasLength(1));
      expect(
        () => model.levels.add(
          PhraseModelLevel(
            name: 'other',
            predictor: _NoOpPredictor(),
            penalty: 2,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => PhraseModel(levels: model.levels, fallbackPenalty: -1),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    });

    test('rejects empty and duplicate level names', () {
      final predictor = _NoOpPredictor();

      expect(
        () => PhraseModel(levels: const [], fallbackPenalty: 1),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
      expect(
        () => PhraseModel(
          levels: [
            PhraseModelLevel(name: '', predictor: predictor, penalty: 1),
          ],
          fallbackPenalty: 1,
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
      expect(
        () => PhraseModel(
          levels: [
            PhraseModelLevel(name: 'same', predictor: predictor, penalty: 1),
            PhraseModelLevel(name: 'same', predictor: predictor, penalty: 2),
          ],
          fallbackPenalty: 1,
        ),
        throwsA(isA<InvalidModelConfigurationException>()),
      );
    });
  });
}

final class _NoOpPredictor implements BoundaryPredictor {
  @override
  List<int> predict(String text) => const [];
}
