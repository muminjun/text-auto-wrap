import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';

import '../core/boundaries.dart';
import '../core/diagnostics.dart';
import '../core/exceptions.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/plan.dart';
import '../core/selection.dart';
import '../core/strategy.dart';
import '../models/language_detection.dart';
import 'controller.dart';
import 'span_codec.dart';
import 'text_geometry.dart';

/// A [RenderParagraph] that chooses semantic line breaks before final layout.
///
/// The inherited paragraph remains responsible for final positioning, paint,
/// hit testing, selection, and semantics. This adapter restores source text
/// when inputs change and commits the selected span during [performLayout],
/// before any intermediate paragraph can be painted.
class RenderTextAutoWrap extends RenderParagraph {
  RenderTextAutoWrap({
    required InlineSpan sourceText,
    required TextWrapModel model,
    required LineBreakStrategy strategy,
    TextAutoWrapController? controller,
    TextAlign textAlign = TextAlign.start,
    required TextDirection textDirection,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    TextScaler textScaler = TextScaler.noScaling,
    int? maxLines,
    Locale? locale,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    TextHeightBehavior? textHeightBehavior,
    List<RenderBox>? children,
    Color? selectionColor,
    SelectionRegistrar? registrar,
    double devicePixelRatio = 1.0,
  }) : _sourceText = sourceText,
       _model = model,
       _strategy = strategy,
       _sourceContainsOpaqueSpan = _containsOpaqueSpan(sourceText),
       _sourceSharable = _isPlainTextTree(sourceText),
       _controller = controller,
       _devicePixelRatio = devicePixelRatio,
       _effectiveTextKey = _InlineSpanCacheKey(sourceText),
       super(
         sourceText,
         textAlign: textAlign,
         textDirection: textDirection,
         softWrap: softWrap,
         overflow: overflow,
         textScaler: textScaler,
         maxLines: maxLines,
         locale: locale,
         strutStyle: strutStyle,
         textWidthBasis: textWidthBasis,
         textHeightBehavior: textHeightBehavior,
         children: children,
         selectionColor: selectionColor,
         registrar: registrar,
       );

  InlineSpan _sourceText;
  TextWrapModel _model;
  LineBreakStrategy _strategy;
  TextAutoWrapController? _controller;
  TextWrapResult? _lastResult;
  List<TextWrapFailure> _lastFailures = const [];
  TextWrapPlan? _cachedPlan;
  bool _cachedPlanShared = false;
  _RendererPlanKey? _cachedPlanKey;
  _RendererSelectionKey? _cachedSelectionKey;
  TextWrapResult? _cachedSelection;
  InlineSpan? _cachedEffectiveText;
  bool _sourceContainsOpaqueSpan;
  bool _sourceSharable;
  bool _opaqueTextNeedsRefresh = false;
  _InlineSpanCacheKey _effectiveTextKey;
  double _devicePixelRatio;
  TextPainter? _sourceQueryPainter;
  Object? _sourceQueryKey;
  final _sourceQueries = <(double, double), _SourceQueryMetrics>{};
  var _planHits = 0;
  var _planMisses = 0;
  var _selectionCacheHits = 0;
  var _selectionCacheMisses = 0;

  // ignore: annotate_overrides
  double get devicePixelRatio => _devicePixelRatio;

