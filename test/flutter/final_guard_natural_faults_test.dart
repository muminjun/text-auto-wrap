// Faults that come from user-defined spans (no package test hooks), so this
// file also runs against older releases to show which paths used to escape.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

const _siblingKey = ValueKey('sibling');

/// A span whose engine-facing entry points can be made to throw on demand.
class _FaultySpan extends TextSpan {
  const _FaultySpan(this.faults) : super(text: 'abcdef', style: wrapStyle);

  final Set<String> faults;

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    if (faults.contains('build')) throw StateError('injected build fault');
    super.build(builder, textScaler: textScaler, dimensions: dimensions);
  }

  @override
  void computeSemanticsInformation(
    List<InlineSpanSemanticsInformation> collector, {
    ui.Locale? inheritedLocale,
    bool inheritedSpellOut = false,
  }) {
    if (faults.contains('semantics')) {
      throw StateError('injected semantics fault');
    }
    super.computeSemanticsInformation(
      collector,
      inheritedLocale: inheritedLocale,
      inheritedSpellOut: inheritedSpellOut,
    );
  }

  @override
  InlineSpan? getSpanForPositionVisitor(
    TextPosition position,
    Accumulator offset,
  ) {
    if (faults.contains('hitTest')) throw StateError('injected hit fault');
    return super.getSpanForPositionVisitor(position, offset);
  }
}

Widget _app(Set<String> faults) => wrapHost(
  Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextAutoWrap.rich(
        _FaultySpan(faults),
        model: offsetModel([3]),
        strategy: offsetStrategy([3]),
      ),
      const SizedBox(key: _siblingKey, width: 5, height: 7),
    ],
  ),
);

void main() {
  testWidgets('a failing paragraph layout still lets the parent finish', (
    tester,
  ) async {
    final faults = <String>{};
    await tester.pumpWidget(_app(faults));
    final render = wrapRender(tester);
    expect(tester.takeException(), isNull);

    faults.add('build');
    render.markNeedsLayout();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_siblingKey)), const Size(5, 7));

    faults.clear();
    render.markNeedsLayout();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(render.result, isNotNull, reason: 'recovers once the fault is gone');
    expect(render.size.height, greaterThan(0));
  });

  testWidgets('failing intrinsic and dry queries never throw', (tester) async {
    final faults = <String>{};
    await tester.pumpWidget(_app(faults));
    final render = wrapRender(tester);
    faults.add('build');
    // Opaque spans bypass the native painter cache, so each query reshapes.
    render.markNeedsLayout();
    expect(() => render.getMinIntrinsicWidth(double.infinity), returnsNormally);
    expect(() => render.getMaxIntrinsicWidth(double.infinity), returnsNormally);
    expect(() => render.getMinIntrinsicHeight(100), returnsNormally);
    expect(() => render.getMaxIntrinsicHeight(100), returnsNormally);
    expect(
      () => render.getDryLayout(const BoxConstraints(maxWidth: 100)),
      returnsNormally,
    );
    expect(
      () => render.getDryBaseline(
        const BoxConstraints(maxWidth: 100),
        TextBaseline.alphabetic,
      ),
      returnsNormally,
    );
    faults.clear();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing semantics description does not abort the frame', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final faults = <String>{};
    await tester.pumpWidget(_app(faults));
    faults.add('semantics');
    wrapRender(tester).markNeedsSemanticsUpdate();
    await tester.pump();
    expect(tester.takeException(), isNull);
    faults.clear();
    handle.dispose();
  });

  testWidgets('a failing hit test is a miss instead of an error', (
    tester,
  ) async {
    final faults = <String>{};
    await tester.pumpWidget(_app(faults));
    faults.add('hitTest');
    await tester.tapAt(tester.getTopLeft(find.byType(TextAutoWrap)));
    expect(tester.takeException(), isNull);
    faults.clear();
  });
}
