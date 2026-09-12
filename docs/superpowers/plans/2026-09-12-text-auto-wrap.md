# text_auto_wrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and release `text_auto_wrap` 0.1.0, a six-platform Flutter package that synchronously selects model-driven line breaks for plain text, rich `TextSpan` trees, and indivisible `WidgetSpan` placeholders.

**Architecture:** A Flutter-independent core works in UTF-16 ranges and exposes replaceable prediction, aggregation, calculation, and selection stages. Korean and English BudouX-compatible presets sit above the core; a `RenderParagraph`-based adapter measures native and candidate layouts with `TextPainter`, rewrites an `InlineSpan` tree without losing metadata, and paints only the final result.

**Tech Stack:** Flutter 3.47.4 stable, Dart 3.13.3, `characters`, `flutter_test`, GitHub Actions, `pana`, pub.dev.

**Spec:** `docs/superpowers/specs/2026-09-12-text-auto-wrap-design.md`

## Global Constraints

- Publish one package named `text_auto_wrap` from `muminjun/text-auto-wrap`, version `0.1.0`.
- Use SDK constraints `>=3.10.0 <4.0.0` and Flutter constraint `>=3.38.0` while developing and releasing with Flutter 3.47.4/Dart 3.13.3.
- Support Android, iOS, Web, macOS, Windows, and Linux without native plugin code.
- Use Apache-2.0 and retain applicable `semantic-wrap` and BudouX attribution in `NOTICE`.
- Treat upstream `semantic-wrap` commit `54ed67688aa5292f14970cae10bbabd9a11f1b5d` as the porting baseline.
- Do not depend on `textwrap.dart`; it is reference material only.
- Keep exact-first computation synchronous and fall back to native Flutter wrapping on runtime uncertainty.
- Keep `WidgetSpan` as one indivisible U+FFFC token and preserve all `InlineSpan` metadata.
- Use UTF-16 offsets at public engine boundaries and validate every model-produced offset.
- Follow test-driven development: add a focused failing test, observe the expected failure, add the minimum behavior, rerun the focused test, then run the affected suite.

## Planned File Structure

```text
.github/workflows/ci.yml                 # analyze, tests, builds, pana, publish dry-run
.github/workflows/publish.yml            # added after 0.1.0 for future OIDC releases
.gitignore                               # generated Flutter and local SDK files
CHANGELOG.md                             # release history
LICENSE                                  # Apache-2.0 text
NOTICE                                   # upstream and modification notices
README.md                                # English package guide
README-ko_kr.md                          # Korean package guide
analysis_options.yaml                    # strict analyzer configuration
benchmark/layout_benchmark.dart          # deterministic engine benchmarks
example/lib/main.dart                    # responsive plain/rich/WidgetSpan demo
example/pubspec.yaml                     # example app metadata
lib/text_auto_wrap.dart                  # single public export surface
lib/src/core/boundaries.dart             # UTF-16/grapheme boundary validation
lib/src/core/diagnostics.dart            # immutable diagnostic records
lib/src/core/exceptions.dart             # typed public input failures
lib/src/core/models.dart                 # model and predictor contracts
lib/src/core/prediction.dart             # prediction and aggregation
lib/src/core/layout.dart                 # measured layouts and candidate calculation
lib/src/core/selection.dart              # native-versus-calculated selection
lib/src/core/strategy.dart               # replaceable stage composition
lib/src/core/plan.dart                   # cached staged execution
lib/src/core/select_text_wrap.dart       # one-shot public engine entry point
lib/src/models/budoux_parser.dart        # dependency-free model inference
lib/src/models/english_model.dart        # English model constants and preset
lib/src/models/korean_model.dart         # Korean model constants and preset
lib/src/models/language_detection.dart   # deterministic auto selection
lib/src/flutter/span_codec.dart          # flatten/rebuild InlineSpan trees
lib/src/flutter/controller.dart          # post-layout result observation
lib/src/flutter/render_text_auto_wrap.dart # synchronous render adapter and cache
lib/src/flutter/text_auto_wrap.dart       # public widget constructors
model_cards/english.md                   # English preset limitations
model_cards/korean.md                    # Korean preset limitations
pubspec.yaml                             # package metadata and constraints
test/core/boundaries_test.dart           # Unicode and offset rules
test/core/prediction_test.dart           # model aggregation rules
test/core/layout_test.dart               # calculators and measurement
test/core/selection_test.dart            # balance and fallback rules
test/core/plan_test.dart                  # cache and diagnostics
test/models/budoux_parser_test.dart       # parser feature scoring
test/models/language_detection_test.dart # auto language decisions
test/models/presets_test.dart             # model regression fixtures
test/flutter/span_codec_test.dart         # rich-span preservation
test/flutter/text_auto_wrap_test.dart     # widget behavior
test/flutter/widget_span_test.dart        # placeholder layout
test/flutter/accessibility_test.dart      # semantics/selection/recognizers
test/flutter/cache_test.dart              # invalidation and safety fallback
test/support/measure.dart                 # deterministic range measurer
tool/bootstrap_flutter.sh                # pinned local SDK bootstrap
```