  // ignore: annotate_overrides
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    if (kIsWeb) markNeedsPaint();
  }

  /// The unmodified span supplied by the widget.
  InlineSpan get sourceText => _sourceText;

  /// The span committed before the current paragraph's final layout.
  @visibleForTesting
  InlineSpan get effectiveText => super.text;

  /// The most recent selection made by this renderer, including fallback.
  @visibleForTesting
  TextWrapResult? get result => _lastResult;

  /// Drops the selections and plans shared by renderers with equal inputs.
  @visibleForTesting
  static void clearSharedCaches() => _SharedLayoutCache.clear();

  /// Entry counts of the shared selection and plan caches.
  @visibleForTesting
  static ({int selections, int plans}) get sharedCacheSizes => (
    selections: _SharedLayoutCache.selectionCount,
    plans: _SharedLayoutCache.planCount,
  );

  /// Adapter failures from the latest layout, including unavailable geometry.
  List<TextWrapFailure> get failures => _lastFailures;

  set sourceText(InlineSpan value) {
    if (identical(_sourceText, value)) return;
    try {
      _fault('sourceText');
      _updateSourceText(value);
    } catch (error, stackTrace) {
      // Comparing or replacing spans runs user-defined span code during the
      // build phase. Keep the new source and let the next layout paint it
      // natively instead of failing the widget update.
      _sourceText = value;
      _sourceContainsOpaqueSpan = true;
      _sourceSharable = false;
      _forceNativeNextLayout = true;
      _discardSelectionCaches();
      _deferFailure('sourceText', error, stackTrace);
      markNeedsLayout();
    }
  }

  void _updateSourceText(InlineSpan value) {
    final unchanged =
        _InlineSpanCacheKey(_sourceText) == _InlineSpanCacheKey(value);
    _sourceText = value;
    _sourceContainsOpaqueSpan = _containsOpaqueSpan(value);
    _sourceSharable = _isPlainTextTree(value);
    // Rebuilt equivalent spans must not temporarily remove semantic breaks:
    // replacing the paragraph disposes active selection fragments, which can
    // collapse selection when the renderer also moves to another parent.
    if (unchanged) {
      markNeedsLayout();
      return;
    }
    // Parents can request intrinsic/dry sizes before performLayout. Restore
    // the current source in Flutter's painters before they choose constraints.
    _replaceParagraphText(value);
    markNeedsLayout();
  }

  set model(TextWrapModel value) {
    if (identical(_model, value)) return;
    _model = value;
    markNeedsLayout();
  }

  set strategy(LineBreakStrategy value) {
    if (identical(_strategy, value)) return;
    _strategy = value;
    markNeedsLayout();
  }

  set controller(TextAutoWrapController? value) {
    if (identical(_controller, value)) return;
    _controller?.detachOwner(this);
    _controller = value;
    final result = _lastResult;
    if (result != null) {
      _controller?.commitResult(this, result, failures: _lastFailures);
    } else if (_lastFailures.isNotEmpty) {
      _controller?.clearResult(this, failures: _lastFailures);
    }
  }

  /// Test hook invoked at the start of each guarded region with its name.
  ///
  /// A hook that throws simulates a failure at that point, which lets tests
  /// prove that the final guard keeps the parent layout alive.
  @visibleForTesting
  static void Function(String point)? debugFaultInjector;

  /// Whether the last layout could not produce any paragraph at all.
  @visibleForTesting
  bool get debugLayoutBroken => _layoutBroken;

  bool _layoutBroken = false;
  bool _forceNativeNextLayout = false;

  void _fault(String point) => debugFaultInjector?.call(point);

  /// Lays out the paragraph with whatever text is currently committed.
  void _layoutNativeParagraph() {
    try {
      _fault('superPerformLayout');
      super.performLayout();
      _layoutBroken = false;
    } catch (_) {
      // Remember whether the failing paragraph was already the plain source:
      // repeating that exact layout cannot succeed, so recovery skips it.
      _nativeLayoutFailedOnSource =
          _effectiveTextKey == _InlineSpanCacheKey(_sourceText);
      rethrow;
    }
  }

  bool _nativeLayoutFailedOnSource = false;

  @override
  void performLayout() {
    // The semantic path is an enhancement: whatever fails inside it, this
    // render object must still finish layout so the parent can complete.
    _nativeLayoutFailedOnSource = false;
    final deferred = _deferredFailures;
    _deferredFailures = const [];
    _lastFailures = const [];
    try {
      _fault('performLayout');
      _performSemanticLayout();
      _layoutBroken = false;
    } catch (error, stackTrace) {
      _recoverLayout(error, stackTrace);
    } finally {
      if (deferred.isNotEmpty) {
        final reasons = _lastFailures.map((failure) => failure.reason).toSet();
        _lastFailures = List.unmodifiable([
          ..._lastFailures,
          for (final failure in deferred)
            if (reasons.add(failure.reason)) failure,
        ]);
        final result = _lastResult;
        if (result == null) {
          _controller?.clearResult(this, failures: _lastFailures);
        } else {
          _controller?.commitResult(this, result, failures: _lastFailures);
        }
      }
    }
  }

  /// Last-resort recovery: paint the source text with plain paragraph layout.
  ///
  /// If even that fails (Flutter or the engine rejects the source itself),
  /// the render object takes the smallest allowed size and stays inert, so
  /// the failure is limited to this one text.
  void _recoverLayout(Object error, StackTrace stackTrace) {
    final nativeFailedOnSource = _nativeLayoutFailedOnSource;
    final failures = <TextWrapFailure>[
      ..._lastFailures,
      TextWrapFailure(
        stage: nativeFailedOnSource
            ? TextWrapFailureStage.nativeMeasurement
            : TextWrapFailureStage.semanticLayout,
        reason: nativeFailedOnSource ? 'nativeLayoutGuard' : 'layoutGuard',
        error: error,
        stackTrace: stackTrace,
      ),
    ];
    _discardSelectionCaches();
    var painted = false;
    if (!nativeFailedOnSource) {
      try {
        _setEffectiveText(_sourceText);
        _layoutNativeParagraph();
        painted = true;
      } catch (nativeError, nativeStack) {
        failures.add(
          TextWrapFailure(
            stage: TextWrapFailureStage.nativeMeasurement,
            reason: 'nativeLayoutGuard',
            error: nativeError,
            stackTrace: nativeStack,
          ),
        );
      }
    }
    if (!painted) {
      size = constraints.constrain(Size.zero);
      _layoutBroken = true;
    }
    _lastResult = null;
    _lastFailures = List.unmodifiable(failures);
    _controller?.clearResult(this, failures: _lastFailures);
  }

  void _discardSelectionCaches() {
    _cachedPlan = null;
    _cachedPlanKey = null;
    _cachedSelection = null;
    _cachedSelectionKey = null;
    _cachedEffectiveText = null;
  }

  void _performSemanticLayout() {
    final constraints = this.constraints;
    if (_forceNativeNextLayout) {
      _forceNativeNextLayout = false;
      _commitFallback(reason: 'guardedFallback', measureNative: false);
      _layoutNativeParagraph();
      return;
    }
    if (!constraints.hasBoundedWidth ||
        !constraints.maxWidth.isFinite ||
        constraints.maxWidth <= 0 ||
        !softWrap) {
      _commitFallback(reason: softWrap ? 'unusableWidth' : 'softWrapDisabled');
      _layoutNativeParagraph();
      return;
    }

    TextPainter? sourcePainter;
    LineBreakLayout? nativeLayout;
    var nativeMeasurementAttempted = false;
    try {
      final encoded = encodeInlineSpan(_sourceText);
      if (encoded.text.length > maxSemanticTextLength) {
        throw const TextWrapInputLimitException(
          'Semantic input exceeds 65536 UTF-16 code units.',
        );
      }
      late final List<PlaceholderDimensions> placeholders;
      try {
        placeholders = _layoutPlaceholders(
          encoded.placeholderSpans,
          constraints.maxWidth,
        );
      } on UnsupportedSpanTransformationException {
        // An opaque custom span with a widget descendant cannot be indexed for
        // candidate measurement. Preserve its real native source layout for
        // the fallback result, without entering the transform path.
        final nativePlaceholders = _layoutPlaceholdersForNativeFallback(
          constraints.maxWidth,
        );
        nativeMeasurementAttempted = true;
        sourcePainter = _painter(_sourceText, nativePlaceholders);
        sourcePainter.layout(
          minWidth: constraints.minWidth,
          maxWidth: _maxLayoutWidth(constraints.maxWidth),
        );
        nativeLayout = measureNativeTextLayout(
          sourcePainter,
          encoded.text,
          constraints.maxWidth,
        );
        rethrow;
      }
      final model = _resolvedModel(encoded.text);
      final planKey = _RendererPlanKey(
        text: encoded.text,
        model: model,
        strategy: _strategy,
      );
      final measurementKey = _RendererMeasurementKey(
        source: _sourceText,
        maxWidth: constraints.maxWidth,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        placeholders: _PlaceholderCacheKey(placeholders),
      );
      // Range widths are shaped at unbounded width, so only the placeholder
      // dimensions (already in the key) tie them to the available width. The
      // plan keeps its range cache while the width changes.
      final rangeKey = measurementKey.withoutWidth();
      final shareable =
          _sourceSharable &&
          placeholders.isEmpty &&
          encoded.text.length <= _SharedLayoutCache.maxTextLength;
      final selectionKey = _RendererSelectionKey(
        plan: planKey,
        measurement: measurementKey,
        minWidth: constraints.minWidth,
        textAlign: textAlign,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
      );
      final cached = _cachedSelection;
      if (shareable) _SharedLayoutCache.prepare();
      final shared =
          shareable && !(_cachedSelectionKey == selectionKey && cached != null)
          ? _SharedLayoutCache.selection(selectionKey)
          : null;
      if (shared != null) {
        // An equivalent renderer already selected and verified this layout.
        _selectionCacheHits++;
        nativeLayout = shared.result.diagnostics?.nativeLayout;
        _cachedSelectionKey = selectionKey;
        _cachedSelection = shared.result;
        _cachedEffectiveText = shared.effectiveText;
        _setEffectiveText(shared.effectiveText);
        _commit(_withRendererCache(shared.result));
      } else if (_cachedSelectionKey == selectionKey && cached != null) {
        _selectionCacheHits++;
        nativeLayout = cached.diagnostics?.nativeLayout;
        // The complete measurement key includes the current child dimensions.
        // Reuse the paragraph already checked against native paint instead of
        // inserting breaks and shaping a second validation paragraph on every
        // equal-height parent pass.
        _setEffectiveText(_cachedEffectiveText!);
        _commit(_withRendererCache(cached));
      } else {
        _selectionCacheMisses++;
        nativeMeasurementAttempted = true;
        sourcePainter = _painter(_sourceText, placeholders);
        sourcePainter.layout(
          minWidth: constraints.minWidth,
          maxWidth: _maxLayoutWidth(constraints.maxWidth),
        );
        nativeLayout = measureNativeTextLayout(
          sourcePainter,
          encoded.text,
          constraints.maxWidth,
        );
        final result = _planFor(planKey, shareable: shareable).select(
          maxWidth: constraints.maxWidth,
          nativeLayout: nativeLayout,
          maxLines: maxLines,
          measureRange: (start, end) =>
              _measureRange(encoded, start, end, placeholders),
          measurementCacheKey: rangeKey,
          diagnostics: true,
        );
        _commitSelection(encoded, _withRendererCache(result), placeholders);
        if (_lastFailures.isEmpty && _lastResult != null) {
          _cachedSelectionKey = selectionKey;
          _cachedSelection = _lastResult;
          _cachedEffectiveText = super.text;
          if (shareable) {
            _SharedLayoutCache.putSelection(
              selectionKey,
              _SharedSelection(_lastResult!, super.text),
            );
          }
        }
      }
    } catch (error, stackTrace) {
      // Rendering valid content wins over a semantic-layout attempt. This also
      // covers invalid custom predictions, unavailable measurements, and span
      // transformations that would discard custom InlineSpan state.
      _commitFallback(
        reason: _fallbackReason(error),
        nativeLayout: nativeLayout,
        measureNative:
            !nativeMeasurementAttempted &&
            error is! TextWrapInputLimitException,
        failures: [
          TextWrapFailure(
            stage: nativeMeasurementAttempted && nativeLayout == null
                ? TextWrapFailureStage.nativeMeasurement
                : TextWrapFailureStage.semanticLayout,
            reason: _fallbackReason(error),
            error: error,
            stackTrace: stackTrace,
          ),
        ],
      );
    } finally {
      sourcePainter?.dispose();
    }
    _layoutNativeParagraph();
  }

  /// Runs a parent-facing geometry query without letting it throw.
  ///
  /// Parents call intrinsic and dry queries before layout, outside
  /// [performLayout]'s own protection. A failure first falls back to Flutter's
  /// native query, then to [safe], and is published as a failure record.
  T _guardedQuery<T>(
    String point,
    T Function() semantic,
    T Function() native,
    T Function() safe,
  ) {
    try {
      _fault(point);
      return semantic();
    } catch (error, stackTrace) {
      _deferFailure(point, error, stackTrace);
    }
    try {
      _fault('${point}Native');
      return native();
    } catch (_) {
      return safe();
    }
  }

  /// Records a failure that happened outside layout and keeps it for the
  /// native relayout that follows, so the record survives the layout reset.
  void _deferFailure(String point, Object error, StackTrace stackTrace) {
    final reason = '${point}Guard';
    final failure =
        _reportQueryFailure(point, error, stackTrace) ??
        _lastFailures.firstWhere((failure) => failure.reason == reason);
    if (_deferredFailures.any((entry) => entry.reason == reason)) return;
    _deferredFailures = List.unmodifiable([..._deferredFailures, failure]);
  }

  List<TextWrapFailure> _deferredFailures = const [];

  TextWrapFailure? _reportQueryFailure(
    String point,
    Object error,
    StackTrace stackTrace,
  ) {
    // Parents repeat queries; keep one record per query point.
    final reason = '${point}Guard';
    if (_lastFailures.any((failure) => failure.reason == reason)) return null;
    final failure = TextWrapFailure(
      stage: TextWrapFailureStage.semanticLayout,
      reason: reason,
      error: error,
      stackTrace: stackTrace,
    );
    _lastFailures = List.unmodifiable([..._lastFailures, failure]);
    final result = _lastResult;
    if (result == null) {
      _controller?.clearResult(this, failures: _lastFailures);
    } else {
      _controller?.commitResult(this, result, failures: _lastFailures);
    }
    return failure;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _guardedQuery(
    'computeMinIntrinsicWidth',
    () => _canUseNativeSourceQueries
        ? super.computeMinIntrinsicWidth(height)
        : _sourceIntrinsicWidth(minimum: true),
    () => super.computeMinIntrinsicWidth(height),
    () => 0,
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _guardedQuery(
    'computeMaxIntrinsicWidth',
    () => _canUseNativeSourceQueries
        ? super.computeMaxIntrinsicWidth(height)
        : _sourceIntrinsicWidth(minimum: false),
    () => super.computeMaxIntrinsicWidth(height),
    () => 0,
  );

  double _sourceIntrinsicWidth({required bool minimum}) {
    // Inserted breaks depend on the width chosen by the parent. Feeding them
    // back into intrinsic width makes a later parent layout shrink based on
    // the previous selection, even when every source input is unchanged.
    final placeholders = layoutInlineChildren(
      double.infinity,
      (child, _) => Size(
        minimum
            ? child.getMinIntrinsicWidth(double.infinity)
            : child.getMaxIntrinsicWidth(double.infinity),
        0,
      ),
      ChildLayoutHelper.getDryBaseline,
    );
    final metrics = _sourceQuery(placeholders, 0, double.infinity);
    return minimum ? metrics.minIntrinsicWidth : metrics.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _guardedQuery(
    'computeMinIntrinsicHeight',
    () => _canUseNativeSourceQueries
        ? super.computeMinIntrinsicHeight(width)
        : _sourceDryMeasurement(width, width).size.height,
    () => super.computeMinIntrinsicHeight(width),
    () => 0,
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _guardedQuery(
    'computeMaxIntrinsicHeight',
    () => _canUseNativeSourceQueries
        ? super.computeMaxIntrinsicHeight(width)
        : _sourceDryMeasurement(width, width).size.height,
    () => super.computeMaxIntrinsicHeight(width),
    () => 0,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) => _guardedQuery(
    'computeDryLayout',
    () => _canUseNativeSourceQueries
        ? super.computeDryLayout(constraints)
        : constraints.constrain(
            _sourceDryMeasurement(
              constraints.minWidth,
              constraints.maxWidth,
            ).size,
          ),
    () => super.computeDryLayout(constraints),
    () => constraints.smallest,
  );

  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _guardedQuery(
    'computeDryBaseline',
    () => _canUseNativeSourceQueries
        ? super.computeDryBaseline(constraints, baseline)
        : _sourceDryMeasurement(
            constraints.minWidth,
            constraints.maxWidth,
          ).baseline,
    () => super.computeDryBaseline(constraints, baseline),
    () => 0,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_layoutBroken) return;
    final canvas = context.canvas;
    final saveCount = canvas.getSaveCount();
    try {
      _fault('paint');
      super.paint(context, offset);
    } catch (error, stackTrace) {
      try {
        // A failed paint can leave save/clip state open on the shared canvas.
        canvas.restoreToCount(saveCount);
      } catch (_) {
        // The canvas may already be finalized by a child layer; nothing to do.
      }
      // Inserted breaks are the only difference from native paint. Relayout
      // once with the source text instead of failing every frame.
      if (_lastResult?.applied ?? false) {
        _deferFailure('paint', error, stackTrace);
        _forceNativeNextLayout = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (attached) markNeedsLayout();
        });
      } else {
        _reportQueryFailure('paint', error, stackTrace);
      }
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_layoutBroken) return false;
    try {
      _fault('hitTestChildren');
      return super.hitTestChildren(result, position: position);
    } catch (error, stackTrace) {
      _reportQueryFailure('hitTestChildren', error, stackTrace);
      return false;
    }
  }

  bool _semanticsDescribeFailed = false;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    _semanticsDescribeFailed = false;
    try {
      _fault('describeSemanticsConfiguration');
      super.describeSemanticsConfiguration(config);
    } catch (error, stackTrace) {
      _semanticsDescribeFailed = true;
      _reportQueryFailure('describeSemanticsConfiguration', error, stackTrace);
      try {
        config
          ..isSemanticBoundary = true
          ..textDirection = textDirection
          ..label = _sourceText.toPlainText(includeSemanticsLabels: false);
      } catch (_) {
        // An unreadable source still leaves a valid, label-less node.
      }
    }
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    if (!_semanticsDescribeFailed) {
      try {
        _fault('assembleSemanticsNode');
        super.assembleSemanticsNode(node, config, children);
        return;
      } catch (error, stackTrace) {
        _reportQueryFailure('assembleSemanticsNode', error, stackTrace);
      }
    }
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: children is List<SemanticsNode>
          ? children
          : children.toList(),
    );
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    if (_layoutBroken) return 0;
    try {
      _fault('computeDistanceToActualBaseline');
      return super.computeDistanceToActualBaseline(baseline);
    } catch (error, stackTrace) {
      _reportQueryFailure('computeDistanceToActualBaseline', error, stackTrace);
      return 0;
    }
  }

  // Flutter's separate intrinsic painter compares span identity/equality. It
  // cannot observe opaque span mutations, even after the painted paragraph was
  // refreshed. Keep those queries in our explicitly invalidated source cache.
  bool get _canUseNativeSourceQueries =>
      !_sourceContainsOpaqueSpan && identical(super.text, _sourceText);

  _SourceQueryMetrics _sourceDryMeasurement(double minWidth, double maxWidth) {
    // A speculative parent query must not inherit breaks chosen for an earlier
    // width. Keep the same source-based estimate used before the first layout,
    // without replacing the committed paragraph or publishing a selection.
    final placeholders = layoutInlineChildren(
      maxWidth,
      ChildLayoutHelper.dryLayoutChild,
      ChildLayoutHelper.getDryBaseline,
    );
    return _sourceQuery(placeholders, minWidth, _maxLayoutWidth(maxWidth));
  }

  _SourceQueryMetrics _sourceQuery(
    List<PlaceholderDimensions> placeholders,
    double minWidth,
    double maxWidth,
  ) {
    final key = (
      _RendererMeasurementKey(
        source: _sourceText,
        maxWidth: 0,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        placeholders: _PlaceholderCacheKey(placeholders),
      ),
      textAlign,
      maxLines,
      overflow,
    );
    if (_sourceQueryKey != key) {
      _clearSourceQueries();
      _sourceQueryPainter = _painter(_sourceText, placeholders);
      _sourceQueryKey = key;
    }
    final bounds = (minWidth, maxWidth);
    final cached = _sourceQueries[bounds];
    if (cached != null) return cached;
    final painter = _sourceQueryPainter!;
    try {
      painter.layout(minWidth: minWidth, maxWidth: maxWidth);
      final metrics = _SourceQueryMetrics(
        painter.minIntrinsicWidth,
        painter.maxIntrinsicWidth,
        painter.size,
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
      _sourceQueries[bounds] = metrics;
      if (_sourceQueries.length > 8) {
        _sourceQueries.remove(_sourceQueries.keys.first);
      }
      return metrics;
    } catch (_) {
      _clearSourceQueries();
      rethrow;
    }
  }

  void _clearSourceQueries() {
    _sourceQueryPainter?.dispose();
    _sourceQueryPainter = null;
    _sourceQueryKey = null;
    _sourceQueries.clear();
  }

  @override
  void markNeedsLayout() {
    // Includes child layout changes and explicitly dirtied custom spans.
    _clearSourceQueries();
    // Custom spans may change their shaping without changing their identity or
    // equality. An explicit invalidation must remeasure them, including ranges
    // held by the plan. Built-in immutable spans use the full measurement key.
    if (_sourceContainsOpaqueSpan) {
      _opaqueTextNeedsRefresh = true;
      _cachedPlan = null;
      _cachedPlanKey = null;
      _cachedSelection = null;
      _cachedSelectionKey = null;
      _cachedEffectiveText = null;
    }
    super.markNeedsLayout();
  }

  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    _clearSourceQueries();
    _SharedLayoutCache.clear();
    // A plan owns shaped range widths, and a cached selection owns the
    // resulting native geometry. Neither remains valid after font metrics
    // change, even when every public render input is unchanged.
    _cachedPlan = null;
    _cachedPlanKey = null;
    _cachedSelection = null;
    _cachedSelectionKey = null;
    _cachedEffectiveText = null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // A clean paragraph can reattach without another performLayout. Restore
    // any notification cancelled by detach using its last committed snapshot.
    final result = _lastResult;
    if (result != null) {
      _controller?.commitResult(this, result, failures: _lastFailures);
    } else if (_lastFailures.isNotEmpty) {
      _controller?.clearResult(this, failures: _lastFailures);
    }
  }

  @override
  void detach() {
    _controller?.detachOwner(this);
    super.detach();
  }

  @override
  void dispose() {
    _clearSourceQueries();
    _controller?.detachOwner(this);
    super.dispose();
  }

  PhraseModel? _resolvedModel(String text) {
    final model = _model;
    return switch (model) {
      PhraseModel() => model,
      AutoTextWrapModel() => model.resolve(text, locale).model,
      _ => null,
    };
  }

  List<PlaceholderDimensions> _layoutPlaceholders(
    List<WidgetSpan> spans,
    double maxWidth,
  ) {
    // Validate the encoded occurrences before Flutter dereferences a child's
    // parent-data span or its required baseline type inside the layout helper.
    if (spans.length != childCount) {
      throw const _UnmeasurablePlaceholder();
    }
    final children = <RenderBox>[];
    var child = firstChild;
    for (final span in spans) {
      final parentData = child?.parentData;
      final needsBaseline = switch (span.alignment) {
        PlaceholderAlignment.baseline ||
        PlaceholderAlignment.aboveBaseline ||
        PlaceholderAlignment.belowBaseline => true,
        _ => false,
      };
      if (child == null ||
          parentData is! TextParentData ||
          !identical(parentData.span, span) ||
          (needsBaseline && span.baseline == null)) {
        throw const _UnmeasurablePlaceholder();
      }
      children.add(child);
      child = childAfter(child);
    }

    // Flutter's helper measures the children in logical span order, including
    // WidgetSpan's native nonlinear scale and real baseline. Keep the complete
    // dimensions for the source painter and the codec's indexed range slices.
    final dimensions = layoutInlineChildren(
      maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    if (dimensions.length != children.length || childCount != children.length) {
      throw const _UnmeasurablePlaceholder();
    }
    child = firstChild;
    for (var index = 0; index < dimensions.length; index++) {
      final dimension = dimensions[index];
      final span = spans[index];
      final parentData = child?.parentData;
      final baselineOffset = dimension.baselineOffset;
      if (!identical(child, children[index]) ||
          parentData is! TextParentData ||
          !identical(parentData.span, span) ||
          dimension.alignment != span.alignment ||
          dimension.baseline != span.baseline ||
          !dimension.size.isFinite ||
          dimension.size.width < 0 ||
          dimension.size.height < 0 ||
          dimension.size != child!.size ||
          (dimension.alignment == PlaceholderAlignment.baseline &&
              (dimension.baseline == null || baselineOffset == null)) ||
          (baselineOffset != null && !baselineOffset.isFinite)) {
        throw const _UnmeasurablePlaceholder();
      }
      final nativeBaseline =
          dimension.alignment == PlaceholderAlignment.baseline
          ? ChildLayoutHelper.getBaseline(
              child,
              child.constraints,
              dimension.baseline!,
            )
          : null;
      if (baselineOffset != nativeBaseline) {
        throw const _UnmeasurablePlaceholder();
      }
      child = childAfter(child);
    }
    return dimensions;
  }

  List<PlaceholderDimensions> _layoutPlaceholdersForNativeFallback(
    double maxWidth,
  ) => layoutInlineChildren(
    maxWidth,
    ChildLayoutHelper.layoutChild,
    ChildLayoutHelper.getBaseline,
  );

  TextPainter _painter(
    InlineSpan span,
    List<PlaceholderDimensions> placeholders, {
    bool finalLayout = true,
  }) => TextPainter(
    text: span,
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: finalLayout ? maxLines : null,
    ellipsis: finalLayout && overflow == TextOverflow.ellipsis
        ? '\u2026'
        : null,
    locale: locale,
    strutStyle: strutStyle,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
  )..setPlaceholderDimensions(placeholders);

  double _measureRange(
    EncodedInlineSpan encoded,
    int start,
    int end,
    List<PlaceholderDimensions> placeholders,
  ) {
    if (start == end) return 0;
    final slice = sliceInlineSpanForMeasurement(encoded, start, end);
    final dimensions = [
      for (final index in slice.placeholderIndices)
        if (index < placeholders.length)
          placeholders[index]
        else
          throw const TextRangeMeasurementException(
            'Missing WidgetSpan dimensions.',
          ),
    ];
    final painter = _painter(slice.span, dimensions, finalLayout: false);
    try {
      painter.layout(maxWidth: double.infinity);
      return normalizedFlutterWidth(painter.width);
    } finally {
      painter.dispose();
    }
  }

  double _maxLayoutWidth(double maxWidth) =>
      softWrap || overflow == TextOverflow.ellipsis
      ? maxWidth
      : double.infinity;

  TextWrapPlan _planFor(_RendererPlanKey key, {required bool shareable}) {
    final plan = _cachedPlan;
    // A plan retains its last measurement key, which owns the source span.
    // Interactive or opaque sources must never write into a globally held plan.
    if (_cachedPlanKey == key &&
        plan != null &&
        (shareable || !_cachedPlanShared)) {
      _planHits++;
      return plan;
    }
    final shared = shareable ? _SharedLayoutCache.plan(key) : null;
    if (shared != null) {
      _planHits++;
      _cachedPlanKey = key;
      _cachedPlan = shared;
      _cachedPlanShared = true;
      return shared;
    }
    _planMisses++;
    final created = createTextWrapPlan(
      text: key.text,
      model: key.model,
      strategy: key.strategy,
    );
    _cachedPlanKey = key;
    _cachedPlan = created;
    _cachedPlanShared = shareable;
    if (shareable) _SharedLayoutCache.putPlan(key, created);
    return created;
  }

  void _commitSelection(
    EncodedInlineSpan encoded,
    TextWrapResult result,
    List<PlaceholderDimensions> placeholders,
  ) {
    final effective = result.applied
        ? insertLineBreaks(encoded, result.breakOffsets)
        : _sourceText;
    var committed = result;
    var matches = true;
    if (result.applied) {
      final painter = _painter(effective, placeholders, finalLayout: false);
      try {
        painter.layout(
          minWidth: constraints.minWidth,
          maxWidth: _maxLayoutWidth(constraints.maxWidth),
        );
        final painted = measureNativeTextLayout(
          painter,
          effective.toPlainText(includeSemanticsLabels: false),
          constraints.maxWidth,
        );
        final ranges = _preservedSelectedRanges(painted, result);
        // Calculated ranges omit boundary whitespace; the painted source keeps
        // it. Verify source coverage and geometry separately, then report the
        // preserved ranges and widths actually painted.
        matches =
            ranges != null &&
            painted.lineCount == result.lineCount &&
            !painted.overflow;
        if (matches) {
          committed = _withLayout(
            result,
            LineBreakLayout(
              sourceText: result.sourceText,
              ranges: ranges,
              widths: painted.widths,
              maxWidth: constraints.maxWidth,
              selectedCandidates: result.selectedCandidates,
            ),
          );
        }
      } finally {
        painter.dispose();
      }
    } else if (result.source == TextWrapSelectionSource.calculated) {
      final native = result.diagnostics?.nativeLayout ?? _fallbackLayout();
      // Identical break offsets paint the native source unchanged. Compare the
      // boundaries, not trimmed calculated ranges against preserved whitespace.
      matches =
          native.lineCount == result.lineCount &&
          native.breakOffsets.length == result.breakOffsets.length;
      for (
        var index = 0;
        matches && index < native.breakOffsets.length;
        index++
      ) {
        matches = native.breakOffsets[index] == result.breakOffsets[index];
      }
      if (matches) committed = _withLayout(result, native);
    }
    if (!matches) {
      _commitFallback(
        reason: 'invalidRuntimeMeasurement',
        nativeLayout: result.diagnostics?.nativeLayout,
        diagnostics: result.diagnostics,
        measureNative: false,
        failures: [
          TextWrapFailure(
            stage: TextWrapFailureStage.semanticLayout,
            reason: 'invalidRuntimeMeasurement',
            error: const TextRangeMeasurementException(
              'Calculated source coverage or geometry differs from native paint.',
            ),
            stackTrace: StackTrace.current,
          ),
        ],
      );
      return;
    }
    _setEffectiveText(effective);
    _commit(committed);
  }

  TextWrapResult _withLayout(TextWrapResult result, LineBreakLayout layout) =>
      TextWrapResult(
        layout: layout,
        applied: result.applied,
        reason: result.reason,
        source: result.source,
        diagnostics: result.diagnostics,
      );

  List<TextLineRange>? _preservedSelectedRanges(
    LineBreakLayout painted,
    TextWrapResult result,
  ) {
    final text = painted.sourceText;
    var inserted = 0;
    int sourceOffset(int effectiveOffset) {
      while (inserted < result.breakOffsets.length &&
          result.breakOffsets[inserted] + inserted < effectiveOffset) {
        inserted++;
      }
      return effectiveOffset - inserted;
    }

    final ranges = <TextLineRange>[];
    for (final paintedRange in painted.ranges) {
      if (ranges.length >= result.lineCount) return null;
      final range = result.ranges[ranges.length];
      final sourceStart = sourceOffset(paintedRange.start);
      final sourceEnd = sourceOffset(paintedRange.end);
      if (sourceStart < 0 ||
          sourceEnd < sourceStart ||
          sourceEnd > result.sourceText.length ||
          sourceStart > range.start ||
          sourceEnd < range.end ||
          result.sourceText
              .substring(sourceStart, range.start)
              .characters
              .any((grapheme) => !isBreakableWhitespace(grapheme)) ||
          result.sourceText
              .substring(range.end, sourceEnd)
              .characters
              .any((grapheme) => !isBreakableWhitespace(grapheme)) ||
          result.sourceText.substring(range.start, range.end) !=
              result.lines[ranges.length] ||
          text.substring(paintedRange.start, paintedRange.end) !=
              result.sourceText.substring(sourceStart, sourceEnd)) {
        return null;
      }
      ranges.add(TextLineRange(sourceStart, sourceEnd));
    }
    return ranges.length == result.lineCount ? ranges : null;
  }

  TextWrapResult _withRendererCache(TextWrapResult result) {
    final diagnostics = result.diagnostics;
    if (diagnostics == null) return result;
    return TextWrapResult(
      layout: result.layout,
      applied: result.applied,
      reason: result.reason,
      source: result.source,
      diagnostics: TextWrapDiagnostics(
        predictions: diagnostics.predictions,
        candidates: diagnostics.candidates,
        calculatedLayouts: diagnostics.calculatedLayouts,
        nativeLayout: diagnostics.nativeLayout,
        selection: diagnostics.selection,
        calculationLimit: diagnostics.calculationLimit,
        cache: diagnostics.cache.copyWith(
          planHits: _planHits,
          planMisses: _planMisses,
          selectionCacheHits: _selectionCacheHits,
          selectionCacheMisses: _selectionCacheMisses,
        ),
      ),
    );
  }

  void _setEffectiveText(InlineSpan value) {
    final key = _InlineSpanCacheKey(value);
    if (_effectiveTextKey == key && !_opaqueTextNeedsRefresh) return;
    // RenderParagraph's public setter correctly resets its private painter,
    // semantics, overflow, and selection caches. Flutter permits this
    // synchronous render-tree mutation through the documented layout callback;
    // the object is already dirty, and the final super.performLayout below
    // consumes the updated painter before this frame can paint it.
    invokeLayoutCallback<BoxConstraints>((_) {
      _replaceParagraphText(value);
    });
  }

  void _replaceParagraphText(InlineSpan value) {
    final key = _InlineSpanCacheKey(value);
    if (_effectiveTextKey == key && !_opaqueTextNeedsRefresh) return;
    // TextSpan.compareTo omits locale/spellOut, which affect semantics and
    // shaping. Force an otherwise comparison-identical replacement through.
    if (_opaqueTextNeedsRefresh ||
        super.text.compareTo(value) == RenderComparison.identical) {
      super.text = _metadataResetSpan(super.text);
    }
    super.text = value;
    _effectiveTextKey = key;
    _opaqueTextNeedsRefresh = false;
  }

  void _commitFallback({
    required String reason,
    LineBreakLayout? nativeLayout,
    TextWrapDiagnostics? diagnostics,
    bool measureNative = true,
    List<TextWrapFailure> failures = const [],
  }) {
    _setEffectiveText(_sourceText);
    final observedFailures = [...failures];
    if (failures.isNotEmpty) {
      _cachedSelection = null;
      _cachedSelectionKey = null;
      _cachedEffectiveText = null;
    }
    LineBreakLayout? layout = nativeLayout;
    if (layout == null && measureNative) {
      try {
        layout = _fallbackLayout();
      } catch (error, stackTrace) {
        // Geometry is optional diagnostics. Do not let a second adapter
        // measurement failure prevent RenderParagraph from painting source.
        observedFailures.add(
          TextWrapFailure(
            stage: TextWrapFailureStage.nativeMeasurement,
            reason: _fallbackReason(error),
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    if (layout == null) {
      // Never publish fabricated geometry or the previous source's result.
      _lastResult = null;
      _lastFailures = List.unmodifiable(observedFailures);
      _cachedPlan = null;
      _cachedPlanKey = null;
      _cachedSelection = null;
      _cachedSelectionKey = null;
      _cachedEffectiveText = null;
      _controller?.clearResult(this, failures: _lastFailures);
      return;
    }
    _commit(
      TextWrapResult(
        layout: layout,
        applied: false,
        reason: reason,
        source: TextWrapSelectionSource.native,
        diagnostics: diagnostics == null
            ? null
            : TextWrapDiagnostics(
                predictions: diagnostics.predictions,
                candidates: diagnostics.candidates,
                calculatedLayouts: diagnostics.calculatedLayouts,
                nativeLayout: layout,
                selection: LayoutSelectionDecision.native(reason: reason),
                cache: diagnostics.cache,
                calculationLimit: diagnostics.calculationLimit,
              ),
      ),
      failures: observedFailures,
    );
  }

  LineBreakLayout _fallbackLayout() {
    final source = encodeInlineSpan(_sourceText).text;
    if (source.length > maxSemanticTextLength) {
      throw const TextWrapInputLimitException(
        'Native diagnostics skipped for source exceeding 65536 UTF-16 code units.',
      );
    }
    // Semantic placeholder validation is intentionally stricter than Flutter's
    // native path (for example, native layout permits a missing real baseline).
    final placeholders = super.layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    final painter = _painter(_sourceText, placeholders);
    try {
      painter.layout(
        minWidth: constraints.minWidth,
        maxWidth: _maxLayoutWidth(constraints.maxWidth),
      );
      return measureNativeTextLayout(
        painter,
        source,
        constraints.maxWidth.isFinite ? constraints.maxWidth : painter.width,
      );
    } finally {
      painter.dispose();
    }
  }

  void _commit(
    TextWrapResult result, {
    List<TextWrapFailure> failures = const [],
  }) {
    _lastResult = result;
    _lastFailures = List.unmodifiable(failures);
    _controller?.commitResult(this, result, failures: _lastFailures);
  }
}

String _fallbackReason(Object error) => switch (error) {
  TextWrapInputLimitException() => 'inputLimit',
  _UnmeasurablePlaceholder() => 'unmeasurablePlaceholder',
  UnsupportedSpanTransformationException() => 'unsupportedSpanTransformation',
  TextRangeMeasurementException() => 'invalidRuntimeMeasurement',
  _ => 'rendererFallback',
};

final class _UnmeasurablePlaceholder implements Exception {
  const _UnmeasurablePlaceholder();
}

final class _RendererPlanKey {
  _RendererPlanKey({
    required this.text,
    required this.model,
    required this.strategy,
  });

  final String text;
  final PhraseModel? model;
  final LineBreakStrategy strategy;

  @override
  bool operator ==(Object other) =>
      other is _RendererPlanKey &&
      text == other.text &&
      _sameModel(model, other.model) &&
      _sameStrategy(strategy, other.strategy);

  // Keys are immutable and hashed by several caches per layout.
  late final int _hash = Object.hash(
    text,
    _modelHash(model),
    _strategyHash(strategy),
  );

  @override
  int get hashCode => _hash;
}

bool _sameModel(PhraseModel? left, PhraseModel? right) {
  if (identical(left, right)) return true;
  if (left == null ||
      right == null ||
      left.boundaryMode != right.boundaryMode ||
      left.fallbackPenalty != right.fallbackPenalty ||
      left.levels.length != right.levels.length) {
    return false;
  }
  for (var index = 0; index < left.levels.length; index++) {
    final leftLevel = left.levels[index];
    final rightLevel = right.levels[index];
    if (leftLevel.name != rightLevel.name ||
        leftLevel.penalty != rightLevel.penalty ||
        leftLevel.predictor != rightLevel.predictor) {
      return false;
    }
  }
  return true;
}

int _modelHash(PhraseModel? model) => model == null
    ? 0
    : Object.hash(
        model.boundaryMode,
        model.fallbackPenalty,
        Object.hashAll([
          for (final level in model.levels)
            (level.name, level.penalty, level.predictor),
        ]),
      );

bool _sameStrategy(LineBreakStrategy left, LineBreakStrategy right) =>
    identical(left, right) ||
    (left.aggregator == right.aggregator &&
        left.calculator == right.calculator &&
        left.selector == right.selector);

int _strategyHash(LineBreakStrategy strategy) =>
    Object.hash(strategy.aggregator, strategy.calculator, strategy.selector);

final class _RendererMeasurementKey {
  _RendererMeasurementKey({
    required InlineSpan source,
    required this.maxWidth,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.strutStyle,
    required this.textWidthBasis,
    required this.textHeightBehavior,
    required this.placeholders,
  }) : source = _InlineSpanCacheKey(source);

  _RendererMeasurementKey._withoutWidth(_RendererMeasurementKey other)
    : source = other.source,
      maxWidth = 0,
      textDirection = other.textDirection,
      textScaler = other.textScaler,
      locale = other.locale,
      strutStyle = other.strutStyle,
      textWidthBasis = other.textWidthBasis,
      textHeightBehavior = other.textHeightBehavior,
      placeholders = other.placeholders;

  /// The same inputs with the available width ignored.
  _RendererMeasurementKey withoutWidth() =>
      _RendererMeasurementKey._withoutWidth(this);

  final _InlineSpanCacheKey source;
  final double maxWidth;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final _PlaceholderCacheKey placeholders;

  @override
  bool operator ==(Object other) =>
      other is _RendererMeasurementKey &&
      source == other.source &&
      maxWidth == other.maxWidth &&
      textDirection == other.textDirection &&
      textScaler == other.textScaler &&
      locale == other.locale &&
      strutStyle == other.strutStyle &&
      textWidthBasis == other.textWidthBasis &&
      textHeightBehavior == other.textHeightBehavior &&
      placeholders == other.placeholders;

  late final int _hash = Object.hash(
    source,
    maxWidth,
    textDirection,
    textScaler,
    locale,
    strutStyle,
    textWidthBasis,
    textHeightBehavior,
    placeholders,
  );

  @override
  int get hashCode => _hash;
}

/// A tree of built-in text spans without recognizers or hover callbacks.
///
/// Only such trees are retained by the cross-renderer caches: a recognizer or
/// callback can capture a widget State that must not outlive its renderer, and
/// a WidgetSpan keeps identity-bound children.
bool _isPlainTextTree(InlineSpan source) {
  final pending = <InlineSpan>[source];
  while (pending.isNotEmpty) {
    final span = pending.removeLast();
    if (span.runtimeType != TextSpan) return false;
    span as TextSpan;
    if (span.recognizer != null ||
        span.onEnter != null ||
        span.onExit != null) {
      return false;
    }
    pending.addAll(span.children ?? const <InlineSpan>[]);
  }
  return true;
}

final class _SharedSelection {
  const _SharedSelection(this.result, this.effectiveText);

  final TextWrapResult result;
  final InlineSpan effectiveText;
}

/// Bounded LRU caches shared by every renderer, so a re-created text widget
/// with the same text, style, width, and strategy skips selection entirely.
///
/// Entries are valid only while the font set and platform locale are unchanged.
final class _SharedLayoutCache {
  static const maxTextLength = 1024;
  static const _maxSelections = 64;
  static const _maxPlans = 32;
  static final _selections = <_RendererSelectionKey, _SharedSelection>{};
  static final _plans = <_RendererPlanKey, TextWrapPlan>{};
  static Listenable? _fonts;
  static Locale? _platformLocale;

  /// Validates the entries against the current fonts and platform locale.
  /// Call once per layout before using the lookups below.
  static void prepare() {
    final fonts = PaintingBinding.instance.systemFonts;
    if (!identical(_fonts, fonts)) {
      _fonts?.removeListener(clear);
      fonts.addListener(clear);
      _fonts = fonts;
    }
    final locale = PlatformDispatcher.instance.locale;
    if (_platformLocale != locale) {
      clear();
      _platformLocale = locale;
    }
  }

  static _SharedSelection? selection(_RendererSelectionKey key) {
    final hit = _selections.remove(key);
    if (hit != null) _selections[key] = hit;
    return hit;
  }

  static void putSelection(_RendererSelectionKey key, _SharedSelection value) {
    _selections.remove(key);
    _selections[key] = value;
    if (_selections.length > _maxSelections) {
      _selections.remove(_selections.keys.first);
    }
  }

  static TextWrapPlan? plan(_RendererPlanKey key) {
    final hit = _plans.remove(key);
    if (hit != null) _plans[key] = hit;
    return hit;
  }

  static void putPlan(_RendererPlanKey key, TextWrapPlan value) {
    _plans.remove(key);
    _plans[key] = value;
    if (_plans.length > _maxPlans) _plans.remove(_plans.keys.first);
  }

  static int get selectionCount => _selections.length;
  static int get planCount => _plans.length;

  static void clear() {
    _selections.clear();
    _plans.clear();
  }
}

bool _containsOpaqueSpan(InlineSpan source) {
  final pending = <InlineSpan>[source];
  while (pending.isNotEmpty) {
    final span = pending.removeLast();
    if (span.runtimeType == WidgetSpan) continue;
    if (span is! TextSpan || span.runtimeType != TextSpan) return true;
    pending.addAll(span.children ?? const <InlineSpan>[]);
  }
  return false;
}

/// Full span-tree equality for cache and committed-text decisions.
///
/// Flutter's [TextSpan] equality and [TextSpan.compareTo] intentionally omit
/// locale and spellOut. They are nevertheless part of this renderer's shaped
/// text and semantics contract, including when inherited by nested spans.
final class _InlineSpanCacheKey {
  _InlineSpanCacheKey(this.span);

  final InlineSpan span;

  @override
  bool operator ==(Object other) =>
      other is _InlineSpanCacheKey && _sameInlineSpan(span, other.span);

  late final int _hash = _inlineSpanHash(span);

  @override
  int get hashCode => _hash;
}

bool _sameInlineSpan(InlineSpan left, InlineSpan right) {
  final pending = [(left, right)];
  while (pending.isNotEmpty) {
    final (left, right) = pending.removeLast();
    if (identical(left, right)) continue;
    if (left.runtimeType != right.runtimeType) return false;
    if (left is! TextSpan || right is! TextSpan) {
      if (left != right) return false;
      continue;
    }
    if (left.runtimeType == TextSpan) {
      // TextSpan equality recursively compares its children. Compare ordinary
      // nodes once here instead of rescanning every subtree at each ancestor.
      if (right.style != left.style ||
          right.text != left.text ||
          right.recognizer != left.recognizer ||
          right.semanticsLabel != left.semanticsLabel ||
          right.semanticsIdentifier != left.semanticsIdentifier ||
          left.onEnter != right.onEnter ||
          left.onExit != right.onExit ||
          left.mouseCursor != right.mouseCursor) {
        return false;
      }
    } else if (left != right) {
      // Preserve opaque subclasses' own equality contract.
      return false;
    }
    if (left.locale != right.locale || left.spellOut != right.spellOut) {
      return false;
    }
    final leftChildren = left.children;
    final rightChildren = right.children;
    if ((leftChildren == null) != (rightChildren == null)) return false;
    if (leftChildren == null || rightChildren == null) continue;
    if (leftChildren.length != rightChildren.length) return false;
    for (var index = leftChildren.length - 1; index >= 0; index--) {
      pending.add((leftChildren[index], rightChildren[index]));
    }
  }
  return true;
}

int _inlineSpanHash(InlineSpan source) {
  // TextSpan.hashCode recursively visits children. Hashing it and then hashing
  // every subtree again makes a nested rich source quadratic on a cache miss.
  // Mirror our iterative equality contract, including child-list shape.
  final values = <Object?>[];
  final pending = <InlineSpan>[source];
  while (pending.isNotEmpty) {
    final span = pending.removeLast();
    values.add(span.runtimeType);
    if (span.runtimeType != TextSpan) {
      values.add(span);
      continue;
    }
    span as TextSpan;
    values.addAll([
      span.style,
      span.text,
      span.recognizer,
      span.semanticsLabel,
      span.semanticsIdentifier,
      span.onEnter,
      span.onExit,
      span.mouseCursor,
      span.locale,
      span.spellOut,
      span.children?.length,
    ]);
    final children = span.children;
    if (children != null) {
      for (var i = children.length - 1; i >= 0; i--) {
        pending.add(children[i]);
      }
    }
  }
  return Object.hashAll(values);
}

InlineSpan _metadataResetSpan(InlineSpan current) {
  const first = TextSpan(text: '\u0000');
  const second = TextSpan(text: '\u0001');
  return current.compareTo(first) == RenderComparison.identical
      ? second
      : first;
}

final class _RendererSelectionKey {
  _RendererSelectionKey({
    required this.plan,
    required this.measurement,
    required this.minWidth,
    required this.textAlign,
    required this.softWrap,
    required this.overflow,
    required this.maxLines,
  });

  final _RendererPlanKey plan;
  final _RendererMeasurementKey measurement;
  final double minWidth;
  final TextAlign textAlign;
  final bool softWrap;
  final TextOverflow overflow;
  final int? maxLines;

  @override
  bool operator ==(Object other) =>
      other is _RendererSelectionKey &&
      plan == other.plan &&
      measurement == other.measurement &&
      minWidth == other.minWidth &&
      textAlign == other.textAlign &&
      softWrap == other.softWrap &&
      overflow == other.overflow &&
      maxLines == other.maxLines;

  late final int _hash = Object.hash(
    plan,
    measurement,
    minWidth,
    textAlign,
    softWrap,
    overflow,
    maxLines,
  );

  @override
  int get hashCode => _hash;
}

final class _PlaceholderCacheKey {
  _PlaceholderCacheKey(List<PlaceholderDimensions> dimensions)
    : dimensions = List.unmodifiable([
        for (final dimension in dimensions)
          (
            dimension.size,
            dimension.alignment,
            dimension.baseline,
            dimension.baselineOffset,
          ),
      ]);

  final List<(Size, PlaceholderAlignment, TextBaseline?, double?)> dimensions;

  @override
  bool operator ==(Object other) {
    if (other is! _PlaceholderCacheKey ||
        dimensions.length != other.dimensions.length) {
      return false;
    }
    for (var index = 0; index < dimensions.length; index++) {
      if (dimensions[index] != other.dimensions[index]) return false;
    }
    return true;
  }

  late final int _hash = Object.hashAll(dimensions);

  @override
  int get hashCode => _hash;
}

final class _SourceQueryMetrics {
  const _SourceQueryMetrics(
    this.minIntrinsicWidth,
    this.maxIntrinsicWidth,
    this.size,
    this.baseline,
  );
  final double minIntrinsicWidth;
  final double maxIntrinsicWidth;
  final Size size;
  final double baseline;
}
