import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:text_auto_wrap/src/flutter/span_codec.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final scenarios = [
    _Scenario('short-20', 'word ' * 4),
    _Scenario('medium-100', 'word ' * 20),
    _Scenario('long-1000', 'word ' * 200),
    _Scenario('nested-100-spans', _nestedSpans(100)),
    _Scenario('placeholders-20', _placeholderSpans(20)),
    _Scenario('worst-case-boundaries', 'a' * 1000, worstCase: true),
  ];

  for (final scenario in scenarios) {
    _run(scenario, warm: false);
    _run(scenario, warm: true);
  }
  exit(0);
}

void _run(_Scenario scenario, {required bool warm}) {
  final model = PhraseModel(
    levels: [
      PhraseModelLevel(
        name: 'every-character',
        predictor: _Boundaries(worstCase: scenario.worstCase),
        penalty: 0,
      ),
    ],
    fallbackPenalty: 1,
    boundaryMode: BoundaryMode.characters,
  );
  final plan = createTextWrapPlan(
    text: scenario.text,
    model: model,
    strategy: LineBreakStrategy(
      calculator: scenario.worstCase ? optimalLayouts() : greedy(),
    ),
  );
  const iterations = 20;
  final key = Object();
  var measurements = 0;
  final stopwatch = Stopwatch()..start();
  TextWrapResult? result;
  for (var iteration = 0; iteration < iterations; iteration++) {
    result = plan.select(
      maxWidth: 120,
      measureRange: (start, end) {
        measurements++;
        return (end - start).toDouble();
      },
      measurementCacheKey: warm ? key : Object(),
      diagnostics: true,
    );
  }
  stopwatch.stop();
  final diagnostics = result!.diagnostics!;
  print(
    jsonEncode({
      'scenario': scenario.name,
      'cache': warm ? 'warm' : 'cold',
      'iterations': iterations,
      'candidateCount': diagnostics.candidates.length,
      'measurements': measurements,
      'cacheHits': diagnostics.cache.measurementHits,
      'elapsedMicroseconds': stopwatch.elapsedMicroseconds,
      'fallback': result.reason,
    }),
  );
}

String _nestedSpans(int count) {
  InlineSpan span = const TextSpan(text: 'word ');
  for (var index = 1; index < count; index++) {
    span = TextSpan(text: 'word ', children: [span]);
  }
  return encodeInlineSpan(span).text;
}

String _placeholderSpans(int count) => encodeInlineSpan(
  TextSpan(
    children: [
      for (var index = 0; index < count; index++) ...[
        const TextSpan(text: 'word '),
        const WidgetSpan(child: SizedBox(width: 12, height: 12)),
      ],
    ],
  ),
).text;

final class _Scenario {
  const _Scenario(this.name, this.text, {this.worstCase = false});

  final String name;
  final String text;
  final bool worstCase;
}

final class _Boundaries implements BoundaryPredictor {
  const _Boundaries({required this.worstCase});

  final bool worstCase;

  @override
  List<int> predict(String text) => [
    for (
      var offset = worstCase ? 1 : 5;
      offset < text.length;
      offset += worstCase ? 1 : 5
    )
      offset,
  ];
}