---

### Task 1: Reproducible package foundation

**Files:**
- Create: `tool/bootstrap_flutter.sh`
- Create: `.gitignore`
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `lib/text_auto_wrap.dart`
- Create: `test/package_smoke_test.dart`
- Create: `LICENSE`
- Create: `NOTICE`

**Interfaces:**
- Produces: a package importable as `package:text_auto_wrap/text_auto_wrap.dart` and a repository-local Flutter command at `.tooling/flutter/bin/flutter`.
- Consumes: no implementation files.

- [ ] **Step 1: Add the bootstrap script and package metadata**

Create an executable `tool/bootstrap_flutter.sh` that clones tag `3.47.4` with `--depth 1` into `.tooling/flutter`, verifies `Flutter 3.47.4`, and runs `flutter precache --web`. Add `.tooling/`, `.dart_tool/`, `build/`, coverage output, IDE files, and example generated platform/build directories to `.gitignore`.

Use this exact package core:

```yaml
name: text_auto_wrap
description: Model-driven semantic line breaking for plain and rich Flutter text.
version: 0.1.0
repository: https://github.com/muminjun/text-auto-wrap
issue_tracker: https://github.com/muminjun/text-auto-wrap/issues
topics: [text, typography, layout, korean, english]
environment:
  sdk: ">=3.10.0 <4.0.0"
  flutter: ">=3.38.0"
dependencies:
  characters: ^1.4.1
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
  lints: ^6.0.0
```

Copy the Apache-2.0 license text into `LICENSE`. In `NOTICE`, name Woohyun Park's `semantic-wrap`, Google LLC's BudouX parser/model work, their source URLs, their licenses, the pinned commit, and state that this distribution contains a modified Dart/Flutter port.

- [ ] **Step 2: Write a failing import smoke test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() {
  test('package exposes its version', () {
    expect(textAutoWrapVersion, '0.1.0');
  });
}
```

- [ ] **Step 3: Bootstrap Flutter and verify the test fails**

Run:

```bash
chmod +x tool/bootstrap_flutter.sh
./tool/bootstrap_flutter.sh
.tooling/flutter/bin/flutter pub get
.tooling/flutter/bin/flutter test test/package_smoke_test.dart
```

Expected: the test fails because `textAutoWrapVersion` is undefined.

- [ ] **Step 4: Add the minimal public library**

```dart
library;

const String textAutoWrapVersion = '0.1.0';
```

- [ ] **Step 5: Verify foundation and commit**

Run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and the smoke test through `.tooling/flutter/bin/`. Expect all to pass.

```bash
git add .gitignore analysis_options.yaml pubspec.yaml tool lib test LICENSE NOTICE
git commit -m "chore: scaffold text_auto_wrap package"
```

### Task 2: UTF-16 boundaries and public model contracts

**Files:**
- Create: `lib/src/core/exceptions.dart`
- Create: `lib/src/core/boundaries.dart`
- Create: `lib/src/core/models.dart`
- Create: `test/core/boundaries_test.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Produces: `TextWrapException`, `InvalidBoundaryException`, `TextRangeMeasurementException`, `TextWrapModel`, `PhraseModel`, `PhraseModelLevel`, `BoundaryPredictor`, `BoundaryMode`, `allowedBoundaries(String, BoundaryMode)`, and `validateOffsets`.
- Consumes: `characters` for grapheme segmentation.

- [ ] **Step 1: Write failing Unicode boundary tests**

Test that `allowedBoundaries('가👨‍👩‍👧‍👦é 나', BoundaryMode.characters)` never returns an offset inside the family emoji or combining sequence, that `spaces` returns the end of the whitespace opportunity, and that U+FFFC is one token. Test that duplicate, descending, endpoint, and surrogate-splitting predictor offsets throw `InvalidBoundaryException`.

