import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BenchmarkHarness(
      onComplete: (rows) {
        for (final row in rows) {
          print(jsonEncode(row));
        }
        exit(0);
      },
    ),
  );
}

/// Drives the renderer through cold and warm layouts for each rich scenario.
///
/// The harness intentionally reports observations only. Shared machines vary
/// too much for an absolute duration to be a correctness threshold.
class BenchmarkHarness extends StatefulWidget {
  const BenchmarkHarness({
    required this.onComplete,
    this.iterations = 20,
    super.key,
  }) : assert(iterations > 0);

  final int iterations;
  final ValueChanged<List<Map<String, Object?>>> onComplete;

  @override
  State<BenchmarkHarness> createState() => _BenchmarkHarnessState();
}

class _BenchmarkHarnessState extends State<BenchmarkHarness> {
  late final List<_BenchmarkScenario> _scenarios = [
    _makeScenario('short-20', TextSpan(text: 'word ' * 4)),
    _makeScenario('medium-100', TextSpan(text: 'word ' * 20)),
    _makeScenario('long-1000', TextSpan(text: 'word ' * 200)),
    _makeScenario('nested-100-spans', _nestedSpans(100), richSpanCount: 100),
    _makeScenario(
      'placeholders-20',
      _placeholderSpans(20),
      placeholderCount: 20,
    ),
    _makeScenario(
      'worst-case-boundaries',
      TextSpan(text: 'a' * 1000),
      worstCase: true,
    ),
  ];
  final _rows = <Map<String, Object?>>[];
  var _scenarioIndex = 0;
  var _warm = false;
  var _iteration = 0;
  var _complete = false;
  GlobalKey _renderKey = GlobalKey();
  TextAutoWrapController _controller = TextAutoWrapController();
  final Stopwatch _stopwatch = Stopwatch();

  _BenchmarkScenario get _scenario => _scenarios[_scenarioIndex];

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 10, color: Color(0xff000000)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 120,
          child: TextAutoWrap.rich(
            key: _renderKey,
            _sourceForIteration(),
            model: _scenario.model,
            strategy: _scenario.strategy,
            controller: _controller,
            // The last warm iteration deliberately bypasses the final-result
            // cache without changing measurement inputs. This observes plan
            // and range-width reuse in addition to final-selection reuse.
            maxLines: _warm && _iteration == widget.iterations - 1
                ? 1000
                : null,
          ),
        ),
      ),
    ),
  );

  InlineSpan _sourceForIteration() {
    if (_warm) return _scenario.span;
    return TextSpan(
      semanticsIdentifier: '${_scenario.name}:$_iteration',
      children: [_scenario.span],
    );
  }

  void _afterFrame(Duration _) {
    if (_complete) return;
    final result = _controller.result;
    if (result == null) {
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
      return;
    }
    if (_iteration + 1 < widget.iterations) {
      setState(() => _iteration++);
      WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
      return;
    }

    _stopwatch.stop();
    final diagnostics = result.diagnostics;
    if (diagnostics == null) {
      throw StateError(
        'Benchmark renderer did not provide diagnostics: ${result.reason}.',
      );
    }
    final cache = diagnostics.cache;
    _rows.add({
      'scenario': _scenario.name,
      'cache': _warm ? 'warm' : 'cold',
      'iterations': widget.iterations,
      'candidateCount': diagnostics.candidates.length,
      'measurements': cache.measurementRuns,
      'cacheHits':
          cache.selectionCacheHits + cache.planHits + cache.measurementHits,
      'elapsedMicroseconds': _stopwatch.elapsedMicroseconds,
      'fallback': result.reason,
      'richSpanCount': _scenario.richSpanCount,
      'placeholderCount': _scenario.placeholderCount,
    });

    if (_warm) {
      _scenarioIndex++;
      _warm = false;
    } else {
      _warm = true;
    }
    if (_scenarioIndex == _scenarios.length) {
      _complete = true;
      widget.onComplete(List.unmodifiable(_rows));
      return;
    }
    setState(() {
      _iteration = 0;
      // Each row begins with a fresh renderer; frames within the row are the
      // cold or warm sequence being measured.
      _renderKey = GlobalKey();
      _controller.dispose();
      _controller = TextAutoWrapController();
      _stopwatch
        ..reset()
        ..start();
    });
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

_BenchmarkScenario _makeScenario(
  String name,
  InlineSpan span, {
  int richSpanCount = 1,
  int placeholderCount = 0,
  bool worstCase = false,
}) => _BenchmarkScenario(
  name: name,
  span: span,
  richSpanCount: richSpanCount,
  placeholderCount: placeholderCount,
  model: PhraseModel(
    levels: [
      PhraseModelLevel(
        name: 'benchmark-boundaries',
        predictor: _Boundaries(worstCase: worstCase),
        penalty: 0,
      ),
    ],
    fallbackPenalty: 1,
    boundaryMode: BoundaryMode.characters,
  ),
  strategy: LineBreakStrategy(
    calculator: worstCase ? optimalLayouts() : greedy(),
  ),
);

InlineSpan _nestedSpans(int count) {
  InlineSpan span = const TextSpan(text: 'word ');
  for (var index = 1; index < count; index++) {
    span = TextSpan(text: 'word ', children: [span]);
  }
  return span;
}

InlineSpan _placeholderSpans(int count) => TextSpan(
  children: [
    for (var index = 0; index < count; index++) ...[
      const TextSpan(text: 'word '),
      const WidgetSpan(child: SizedBox(width: 12, height: 12)),
    ],
  ],
);

final class _BenchmarkScenario {
  const _BenchmarkScenario({
    required this.name,
    required this.span,
    required this.model,
    required this.strategy,
    required this.richSpanCount,
    required this.placeholderCount,
  });

  final String name;
  final InlineSpan span;
  final PhraseModel model;
  final LineBreakStrategy strategy;
  final int richSpanCount;
  final int placeholderCount;
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
