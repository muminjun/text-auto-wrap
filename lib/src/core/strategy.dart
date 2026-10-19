import 'layout.dart';
import 'prediction.dart';
import 'selection.dart';

/// Immutable stage configuration; omitted stages use the library defaults.
///
/// Widgets may reuse selections across renderers with equal configuration.
/// Custom stages must produce the same output for the same inputs while their
/// identity/equality remains unchanged. Replace the model/strategy when external
/// state changes; direct plan calculation still invokes the custom calculator.
final class LineBreakStrategy {
  const LineBreakStrategy({
    PredictionAggregator? aggregator,
    LayoutCalculator? calculator,
    this.selector = const BalanceStrategy(),
  }) : _aggregator = aggregator,
       _calculator = calculator;

  final PredictionAggregator? _aggregator;
  final LayoutCalculator? _calculator;
  PredictionAggregator get aggregator => _aggregator ?? lowestPenalty();
  LayoutCalculator get calculator => _calculator ?? optimalLayouts();
  final LayoutSelector selector;
}