```dart
expect(
  () => validateOffsets('😀', [1]),
  throwsA(isA<InvalidBoundaryException>()),
);
```

- [ ] **Step 2: Run the focused test and observe missing APIs**

Run `.tooling/flutter/bin/flutter test test/core/boundaries_test.dart`. Expected: compile failure for the new types and functions.

- [ ] **Step 3: Implement immutable contracts and boundary validation**

Use these signatures:

```dart
abstract interface class TextWrapModel {}
abstract interface class BoundaryPredictor {
  List<int> predict(String text);
}
enum BoundaryMode { spaces, characters }
final class PhraseModel implements TextWrapModel {
  const PhraseModel({required this.levels, required this.fallbackPenalty,
    this.boundaryMode = BoundaryMode.spaces});
  final List<PhraseModelLevel> levels;
  final double fallbackPenalty;
  final BoundaryMode boundaryMode;
}
```

Validate finite non-negative penalties, unique non-empty level names, at least one level, strictly ascending offsets, interior offsets, allowed boundary membership, grapheme integrity, and U+FFFC indivisibility. Copy caller lists into unmodifiable views.

- [ ] **Step 4: Export, verify, and commit**

Run the focused test and `flutter analyze`; expect success.

```bash
git add lib test/core
git commit -m "feat: define model and boundary contracts"
```

### Task 3: Prediction and aggregation

**Files:**
- Create: `lib/src/core/prediction.dart`
- Create: `test/core/prediction_test.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Consumes: `PhraseModel`, validated allowed boundaries.
- Produces: immutable `BreakPrediction`, `BreakCandidate`, `PredictionSnapshot`, `CandidateAggregator`, `lowestPenalty()`, and `consensus({required int minimumModels})`.

- [ ] **Step 1: Port failing upstream aggregation cases**

Cover repeated offsets at different penalties, fallback candidates, invalid predictor output, stable ascending order, consensus counts, and immutable returned lists. Pin expected values explicitly:

```dart
expect(snapshot.candidates.map((c) => (c.offset, c.penalty)), [
  (4, 0.0),
  (8, 1.0),
]);
```

- [ ] **Step 2: Run and observe compile failure**

Run `.tooling/flutter/bin/flutter test test/core/prediction_test.dart`.

- [ ] **Step 3: Implement prediction and both aggregators**

Define `CandidateAggregator` as a function object with `aggregate(PredictionContext)`. Keep raw predictions per model level for diagnostics. `lowestPenalty` keeps the lowest penalty and its level/name at each offset; `consensus` retains offsets predicted by at least `minimumModels` distinct levels. Add fallback candidates only at allowed positions not predicted by retained levels.

- [ ] **Step 4: Verify upstream parity and commit**

Run prediction and boundary suites, then analyze.

```bash
git add lib/src/core/prediction.dart lib/text_auto_wrap.dart test/core
git commit -m "feat: add boundary prediction aggregation"
```

### Task 4: Layout calculation and measurement

**Files:**
- Create: `lib/src/core/layout.dart`
- Create: `test/core/layout_test.dart`
- Create: `test/support/measure.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Consumes: ordered `BreakCandidate` values and `double Function(int start, int end)`.
- Produces: `TextRangeMeasurer`, `LineBreakLayoutCandidate`, `LineBreakLayout`, `LayoutCalculator`, `optimalLayouts()`, `greedy()`, and `nearbyLayouts()`.

- [ ] **Step 1: Add a deterministic range measurer and failing calculator tests**

The support measurer assigns each Unicode grapheme a declared width and U+FFFC its placeholder width. Test exact fits, overflow, minimum-line layouts, lower model cost, visual imbalance, empty text, hard-newline paragraph ranges, and a candidate ceiling fallback signal.

```dart
final measure = FixedRangeMeasurer(text, defaultWidth: 10);
expect(layout.widths, [40.0, 30.0]);
expect(layout.overflow, isFalse);
```

- [ ] **Step 2: Run and observe missing layout APIs**

Run `.tooling/flutter/bin/flutter test test/core/layout_test.dart`.

- [ ] **Step 3: Implement measured layout primitives**

Measure half-open UTF-16 ranges, trim only boundary whitespace according to the selected boundary record, and reject non-finite or negative measurements with `TextRangeMeasurementException`. Compute `lineCount`, `maxLineWidth`, normalized imbalance, total model cost, and overflow once in immutable `LineBreakLayout`.

