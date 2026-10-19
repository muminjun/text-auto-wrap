// Opt-in; not part of the default suite.
// flutter test test/fuzz/splash_phrase_matrix_review.dart \
//   [--dart-define=TAW_FONT_PATH=/path/to/PretendardVariable.ttf]
// Targets the production S9 input: the splash phrase in the app's body style
// (14px, height 1.5, letterSpacing -0.2, w600) at scale 1.94, swept across
// widths/softWrap. With TAW_FONT_PATH set it uses the real Pretendard font.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

const _fontPath = String.fromEnvironment('TAW_FONT_PATH');
const _phrases = ['프랜차이즈를 프랜차이즈답게', '로그인 정보를 불러오지 못했어요'];

void main() {
  testWidgets('splash phrase matrix', (tester) async {
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

    final out = StringBuffer('font=$family\n');
    for (final phrase in _phrases) {
      for (final scale in [1.0, 1.94, 3.0]) {
        for (final softWrap in [true, false]) {
          final row = <String>[];
          for (final width in [
            0.0,
            0.0001,
            1.0,
            10.0,
            26.0,
            27.2,
            54.4,
            100.0,
            200.0,
            300.0,
            340.0,
            393.0,
            430.0,
            double.infinity,
          ]) {
            caught.clear();
            final child = TextAutoWrap(
              phrase,
              softWrap: softWrap,
              style: TextStyle(
                fontFamily: family,
                fontSize: 14,
                height: 1.5,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF000000),
              ),
              textScaler: TextScaler.linear(scale),
              textAlign: TextAlign.center,
            );
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: width.isInfinite
                      ? OverflowBox(
                          minWidth: 0,
                          maxWidth: double.infinity,
                          alignment: Alignment.topLeft,
                          child: child,
                        )
                      : SizedBox(width: width, child: child),
                ),
              ),
            );
            tester.takeException();
            var note = caught.isEmpty ? 'ok' : caught.first;
            if (caught.isEmpty) {
              try {
                final r = tester.allRenderObjects
                    .whereType<RenderTextAutoWrap>()
                    .toSet()
                    .single;
                final f = (r as dynamic).failures as List;
                final res = r.result;
                note = f.isEmpty
                    ? 'ok(${res == null ? 'noresult' : (res.applied ? 'wrapped' : res.reason)})'
                    : 'FAIL:${f.map((e) => '${e.stage}/${e.reason}').join('+')}';
              } catch (e) {
                note = 'probe-error:$e';
              }
            }
            row.add(note);
          }
          out.writeln(
            '$phrase scale=$scale softWrap=$softWrap -> ${row.join(' ')}',
          );
        }
      }
    }
    // ignore: avoid_print
    print(out);
  });
}
