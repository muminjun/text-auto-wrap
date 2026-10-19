// Opt-in; not part of the default suite.
// flutter test test/fuzz/atom_failure_rate_review.dart \
//   [--dart-define=TAW_FONT_PATH=/path/to/PretendardVariable.ttf]
// Which Unicode atoms still produce failure records (engine geometry that the
// adapter cannot use) after the hanging-space fix? Informational.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import 'fuzz_corpus.dart';

const _fontPath = String.fromEnvironment('TAW_FONT_PATH');

void main() {
  testWidgets('atom failure rates', (tester) async {
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
    final rows = <String>[];
    for (final atom in fuzzAtoms) {
      for (final template in const ['A', 'B']) {
        final text = template == 'A' ? atom * 6 : 'ab $atom cd $atom ef';
        var cases = 0, bad = 0, thrown = 0;
        final reasons = <String>{};
        for (final scale in const [1.0, 1.94]) {
          for (final width in const [
            0.0,
            3.0,
            10.0,
            15.0,
            20.0,
            25.0,
            30.0,
            45.0,
            60.0,
            100.0,
            300.0,
          ]) {
            caught.clear();
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: TextAutoWrap(
                      text,
                      textScaler: TextScaler.linear(scale),
                      style: TextStyle(
                        fontFamily: family,
                        fontSize: 10,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            );
            tester.takeException();
            cases++;
            if (caught.isNotEmpty) {
              thrown++;
              continue;
            }
            final r = tester.allRenderObjects
                .whereType<RenderTextAutoWrap>()
                .toSet()
                .single;
            final f = r.failures;
            if (f.isNotEmpty) {
              bad++;
              reasons.add(f.first.error.toString().split(':').last.trim());
            }
          }
        }
        if (bad > 0 || thrown > 0) {
          rows.add(
            '${atom.codeUnits.map((u) => u.toRadixString(16)).join('+')} $template bad=$bad/$cases thrown=$thrown ${reasons.take(2).join(' | ')}',
          );
        }
      }
    }
    // ignore: avoid_print
    print('ATOMS font=$family\n${rows.join('\n')}');
  });
}
