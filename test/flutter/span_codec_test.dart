import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('encodes source text, newlines, and one code unit per widget', () {
    const root = TextSpan(
      text: 'A\n',
      semanticsLabel: 'spoken A',
      children: [
        TextSpan(
          text: '😀',
          children: [WidgetSpan(child: SizedBox())],
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.aboveBaseline,
          baseline: TextBaseline.alphabetic,
          child: SizedBox(width: 3),
        ),
        TextSpan(text: 'B'),
      ],
    );

    final encoded = encodeInlineSpan(root);

    expect(encoded.text, 'A\n😀\uFFFC\uFFFCB');
    expect(encoded.text.length, 7);
    expect(insertLineBreaks(encoded, []), same(root));
  });

  test(
    'splits nested text with all metadata and preserves untouched spans',
    () {
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      void onEnter(PointerEnterEvent event) {}
      void onExit(PointerExitEvent event) {}
      const style = TextStyle(color: Color(0xff123456), fontSize: 17);
      const locale = Locale('ko', 'KR');
      const widget = WidgetSpan(
        style: TextStyle(fontSize: 20),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.ideographic,
        child: SizedBox(width: 8, height: 9),
      );
      const secondWidget = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(width: 4),
      );
      const tail = TextSpan(text: 'tail');
      final leaf = TextSpan(
        text: 'abcd',
        style: style,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.help,
        onEnter: onEnter,
        onExit: onExit,
        semanticsLabel: 'spoken letters',
        semanticsIdentifier: 'letters',
        locale: locale,
        spellOut: true,
        children: const [widget],
      );
      final branch = TextSpan(style: style, children: [leaf, secondWidget]);
      final root = TextSpan(text: 'X', children: [branch, tail]);

      final rebuilt =
          insertLineBreaks(encodeInlineSpan(root), [2, 4]) as TextSpan;

      expect(_plain(rebuilt), 'Xa\nbc\nd\uFFFC\uFFFCtail');
      expect(_plain(root), 'Xabcd\uFFFC\uFFFCtail');
      expect(rebuilt, isNot(same(root)));
      expect(rebuilt.children!.last, same(tail));
      final rebuiltBranch = rebuilt.children!.first as TextSpan;
      expect(rebuiltBranch, isNot(same(branch)));
      expect(rebuiltBranch.style, same(style));
      expect(rebuiltBranch.children!.last, same(secondWidget));
      final runs = _textSpans(
        rebuilt,
      ).where((span) => const ['a', 'bc', 'd'].contains(span.text));
      expect(runs, hasLength(3));
      for (final run in runs) {
        _expectMetadata(run, leaf);
      }
      final widgets = _allSpans(rebuilt).whereType<WidgetSpan>().toList();
      expect(widgets[0], same(widget));
      expect(widgets[0].child, same(widget.child));
      expect(widgets[1], same(secondWidget));
      expect(widgets[1].child, same(secondWidget.child));
      final newlines = _textSpans(rebuilt).where((span) => span.text == '\n');
      expect(newlines, hasLength(2));
      for (final newline in newlines) {
        expect(newline, same(const TextSpan(text: '\n')));
      }
    },
  );

  test('inserts at span and widget edges without cloning intact leaves', () {
    const left = TextSpan(text: 'ab');
    const empty = TextSpan(text: '');
    const widget = WidgetSpan(child: SizedBox());
    const right = TextSpan(text: 'cd');
    const branch = TextSpan(children: [left, empty, widget]);
    const root = TextSpan(children: [branch, right]);

    final rebuilt = insertLineBreaks(encodeInlineSpan(root), [2, 3]);

    expect(_plain(rebuilt), 'ab\n\uFFFC\ncd');
    for (final original in [left, empty, widget, right]) {
      expect(
        _allSpans(rebuilt).any((span) => identical(span, original)),
        isTrue,
      );
    }
  });

  test('splits root text before its existing children without reordering', () {
    const child = TextSpan(text: 'ef');
    const root = TextSpan(text: 'abcd', children: [child]);

    final rebuilt = insertLineBreaks(encodeInlineSpan(root), [1, 3, 4]);

    expect(_plain(rebuilt), 'a\nbc\nd\nef');
    expect(_allSpans(rebuilt).any((span) => identical(span, child)), isTrue);
  });

  test('maps repeated source span instances by their occurrence', () {
    const shared = TextSpan(text: 'ab');
    const root = TextSpan(children: [shared, shared]);

    final rebuilt = insertLineBreaks(encodeInlineSpan(root), [3]) as TextSpan;

    expect(_plain(rebuilt), 'aba\nb');
    expect(rebuilt.children!.first, same(shared));
    expect(rebuilt.children!.last, isNot(same(shared)));
  });

  test('preserves UTF-16 offsets after emoji and existing newlines', () {
    const root = TextSpan(text: '😀a\nbc');
    final encoded = encodeInlineSpan(root);

    expect(_plain(insertLineBreaks(encoded, [2, 5])), '😀\na\nb\nc');
    expect(insertLineBreaks(encoded, []), same(root));
    expect(_plain(insertLineBreaks(encoded, [5])), '😀a\nb\nc');
  });

  test('rejects endpoints, out-of-range, duplicate and descending offsets', () {
    final encoded = encodeInlineSpan(const TextSpan(text: 'abcd'));
    for (final offsets in [
      [0],
      [4],
      [-1],
      [5],
      [1, 1],
      [2, 1],
    ]) {
      expect(
        () => insertLineBreaks(encoded, offsets),
        throwsA(isA<InvalidBoundaryException>()),
        reason: '$offsets',
      );
    }
  });

  test('rejects grapheme interiors even across text-span boundaries', () {
    const fixtures = [
      TextSpan(text: 'a😀b'),
      TextSpan(
        text: 'ae',
        children: [TextSpan(text: '\u0301b')],
      ),
      TextSpan(
        text: 'a👨',
        children: [TextSpan(text: '\u200d👩b')],
      ),
    ];
    for (final root in fixtures) {
      expect(
        () => insertLineBreaks(encodeInlineSpan(root), [2]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    }
  });

  test('rejects either side of explicit newlines, including across spans', () {
    const root = TextSpan(
      text: 'ab',
      children: [TextSpan(text: '\ncd')],
    );
    for (final offset in [2, 3]) {
      expect(
        () => insertLineBreaks(encodeInlineSpan(root), [offset]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    }
    final crlf = encodeInlineSpan(const TextSpan(text: 'ab\r\ncd'));
    for (final offset in [2, 3, 4]) {
      expect(
        () => insertLineBreaks(crlf, [offset]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    }
  });

  test('handles empty trees and a standalone widget without rebuilding', () {
    for (final root in const <InlineSpan>[
      TextSpan(),
      TextSpan(text: '', children: [TextSpan()]),
      WidgetSpan(child: SizedBox()),
    ]) {
      final encoded = encodeInlineSpan(root);
      expect(insertLineBreaks(encoded, []), same(root));
      expect(
        () => insertLineBreaks(encoded, [0]),
        throwsA(isA<InvalidBoundaryException>()),
      );
    }
  });
}

String _plain(InlineSpan span) =>
    span.toPlainText(includeSemanticsLabels: false);

Iterable<InlineSpan> _allSpans(InlineSpan span) sync* {
  yield span;
  if (span is TextSpan) {
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _allSpans(child);
    }
  }
}

Iterable<TextSpan> _textSpans(InlineSpan span) =>
    _allSpans(span).whereType<TextSpan>();

void _expectMetadata(TextSpan actual, TextSpan original) {
  expect(actual.style, same(original.style));
  expect(actual.recognizer, same(original.recognizer));
  expect(actual.mouseCursor, same(original.mouseCursor));
  expect(actual.onEnter, same(original.onEnter));
  expect(actual.onExit, same(original.onExit));
  expect(actual.semanticsLabel, same(original.semanticsLabel));
  expect(actual.semanticsIdentifier, same(original.semanticsIdentifier));
  expect(actual.locale, same(original.locale));
  expect(actual.spellOut, original.spellOut);
}