- [ ] **Step 4: Implement calculators with bounded work**

`optimalLayouts()` uses dynamic programming and retains only non-dominated minimum-line states across cost and imbalance. `greedy()` selects the furthest fitting boundary. `nearbyLayouts()` enumerates configurable neighbors around a baseline. Use internal constants `maxCandidateCount = 4096` and `maxStateCount = 16384`; return a typed calculation-limit outcome used by widget fallback rather than partial results.

- [ ] **Step 5: Verify and commit**

Run core boundary, prediction, and layout tests plus analyze.

```bash
git add lib test/core test/support
git commit -m "feat: calculate measured line layouts"
```

### Task 5: Selection, strategies, plans, and diagnostics

**Files:**
- Create: `lib/src/core/selection.dart`
- Create: `lib/src/core/strategy.dart`
- Create: `lib/src/core/diagnostics.dart`
- Create: `lib/src/core/plan.dart`
- Create: `lib/src/core/select_text_wrap.dart`
- Create: `test/core/selection_test.dart`
- Create: `test/core/plan_test.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Produces: `BalanceStrategy`, `LineBreakStrategy`, `TextWrapInput`, `TextWrapResult`, `TextWrapDiagnostics`, `TextWrapPlan`, `createTextWrapPlan`, and `selectTextWrap`.
- Consumes: Tasks 2-4 contracts.

- [ ] **Step 1: Write failing selection tests**

Port upstream cases for native fit, native overflow, equal model cost, lower cost with unacceptable balance, tolerance boundary `0.12`, no native layout, custom selector reason, hard newlines, and maximum lines. Assert stable reasons: `nativeNoModelImprovement`, `nativeSelected`, `calculatedSelected`, `unsupportedLanguage`, `calculationLimit`, and `invalidRuntimeMeasurement`.

- [ ] **Step 2: Write failing plan/cache tests**

Use counting predictors and measurers to prove `predict()` and `aggregate()` run once per immutable plan, while `calculate()` and `select()` rerun for a new width. Verify diagnostics contain raw predictions, aggregated candidates, calculated layouts, native layout, cache counters, and selection source.

- [ ] **Step 3: Run both tests and observe missing APIs**

Run `.tooling/flutter/bin/flutter test test/core/selection_test.dart test/core/plan_test.dart`.

- [ ] **Step 4: Implement default strategy and one-shot API**

Use this entry signature:

```dart
TextWrapResult selectTextWrap(
  TextWrapInput input, {
  LineBreakStrategy strategy = const LineBreakStrategy(),
  bool diagnostics = false,
});
```

When native fits, accept only non-overflowing, same-line-count candidates with lower model cost, then apply balance tolerance. When native overflows, allow any fitting calculated candidate. Freeze all result collections.

- [ ] **Step 5: Implement staged cached plans**

Expose synchronous `predict`, `aggregate`, `calculate`, and `select`; later stages invoke missing prerequisites. Cache only text/model/strategy-dependent snapshots. Never cache width-dependent measurements across different measurement cache keys.

- [ ] **Step 6: Verify the entire core and commit**

Run `.tooling/flutter/bin/flutter test test/core` and analyze.

```bash
git add lib test/core
git commit -m "feat: expose semantic wrap engine"
```

### Task 6: BudouX-compatible parser and bundled presets

**Files:**
- Create: `lib/src/models/budoux_parser.dart`
- Create: `lib/src/models/english_model.dart`
- Create: `lib/src/models/korean_model.dart`
- Create: `test/models/budoux_parser_test.dart`
- Create: `test/models/presets_test.dart`
- Modify: `lib/text_auto_wrap.dart`
- Modify: `NOTICE`

**Interfaces:**
- Produces: `BudouxPredictor`, `TextAutoWrapModels.korean`, and `TextAutoWrapModels.english`.
- Consumes: `BoundaryPredictor` and `PhraseModel`.

- [ ] **Step 1: Pin and record upstream source material**

Fetch only commit `54ed67688aa5292f14970cae10bbabd9a11f1b5d` into a temporary directory. Record the exact adapted source files in `NOTICE`: `packages/core/src/core/budoux-parser.ts`, `packages/core/src/core/predictors.ts`, `packages/en/src/models.ts`, and `packages/ko/src/models.ts`. Do not copy repository metadata or introduce an npm/runtime dependency.

- [ ] **Step 2: Port failing parser fixtures**

Port feature scoring fixtures for UW/BW/TW keys, threshold behavior, ascending UTF-16 offsets, empty/single-character strings, Hangul, Latin, emoji adjacency, and malformed model maps.

- [ ] **Step 3: Run and observe missing parser**

Run `.tooling/flutter/bin/flutter test test/models/budoux_parser_test.dart`.

- [ ] **Step 4: Port the dependency-free parser and model constants**

Translate model maps without lossy JSON conversion. Keep them `const` where Dart permits and otherwise expose one lazily initialized immutable instance. Add prominent source/modification headers to adapted files and preserve Apache notices.

- [ ] **Step 5: Add preset regression tests**

Use every published example from both upstream model cards plus punctuation and explicit newline cases. Assert break candidates and penalties, not only final lines, so model drift is visible.

- [ ] **Step 6: Verify model suites, archive size, and commit**

Run model and core suites. Run `flutter pub publish --dry-run` and check that compressed/uncompressed size remains far below pub.dev limits.

```bash
git add lib/src/models lib/text_auto_wrap.dart test/models NOTICE
git commit -m "feat: bundle Korean and English models"
```

### Task 7: Automatic language detection

**Files:**
- Create: `lib/src/models/language_detection.dart`
- Create: `test/models/language_detection_test.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Produces: `AutoTextWrapModel`, `TextAutoWrapModels.auto`, `LanguageDetectionResult`, and `detectTextWrapLanguage(String, Locale?)`.
- Consumes: Korean and English presets.

