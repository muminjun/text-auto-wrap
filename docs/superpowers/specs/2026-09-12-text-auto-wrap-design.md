# text_auto_wrap Design

## Summary

`text_auto_wrap` is a single Flutter package that provides model-driven line breaking for plain and rich text. It ports the language-independent selection pipeline and the experimental Korean and English presets from [`semantic-wrap`](https://github.com/woohyun-park/semantic-wrap) to Dart, then integrates them with Flutter's text layout system.

The package will be developed in the public GitHub repository `muminjun/text-auto-wrap` and published to pub.dev as `text_auto_wrap`. The first release will be `0.1.0` because the bundled language models are experimental and the public API should receive field feedback before a stable release.

## Goals

- Produce semantically natural, visually balanced line breaks using the actual rendered width.
- Render the exact selected layout on the first visible frame.
- Support plain strings, nested `TextSpan` trees, and `WidgetSpan` children.
- Preserve Flutter text behavior, including styles, recognizers, semantics, selection, bidirectional text, scaling, and overflow.
- Bundle experimental Korean and English presets with automatic language selection and explicit override support.
- Expose both a convenient Flutter widget and an independent, customizable layout engine.
- Support Android, iOS, Web, macOS, Windows, and Linux without platform-specific native code.
- Fail safely to Flutter's native wrapping when semantic wrapping cannot be applied reliably.

## Non-goals for 0.1.0

- Training new language models or claiming production-grade linguistic accuracy for the bundled presets.
- Supporting languages other than Korean and English with bundled models.
- Asynchronous or post-paint reflow modes.
- Depending on `textwrap.dart` or reproducing Python's character-count wrapping behavior.
- Providing a visual editor, remote inference service, or runtime model downloader.

## Package and Repository

- GitHub repository: `https://github.com/muminjun/text-auto-wrap`
- pub.dev package name: `text_auto_wrap`
- Dart import: `package:text_auto_wrap/text_auto_wrap.dart`
- Initial version: `0.1.0`
- License: Apache License 2.0

The package will include `LICENSE` and `NOTICE`. `NOTICE` will preserve applicable attribution for `semantic-wrap` and its BudouX-compatible parser and model data, identify this project as a Dart/Flutter port, and describe that the files were modified. Model cards will document the experimental status and known limitations of both presets.

## Architecture

The single published package contains three internally isolated layers.

### Core engine

The core engine owns boundary prediction, candidate aggregation, layout calculation, and final selection. Its public API does not require a widget tree. It operates on UTF-16 source offsets, matching Dart strings and Flutter `TextPosition` offsets.

The engine accepts a range measurement callback rather than measuring substring text directly:

```dart
double measureRange(int start, int end);
```

Range measurement supports plain strings while also allowing the Flutter adapter to account for different styles and placeholder dimensions across a rich span tree. The engine returns immutable results containing source text, selected line ranges and strings, break offsets, measured widths, selected candidates, overflow state, whether calculated wrapping was applied, and a stable selection reason.

The engine exposes reusable plans so prediction and aggregation can be cached while width-dependent calculation and selection are repeated.

### Language presets

The package bundles immutable Korean and English BudouX-compatible model data as Dart constants. Presets implement the same public `PhraseModel` interface as custom models.

Automatic selection uses the following order:

1. An explicitly supplied model always wins.
2. Otherwise, supported-script characters are counted after whitespace, punctuation, digits, and widget placeholders are ignored.
3. A clearly dominant Hangul or Latin script selects the corresponding preset.
4. A supported `ko` or `en` locale resolves close mixed-script results when the text contains that locale's script.
5. Unsupported scripts, empty evidence, or unresolved mixed text cause native Flutter wrapping.

The exact dominance threshold will be a named, tested constant rather than hidden inline arithmetic. Diagnostics report the selected model, script counts, locale influence, and fallback reason.

### Flutter rendering

`TextAutoWrap` mirrors Flutter's `Text` API, while `TextAutoWrap.rich` accepts an `InlineSpan` tree. The rendering layer uses Flutter text layout primitives and `RenderParagraph` behavior wherever possible so it retains native selection, gesture recognition, semantics, bidirectional layout, scaling, and painting.

Within one layout frame, the renderer:

1. Measures inline placeholder children.
2. Lays out the unmodified span tree to obtain the native baseline.
3. Runs semantic candidate calculation with the actual constraints, text styles, and placeholder sizes.
4. Builds an effective span tree containing only the selected additional line breaks.
5. Performs the final paragraph layout before paint.

The internal extra measurement does not expose an intermediate frame. Cache hits skip prediction and candidate recomputation when only reusable layout inputs remain unchanged.

## Rich Text and Placeholder Mapping

The renderer flattens an `InlineSpan` tree into a source sequence while recording a reversible mapping to every original leaf span. `WidgetSpan` is represented in the model input as one U+FFFC object-replacement character. It is an indivisible token and is never a valid internal break location.

Selected breaks are inserted by rebuilding only the necessary span paths. The transformation preserves:

- `TextStyle` and inherited style structure;
- gesture recognizers and mouse cursors;
- semantics labels and identifiers;
- locale and spell-out metadata;
- `WidgetSpan` child identity, alignment, baseline, and baseline type.

Unicode break positions must be valid grapheme boundaries. The engine must never divide a surrogate pair, combining sequence, emoji modifier sequence, or ZWJ sequence. Explicit newline characters are preserved and split the input into independently optimized paragraphs.

If a placeholder cannot be measured, the renderer keeps the original span tree and uses native wrapping.

## Public API

The package has one public library entry point:

```dart
import 'package:text_auto_wrap/text_auto_wrap.dart';
```

### Widget API

```dart
TextAutoWrap(
  String data, {
  Key? key,
  TextStyle? style,
  StrutStyle? strutStyle,
  TextAlign? textAlign,
  TextDirection? textDirection,
  Locale? locale,
  bool? softWrap,
  TextOverflow? overflow,
  TextScaler? textScaler,
  int? maxLines,
  String? semanticsLabel,
  TextWidthBasis? textWidthBasis,
  TextHeightBehavior? textHeightBehavior,
  Color? selectionColor,
  TextWrapModel? model,
  LineBreakStrategy? strategy,
  TextAutoWrapController? controller,
});

TextAutoWrap.rich(
  InlineSpan textSpan, {
  // The same layout, model, strategy, and diagnostics options.
});
```

`TextWrapModel` is the common configuration type implemented by the automatic selector and concrete phrase models. Omitting `model` is equivalent to `TextAutoWrapModels.auto`. A custom `PhraseModel` can be passed directly. `softWrap: false` disables inserted semantic breaks but preserves explicit newlines. `maxLines` and `overflow` remain final Flutter rendering rules.

`TextAutoWrapController` exposes the most recently committed selection and diagnostics. Controller notification happens after layout, not from inside layout, so consumers can observe results without causing reentrant builds.

### Engine API

The stable low-level surface includes:

- `selectTextWrap` and `createTextWrapPlan`;
- `TextWrapInput`, `TextWrapResult`, and `TextWrapDiagnostics`;
- `TextWrapModel`, `PhraseModel`, `PhraseModelLevel`, and `BoundaryPredictor`;
- `TextAutoWrapModels.auto`, `.korean`, and `.english`;
- candidate aggregator, layout calculator, and layout selector interfaces;
- default lowest-penalty aggregation, optimal layout calculation, and balance selection;
- optional consensus, greedy, and nearby-layout strategies.

Configuration objects and returned snapshots are immutable. Model definitions validate and freeze boundary behavior at construction time.

## Selection Behavior

For each paragraph, the default pipeline performs these stages:

1. The selected phrase model predicts semantic boundary offsets at one or more priority levels.
2. Predictions are filtered to permitted grapheme or whitespace boundaries and aggregated by lowest penalty.
3. Fallback boundaries receive the model's fallback penalty.
4. Dynamic programming creates non-dominated, minimum-line candidates across model cost and visual balance while respecting width and configured safety limits.
5. Candidates are measured using the real range measurer.
6. The selector compares calculated candidates with Flutter's native layout.

If the native layout fits, a calculated layout may replace it only when it has the same line count, does not overflow, and improves model cost. Visual balance then decides whether the improvement remains acceptable. If native wrapping overflows, any fitting calculated layout may replace it. If no candidate is better, native wrapping is retained.

The initial balance tolerance follows the upstream default of `0.12` and remains configurable through the strategy API.

## Caching and Performance Safety

Synchronous exact-first rendering requires bounded work. The implementation uses:

- immutable plan caches for prediction and aggregation;
- range-width measurement caches scoped to the current layout inputs;
- a renderer cache keyed by span content and identity-relevant metadata, effective style, width, direction, locale, scaler, strut, width basis, height behavior, maximum lines, model, strategy, and placeholder dimensions;
- configurable internal safety ceilings for candidate count and optimization work;
- deterministic native fallback when a ceiling is exceeded.

Safety ceilings are documented behavior but are not part of the initial public configuration surface. Benchmarks will determine conservative defaults. Diagnostics identify cache use and safety-limit fallback.

## Error and Fallback Policy

The widget prioritizes rendering valid content. It falls back to the original Flutter paragraph for:

- unsupported or ambiguous language detection;
- unbounded or non-positive usable width;
- unmeasurable placeholders;
- no valid semantic candidate;
- candidate or work safety-limit exhaustion;
- errors raised by a custom predictor or strategy.

The fallback is observable through diagnostics and does not remove explicit newlines or alter the input span tree.

Direct engine calls reject programmer errors with typed `TextWrapException` subclasses. Invalid cases include non-finite or negative widths, unordered or out-of-range offsets, offsets that split an invalid boundary, non-finite measurement results, and malformed model configuration. The engine does not silently convert invalid public inputs into plausible results.

## Testing

### Engine tests

- Port and adapt upstream regression cases for aggregation, calculators, nearby layouts, selection, plan caching, and diagnostics.
- Test immutable configuration and result snapshots.
- Test invalid input and typed exception behavior.
- Cross-check plain-text measurement helpers against known layouts.

### Language tests

- Korean and English preset fixtures from their model cards.
- Locale-assisted mixed text and explicit model overrides.
- Unsupported languages and ambiguous mixed-script native fallback.
- Stable diagnostics for every selection path.

### Flutter widget tests

- Plain text and nested styled `TextSpan` trees.
- Recognizers, semantics metadata, selection, and span identity preservation.
- Multiple `WidgetSpan` alignments and dynamically changing child sizes.
- Width changes, theme/style changes, locale, direction, and `TextScaler` changes.
- `softWrap`, hard newlines, `maxLines`, and every `TextOverflow` behavior supported by `Text`.
- Verification that the first painted frame contains the final selected layout.

### Unicode and directionality tests

- Surrogate pairs, combining marks, variation selectors, emoji modifiers, and ZWJ sequences.
- Korean/Latin mixed strings and punctuation.
- RTL paragraphs and mixed bidirectional runs, which must preserve Flutter behavior even when the bundled models are not applied.

### Visual and performance tests

Core correctness uses break offsets, line counts, overflow state, and width comparisons with explicit tolerances. A small set of golden tests uses a test-only fixed font to avoid host font differences. Benchmarks cover short titles, long text, deeply nested spans, many candidates, repeated layout cache hits, and multiple placeholders. Performance regression checks avoid brittle absolute wall-clock thresholds on shared CI machines.

## Documentation and Example

The repository and published archive include:

- an English `README.md` and Korean `README-ko_kr.md`;
- installation and quick-start examples for plain, rich, and widget-span content;
- automatic detection, explicit presets, custom models, strategies, controller diagnostics, and fallback documentation;
- `CHANGELOG.md`, API dartdoc, `LICENSE`, and `NOTICE`;
- separate Korean and English model cards;
- an example Flutter app demonstrating responsive width changes and all supported content forms.

Documentation clearly distinguishes semantic wrapping from Python-style fixed-column wrapping and does not promise linguistic correctness beyond the experimental model evidence.

## CI and Release

GitHub Actions runs formatting checks, static analysis, unit/widget tests, web compilation, `pana`, and a publish dry run. A Flutter stable matrix covers Linux, macOS, and Windows where practical; the package contains no platform-specific native implementation. The example is compiled for representative supported targets.

Release readiness requires:

1. All tests and analysis pass on a clean checkout.
2. Public API documentation has no analyzer warnings.
3. Package contents, size, license, and `NOTICE` pass review.
4. `dart pub publish --dry-run` and `pana` pass without release-blocking findings.
5. The GitHub repository points to the final public commit.
6. Version `0.1.0` is tagged as `v0.1.0` and accompanied by a GitHub Release.
7. The pub.dev upload is performed from the verified release contents and then checked on pub.dev.

Publishing is permanent, so the actual pub.dev submission occurs only after the release artifact and account state have been verified. Existing uploader access demonstrated by the published `dup` package does not remove the need to authenticate the local Dart/Flutter toolchain.

## Implementation Constraints

The current shell does not expose a `flutter` executable. Implementation must first establish a repository-scoped, reproducible Flutter stable toolchain without overwriting unrelated system configuration. The selected Flutter and Dart minimum versions will be recorded in `pubspec.yaml`, CI, and contributor documentation after compatibility with the required public rendering APIs is confirmed.

The implementation will be original Dart code or a clearly identified Apache-2.0 adaptation. It will not depend on `textwrap.dart`; that project is only a reference for Dart package conventions and text utility ergonomics.
