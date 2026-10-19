// Opt-in; not part of the default suite.
// flutter test test/fuzz/app_phrase_width_sweep_review.dart \
//   [--dart-define=TAW_FONT_PATH=/path/to/PretendardVariable.ttf]
// Sweeps every app login/session/splash phrase over scales and a dense width
// ladder (including sub-glyph widths) and tallies exceptions and failure
// records. TAW_FONT_PATH switches Ahem to the real Pretendard font.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import 'ko_phrases.dart';

const _fontPath = String.fromEnvironment('TAW_FONT_PATH');

void main() {
  testWidgets('app phrases x scales x widths', (tester) async {
    var family = 'Ahem';
    if (_fontPath.isNotEmpty) {
      final loader = FontLoader('Pretendard')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              Uint8List.fromList(File(_fontPath).readAsBytesSync()),
            ),
          ),
        );
      await loader.load();
      family = 'Pretendard';
    }
    final caught = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => caught.add('${d.exception.runtimeType}');
    addTearDown(() => FlutterError.onError = previous);

    final watch = Stopwatch()..start();
    var cases = 0, exceptions = 0, withFailures = 0, wrapped = 0;
    final reasons = <String, int>{};
    final exceptionTypes = <String, int>{};
    outer:
    for (final phrase in appKoreanPhrases) {
      for (final scale in const [1.0, 1.3, 1.5, 1.94, 2.0, 3.0]) {
        for (var width = 0.0; width <= 460; width += width < 40 ? 1.7 : 9.3) {
          if (watch.elapsed.inSeconds > 100) break outer;
          caught.clear();
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: TextAutoWrap(
                    phrase,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.linear(scale),
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF000000),
                    ),
                  ),
                ),
              ),
            ),
          );
          tester.takeException();
          cases++;
          if (caught.isNotEmpty) {
            exceptions++;
            exceptionTypes[caught.first] =
                (exceptionTypes[caught.first] ?? 0) + 1;
            continue;
          }
          final render = tester.allRenderObjects
              .whereType<RenderTextAutoWrap>()
              .toSet()
              .single;
          final failures = render.failures;
          if (render.result?.applied ?? false) wrapped++;
          if (failures.isNotEmpty) {
            withFailures++;
            for (final f in failures) {
              final k = '${f.stage}/${f.reason}';
              reasons[k] = (reasons[k] ?? 0) + 1;
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print(
      'APPSWEEP font=$family cases=$cases exceptions=$exceptions '
      'withFailureRecords=$withFailures semanticWrapApplied=$wrapped '
      'elapsed=${watch.elapsed.inSeconds}s $exceptionTypes $reasons',
    );
    expect(exceptions, 0);
    expect(withFailures, 0);
    var widthCount = 0;
    for (var width = 0.0; width <= 460; width += width < 40 ? 1.7 : 9.3) {
      widthCount++;
    }
    expect(
      cases,
      appKoreanPhrases.length * 6 * widthCount,
      reason: 'the review must finish its declared grid within the budget',
    );
  }, timeout: const Timeout(Duration(seconds: 118)));
}
