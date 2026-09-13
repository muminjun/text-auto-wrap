import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/span_codec.dart';
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
    'slices styled text and retains matching widget placeholder indices',
    () {
      const childStyle = TextStyle(fontWeight: FontWeight.bold);
      const root = TextSpan(
        text: 'x',
        children: [
          TextSpan(text: 'ab', style: childStyle),
          WidgetSpan(child: SizedBox(width: 4, height: 5)),
          TextSpan(text: 'c'),
        ],
      );

      final slice = sliceInlineSpanForMeasurement(encodeInlineSpan(root), 1, 4);
      final slicedRoot = slice.span as TextSpan;

      expect(_plain(slicedRoot), 'ab\uFFFC');
      expect(slice.placeholderIndices, [0]);
      expect((slicedRoot.children!.first as TextSpan).style, childStyle);
      expect(slicedRoot.children!.last, isA<WidgetSpan>());
    },
  );

  test('rejects opaque custom slices that contain widget descendants', () {
    const custom = _CustomTextSpan(
      text: 'a',
      children: [WidgetSpan(child: SizedBox(width: 7, height: 10))],
      marker: 'custom widget subtree',
    );
    const root = TextSpan(
      children: [
        custom,
        WidgetSpan(child: SizedBox(width: 13, height: 10)),
        TextSpan(text: 'b'),
      ],
    );

    expect(
      () => sliceInlineSpanForMeasurement(encodeInlineSpan(root), 0, 3),
      throwsA(isA<UnsupportedSpanTransformationException>()),
    );
  });

  test(
    'breaks nested text with all metadata and preserves untouched spans',
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
      final rebuiltLeaf = rebuiltBranch.children!.first as TextSpan;
      expect(rebuiltLeaf.text, 'a\nbc\nd');
      _expectMetadata(rebuiltLeaf, leaf);
      expect(rebuiltLeaf.children, same(leaf.children));
      final widgets = _allSpans(rebuilt).whereType<WidgetSpan>().toList();
      expect(widgets[0], same(widget));
      expect(widgets[0].child, same(widget.child));
      expect(widgets[1], same(secondWidget));
      expect(widgets[1].child, same(secondWidget.child));
    },
  );

  test('internal breaks retain one effective semantics and gesture unit', () {
    final recognizer = TapGestureRecognizer();
    addTearDown(recognizer.dispose);
    final root = TextSpan(
      text: 'abcd',
      semanticsLabel: 'spoken letters',
      semanticsIdentifier: 'letters',
      recognizer: recognizer,
      locale: const Locale('ko'),
      spellOut: true,
    );

    final rebuilt = insertLineBreaks(encodeInlineSpan(root), [1, 3]);

    expect(_plain(rebuilt), 'a\nbc\nd');
    expect(rebuilt.toPlainText(), 'spoken letters');
    final semantics = rebuilt.getSemanticsInformation();
    expect(semantics, hasLength(1));
    expect(semantics.single.text, 'a\nbc\nd');
    expect(semantics.single.semanticsLabel, 'spoken letters');
    expect(semantics.single.semanticsIdentifier, 'letters');
    expect(semantics.single.recognizer, same(recognizer));
    expect(semantics.single.requiresOwnNode, isTrue);
    final attributes = semantics.single.stringAttributes;
    expect(attributes.whereType<ui.LocaleStringAttribute>(), hasLength(1));
    expect(attributes.whereType<ui.SpellOutStringAttribute>(), hasLength(1));
    for (final offset in [0, 2, 3, 5]) {
      expect(
        rebuilt.getSpanForPosition(TextPosition(offset: offset)),
        same(rebuilt),
      );
    }
    expect(
      _textSpans(rebuilt).where((span) => span.recognizer != null),
      hasLength(1),
    );
  });

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
    final newlines = _textSpans(rebuilt).where((span) => span.text == '\n');
    expect(newlines, hasLength(2));
    for (final newline in newlines) {
      expect(newline, same(const TextSpan(text: '\n')));
    }
  });

  test('reuses unchanged TextSpan subclasses and rejects changed ones', () {
    const custom = _CustomTextSpan(text: 'ab', marker: 'custom state');
    const root = TextSpan(
      children: [
        custom,
        TextSpan(text: 'cd'),
      ],
    );
    final encoded = encodeInlineSpan(root);

    expect(insertLineBreaks(encodeInlineSpan(custom), []), same(custom));
    final rebuilt = insertLineBreaks(encoded, [2, 3]) as TextSpan;
    expect(_plain(rebuilt), 'ab\nc\nd');
    expect(rebuilt.children!.first, same(custom));
    expect(
      () => insertLineBreaks(encoded, [1]),
      throwsA(isA<UnsupportedSpanTransformationException>()),
    );
  });

  test('rejects a changed subclass ancestor without demoting its state', () {
    const root = _CustomTextSpan(
      marker: 'ancestor state',
      children: [
        TextSpan(text: 'ab'),
        TextSpan(text: 'cd'),
      ],
    );
    for (final offset in [1, 2]) {
      expect(
        () => insertLineBreaks(encodeInlineSpan(root), [offset]),
        throwsA(isA<UnsupportedSpanTransformationException>()),
      );
    }
  });

  test('encodes and reuses opaque spans until a break must transform them', () {
    const opaque = _OpaqueSpan('ab');
    const root = TextSpan(
      children: [
        opaque,
        TextSpan(text: 'cd'),
      ],
    );

    final encoded = encodeInlineSpan(root);

    expect(encoded.text, 'abcd');
    expect(insertLineBreaks(encodeInlineSpan(opaque), []), same(opaque));
    final rebuilt = insertLineBreaks(encoded, [2, 3]) as TextSpan;
    expect(_plain(rebuilt), 'ab\nc\nd');
    expect(rebuilt.children!.first, same(opaque));
    expect(
      () => insertLineBreaks(encoded, [1]),
      throwsA(isA<UnsupportedSpanTransformationException>()),
    );
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

  for (final newline in ['\u2028', '\u2029']) {
    for (final offset in [2, 3]) {
      test('rejects hard separator ${newline.codeUnitAt(0)} at $offset', () {
        final root = TextSpan(
          text: 'ab',
          children: [TextSpan(text: '${newline}cd')],
        );
        final encoded = encodeInlineSpan(root);
        expect(encoded.text, 'ab${newline}cd');
        expect(
          () => insertLineBreaks(encoded, [offset]),
          throwsA(isA<InvalidBoundaryException>()),
        );
      });
    }
  }
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

class _CustomTextSpan extends TextSpan {
  const _CustomTextSpan({super.text, super.children, required this.marker});

  final String marker;
}

class _OpaqueSpan extends InlineSpan {
  const _OpaqueSpan(this.value);

  final String value;

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) => builder.addText(value);

  @override
  bool visitChildren(InlineSpanVisitor visitor) => visitor(this);

  @override
  bool visitDirectChildren(InlineSpanVisitor visitor) => true;

  @override
  InlineSpan? getSpanForPositionVisitor(
    TextPosition position,
    Accumulator offset,
  ) {
    final local = position.offset - offset.value;
    offset.increment(value.length);
    return local >= 0 && local < value.length ? this : null;
  }

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) => buffer.write(value);

  @override
  void computeSemanticsInformation(
    List<InlineSpanSemanticsInformation> collector,
  ) {
    collector.add(InlineSpanSemanticsInformation(value));
  }

  @override
  int? codeUnitAtVisitor(int index, Accumulator offset) {
    final local = index - offset.value;
    offset.increment(value.length);
    return local >= 0 && local < value.length ? value.codeUnitAt(local) : null;
  }

  @override
  RenderComparison compareTo(InlineSpan other) => identical(this, other)
      ? RenderComparison.identical
      : RenderComparison.layout;
}
