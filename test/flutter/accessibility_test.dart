import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets('recognizers survive a break inside their original text span', (
    tester,
  ) async {
    var taps = 0;
    final recognizer = TapGestureRecognizer()..onTap = () => taps++;
    addTearDown(recognizer.dispose);
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          TextSpan(text: 'abcdef', recognizer: recognizer),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    for (final selection in [
      const TextSelection(baseOffset: 0, extentOffset: 1),
      const TextSelection(baseOffset: 4, extentOffset: 5),
    ]) {
      final rect = render.getBoxesForSelection(selection).single.toRect();
      await tester.tapAt(render.localToGlobal(rect.center));
    }
    expect(taps, 2);
  });

  testWidgets(
    'inserted newline leaves add no gesture or focus targets',
    (tester) async => _withSemantics(tester, () async {
      var taps = 0;
      final recognizer = TapGestureRecognizer()..onTap = () => taps++;
      addTearDown(recognizer.dispose);
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'abc',
                  recognizer: recognizer,
                  semanticsLabel: 'first',
                ),
                const TextSpan(text: 'def', semanticsLabel: 'second'),
              ],
            ),
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      final newlineLeaves = <TextSpan>[];
      render.effectiveText.visitChildren((span) {
        if (span is TextSpan && span.text == '\n') newlineLeaves.add(span);
        return true;
      });
      expect(newlineLeaves, hasLength(1));
      expect(newlineLeaves.single.semanticsLabel, isNull);
      expect(newlineLeaves.single.recognizer, isNull);
      final nodes = _semantics(tester);
      expect(
        nodes.where((data) => data.hasAction(SemanticsAction.tap)),
        hasLength(1),
      );
      expect(
        nodes.where(
          (data) => data.flagsCollection.isFocused != ui.Tristate.none,
        ),
        isEmpty,
      );
      expect(nodes.map((data) => data.label).join(), contains('first'));
      expect(nodes.map((data) => data.label).join(), contains('second'));
      expect(
        nodes.where((data) => data.label.trim().isEmpty && data.actions != 0),
        isEmpty,
      );
      await tester.tapAt(render.localToGlobal(const Offset(70, 5)));
      expect(taps, 0);
      await tester.tapAt(render.localToGlobal(const Offset(5, 5)));
      expect(taps, 1);
    }),
  );

  testWidgets(
    'semanticsLabel replaces the complete effective paragraph',
    (tester) async => _withSemantics(tester, () async {
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            'abcdef',
            semanticsLabel: 'accessible description',
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      expect(wrapRender(tester).result!.applied, isTrue);
      expect(
        _semantics(
          tester,
        ).where((data) => data.label.isNotEmpty).map((data) => data.label),
        ['accessible description'],
      );
    }),
  );

  testWidgets(
    'unmeasurable baseline preserves widget semantics and tap target',
    (tester) async => _withSemantics(tester, () async {
      var taps = 0;
      const childKey = ValueKey('inline button');
      final source = TextSpan(
        text: 'ab',
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Semantics(
              label: 'inline action',
              button: true,
              child: GestureDetector(
                key: childKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 20, height: 18),
              ),
            ),
          ),
          const TextSpan(text: 'cd', semanticsLabel: 'last'),
        ],
      );
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.reason, 'unmeasurablePlaceholder');
      expect(render.effectiveText, same(render.sourceText));
      expect(
        _semantics(
          tester,
        ).where((data) => data.label.contains('inline action')),
        hasLength(1),
      );
      expect(
        _semantics(tester).where((data) => data.hasAction(SemanticsAction.tap)),
        hasLength(1),
      );
      await tester.tap(find.byKey(childKey));
      expect(taps, 1);
      final semantics = _semantics(
        tester,
      ).map((data) => (data.label, data.actions)).toList();
      await tester.pumpWidget(wrapHost(Text.rich(source)));
      expect(
        _semantics(tester).map((data) => (data.label, data.actions)),
        semantics,
      );
    }),
  );

  testWidgets(
    'SelectionArea selects across inserted line breaks and relayout',
    (tester) async {
      SelectedContent? selected;
      final width = ValueNotifier<double>(100);
      addTearDown(width.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              onSelectionChanged: (value) => selected = value,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, width, _) => wrapHost(
                  TextAutoWrap(
                    'abcdef',
                    model: offsetModel([3]),
                    strategy: offsetStrategy([3]),
                  ),
                  width: width,
                ),
              ),
            ),
          ),
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      await _dragSelection(tester, render, 0, 7);
      expect(selected!.plainText, 'abc\ndef');
      expect(
        render.selections.single,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      width.value = 60;
      await tester.pump();
      await _dragSelection(tester, render, 4, 7);
      expect(selected!.plainText, 'def');
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets('$direction mixed bidi uses native visual positions', (
      tester,
    ) async {
      const source = 'אבג abc דהו';
      const expected = 'אבג abc \nדהו';
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap(
            source,
            model: offsetModel([8]),
            strategy: offsetStrategy([8]),
          ),
          direction: direction,
          width: 200,
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      expect(render.effectiveText.toPlainText(), expected);
      final boxes = _textBoxes(render, expected.length);
      final carets = _carets(render, expected.length);
      await tester.pumpWidget(
        wrapHost(const Text(expected), direction: direction, width: 200),
      );
      final native = _native(tester);
      expect(_textBoxes(native, expected.length), boxes);
      expect(_carets(native, expected.length), carets);
    });
  }

  testWidgets('hard newlines remain mandatory around calculated breaks', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap(
          'ab\n\ncdef\n',
          model: offsetModel([6]),
          strategy: offsetStrategy([6]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    expect(render.effectiveText.toPlainText(), 'ab\n\ncd\nef\n');
    final size = render.size;
    final boxes = _textBoxes(render, 10);
    await tester.pumpWidget(wrapHost(const Text('ab\n\ncd\nef\n')));
    expect(_native(tester).size, size);
    expect(_textBoxes(_native(tester), 10), boxes);
  });

  for (final overflow in TextOverflow.values) {
    for (final softWrap in [false, true]) {
      for (final maxLines in <int?>[null, 1, 2]) {
        testWidgets(
          '$overflow softWrap=$softWrap maxLines=$maxLines native paint',
          (tester) async {
            const source = 'abcdef\njkl';
            final applied = softWrap && maxLines == null;
            final expected = applied ? 'abc\ndef\njkl' : source;
            Widget frame(Widget child) => wrapHost(
              RepaintBoundary(
                key: const ValueKey('paint'),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: 40, height: 14, child: child),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(
              frame(
                TextAutoWrap(
                  source,
                  softWrap: softWrap,
                  overflow: overflow,
                  maxLines: maxLines,
                  model: offsetModel([3]),
                  strategy: offsetStrategy([3]),
                ),
              ),
            );
            final render = wrapRender(tester);
            expect(render.result!.applied, applied);
            if (!softWrap) expect(render.result!.reason, 'softWrapDisabled');
            final size = render.size;
            final exceeded = render.didExceedMaxLines;
            final fade = render.debugHasOverflowShader;
            final pixels = await _pixels(tester);
            await tester.pumpWidget(
              frame(
                Text(
                  expected,
                  softWrap: softWrap,
                  overflow: overflow,
                  maxLines: maxLines,
                ),
              ),
            );
            final native = _native(tester);
            expect(native.size, size);
            expect(native.didExceedMaxLines, exceeded);
            expect(native.debugHasOverflowShader, fade);
            expect(await _pixels(tester), pixels);
          },
        );
      }
    }
  }

  testWidgets(
    'nonlinear scaling measures each text and widget style natively',
    (tester) async {
      const source = TextSpan(
        text: 'ab',
        children: [
          TextSpan(
            style: TextStyle(fontSize: 20),
            text: 'cd',
            children: [WidgetSpan(child: SizedBox(width: 12, height: 8))],
          ),
          TextSpan(text: 'ef'),
        ],
      );
      await tester.pumpWidget(
        wrapHost(
          TextAutoWrap.rich(
            source,
            textScaler: const _NonlinearScaler(),
            model: offsetModel([5]),
            strategy: offsetStrategy([5]),
          ),
          width: 200,
        ),
      );
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      // 2 * scale(10) + 2 * scale(20) + 12 * scale(20) / 20.
      expect(render.result!.widths, [closeTo(102.4, .001), 40]);
      final size = render.size;
      final box =
          (render.firstChild!.parentData! as TextParentData).offset! &
          render.firstChild!.size;
      await tester.pumpWidget(
        wrapHost(
          const Text.rich(
            TextSpan(
              text: 'ab',
              children: [
                TextSpan(
                  style: TextStyle(fontSize: 20),
                  text: 'cd',
                  children: [WidgetSpan(child: SizedBox(width: 12, height: 8))],
                ),
                TextSpan(text: '\nef'),
              ],
            ),
            textScaler: _NonlinearScaler(),
          ),
          width: 200,
        ),
      );
      final native = _native(tester);
      expect(native.size, size);
      expect(
        (native.firstChild!.parentData! as TextParentData).offset! &
            native.firstChild!.size,
        box,
      );
    },
  );

  testWidgets('unsupported language keeps original spans and native layout', (
    tester,
  ) async {
    const source = TextSpan(
      text: '日本語の文章です。',
      children: [
        WidgetSpan(child: SizedBox(width: 12, height: 15)),
        TextSpan(text: '続きです。'),
      ],
    );
    await tester.pumpWidget(
      wrapHost(const TextAutoWrap.rich(source), width: 50),
    );
    final render = wrapRender(tester);
    expect(render.result!.reason, 'unsupportedLanguage');
    expect(render.result!.applied, isFalse);
    expect(render.effectiveText, same(render.sourceText));
    final size = render.size;
    final boxes = _textBoxes(render, 16);
    await tester.pumpWidget(wrapHost(const Text.rich(source), width: 50));
    expect(_native(tester).size, size);
    expect(_textBoxes(_native(tester), 16), boxes);
  });
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

List<SemanticsData> _semantics(WidgetTester tester) {
  final result = <SemanticsData>[];
  void visit(SemanticsNode node) {
    result.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return result;
}

RenderParagraph _native(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderParagraph>().toSet().single;

List<List<ui.TextBox>> _textBoxes(RenderParagraph render, int length) => [
  for (var i = 0; i < length; i++)
    render.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    ),
];

List<Offset> _carets(RenderParagraph render, int length) => [
  for (var i = 0; i <= length; i++)
    render.getOffsetForCaret(TextPosition(offset: i), Rect.zero),
];

Future<void> _dragSelection(
  WidgetTester tester,
  RenderParagraph render,
  int start,
  int end,
) async {
  Offset position(int offset) => render.localToGlobal(
    render.getOffsetForCaret(TextPosition(offset: offset), Rect.zero) +
        const Offset(0, 5),
  );
  final gesture = await tester.startGesture(
    position(start),
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(position(end));
  await gesture.up();
  await tester.pump();
}

Future<Uint8List> _pixels(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('paint')),
      );
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 10 ? fontSize * 2 : fontSize * 1.2;

  @override
  double get textScaleFactor => 2;
}
