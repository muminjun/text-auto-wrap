import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

import '../support/flutter_wrap.dart';

void main() {
  testWidgets('source query retries after a painter constructor failure', (
    tester,
  ) async {
    var failOnce = false;
    final probe = _ValidatedSpan(() {
      if (failOnce) {
        failOnce = false;
        throw StateError('injected painter validation failure');
      }
    });
    await tester.pumpWidget(
      wrapHost(
        TextAutoWrap.rich(
          TextSpan(
            children: [
              probe,
              const TextSpan(text: 'def'),
            ],
          ),
          model: offsetModel([3]),
          strategy: offsetStrategy([3]),
        ),
      ),
    );
    final render = wrapRender(tester);
    expect(render.result!.applied, isTrue);
    final effective = render.effectiveText;
    final selection = render.result;
    render.markNeedsLayout();
    failOnce = true;
    const query = BoxConstraints(maxWidth: 100);
    // Parent-facing queries never throw: the failure is recorded and the
    // native paragraph answers instead.
    expect(render.computeDryLayout(query), isA<Size>());
    expect(render.failures.single.reason, 'computeDryLayoutGuard');
    expect(render.failures.single.error, isA<StateError>());
    expect(render.effectiveText, same(effective));
    expect(render.result, same(selection));
    expect(render.computeDryLayout(query), const Size(60, 10));
    expect(render.computeDryLayout(query), const Size(60, 10));
    await tester.pump();
    expect(render.result!.applied, isTrue);
    expect(render.failures.single.reason, 'computeDryLayoutGuard');
    render.markNeedsLayout();
    await tester.pump();
    expect(render.result!.applied, isTrue);
    expect(render.failures, isEmpty);
  });
}

class _ValidatedSpan extends TextSpan {
  const _ValidatedSpan(this.validate) : super(text: 'abc', style: wrapStyle);
  final VoidCallback validate;

  @override
  bool debugAssertIsValid() {
    validate();
    return super.debugAssertIsValid();
  }
}