- [ ] **Step 1: Write the decision table as failing tests**

Ignore punctuation, whitespace, digits, and U+FFFC. Select a script at `70%` or greater supported-letter share. For shares from `40%` through `60%`, let matching `ko` or `en` locale select its script when at least one matching letter exists. Treat the interval above `60%` and below `70%` without matching locale as ambiguous. Test Korean, English, product-name mixtures, Japanese, Arabic, emoji-only, numbers-only, and explicit preset override.

- [ ] **Step 2: Run and observe missing detector**

Run `.tooling/flutter/bin/flutter test test/models/language_detection_test.dart`.

- [ ] **Step 3: Implement deterministic detection**

Count Unicode Hangul syllables/jamo and Latin letters by code point without classifying combining marks as evidence. Return immutable counts, ratio, selected preset or null, whether locale resolved the decision, and a stable fallback reason.

- [ ] **Step 4: Verify and commit**

Run all model tests and analyze.

```bash
git add lib/src/models lib/text_auto_wrap.dart test/models
git commit -m "feat: detect Korean and English text"
```

### Task 8: Reversible rich-span codec

**Files:**
- Create: `lib/src/flutter/span_codec.dart`
- Create: `test/flutter/span_codec_test.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Produces: internal `EncodedInlineSpan`, `encodeInlineSpan(InlineSpan)`, and `insertLineBreaks(EncodedInlineSpan, List<int>)`.
- Consumes: UTF-16 boundary utilities.

- [ ] **Step 1: Write failing structure-preservation tests**

Build nested spans containing text, styles, recognizers, mouse cursors, semantics labels/identifiers, locale, spell-out metadata, and multiple aligned `WidgetSpan` children. Assert encoded plain text uses exactly one U+FFFC per placeholder and a rebuilt tree preserves property identity while adding newline leaves only at requested valid offsets.

- [ ] **Step 2: Run and observe missing codec**

Run `.tooling/flutter/bin/flutter test test/flutter/span_codec_test.dart`.

- [ ] **Step 3: Implement flattening with source segments**

Record half-open source ranges and their original leaf/path. Preserve explicit newlines. Reject a requested break at offset zero, the source end, inside a grapheme, inside U+FFFC, or adjacent to an existing newline with `InvalidBoundaryException`.

- [ ] **Step 4: Implement minimal-path rebuilding**

Clone only ancestors whose descendants change. Split a text leaf at valid UTF-16 offsets and insert `const TextSpan(text: '\n')`; reuse untouched spans and every `WidgetSpan.child` instance.

- [ ] **Step 5: Verify and commit**

Run codec and boundary suites plus analyze.

```bash
git add lib/src/flutter lib/text_auto_wrap.dart test/flutter
git commit -m "feat: preserve rich spans across inserted breaks"
```

### Task 9: Plain and styled TextAutoWrap renderer

**Files:**
- Create: `lib/src/flutter/controller.dart`
- Create: `lib/src/flutter/render_text_auto_wrap.dart`
- Create: `lib/src/flutter/text_auto_wrap.dart`
- Create: `test/flutter/text_auto_wrap_test.dart`
- Modify: `lib/text_auto_wrap.dart`

**Interfaces:**
- Produces: `TextAutoWrap`, `TextAutoWrap.rich`, `TextAutoWrapController`, and internal `RenderTextAutoWrap extends RenderParagraph`.
- Consumes: engine, auto model, and span codec.

- [ ] **Step 1: Write failing constructor and exact-first widget tests**

Assert parameter parity for `style`, `strutStyle`, `textAlign`, `textDirection`, `locale`, `softWrap`, `overflow`, `textScaler`, `maxLines`, `semanticsLabel`, `textWidthBasis`, `textHeightBehavior`, and `selectionColor`. Pump once at a fixed width and assert the render object's effective span already contains the selected breaks without a second pump.

- [ ] **Step 2: Run and observe missing widget**

Run `.tooling/flutter/bin/flutter test test/flutter/text_auto_wrap_test.dart`.

- [ ] **Step 3: Implement the widget/render-object bridge**

Model `TextAutoWrap` on Flutter 3.47.4's `RichText` `MultiChildRenderObjectWidget`: merge `DefaultTextStyle`, resolve locale/direction/scaler from context, extract inline widget children with Flutter's public `WidgetSpan` helper, and create/update `RenderTextAutoWrap` with source span, resolved model selector, strategy, and controller.

- [ ] **Step 4: Implement synchronous source and final layouts**

In `performLayout`, call the public `layoutInlineChildren` helper to obtain placeholder dimensions, configure a source `TextPainter`, collect native line boundaries with `getLineBoundary`, and use range-specific `TextPainter` instances to measure candidates. Resolve semantic breaks, assign the effective span to the inherited paragraph before its final layout, then delegate final positioning, painting, hit testing, selection, and semantics to `RenderParagraph`. Ensure internal effective-text changes do not schedule a second visible layout.

- [ ] **Step 5: Implement controller publication safely**

Store the committed immutable result immediately, then schedule at most one post-frame `notifyListeners` call when the value materially changes. Detaching or disposing the render object cancels pending publication ownership.

- [ ] **Step 6: Verify behavior and commit**

Run text widget, codec, and full core/model suites plus analyze.

```bash
git add lib test/flutter
git commit -m "feat: render exact semantic text wrapping"
```

### Task 10: WidgetSpan layout, overflow, and accessibility

**Files:**
- Create: `test/flutter/widget_span_test.dart`
- Create: `test/flutter/accessibility_test.dart`
- Modify: `lib/src/flutter/render_text_auto_wrap.dart`
- Modify: `lib/src/flutter/text_auto_wrap.dart`

**Interfaces:**
- Consumes: `RenderTextAutoWrap` and span codec.
- Produces: correct placeholder measurement and Flutter-compatible interaction behavior.

- [ ] **Step 1: Write failing placeholder tests**

Test above/below/middle/baseline alignments, multiple placeholders, width-changing children, a placeholder wider than constraints, and U+FFFC-adjacent candidate positions. Assert child identity is stable, no break occurs inside a placeholder, and the final child boxes match the effective paragraph.

- [ ] **Step 2: Write failing accessibility and text behavior tests**

Test tap recognizers, `SelectionArea` selection, semantics labels, RTL, explicit newlines, `softWrap: false`, all `TextOverflow` values, `maxLines`, nonlinear `TextScaler`, and unsupported-language native fallback.

- [ ] **Step 3: Run tests and capture exact failures**

Run both new files independently. Expected: failures identify incomplete placeholder sizing or inherited paragraph behavior, not skipped assertions.

- [ ] **Step 4: Complete placeholder dimension mapping**

Match placeholder indices from the encoded tree to render children. Feed each `PlaceholderDimensions` size, alignment, baseline, and baseline offset to every source/candidate `TextPainter`. If baseline data or finite size is unavailable, retain the source span and record `unmeasurablePlaceholder`.

- [ ] **Step 5: Preserve native paragraph behavior**

Delegate selection registrar, painting, hit testing, semantics assembly, clipping/fade/ellipsis, and bidi positioning to `RenderParagraph`. Inserted newline spans use no semantics label and do not create additional focus or gesture targets.

- [ ] **Step 6: Verify and commit**

Run all Flutter tests, all package tests, and analyze.

```bash
git add lib/src/flutter test/flutter
git commit -m "feat: support widget spans and accessibility"
```

### Task 11: Cache invalidation and performance limits

**Files:**
- Create: `test/flutter/cache_test.dart`
- Create: `benchmark/layout_benchmark.dart`
- Modify: `lib/src/flutter/render_text_auto_wrap.dart`
- Modify: `lib/src/core/diagnostics.dart`

**Interfaces:**
- Produces: observable cache counters and deterministic safety fallback.
- Consumes: immutable core plan and render inputs.

- [ ] **Step 1: Write failing cache-key tests**

Use counting model/measurer fakes. Prove unchanged layout reuses prediction and measurements; width changes reuse prediction only; text, span metadata, style, direction, locale, scaler, strut, width basis, height behavior, model, strategy, maximum lines, and placeholder-size changes invalidate the required layers.

- [ ] **Step 2: Write the benchmark harness**

Benchmark 20/100/1000-character strings, 100 nested spans, 20 placeholders, worst-case boundaries, cold layout, and warm cache. Print iterations, candidate count, measurements, and elapsed microseconds as machine-readable JSON; do not fail on absolute timing.

- [ ] **Step 3: Run tests and baseline benchmark**

Run the cache test and `flutter run -d flutter-tester benchmark/layout_benchmark.dart`. Save no host-specific timing artifact in git.

- [ ] **Step 4: Implement layered cache keys and ceilings**

Cache immutable plans separately from range widths and final selection. Hash value-semantic configuration and include placeholder sizes/baselines. At 4096 candidates or 16384 DP states, abort before allocating further states, select native layout, and record the exact ceiling and observed count in diagnostics.

- [ ] **Step 5: Verify and commit**

Run all tests, analyze, then run the benchmark twice and confirm warm iterations report cache hits.

```bash
git add lib benchmark test/flutter/cache_test.dart
git commit -m "perf: cache layouts and bound candidate work"
```

### Task 12: Example, package documentation, and model cards

**Files:**
- Create: `README.md`
- Create: `README-ko_kr.md`
- Create: `CHANGELOG.md`
- Create: `model_cards/english.md`
- Create: `model_cards/korean.md`
- Create: `example/pubspec.yaml`
- Create: `example/lib/main.dart`
- Create: `test/public_api_test.dart`

**Interfaces:**
- Consumes: final public exports.
- Produces: publishable user documentation and a compiling example.

- [ ] **Step 1: Write a public API compile test**

Import only `package:text_auto_wrap/text_auto_wrap.dart` and instantiate plain, rich, automatic, explicit Korean/English, custom predictor/strategy, `WidgetSpan`, controller, engine, plan, and diagnostics examples. This prevents docs from relying on private imports.

- [ ] **Step 2: Run and fix export omissions**

Run `.tooling/flutter/bin/flutter test test/public_api_test.dart`; update only `lib/text_auto_wrap.dart` exports until it passes.

- [ ] **Step 3: Build the responsive example**

Create one screen with a width slider and cards for Korean plain text, English plain text, styled `TextSpan`, `WidgetSpan`, unsupported-language fallback, explicit model selection, and live controller diagnostics. Use no network assets.

- [ ] **Step 4: Write both READMEs and model cards**

Document installation, constructor parity, automatic detection thresholds, explicit models, custom predictors/strategies, engine measurement contract, controller use, fallback reasons, Unicode offsets, performance ceilings, accessibility, and attribution. Mark bundled presets experimental and include the upstream model-card limitations without expanding their claims.

- [ ] **Step 5: Add release notes and verify documentation**

Set `CHANGELOG.md` entry `## 0.1.0 - 2026-09-12`. Run `.tooling/flutter/bin/dart pub global activate dartdoc`, then `.tooling/flutter/bin/dart pub global run dartdoc`; build the example for web and fix every warning originating in this package.

