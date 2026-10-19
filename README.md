# text_auto_wrap

[한국어](https://github.com/muminjun/text-auto-wrap/blob/main/README-ko_kr.md)

Model-driven semantic line breaking for plain and rich Flutter text. `TextAutoWrap` measures the text with Flutter's current layout inputs, evaluates phrase-boundary candidates, and either renders the selected layout in the first visible frame or keeps Flutter's native wrapping.

This is semantic wrapping, not Python-style fixed-column wrapping. Width is based on shaped pixels, and an inserted break is chosen from valid source-text boundaries rather than a character count.

> The bundled Korean and English title presets are **experimental**. They are small, domain-specific starting points for short display titles, not general language models or production accuracy guarantees. Validate them on unseen content with your application's fonts and widths. See the [English](https://github.com/muminjun/text-auto-wrap/blob/main/model_cards/english.md) and [Korean](https://github.com/muminjun/text-auto-wrap/blob/main/model_cards/korean.md) model cards.

## Installation

```yaml
dependencies:
  text_auto_wrap: ^0.1.3
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

For widget results, `ranges`, `lines`, and `widths` describe the final painted layout and retain source whitespace around inserted breaks. Calculation layouts in `diagnostics.calculatedLayouts` omit selected boundary whitespace when evaluating candidates. Their ranges and widths can therefore differ from the committed widget result. A calculated selection that reuses the native break offsets has `applied: false` and reports the unchanged native geometry.

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
| `layoutGuard` / `nativeLayoutGuard` / `<query>Guard` | The final guard absorbed a failure outside the semantic stage: the paragraph layout, or a parent-facing query such as `computeDryLayoutGuard`, `paintGuard`, or `hitTestChildrenGuard`. |

Applications should treat reasons as diagnostics, not as user-facing localized messages. A custom selector may return its own application-specific reason.

Fallback results contain validated native ranges and widths when available. A failed native diagnostic measurement is not retried in the same layout. If native geometry cannot be represented safely, `controller.result` is cleared to `null`, the original span still goes to Flutter's paragraph, and `controller.failures` exposes the stage, reason, exception, and stack trace. A query failure remains visible through the following layout snapshot, then clears after a clean layout. Listener notifications remain frame-deferred. Do not interpret a null result as a zero-width or empty source layout. If the semantic stage fails, the paragraph is laid out again from the source and a `layoutGuard` failure is recorded. If Flutter's own paragraph cannot lay out the source either, the text becomes inert at the smallest allowed size (no paint, no hit target) and a `nativeLayoutGuard` failure is recorded instead of throwing, so the parent layout still completes.

## Unicode, performance, and accessibility

All offsets are UTF-16 offsets, matching Dart `String`, Flutter `TextPosition`, and `TextRange`. Candidate validation uses Unicode grapheme boundaries, so breaks do not split surrogate pairs, combining sequences, emoji modifiers, ZWJ sequences, or the U+FFFC placeholder token. Existing CR, LF, CRLF, VT, FF, NEL, U+2028, and U+2029 paragraph separators are preserved; engine differences retain native source rendering.

Soft opportunities protect Unicode 16.0 `Line_Break=GL/WJ` glue, including nonbreaking spaces, word joiners, and BOM, independently of raw grapheme endpoints. These characters are never removed or normalized. This is not a complete UAX #14 implementation. Flutter controls the final rendering of soft hyphens, bidi text, and hard separators; if calculated geometry disagrees with native paint, the adapter retains the source.

Negative letter spacing can produce a finite negative native glyph advance even when UTF-16 ranges are valid. The Flutter adapter represents that advance as zero occupied width. Non-finite measurements, invalid ranges, and negative widths from custom `measureRange` callbacks remain errors. For engine limitations, SDK verification, and reproducible Unicode tests, see [Unicode stability](doc/unicode-stability.md).

Synchronous exact-first layout is bounded. Version 0.1.0 falls back atomically at more than 4,096 candidates or after 16,384 optimizer states; no partial calculated layout is exposed. A reusable plan retains at most 65,536 measured ranges for its current non-null cache key. Renderer caches are keyed by text/span metadata, effective style, width, direction, locale, scaler, strut, line constraints, strategy/model, and placeholder dimensions. These ceilings are deterministic safeguards, not latency guarantees, and are not public tuning parameters. Benchmark on target devices with representative fonts and content.

Repeated layouts with unchanged measurement inputs reuse the verified paragraph, including when a parent changes only its minimum height. Intrinsic and dry queries continue to measure the original source. Custom spans that change without replacing their identity must mark their renderer as needing layout; this refreshes both speculative measurements and native paint geometry. The renderer benchmark includes repeated intrinsic rows, tables, image-choice grids, rich lists, 1.5× inline widgets, and three-pass parents.

Inserted breaks preserve nested `TextSpan` metadata, recognizers, mouse cursors, locale, spell-out metadata, semantics labels/identifiers, and `WidgetSpan` child identity and alignment. Selection remains integrated with Flutter's selection registrar. `semanticsLabel` has the same override role as on `Text`. If safe transformation or placeholder measurement is not possible, native wrapping keeps the original span tree. Test screen-reader output, text scaling, selection, bidi content, and interactive spans in every supported target application.

## Example and attribution

Run the responsive sample, including live controller diagnostics:

```sh
cd example
flutter run -d chrome
```

This project is licensed under Apache-2.0. It is a modified Dart/Flutter port of [`semantic-wrap`](https://github.com/woohyun-park/semantic-wrap) at commit `54ed67688aa5292f14970cae10bbabd9a11f1b5d`, including a BudouX-compatible inference implementation and the experimental English/Korean weights. See [NOTICE](https://github.com/muminjun/text-auto-wrap/blob/main/NOTICE), [LICENSE](https://github.com/muminjun/text-auto-wrap/blob/main/LICENSE), and the model cards for exact attribution and limitations.

Semantic work is limited to 65,536 UTF-16 units, 16,384 span occurrences, and depth 1,024 (root depth zero). Larger inputs bypass prediction and candidate work. Widgets also skip duplicate diagnostic shaping, keep native source rendering, and may publish `controller.result == null` with `TextWrapInputLimitException` in `failures`. Core `calculate()`, `predict()`, and `aggregate()` throw the independent `TextWrapInputLimitException` for oversized text. `select()` reuses a supplied valid native layout with reason `inputLimit` and no calculation-limit record, or throws that exception if no native layout is supplied. Existing exhaustive switches over calculation-limit kinds and invalid-input exceptions remain valid. Native Flutter rendering still has its own input-dependent cost.

Soft opportunities protect boundaries immediately following ZWJ, grouped numbers, and the inner sides of common brackets. GL/WJ protection remains deliberately more conservative than Unicode's space-before-glue exceptions. This is not full UAX #14 conformance. Shared controllers expose the last committed snapshot; use one controller per widget for independent observation.

## 0.1.3 performance controls

Equivalent plain `TextSpan` trees may share up to 64 verified selections and 32
plans for sources up to 1,024 UTF-16 units. Recognizers, hover callbacks,
`WidgetSpan`s, and custom spans are excluded. Font or platform-locale changes
clear shared entries. Custom predictors/calculators/selectors must return the same
output for equal inputs while their configuration identity/equality is unchanged.
If external configuration changes, supply a new model/strategy rather than mutate
an object already used as a cache key. Direct `TextWrapPlan.calculate`/`select`
calls still run custom calculators and preserve their validation errors.
Range caches ignore available width only when the actual
measurement inputs, including placeholder dimensions, remain equal.

`optimalLayouts(assumeMonotonicWidths: true)` and
`greedy(assumeMonotonicWidths: true)` are optional shortcuts for measurers whose
width never decreases as a range grows. They can change results for other
measurers and are disabled by default. See [performance benchmark](doc/performance-benchmark.md)
for repeatable local measurements and exact-layout comparisons.
