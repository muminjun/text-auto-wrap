// Sub-glyph widths (S9): every glyph gets its own line and the space between
// words falls outside all reported line boundaries. This used to surface as
// InvalidBoundaryException from layout (0.1.1) and as a spurious
// nativeMeasurement failure on every such layout (0.1.2).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

const _phrases = ['프랜차이즈를 프랜차이즈답게', '로그인 정보를 불러오지 못했어요', 'a b c', '한 글  두 칸'];

Widget _host(String text, double scale, double width) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: TextAutoWrap(
        text,
        style: wrapStyle.copyWith(letterSpacing: -0.2),
        textScaler: TextScaler.linear(scale),
      ),
    ),
  ),
);

void main() {
  for (final phrase in _phrases) {
    for (final scale in const [1.0, 1.94, 3.0]) {
      final glyph = 10 * scale;
      for (final width in <double>[
        0,
        0.0001,
        1,
        glyph / 2,
        glyph - 0.01,
        glyph,
      ]) {
        testWidgets('"$phrase" x$scale at width $width lays out cleanly', (
          tester,
        ) async {
          await tester.pumpWidget(_host(phrase, scale, width));
          expect(tester.takeException(), isNull);
          final render = wrapRender(tester);
          expect(render.failures, isEmpty);
          final result = render.result!;
          expect(result.sourceText, phrase);
          // Ranges stay ordered and skip nothing but hanging spaces.
          var previousEnd = 0;
          for (final range in result.ranges) {
            expect(range.start, greaterThanOrEqualTo(previousEnd));
            expect(
              phrase.substring(previousEnd, range.start).trim(),
              isEmpty,
              reason: 'only whitespace may fall between lines',
            );
            previousEnd = range.end;
          }
          expect(phrase.substring(previousEnd).trim(), isEmpty);
        });
      }
    }
  }
}
