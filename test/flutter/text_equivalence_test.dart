// TextAutoWrap must behave like the default Text wherever semantic breaks are
// not applied, and keep native semantics where they are: size, overflow state,
// selection geometry, hit mapping, semantics and recognizers across text
// scales, maxLines, ellipsis and widths (including widths narrower than a glyph).
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

const _phrases = [
  '프랜차이즈를 프랜차이즈답게',
  'Hello wide world of text',
  '로그인 정보를 불러오지 못했어요\n다시 시도해 주세요.',
];

Widget _pair(
  Widget wrapped,
  Widget native,
  double width, {
  TextDirection direction = TextDirection.ltr,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        maxHeight: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [wrapped, native],
        ),
      ),
    ),
  ),
);

RenderParagraph _native(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderParagraph>()
    .where((render) => render is! RenderTextAutoWrap)
    .toSet()
    .single;

String? _label(RenderParagraph render) =>
    render.debugSemantics?.getSemanticsData().label;

void main() {
  testWidgets('plain text matches the default Text across the option grid', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var compared = 0;
    var applied = 0;
    for (final phrase in _phrases) {
      for (final scale in const [1.0, 1.3, 1.5, 1.94, 2.0, 3.0]) {
        for (final maxLines in const <int?>[null, 1, 2]) {
          for (final overflow in const [
            TextOverflow.clip,
            TextOverflow.ellipsis,
          ]) {
            for (final width in const <double>[0, 5, 25, 60, 150, 400]) {
              final reason =
                  '"$phrase" scale=$scale maxLines=$maxLines '
                  'overflow=$overflow width=$width';
              final scaler = TextScaler.linear(scale);
              await tester.pumpWidget(
                _pair(
                  TextAutoWrap(
                    phrase,
                    style: wrapStyle,
                    textScaler: scaler,
                    maxLines: maxLines,
                    overflow: overflow,
                  ),
                  Text(
                    phrase,
                    style: wrapStyle,
                    textScaler: scaler,
                    maxLines: maxLines,
                    overflow: overflow,
                  ),
                  width,
                ),
              );
              expect(tester.takeException(), isNull, reason: reason);
              final wrapped = wrapRender(tester);
              final native = _native(tester);
              compared++;
              if (wrapped.result?.applied ?? false) {
                applied++;
                // Inserted breaks are real newlines in the semantics label
                // (the inserted leaf deliberately has no semanticsLabel);
                // nothing else may differ from the native label.
                expect(
                  _label(wrapped)?.replaceAll('\n', ''),
                  _label(native)?.replaceAll('\n', ''),
                  reason: reason,
                );
                continue;
              }
              expect(_label(wrapped), _label(native), reason: reason);
              // No semantic break was inserted: native behavior, exactly.
              expect(wrapped.size, native.size, reason: reason);
              expect(
                wrapped.didExceedMaxLines,
                native.didExceedMaxLines,
                reason: reason,
              );
              final all = TextSelection(
                baseOffset: 0,
                extentOffset: phrase.length,
              );
              expect(
                wrapped.getBoxesForSelection(all),
                native.getBoxesForSelection(all),
                reason: reason,
              );
              for (final dx in const [0.0, 7.0, 31.0, 123.0]) {
                expect(
                  wrapped.getPositionForOffset(Offset(dx, 3)),
                  native.getPositionForOffset(Offset(dx, 3)),
                  reason: '$reason dx=$dx',
                );
              }
            }
          }
        }
      }
    }
    semantics.dispose();
    expect(compared, 3 * 6 * 3 * 2 * 6);
    expect(applied, lessThan(compared), reason: 'both branches are covered');
  });

  for (final direction in TextDirection.values) {
    testWidgets('$direction recognizers fire like the default Text under '
        'scale, ellipsis and a break inside the span', (tester) async {
      var wrappedTaps = 0;
      var nativeTaps = 0;
      final wrappedRecognizer = TapGestureRecognizer()
        ..onTap = () => wrappedTaps++;
      final nativeRecognizer = TapGestureRecognizer()
        ..onTap = () => nativeTaps++;
      addTearDown(wrappedRecognizer.dispose);
      addTearDown(nativeRecognizer.dispose);
      TextSpan span(GestureRecognizer recognizer) => TextSpan(
        style: wrapStyle,
        children: [
          const TextSpan(text: 'ab '),
          TextSpan(text: 'tap target', recognizer: recognizer),
          const TextSpan(text: ' tail'),
        ],
      );
      await tester.pumpWidget(
        _pair(
          TextAutoWrap.rich(
            span(wrappedRecognizer),
            textScaler: const TextScaler.linear(1.94),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          Text.rich(
            span(nativeRecognizer),
            textScaler: const TextScaler.linear(1.94),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          200,
          direction: direction,
        ),
      );
      final wrapped = wrapRender(tester);
      final native = _native(tester);
      // The span starts at offset 3; tap its first glyph in each paragraph.
      for (final (render, label) in [
        (wrapped, 'wrapped'),
        (native, 'native'),
      ]) {
        final box = render
            .getBoxesForSelection(
              const TextSelection(baseOffset: 3, extentOffset: 4),
            )
            .first;
        await tester.tapAt(render.localToGlobal(box.toRect().center));
        expect(tester.takeException(), isNull, reason: label);
      }
      expect(wrappedTaps, 1);
      expect(nativeTaps, 1);
    });
  }
}