- [ ] **Step 6: Commit**

```bash
git add README.md README-ko_kr.md CHANGELOG.md model_cards example lib/text_auto_wrap.dart test/public_api_test.dart
git commit -m "docs: prepare text_auto_wrap 0.1.0"
```

### Task 13: CI, package scoring, and public GitHub repository

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: reproducible pull-request validation and a public source repository.
- Consumes: complete package and example.

- [ ] **Step 1: Add CI workflow**

Use `subosito/flutter-action@v2` pinned to Flutter `3.47.4`. On pushes and pull requests run `flutter pub get`, format check, analyze, all tests with coverage, example web build, `dart pub global activate pana`, `pana --no-warning`, and `flutter pub publish --dry-run`. Add macOS and Windows test jobs at Flutter 3.47.4 plus a minimum-version Linux job at Flutter 3.38.0.

- [ ] **Step 2: Run every local release check**

```bash
.tooling/flutter/bin/dart format --output=none --set-exit-if-changed lib test benchmark example
.tooling/flutter/bin/flutter analyze
.tooling/flutter/bin/flutter test --coverage
(cd example && ../.tooling/flutter/bin/flutter build web)
.tooling/flutter/bin/dart pub global run pana --no-warning
.tooling/flutter/bin/flutter pub publish --dry-run
```

