import 'diagnostics.dart';
import 'layout.dart';
import 'models.dart';
import 'plan.dart';
import 'strategy.dart';

/// Input for a synchronous one-shot selection.
final class TextWrapInput {
  const TextWrapInput({
    required this.text,
    required this.model,
    required this.maxWidth,
    required this.measureRange,
    this.nativeLayout,
    this.maxLines,
    this.measurementCacheKey,
  });
  final String text;

  /// A resolved phrase model; null explicitly requests unsupported-language fallback.
  final PhraseModel? model;
  final double maxWidth;
  final TextRangeMeasurer measureRange;
  final LineBreakLayout? nativeLayout;
  final int? maxLines;
  final Object? measurementCacheKey;
}

/// Runs the complete synchronous engine with optional stage diagnostics.
TextWrapResult selectTextWrap(
  TextWrapInput input, {
  LineBreakStrategy strategy = const LineBreakStrategy(),
  bool diagnostics = false,
}) =>
    createTextWrapPlan(
      text: input.text,
      model: input.model,
      strategy: strategy,
    ).select(
      maxWidth: input.maxWidth,
      measureRange: input.measureRange,
      nativeLayout: input.nativeLayout,
      maxLines: input.maxLines,
      measurementCacheKey: input.measurementCacheKey,
      diagnostics: diagnostics,
    );
