# Changelog

## 0.1.3 - 2026-10-19

- Reuse bounded shared selections and plans for equivalent plain text trees, and retain range widths across width changes. Interactive, widget, and custom spans stay renderer-local; system-font or platform-locale changes invalidate shared entries.
- Skip bundled-model prediction/calculation for an already fitting single native line under `BalanceStrategy` with a built-in calculator. Caller-supplied predictors, aggregators, and calculators continue through validation.
- Score bundled BudouX space models only at the whitespace starts they consume, preserving the full-inference predictions. Hash built-in span trees in one iterative pass instead of revisiting nested subtrees.
- Skip provably dominated optimizer transitions before requesting range measurements, without assuming monotonic widths. The local long-phrase 256-request limit rate falls from 40.0% to 31.7%; four formerly limited conditions now equal the unbounded 0.1.2 semantic layout instead of native fallback.
- Add optional `assumeMonotonicWidths` to `optimalLayouts` and `greedy`; it remains off by default because shaping can shorten an extended range.
- Isolate shared plans before switching to interactive source spans, and preserve parent-query failure records through the following layout/controller snapshot.
- Reject incomplete or inconsistent benchmark references and non-positive repetition counts.
- Add a single-process, multi-scale benchmark with repeated statistics and reference-layout assertions. See `doc/performance-benchmark.md` for conditions, variation, and limitations.

- Fix native line measurement when a line holds a single glyph wider than the available width (for example a text laid out at a width below one character, such as 0 during a transition, at large text scales). The engine then reports the spaces after that line outside every line boundary, which 0.1.1 surfaced as `InvalidBoundaryException` from layout and 0.1.2 absorbed as a `nativeMeasurement` failure on every such layout. Hanging spaces now close the previous line, so semantic wrapping and diagnostics keep working and no failure is recorded.
- Add a final layout guard to `RenderTextAutoWrap`: any failure while laying out one text falls back to the plain source paragraph (recorded as a `layoutGuard` failure), and a paragraph the engine cannot lay out at all becomes inert at the smallest size so the parent layout always completes.
- Guard intrinsic, dry-layout, dry-baseline and baseline queries, `paint`, `hitTestChildren`, semantics description and assembly, and source replacement. A failing query answers from the native paragraph (or a safe value) and is reported as a `<query>Guard` failure instead of throwing into the parent.
- Add regression coverage for sub-glyph widths with Hangul phrases, fault injection at every guarded point, equivalence with the default `Text` across text scales, `maxLines`, ellipsis, widths, and recognizers, and opt-in sweep reviews that can use a real font through `--dart-define=TAW_FONT_PATH`.

## 0.1.2 - 2026-10-19

- Preserve active selections when an equivalent rich source moves with a GlobalKey.
- Compare ordinary span trees once per node instead of repeatedly comparing subtrees.
- Keep source-query caches retryable after painter-constructor failures.
- Preserve exhaustive switches over existing public limits and invalid-input exceptions while exposing resource-limit failures separately.
- Add native pixel, font-loading, locale shaping, source-cache, and selection lifecycle checks; run the full suite on Chrome Wasm in CI.

- Protect ZWJ-following boundaries, grouped numbers, and common bracket pairs.
- Share CR/LF/VT/FF/NEL/LS/PS delimiter handling across core, span, and geometry paths; retain native rendering when engine behavior differs.
- Reuse source intrinsic/dry shaping and up to eight query results, invalidating on font, layout input, child geometry, or explicit layout changes.
- Skip semantic preprocessing beyond 65,536 UTF-16 units, 16,384 span occurrences, or depth 1,024; preserve the native source and publish nullable diagnostics.
- Cover negative-spacing pixels, frame-coalesced controller ownership, source-query failures, and repeated parent layouts; add Flutter 3.47.3 Chrome CI coverage.
- Add a Web Profile source-query benchmark and multi-widget renderer fixtures.


- Reuse verified paragraphs across repeated equal-width layouts instead of reshaping them during each equal-height parent pass; invalidate opaque custom spans when explicitly dirtied.
- Refresh native paragraph shaping as well as measured geometry when an explicitly dirtied custom span changes without replacing its identity.
- Extend renderer benchmarks with repeated intrinsic timeline rows, intrinsic table columns, survey grids, rich search results, scaled inline widgets, and three-pass parent layouts.

- Make near-equal cost and balance selection independent of candidate order by anchoring epsilon ties to shared minima.
- Suppress equivalent NaN-valued argument failure notifications consistently on VM and Web, while retaining changed-error and recovery notifications.

- Keep intrinsic height, dry size, and dry baseline queries independent of previously inserted semantic breaks.
- Restore pending controller notifications when a clean renderer reattaches without another layout.

- Normalize finite negative Flutter text widths to zero across native, calculated, and fallback layouts, preventing crashes with negative letter spacing and invisible Unicode characters.
- Preserve source characters and hard line breaks, with regression coverage for soft hyphens, joiners, bidirectional controls, variation selectors, and other formatting characters in plain and rich text.
- Validate native line bounds, grapheme endpoints, coverage, and progress; correct legacy CanvasKit affinity at soft wraps without repeating an entire failed measurement.
- Protect Unicode 16.0 GL/WJ glue from semantic breaks and whitespace trimming, including supplementary code points and combining sequences.
- Validate custom measurement and styled span ranges before slicing or calling user code, and reuse grapheme endpoints within plans and encoded spans.
- Keep source rendering independent from diagnostic measurement failures, clear stale cached results, and expose frame-deferred `TextAutoWrapController.failures` records.
- Preserve pending controller notifications when equivalent results transfer between owners or detach and reattach before frame delivery.
- Reject overflowing BudouX aggregate and feature scores instead of silently producing incorrect predictions from finite weights.
- Retain valid empty terminal source ranges for native ellipsis truncation and report applied source ranges from actual painted line boundaries.
- Reject non-finite published layout costs while retaining valid finite optima when overflowing alternatives are dominated.
- Keep nearby-layout neighborhoods complete for very large radii without overflowing integer index arithmetic.
- Measure intrinsic widths from the original source so parent relayout does not shrink based on previously inserted breaks.
- Preserve valid labeled ancestors in child-only rich-span measurement slices.
- Notify failure observers when RangeError bounds or IndexError lengths change, while suppressing equivalent repeated errors.

## 0.1.1 - 2026-10-14

- Apply semantic breaks at whitespace boundaries without rejecting preserved source spaces.
- Report painted source ranges and widths while keeping trimmed calculation layouts in diagnostics.
- Preserve native geometry when a calculated selection reuses the native break offsets.
- Keep native fallback for added soft wraps, invalid measurements, and overflowing painted lines.

## 0.1.0 - 2026-09-12

- Initial release of model-driven semantic wrapping for plain and rich Flutter text.
- Added experimental Korean and English title presets with automatic or explicit selection.
- Added custom predictor, aggregation, layout, and selection APIs.
- Added `WidgetSpan`, Unicode-safe offset, accessibility, controller diagnostics, and bounded caching support.
