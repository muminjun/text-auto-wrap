// Injects a failure at every guarded point and checks that one text falls back
// to the source paragraph (or goes inert) while the parent layout completes.
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/src/flutter/render_text_auto_wrap.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

const _siblingKey = ValueKey('sibling');

Widget _app({TextAutoWrapController? controller, String text = 'abcdef'}) =>
    wrapHost(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextAutoWrap(
            text,
            model: offsetModel([3]),
            strategy: offsetStrategy([3]),
            controller: controller,
          ),
          const SizedBox(key: _siblingKey, width: 5, height: 7),
        ],
      ),
    );

void _expectParentFinished(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(tester.getSize(find.byKey(_siblingKey)), const Size(5, 7));
}

void main() {
  tearDown(() => RenderTextAutoWrap.debugFaultInjector = null);

  group('layout', () {
    testWidgets('semantic stage failure repaints the source paragraph', (
      tester,
    ) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller: controller));
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);

      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'performLayout') throw StateError('semantic fault');
      };
      render.markNeedsLayout();
      await tester.pump();

      _expectParentFinished(tester);
      expect(render.effectiveText, same(render.sourceText));
      expect(render.debugLayoutBroken, isFalse);
      expect(render.size.height, greaterThan(0));
      expect(render.result, isNull);
      expect(render.failures.single.reason, 'layoutGuard');
      expect(render.failures.single.stage, TextWrapFailureStage.semanticLayout);
      expect(controller.result, isNull);
      expect(controller.failures.single.error, isA<StateError>());
    });

    testWidgets('a failing wrapped paragraph is retried with the source', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      final sourceHeight = (TextPainter(
        text: render.sourceText,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 100)).height;

      var failures = 1;
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'superPerformLayout' && failures-- > 0) {
          throw StateError('engine rejected the wrapped paragraph');
        }
      };
      render.markNeedsLayout();
      await tester.pump();

      _expectParentFinished(tester);
      expect(render.effectiveText, same(render.sourceText));
      expect(render.debugLayoutBroken, isFalse);
      expect(render.size.height, sourceHeight);
      expect(render.failures.single.reason, 'layoutGuard');
    });

    testWidgets('an unlayoutable source goes inert but never throws', (
      tester,
    ) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller: controller));
      final render = wrapRender(tester);

      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'superPerformLayout') throw StateError('engine fault');
      };
      render.markNeedsLayout();
      await tester.pump();

      _expectParentFinished(tester);
      expect(render.debugLayoutBroken, isTrue);
      expect(render.size, Size.zero);
      expect(render.result, isNull);
      expect(
        render.failures.map((failure) => failure.reason),
        contains('nativeLayoutGuard'),
      );
      // Inert state: no paint, hit test, or baseline work on a missing layout.
      expect(
        render.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        0,
      );
      expect(
        render.hitTest(BoxHitTestResult(), position: Offset.zero),
        isFalse,
      );

      RenderTextAutoWrap.debugFaultInjector = null;
      render.markNeedsLayout();
      await tester.pump();
      _expectParentFinished(tester);
      expect(render.debugLayoutBroken, isFalse);
      expect(render.result, isNotNull);
      expect(render.failures, isEmpty);
    });
  });

  group('parent queries', () {
    testWidgets('parent query failures survive the following layout snapshot', (
      tester,
    ) async {
      final controller = TextAutoWrapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller: controller));
      final render = wrapRender(tester);
      var throwsLeft = 1;
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'computeMaxIntrinsicWidth' && throwsLeft-- > 0) {
          throw StateError('one parent query failed');
        }
      };
      for (var frame = 0; frame < 2; frame++) {
        render.markNeedsLayout();
        throwsLeft = 1;
        render.getMaxIntrinsicWidth(double.infinity);
        await tester.pump();
        expect(
          render.failures.map((f) => f.reason),
          contains('computeMaxIntrinsicWidthGuard'),
        );
        expect(
          controller.failures.map((f) => f.reason),
          contains('computeMaxIntrinsicWidthGuard'),
        );
      }
      RenderTextAutoWrap.debugFaultInjector = null;
      render.markNeedsLayout();
      await tester.pump();
      expect(render.failures, isEmpty);
      expect(controller.failures, isEmpty);
    });

    for (final point in const [
      'computeMinIntrinsicWidth',
      'computeMaxIntrinsicWidth',
      'computeMinIntrinsicHeight',
      'computeMaxIntrinsicHeight',
      'computeDryLayout',
      'computeDryBaseline',
    ]) {
      testWidgets('$point falls back to the native query', (tester) async {
        await tester.pumpWidget(_app());
        final render = wrapRender(tester);
        RenderTextAutoWrap.debugFaultInjector = (name) {
          if (name == point) throw StateError('fault at $point');
        };
        render.markNeedsLayout();
        // The native fallback answers for the committed (wrapped) paragraph.
        const constraints = BoxConstraints(maxWidth: 100);
        switch (point) {
          case 'computeMinIntrinsicWidth':
            expect(render.getMinIntrinsicWidth(double.infinity), 30);
          case 'computeMaxIntrinsicWidth':
            expect(render.getMaxIntrinsicWidth(double.infinity), 30);
          case 'computeMinIntrinsicHeight':
            expect(render.getMinIntrinsicHeight(100), 20);
          case 'computeMaxIntrinsicHeight':
            expect(render.getMaxIntrinsicHeight(100), 20);
          case 'computeDryLayout':
            expect(render.getDryLayout(constraints), const Size(30, 20));
          case 'computeDryBaseline':
            expect(
              render.getDryBaseline(constraints, TextBaseline.alphabetic),
              isA<double>(),
            );
        }
        expect(render.failures.single.reason, '${point}Guard');
        RenderTextAutoWrap.debugFaultInjector = null;
        await tester.pump();
        _expectParentFinished(tester);
      });
    }

    testWidgets('a query that fails natively too returns a safe value', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      final render = wrapRender(tester);
      render.markNeedsLayout();
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point.startsWith('computeDryLayout')) {
          throw StateError('fault at $point');
        }
      };
      const constraints = BoxConstraints(minWidth: 3, maxWidth: 100);
      expect(render.getDryLayout(constraints), constraints.smallest);
      expect(render.failures.single.reason, 'computeDryLayoutGuard');
    });

    testWidgets('baseline lookup failure reports and answers zero', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      final render = wrapRender(tester);
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'computeDistanceToActualBaseline') {
          throw StateError('baseline fault');
        }
      };
      expect(
        render.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        0,
      );
      expect(
        render.failures.single.reason,
        'computeDistanceToActualBaselineGuard',
      );
    });
  });

  group('paint, hit test and semantics', () {
    testWidgets('a paint failure skips the frame and repaints natively', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      final render = wrapRender(tester);
      expect(render.result!.applied, isTrue);
      var failures = 1;
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'paint' && failures-- > 0) throw StateError('paint fault');
      };
      render.markNeedsPaint();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(render.failures.single.reason, 'paintGuard');
      // The post-frame relayout drops the inserted breaks and keeps the record.
      await tester.pump();
      await tester.pump();
      _expectParentFinished(tester);
      expect(render.effectiveText, same(render.sourceText));
      expect(render.failures.single.reason, 'paintGuard');
    });

    testWidgets('a hit test failure is a miss', (tester) async {
      await tester.pumpWidget(_app());
      final render = wrapRender(tester);
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'hitTestChildren') throw StateError('hit fault');
      };
      expect(
        render.hitTest(BoxHitTestResult(), position: const Offset(1, 1)),
        isTrue,
        reason: 'the paragraph itself still claims the pointer',
      );
      expect(render.failures.single.reason, 'hitTestChildrenGuard');
    });

    testWidgets('a semantics description failure keeps a plain label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());
      final render = wrapRender(tester);
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'describeSemanticsConfiguration') {
          throw StateError('semantics fault');
        }
      };
      render.markNeedsSemanticsUpdate();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        render.failures.single.reason,
        'describeSemanticsConfigurationGuard',
      );
      expect(find.bySemanticsLabel('abcdef'), findsOneWidget);
      RenderTextAutoWrap.debugFaultInjector = null;
      handle.dispose();
    });

    testWidgets('a semantics assembly failure still updates the node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final recognizer = TapGestureRecognizer();
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
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'assembleSemanticsNode') {
          throw StateError('assemble fault');
        }
      };
      render.markNeedsSemanticsUpdate();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        render.failures.map((failure) => failure.reason),
        contains('assembleSemanticsNodeGuard'),
      );
      RenderTextAutoWrap.debugFaultInjector = null;
      handle.dispose();
    });
  });

  group('widget update', () {
    testWidgets('a source swap that throws is deferred to native layout', (
      tester,
    ) async {
      await tester.pumpWidget(_app(text: 'abcdef'));
      final render = wrapRender(tester);
      RenderTextAutoWrap.debugFaultInjector = (point) {
        if (point == 'sourceText') throw StateError('span comparison fault');
      };
      await tester.pumpWidget(_app(text: 'ghijkl'));
      RenderTextAutoWrap.debugFaultInjector = null;
      await tester.pump();

      _expectParentFinished(tester);
      expect(render.sourceText.toPlainText(), 'ghijkl');
      expect(render.effectiveText.toPlainText(), 'ghijkl');
      expect(render.failures.single.reason, 'sourceTextGuard');
    });
  });
}
