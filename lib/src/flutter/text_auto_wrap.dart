import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/models.dart';
import '../core/strategy.dart';
import '../models/language_detection.dart';
import 'controller.dart';
import 'render_text_auto_wrap.dart';

/// Model-driven semantic wrapping with the layout options of [Text].
class TextAutoWrap extends StatelessWidget {
  /// Creates plain text that receives semantic line breaks when useful.
  const TextAutoWrap(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.model,
    this.strategy = const LineBreakStrategy(),
    this.controller,
  }) : textSpan = null;

  /// Creates rich text that receives semantic line breaks when useful.
  const TextAutoWrap.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.model,
    this.strategy = const LineBreakStrategy(),
    this.controller,
  }) : data = null;

  /// The plain text to render, or null for [TextAutoWrap.rich].
  final String? data;

  /// The rich source tree to render, or null for the plain constructor.
  final InlineSpan? textSpan;

  /// The style merged with the nearest [DefaultTextStyle].
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  /// A phrase model or automatic selector. Omitting it selects [TextAutoWrapModels.auto].
  final TextWrapModel? model;

  /// Candidate aggregation, layout, and selection stages.
  final LineBreakStrategy strategy;

  /// Receives the result committed by the renderer after each material change.
  final TextAutoWrapController? controller;

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    var effectiveStyle = style;
    if (effectiveStyle == null || effectiveStyle.inherit) {
      effectiveStyle = defaults.style.merge(effectiveStyle);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final lineHeightScale = MediaQuery.maybeLineHeightScaleFactorOverrideOf(
      context,
    );
    final effectiveStrut = strutStyle?.merge(
      StrutStyle(height: lineHeightScale),
    );
    final effectiveScaler = textScaler ?? MediaQuery.textScalerOf(context);
    final effectiveSpan = TextSpan(
      style: effectiveStyle,
      text: data,
      locale: locale,
      children: textSpan == null ? null : <InlineSpan>[textSpan!],
    );
    final registrar = SelectionContainer.maybeOf(context);
    final effectiveSelectionColor =
        selectionColor ??
        DefaultSelectionStyle.of(context).selectionColor ??
        DefaultSelectionStyle.defaultColor;

    Widget result = _TextAutoWrapParagraph(
      text: effectiveSpan,
      model: model ?? TextAutoWrapModels.auto,
      strategy: strategy,
      controller: controller,
      textAlign: textAlign ?? defaults.textAlign ?? TextAlign.start,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap ?? defaults.softWrap,
      overflow: overflow ?? effectiveStyle.overflow ?? defaults.overflow,
      textScaler: effectiveScaler,
      maxLines: maxLines ?? defaults.maxLines,
      strutStyle: effectiveStrut,
      textWidthBasis: textWidthBasis ?? defaults.textWidthBasis,
      textHeightBehavior:
          textHeightBehavior ??
          defaults.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
      selectionRegistrar: registrar,
      selectionColor: effectiveSelectionColor,
    );
    if (registrar != null) {
      result = MouseRegion(
        cursor:
            DefaultSelectionStyle.of(context).mouseCursor ??
            SystemMouseCursors.text,
        child: result,
      );
    }
    if (semanticsLabel != null) {
      result = Semantics(
        textDirection: textDirection,
        label: semanticsLabel,
        child: ExcludeSemantics(child: result),
      );
    }
    return result;
  }
}

/// The direct RenderParagraph bridge; mirrors Flutter 3.47.4 [RichText].
final class _TextAutoWrapParagraph extends MultiChildRenderObjectWidget {
  _TextAutoWrapParagraph({
    required this.text,
    required this.model,
    required this.strategy,
    required this.controller,
    required this.textAlign,
    required this.textDirection,
    required this.locale,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    required this.maxLines,
    required this.strutStyle,
    required this.textWidthBasis,
    required this.textHeightBehavior,
    required this.selectionRegistrar,
    required this.selectionColor,
  }) : super(children: WidgetSpan.extractFromInlineSpan(text, textScaler));

  final InlineSpan text;
  final TextWrapModel model;
  final LineBreakStrategy strategy;
  final TextAutoWrapController? controller;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final SelectionRegistrar? selectionRegistrar;
  final Color selectionColor;

  double _devicePixelRatio(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.maybeOf(context)?.devicePixelRatio ??
      1.0;

  @override
  RenderTextAutoWrap createRenderObject(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    return RenderTextAutoWrap(
      sourceText: text,
      model: model,
      strategy: strategy,
      controller: controller,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
      devicePixelRatio: _devicePixelRatio(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTextAutoWrap renderObject,
  ) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    renderObject
      ..sourceText = text
      ..model = model
      ..strategy = strategy
      ..controller = controller
      ..textAlign = textAlign
      ..textDirection = textDirection ?? Directionality.of(context)
      ..softWrap = softWrap
      ..overflow = overflow
      ..textScaler = textScaler
      ..maxLines = maxLines
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..locale = locale ?? Localizations.maybeLocaleOf(context)
      ..registrar = selectionRegistrar
      ..selectionColor = selectionColor
      ..devicePixelRatio = _devicePixelRatio(context);
  }
}
