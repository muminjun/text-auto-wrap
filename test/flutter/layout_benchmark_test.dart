import 'package:flutter_test/flutter_test.dart';

import '../../benchmark/layout_benchmark.dart';

void main() {
  testWidgets(
    'renderer benchmark records real rich scenarios and warm cache reuse',
    (tester) async {
      List<Map<String, Object?>>? rows;

      await tester.pumpWidget(
        BenchmarkHarness(iterations: 2, onComplete: (value) => rows = value),
      );
      await tester.pumpAndSettle();

      expect(rows, hasLength(12));
      final completed = rows!;
      expect(
        completed.map((row) => row['scenario']),
        containsAll(<String>['nested-100-spans', 'placeholders-20']),
      );
      expect(
        completed.singleWhere(
          (row) =>
              row['scenario'] == 'nested-100-spans' && row['cache'] == 'warm',
        )['richSpanCount'],
        100,
      );
      expect(
        completed.singleWhere(
          (row) =>
              row['scenario'] == 'placeholders-20' && row['cache'] == 'warm',
        )['placeholderCount'],
        20,
      );
      for (final row in completed.where((row) => row['cache'] == 'warm')) {
        expect(row['cacheHits'], greaterThan(0));
      }
    },
  );
}
