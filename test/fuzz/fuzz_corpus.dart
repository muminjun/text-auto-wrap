import 'dart:math';

import 'ko_phrases.dart';

/// Atoms covering the Unicode classes that can make an engine report a line
/// boundary inside a grapheme: zero-width, combining, ZWJ, variation
/// selectors, surrogate pairs, decomposed Hangul, hard breaks and bidi marks.
/// Lone surrogates are excluded because the engine rejects them up front.
const fuzzAtoms = <String>[
  'a',
  'English ',
  '한글',
  '한',
  // Decomposed (conjoining) Hangul jamo: L + V + T.
  '한',
  '하',
  // Hangul syllable + trailing jamo T.
  '각',
  'العربية',
  'עברית',
  'e\u0301',
  '\u0301',
  'a\u0301\u0302\u0303',
  'กำ', // Thai with SARA AM
  'क\u094dष', // Devanagari conjunct
  '👩🏽\u200d💻',
  '👨\u200d👩\u200d👧\u200d👦',
  '🇰🇷',
  '🇰🇷🇺🇸',
  '1\ufe0f\u20e3',
  '❤\ufe0f',
  '❤\ufe0e',
  '🏴\u{e0067}\u{e0062}\u{e007f}',
  '\u{1f600}',
  '\u00ad',
  '\u200b',
  '\u200c',
  '\u200d',
  '\u2060',
  '\ufeff',
  '\u00a0',
  '\u202f',
  ' ',
  '\t',
  '\n',
  '\r',
  '\r\n',
  '\u2028',
  '\u2029',
  '\u2066',
  '\u2067',
  '\u2069',
  '\u200e',
  '\u200f',
  '\ufe0f',
  '\u034f',
  '-',
  '/',
  '、',
];

/// Zero-advance-only strings, the 0.1.1 crash input class.
const zeroWidthOnly = <String>[
  '\u200b',
  '\u200b\u200b\u200b',
  '\u200d',
  '\u2060\u2060',
  '\ufeff',
  '\u00ad',
  '\u00ad\u00ad\u00ad',
  '\u034f',
  '\u0301',
  '\ufe0f',
  '\u200e\u200f',
];

List<String> buildCorpus({int randomCount = 400, int seed = 0x5339}) {
  final random = Random(seed);
  final result = <String>[
    ...appKoreanPhrases,
    ...zeroWidthOnly,
    ...fuzzAtoms,
    // Same atom repeated: stresses wrap-at-every-cluster behaviour.
    for (final atom in fuzzAtoms) atom * 6,
    '프랜차이즈를 프랜차이즈답게\n프랜차이즈를\u200b프랜차이즈답게',
    '한' * 10,
    '👨\u200d👩\u200d👧\u200d👦' * 4,
    '🇰🇷' * 7,
    'a\u0301\u0302\u0303\u0304\u0305\u0306 b',
  ];
  for (var i = 0; i < randomCount; i++) {
    result.add(
      List.generate(
        2 + random.nextInt(10),
        (_) => fuzzAtoms[random.nextInt(fuzzAtoms.length)],
      ).join(),
    );
  }
  return result;
}
