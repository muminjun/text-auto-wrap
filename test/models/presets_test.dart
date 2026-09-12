// Regression titles and preset metadata adapted from semantic-wrap,
// Copyright 2026 Woohyun Park, licensed under Apache-2.0 (see LICENSE).
// Pinned commit: 54ed67688aa5292f14970cae10bbabd9a11f1b5d.
// Sources: packages/{en,ko}/{README.md,README-ko_kr.md,MODEL_CARD.md}
// and packages/{en,ko}/tests/{en,ko}.test.ts.
// Modified for Dart: independently captured upstream predictions are projected
// from whitespace-run starts to this package's UTF-16 whitespace-run ends.

import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  // Neither pinned model card contains literal example titles. These cover all
  // titles in the published language READMEs and their frozen test regressions.
  final english = TextAutoWrapModels.english;
  final korean = TextAutoWrapModels.korean;
  final fixtures = <_Fixture>[
    (
      name: 'English published README example',
      model: english,
      text: 'Designing products people trust without slowing down delivery',
      predictions: [
        [32],
        [32],
        [19, 32],
      ],
      candidates: [
        (10, 1),
        (19, .7),
        (26, 1),
        (32, 0),
        (40, 1),
        (48, 1),
        (53, 1),
      ],
    ),
    (
      name: 'English upstream frozen title',
      model: english,
      text: 'Write headlines for readers not for internal approval',
      predictions: [
        [28],
        [6, 28],
        [16, 28],
      ],
      candidates: [
        (6, .35),
        (16, .7),
        (20, 1),
        (28, 0),
        (32, 1),
        (36, 1),
        (45, 1),
      ],
    ),
    (
      name: 'English punctuation',
      model: english,
      text: 'Write headlines, for readers: not for internal approval!',
      predictions: [
        [17, 30],
        [6, 17, 30],
        [17, 30],
      ],
      candidates: [
        (6, .35),
        (17, 0),
        (21, 1),
        (30, 0),
        (34, 1),
        (38, 1),
        (47, 1),
      ],
    ),
    (
      name: 'English explicit newline',
      model: english,
      text: 'Write headlines\nfor readers not for internal approval',
      predictions: [
        [28],
        [6, 28],
        [16, 28],
      ],
      candidates: [
        (6, .35),
        (16, .7),
        (20, 1),
        (28, 0),
        (32, 1),
        (36, 1),
        (45, 1),
      ],
    ),
    (
      name: 'English CRLF',
      model: english,
      text: 'Write headlines\r\nfor readers not for internal approval',
      predictions: [
        [29],
        [6, 29],
        [17, 29],
      ],
      candidates: [
        (6, .35),
        (17, .7),
        (21, 1),
        (29, 0),
        (33, 1),
        (37, 1),
        (46, 1),
      ],
    ),
    (
      name: 'English emoji UTF-16 offsets',
      model: english,
      text: '😀 Write headlines for readers not for internal approval',
      predictions: [
        [31],
        [9, 31],
        [19, 31],
      ],
      candidates: [
        (3, 1),
        (9, .35),
        (19, .7),
        (23, 1),
        (31, 0),
        (35, 1),
        (39, 1),
        (48, 1),
      ],
    ),
    (
      name: 'English contiguous spaces and tab',
      model: english,
      text: 'Write  headlines\tfor readers not for internal approval',
      predictions: [
        [29],
        [7, 29],
        [17, 29],
      ],
      candidates: [
        (7, .35),
        (17, .7),
        (21, 1),
        (29, 0),
        (33, 1),
        (37, 1),
        (46, 1),
      ],
    ),
    (
      name: 'Korean published README example',
      model: korean,
      text: '더 나은 사용자 경험을 만드는 방법',
      predictions: [
        [5],
        [5, 13],
        [13],
      ],
      candidates: [(2, 1), (5, 0), (9, 1), (13, .35), (17, 1)],
    ),
    (
      name: 'Korean upstream frozen title',
      model: korean,
      text: '사용자를 이해하고, 더 나은 해결책을 만드는 방법',
      predictions: [
        [],
        [21],
        [5, 11, 21],
      ],
      candidates: [(5, .7), (11, .7), (13, 1), (16, 1), (21, .35), (25, 1)],
    ),
    (
      name: 'Korean punctuation',
      model: korean,
      text: '더 나은 사용자 경험을 만드는 방법!',
      predictions: [
        [5],
        [5, 13],
        [13],
      ],
      candidates: [(2, 1), (5, 0), (9, 1), (13, .35), (17, 1)],
    ),
    (
      name: 'Korean explicit newline',
      model: korean,
      text: '사용자를 이해하고,\n더 나은 해결책을 만드는 방법',
      predictions: [
        [],
        [21],
        [5, 11, 21],
      ],
      candidates: [(5, .7), (11, .7), (13, 1), (16, 1), (21, .35), (25, 1)],
    ),
    (
      name: 'Korean CRLF',
      model: korean,
      text: '사용자를 이해하고,\r\n더 나은 해결책을 만드는 방법',
      predictions: [
        [],
        [22],
        [5, 22],
      ],
      candidates: [(5, .7), (12, 1), (14, 1), (17, 1), (22, .35), (26, 1)],
    ),
    (
      name: 'Korean emoji UTF-16 offsets',
      model: korean,
      text: '😀 더 나은 사용자 경험을 만드는 방법',
      predictions: [
        [8],
        [8, 16],
        [3, 16],
      ],
      candidates: [(3, .7), (5, 1), (8, 0), (12, 1), (16, .35), (20, 1)],
    ),
    (
      name: 'Korean contiguous spaces and tab',
      model: korean,
      text: '더  나은\t사용자 경험을 만드는 방법',
      predictions: [
        [6],
        [6, 14],
        [14],
      ],
      candidates: [(3, 1), (6, 0), (10, 1), (14, .35), (18, 1)],
    ),
  ];

  for (final fixture in fixtures) {
    test('${fixture.name}: preserves predictions and candidate penalties', () {
      final snapshot = lowestPenalty().aggregate(
        PredictionContext(text: fixture.text, model: fixture.model),
      );

      expect(
        snapshot.predictions.map((prediction) => prediction.offsets),
        fixture.predictions,
      );
      expect(
        snapshot.predictions.map(
          (prediction) => (prediction.levelName, prediction.penalty),
        ),
        [('coarse', 0.0), ('medium', .35), ('fine', .7)],
      );
      expect(
        snapshot.candidates.map(
          (candidate) => (candidate.offset, candidate.penalty),
        ),
        fixture.candidates,
      );
      for (final candidate in snapshot.candidates) {
        expect(candidate.isFallback, candidate.penalty == 1);
        expect(candidate.levelName, switch (candidate.penalty) {
          0 => 'coarse',
          .35 => 'medium',
          .7 => 'fine',
          _ => null,
        });
      }
    });
  }

  for (final (name, model) in [('English', english), ('Korean', korean)]) {
    test('$name has no word-internal or unsafe grapheme candidates', () {
      for (final text in [
        '',
        'a',
        '가',
        'unbroken',
        '띄어쓰기없이',
        '😀',
        'a😀b',
        'é👩🏽‍💻',
      ]) {
        final snapshot = lowestPenalty().aggregate(
          PredictionContext(text: text, model: model),
        );
        expect(snapshot.candidates, isEmpty, reason: text);
        expect(
          snapshot.predictions.every(
            (prediction) => prediction.offsets.isEmpty,
          ),
          isTrue,
          reason: text,
        );
      }
    });

    test('$name freezes reusable preset levels', () {
      expect(() => model.levels.clear(), throwsUnsupportedError);
      expect(model.boundaryMode, BoundaryMode.spaces);
    });

    test('$name preserves hard newlines through the core engine', () {
      const text = 'First title\r\n다음 제목\n';
      final result = selectTextWrap(
        TextWrapInput(
          text: text,
          model: model,
          maxWidth: 100,
          measureRange: (start, end) => (end - start).toDouble(),
        ),
      );

      expect(result.lines, ['First title', '다음 제목', '']);
      expect(result.sourceText, text);
    });
  }

  test('reuses the same immutable preset instances', () {
    expect(identical(english, TextAutoWrapModels.english), isTrue);
    expect(identical(korean, TextAutoWrapModels.korean), isTrue);
  });
}

typedef _Fixture = ({
  String name,
  PhraseModel model,
  String text,
  List<List<int>> predictions,
  List<(int, double)> candidates,
});
