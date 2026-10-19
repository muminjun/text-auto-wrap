import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('dominated line counts do not spend the 256 measurement budget', () {
    final text = List.filled(24, 'abc').join(' ');
    final candidates = [
      for (var i = 1; i < 24; i++)
        BreakCandidate(
          offset: i * 4,
          penalty: 0,
          levelName: 'test',
          consensusCount: 1,
          isFallback: false,
        ),
    ];
    var calls = 0;
    final result =
        optimalLayouts().calculate(
              text: text,
              candidates: candidates,
              maxWidth: 350,
              measureRange: (start, end) {
                calls++;
                if (calls > 256) {
                  throw StateError('measurement budget exceeded');
                }
                return (end - start) * 10.0;
              },
            )
            as LayoutCalculationSuccess;
    expect(result.layouts.first.lineCount, 3);
    expect(calls, lessThan(256));
  });
}