Expected: every command exits zero and the dry run includes only intended source, docs, licenses, model cards, and example files.

- [ ] **Step 3: Commit the validated CI configuration**

```bash
git add .github/workflows/ci.yml pubspec.yaml
git commit -m "ci: validate Flutter package"
```

- [ ] **Step 4: Create and push the public repository**

First confirm `gh repo view muminjun/text-auto-wrap` reports not found and `git status --short` is empty. Then run:

```bash
gh repo create muminjun/text-auto-wrap --public --source=. --remote=origin --push 
gh repo edit muminjun/text-auto-wrap --description "Model-driven semantic line breaking for plain and rich Flutter text" --add-topic flutter --add-topic dart --add-topic typography --add-topic korean
```

- [ ] **Step 5: Wait for CI and commit any workflow correction separately**

Use `gh run watch --exit-status`. If a workflow-only defect appears, reproduce it locally, add a focused correction, rerun the affected command, and commit with `fix(ci): correct release validation`.

### Task 14: Final review and 0.1.0 release

**Files:**
- Create after the first pub.dev release: `.github/workflows/publish.yml`
- Modify only other files required by evidence from final verification.
- Verify: entire repository and pub.dev archive.

**Interfaces:**
- Produces: GitHub tag/release `v0.1.0` and pub.dev package `text_auto_wrap` 0.1.0.
- Consumes: clean, passing Task 13 main branch.

