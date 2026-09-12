import 'layout.dart';
import 'prediction.dart';
import 'selection.dart';

/// Immutable stage configuration; omitted stages use the library defaults.
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
