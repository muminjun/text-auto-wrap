import 'dart:math' as math;

import 'exceptions.dart';
import 'layout.dart';

/// The origin of the selected layout.
enum TextWrapSelectionSource { native, calculated }

/// An immutable decision referring to the supplied selection context.
final class LayoutSelectionDecision {
  const LayoutSelectionDecision.native({this.reason = 'nativeSelected'})
    : source = TextWrapSelectionSource.native,
      index = null;

  const LayoutSelectionDecision.calculated(
    int this.index, {
    this.reason = 'calculatedSelected',
  }) : source = TextWrapSelectionSource.calculated;

  final TextWrapSelectionSource source;
  final int? index;

  /// Stable library reason, or a custom selector's application-specific reason.
  final String reason;
}

/// Immutable layouts and final rendering line limit for a selector.
final class LayoutSelectionContext {
  LayoutSelectionContext({
    required List<LineBreakLayout> calculatedLayouts,
    this.nativeLayout,
    this.maxLines,
  }) : calculatedLayouts = List.unmodifiable(calculatedLayouts) {
    if (maxLines != null && maxLines! < 1) {
      throw const InvalidModelConfigurationException(
        'maxLines must be positive.',
      );
    }
  }
  final List<LineBreakLayout> calculatedLayouts;
  final LineBreakLayout? nativeLayout;
  final int? maxLines;
}

/// Selects a measured calculated layout or the native baseline.
abstract interface class LayoutSelector {
  LayoutSelectionDecision select(LayoutSelectionContext context);
}

/// Requires model improvement before replacing a fitting native layout.
///
/// Among minimum-line layouts, first retain those within [tolerance] of the
/// best imbalance, then prefer model cost, balance, native, and break order.
/// Adapted from semantic-wrap's selectors.ts at the revision in NOTICE.
final class BalanceStrategy implements LayoutSelector {
  const BalanceStrategy({this.tolerance = .12});
  final double tolerance;
  static const _epsilon = 1e-9;

  @override
  LayoutSelectionDecision select(LayoutSelectionContext context) {
    if (!tolerance.isFinite || tolerance < 0 || tolerance > 1) {
      throw const InvalidModelConfigurationException(
        'Balance tolerance must be between zero and one.',
      );
    }
    final calculated = [
      for (var i = 0; i < context.calculatedLayouts.length; i++)
        (
          layout: context.calculatedLayouts[i],
          decision: LayoutSelectionDecision.calculated(i),
        ),
    ];
    bool fits(LineBreakLayout layout) =>
        !layout.overflow &&
        (context.maxLines == null || layout.lineCount <= context.maxLines!);
    final fitting = calculated.where((entry) => fits(entry.layout)).toList();
    final native = context.nativeLayout;
    if (native == null) {
      return _choose(fitting.isEmpty ? calculated : fitting);
    }
    if (!fits(native)) {
      return fitting.isEmpty
          ? const LayoutSelectionDecision.native()
          : _choose(fitting);
    }
    final improved = fitting
        .where(
          (entry) =>
              entry.layout.lineCount == native.lineCount &&
              entry.layout.totalModelCost < native.totalModelCost - _epsilon,
        )
        .toList();
    if (improved.isEmpty) {
      return const LayoutSelectionDecision.native(
        reason: 'nativeNoModelImprovement',
      );
    }
    return _choose([
      ...improved,
      (layout: native, decision: const LayoutSelectionDecision.native()),
    ]);
  }

  LayoutSelectionDecision _choose(
    List<({LineBreakLayout layout, LayoutSelectionDecision decision})> layouts,
  ) {
    if (layouts.isEmpty) {
      throw const InvalidModelConfigurationException(
        'A selector needs at least one layout.',
      );
    }
    final count = layouts
        .map((entry) => entry.layout.lineCount)
        .reduce(math.min);
    var eligible = layouts
        .where((entry) => entry.layout.lineCount == count)
        .toList();
    final best = eligible
        .map((entry) => entry.layout.imbalance)
        .reduce(math.min);
    eligible = eligible
        .where((entry) => entry.layout.imbalance <= best + tolerance + _epsilon)
        .toList();
    eligible.sort((left, right) {
      final cost = left.layout.totalModelCost - right.layout.totalModelCost;
      if (cost.abs() > _epsilon) return cost.sign.toInt();
      final balance = left.layout.imbalance - right.layout.imbalance;
      if (balance.abs() > _epsilon) return balance.sign.toInt();
      if (left.decision.source != right.decision.source) {
        return left.decision.source == TextWrapSelectionSource.native ? -1 : 1;
      }
      return left.layout.breakOffsets
          .join(',')
          .compareTo(right.layout.breakOffsets.join(','));
    });
    return eligible.first.decision;
  }
}
