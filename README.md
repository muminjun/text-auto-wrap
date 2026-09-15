# text_auto_wrap

[한국어](https://github.com/muminjun/text-auto-wrap/blob/main/README-ko_kr.md)

Model-driven semantic line breaking for plain and rich Flutter text. `TextAutoWrap` measures the text with Flutter's current layout inputs, evaluates phrase-boundary candidates, and either renders the selected layout in the first visible frame or keeps Flutter's native wrapping.

This is semantic wrapping, not Python-style fixed-column wrapping. Width is based on shaped pixels, and an inserted break is chosen from valid source-text boundaries rather than a character count.

> The bundled Korean and English title presets are **experimental**. They are small, domain-specific starting points for short display titles, not general language models or production accuracy guarantees. Validate them on unseen content with your application's fonts and widths. See the [English](https://github.com/muminjun/text-auto-wrap/blob/main/model_cards/english.md) and [Korean](https://github.com/muminjun/text-auto-wrap/blob/main/model_cards/korean.md) model cards.

## Installation

```yaml
dependencies:
  text_auto_wrap: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';
```

The package is pure Dart/Flutter and contains no platform-specific native implementation.

## Plain, rich, and inline-widget text

Omitting `model` uses `TextAutoWrapModels.auto`:

```dart
const TextAutoWrap(
  'Designing products people trust without slowing down delivery',
  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
);
```

Rich trees retain their styling and inline widgets:

```dart
TextAutoWrap.rich(
  TextSpan(
    children: [
      const TextSpan(
        text: 'Ship a ',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(Icons.verified, size: 18),
      ),
      const TextSpan(text: ' stable experience'),
    ],
  ),
);
```

The plain and rich constructors accept the same layout, model, strategy, and diagnostics options; only the source differs (`String` versus `InlineSpan`). Their Flutter-facing options parallel `Text`: `style`, `strutStyle`, `textAlign`, `textDirection`, `locale`, `softWrap`, `overflow`, `textScaler`, `maxLines`, `semanticsLabel`, `textWidthBasis`, `textHeightBehavior`, and `selectionColor`. `maxLines` and `overflow` remain final Flutter rendering rules. Setting `softWrap: false` disables additional semantic breaks while preserving explicit newlines.

## Automatic and explicit models

Automatic detection counts Unicode code points assigned as Hangul letters and Latin letters. Whitespace, punctuation, digits, combining marks, other scripts, and U+FFFC widget placeholders provide no evidence.

- A script with at least 70% of supported-letter evidence selects its preset.
- Below 70%, a matching `ko` or `en` locale may select a preset when that script supplies at least 40% of the evidence.
- No supported letters produce `unsupportedLanguage`; an unresolved mix produces `ambiguousLanguage` from `detectTextWrapLanguage`.
- The widget uses native Flutter wrapping whenever automatic resolution returns no model.

Inspect detection separately when you need counts or locale influence:

```dart
final detection = detectTextWrapLanguage(text, Localizations.localeOf(context));
debugPrint(
  'ko=${detection.koreanCount}, en=${detection.englishCount}, '
  'locale=${detection.localeInfluenced}, fallback=${detection.fallbackReason}',
);
```

Explicit selection always bypasses automatic detection:

```dart
TextAutoWrap(title, model: TextAutoWrapModels.korean);
TextAutoWrap(title, model: TextAutoWrapModels.english);
```

Both bundled presets operate on whitespace boundaries and use coarse, medium, and fine penalties of `0`, `0.35`, and `0.7`; an unpredicted source-space boundary costs `1`.

## Custom predictors and strategies

A predictor returns strictly ascending UTF-16 offsets. Each offset must be an interior boundary allowed by the model's `BoundaryMode`; `spaces` means the end of a contiguous whitespace run, while `characters` permits Unicode grapheme boundaries.

```dart
final model = PhraseModel(
  levels: [
    PhraseModelLevel(
      name: 'preferred',
      predictor: MyPredictor(),
      penalty: 0,
    ),
  ],
  fallbackPenalty: 1,
  boundaryMode: BoundaryMode.spaces,
);

final strategy = LineBreakStrategy(
  aggregator: consensus(minimumModels: 1),
  calculator: nearbyLayouts(radius: 1),
  selector: const BalanceStrategy(tolerance: .12),
);

TextAutoWrap(title, model: model, strategy: strategy);
```

`lowestPenalty()` and `optimalLayouts()` are the defaults. `consensus`, `greedy`, `nearbyLayouts`, and a custom implementation of `PredictionAggregator`, `LayoutCalculator`, or `LayoutSelector` can replace individual stages. Custom configuration errors are typed `TextWrapException`s in direct engine calls; the widget protects rendering by falling back to its original paragraph.

## Low-level engine and measurement contract

Use `selectTextWrap` for one selection or `createTextWrapPlan` when prediction and aggregation should be reused across widths:

```dart
final plan = createTextWrapPlan(
  text: source,
  model: TextAutoWrapModels.english,
);

final result = plan.select(
  maxWidth: 320,
  measureRange: (start, end) {
    final painter = TextPainter(
      text: TextSpan(text: source.substring(start, end), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    try {
      return painter.width;
    } finally {
      painter.dispose();
    }
  },
  diagnostics: true,
);
```

`measureRange(start, end)` receives a half-open range in the original string's UTF-16 offsets. It must return the current rendered width as a finite, non-negative `double`. Widths are not assumed to be additive or monotonic: shaping, bidi text, styles, text scaling, and placeholders can change every slice. Rich-text adapters must measure the corresponding styled span slice and its real placeholder dimensions. Explicit hard-newline delimiters are preserved and are not passed as line content.

Pass a non-null `measurementCacheKey` only when it identifies every measurement input; change it when style, direction, scaling, placeholders, or a width-sensitive callback changes. Omitting the key disables cross-call range reuse. Invalid widths, offsets, model configuration, or measurements throw a typed exception from the direct engine.

## Controller and diagnostics

`TextAutoWrapController.result` is the latest immutable `TextWrapResult`. The renderer assigns it during layout and defers listener notification until the end of the frame to avoid reentrant builds.

```dart
final controller = TextAutoWrapController();

TextAutoWrap(
  title,
  controller: controller,
  model: TextAutoWrapModels.english,
);

ListenableBuilder(
  listenable: controller,
  builder: (context, _) {
    final result = controller.result;
    return Text(
      result == null
          ? 'Waiting for layout'
          : '${result.reason}: ${result.breakOffsets}',
    );
  },
);

// Dispose an owned controller from State.dispose().
controller.dispose();
```

Results report source ranges, lines, widths, inserted break offsets, overflow, whether semantic wrapping was applied, a stable reason, and optional stage/cache diagnostics. Common reasons are:

| Reason | Meaning |
| --- | --- |
| `calculatedSelected` | A calculated semantic layout was selected. |
| `nativeSelected` / `nativeNoModelImprovement` | Native wrapping won selection. |
| `unsupportedLanguage` | Automatic selection resolved no bundled model. Use `detectTextWrapLanguage` to distinguish an unsupported script from an ambiguous mix. |
| `softWrapDisabled` | `softWrap` disabled inserted breaks. |
| `unusableWidth` | Layout width was unbounded, non-finite, or non-positive. |
| `calculationLimit` | A deterministic work ceiling was reached. |
| `unmeasurablePlaceholder` | A `WidgetSpan` could not provide consistent dimensions or required baseline data. |
| `unsupportedSpanTransformation` | A custom `InlineSpan` could not be transformed without losing state. |
| `invalidRuntimeMeasurement` / `rendererFallback` | Runtime measurement or another guarded renderer operation failed. |

Applications should treat reasons as diagnostics, not as user-facing localized messages. A custom selector may return its own application-specific reason.

Fallback results contain measured native ranges and widths. If invalid span or child metadata also prevents Flutter's native paragraph layout, the native error propagates and no new result is committed.

## Unicode, performance, and accessibility

All offsets are UTF-16 offsets, matching Dart `String`, Flutter `TextPosition`, and `TextRange`. Candidate validation uses Unicode grapheme boundaries, so breaks do not split surrogate pairs, combining sequences, emoji modifiers, ZWJ sequences, or the U+FFFC placeholder token. Existing CR, LF, CRLF, U+2028, and U+2029 paragraph separators are preserved.

Synchronous exact-first layout is bounded. Version 0.1.0 falls back atomically at more than 4,096 candidates or after 16,384 optimizer states; no partial calculated layout is exposed. A reusable plan retains at most 65,536 measured ranges for its current non-null cache key. Renderer caches are keyed by text/span metadata, effective style, width, direction, locale, scaler, strut, line constraints, strategy/model, and placeholder dimensions. These ceilings are deterministic safeguards, not latency guarantees, and are not public tuning parameters. Benchmark on target devices with representative fonts and content.

Inserted breaks preserve nested `TextSpan` metadata, recognizers, mouse cursors, locale, spell-out metadata, semantics labels/identifiers, and `WidgetSpan` child identity and alignment. Selection remains integrated with Flutter's selection registrar. `semanticsLabel` has the same override role as on `Text`. If safe transformation or placeholder measurement is not possible, native wrapping keeps the original span tree. Test screen-reader output, text scaling, selection, bidi content, and interactive spans in every supported target application.

## Example and attribution

Run the responsive sample, including live controller diagnostics:

```sh
cd example
flutter run -d chrome
```

This project is licensed under Apache-2.0. It is a modified Dart/Flutter port of [`semantic-wrap`](https://github.com/woohyun-park/semantic-wrap) at commit `54ed67688aa5292f14970cae10bbabd9a11f1b5d`, including a BudouX-compatible inference implementation and the experimental English/Korean weights. See [NOTICE](https://github.com/muminjun/text-auto-wrap/blob/main/NOTICE), [LICENSE](https://github.com/muminjun/text-auto-wrap/blob/main/LICENSE), and the model cards for exact attribution and limitations.