- [ ] **Step 1: Review attribution and the exact archive**

Compare every adapted file header and `NOTICE` against pinned upstream sources. Run `flutter pub publish --dry-run`, inspect its complete file list, and verify no `.tooling`, credentials, coverage, screenshots, temporary clones, or unrelated files are included.

- [ ] **Step 2: Run clean-checkout verification**

Clone `https://github.com/muminjun/text-auto-wrap` into a new temporary directory, bootstrap Flutter, and run format, analyze, all tests, example web build, `pana --no-warning`, and publish dry-run. Confirm `git status --short` remains empty.

- [ ] **Step 3: Confirm package name immediately before irreversible release**

Run `curl -f https://pub.dev/api/packages/text_auto_wrap`. Expected before first publication: HTTP 404. If it returns package metadata owned by anyone else, stop without tagging or publishing because the approved name is unavailable.

- [ ] **Step 4: Tag and create the GitHub release**

```bash
git tag -a v0.1.0 -m "text_auto_wrap 0.1.0"
git push origin v0.1.0
gh release create v0.1.0 --title "text_auto_wrap 0.1.0" --notes-from-tag
```

Verify the tag resolves to the tested main commit and the GitHub Release is public.

- [ ] **Step 5: Publish the first version interactively**

From the same clean tagged checkout, run:

```bash
.tooling/flutter/bin/flutter pub publish
```

Authenticate with the Google account that owns the existing `dup` uploader identity when prompted, inspect the final confirmation, and submit 0.1.0. Do not use `--force` for the first release.

- [ ] **Step 6: Verify the public package**

Poll `https://pub.dev/api/packages/text_auto_wrap` until version `0.1.0` appears. Open the package page and verify README rendering, six platform badges, repository/issue links, license recognition, API docs, model-card inclusion, and score diagnostics. Record any non-blocking pub score follow-up as a GitHub issue rather than mutating the released tag.

- [ ] **Step 7: Configure future automated publishing**

After 0.1.0 exists, create `.github/workflows/publish.yml` with tag pattern `v[0-9]+.[0-9]+.[0-9]+`, permission `id-token: write`, and reusable workflow `dart-lang/setup-dart/.github/workflows/publish.yml@v1`. In the pub.dev Admin tab, enable GitHub Actions publishing for repository `muminjun/text-auto-wrap` and tag pattern `v{{version}}`. Commit the workflow as `ci: automate future pub releases`, push `main`, and confirm no long-lived pub credential is stored in GitHub secrets or the repository.
