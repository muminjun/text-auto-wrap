# Task 9 report: plain and styled `TextAutoWrap` renderer

## Result

Implemented and exported `TextAutoWrap`, `TextAutoWrap.rich`, and
`TextAutoWrapController`, backed by `RenderTextAutoWrap extends
RenderParagraph`.

The widget mirrors the requested Text-style inputs: `style`, `strutStyle`,
`textAlign`, `textDirection`, `locale`, `softWrap`, `overflow`, `textScaler`,
`maxLines`, `semanticsLabel`, `textWidthBasis`, `textHeightBehavior`, and
`selectionColor`. Omitted `model` resolves to `TextAutoWrapModels.auto`.

## RED / GREEN

RED was observed with the requested focused command before implementation:

```text
Error when reading lib/src/flutter/render_text_auto_wrap.dart
Method not found: TextAutoWrap
Type RenderTextAutoWrap not found
```

Focused tests now cover constructor/render-object parameter parity; one-pump
plain and styled rich span transformation (`abc\\ndef` is already the
effective span after the first pump); immediate controller result publication;
post-frame notification; and suppression of equivalent repeated results.

The controller equivalence test was independently RED first (two notifications
for equivalent ranges), then GREEN after comparing `TextLineRange.start/end`
by value.

## Flutter 3.47.4 source evidence and adjustment

* `widgets/basic.dart`: `RichText` is a `MultiChildRenderObjectWidget`
  (line 6496), extracts children via `WidgetSpan.extractFromInlineSpan`
  (line 6533), and passes resolved paragraph inputs into `RenderParagraph`
  (lines 6634-6654).
* `widgets/widget_span.dart`: the public child extraction helper is defined at
  lines 96-142.
* `rendering/paragraph.dart`: `layoutInlineChildren` is the protected public
  helper (lines 194-205), and `RenderParagraph.performLayout` lays children
  before final text layout (lines 956-966).
* `painting/text_painter.dart`: native line boundaries come from
  `TextPainter.getLineBoundary` (lines 1747-1753).
* `rendering/object.dart`: synchronous mutation during layout is permitted by
  `invokeLayoutCallback` (lines 3025-3047).

Directly assigning `super.text` in `performLayout` hit Flutter's debug
"mutated in its own performLayout" assertion because `RenderParagraph.text=`
marks layout dirty. The smallest source-backed adjustment is to use
`invokeLayoutCallback` around that inherited setter. It retains the framework
setter's private TextPainter/selection/semantics cache handling, and the
following `super.performLayout` lays out the final span in the same frame.

## Verification

All run with repository Flutter 3.47.4:

```text
.tooling/flutter/bin/flutter test test/flutter/text_auto_wrap_test.dart test/flutter/span_codec_test.dart  # pass
.tooling/flutter/bin/flutter test test/core test/models                                      # pass
.tooling/flutter/bin/flutter analyze                                                         # No issues found
.tooling/flutter/bin/flutter test                                                             # 182 passed
git diff --check                                                                              # clean
```

## Files

* Added `lib/src/flutter/controller.dart`
* Added `lib/src/flutter/render_text_auto_wrap.dart`
* Added `lib/src/flutter/text_auto_wrap.dart`
* Added `test/flutter/text_auto_wrap_test.dart`
* Updated `lib/text_auto_wrap.dart`

## Self-review and concerns

The renderer preserves the original source span on unsupported/ambiguous
language, disabled soft wrapping, unusable width, invalid measurement/custom
strategy/predictor failures, and `UnsupportedSpanTransformationException`.
It extracts WidgetSpan children through Flutter's public helper and passes
placeholder dimensions into source and candidate painters; Task 10 remains the
dedicated coverage point for detailed placeholder, selection, overflow, bidi,
and accessibility behavior.

Candidate range measurements use fresh `TextPainter` instances with the full
styled source and select the requested range's boxes, preserving source styles
and placeholder dimensions. Complex bidi/placeholder edge cases should be
extended by Task 10's required tests.

## Round 1 review fixes

### RED / GREEN

The requested focused RED run was captured with:

```text
.tooling/flutter/bin/flutter test test/flutter/text_auto_wrap_test.dart
```

It produced five failures: equivalent diagnostic payload was not retained;
range measurement returned `[30, 0, 0]` rather than `[30, 10, 20]` behind
`maxLines: 1`; and strategy fallback fabricated one full-source zero-width
line for consecutive LF, CRLF, and leading/trailing-newline inputs.

GREEN coverage now verifies that controller values are replaced without an
extra notification when geometry is equivalent; styled logical ranges are
painted in isolation (including a concrete bidi-discontiguous selection);
hidden hard-newline ranges ignore final truncation; and `a\n\nb`,
`a\r\n\r\nb`, and `\na\n` retain native ranges and native line-metric widths.
It also covers predictor, strategy, and unsupported-span fallbacks, and codec
coverage asserts styled slicing and matching `WidgetSpan` placeholder indices.

### Implementation and Flutter 3.47.4 evidence

`_measureRange` now builds a private/internal `InlineSpan` slice from the
codec's occurrence tree, maps only retained `WidgetSpan` indices to the public
`layoutInlineChildren` dimensions, and lays that slice with a separate
untruncated painter. This avoids retaining source-neighbour shaping or taking
a bidi selection-box envelope. Custom/opaque partial spans throw the existing
typed transformation error and preserve native rendering.

`TextPainter.getLineBoundary` is documented at
`packages/flutter/lib/src/painting/text_painter.dart:1750-1753`; its line
metrics are ordered and expose widths at `1783-1806`. Native adapter widths now
come directly from those metrics. In this pinned SDK, the observed CRLF
boundary includes the CR code unit while the LF remains after it, and an empty
terminal metric maps `getLineBoundary(source.length)` to the preceding line.
The adapter therefore normalizes only `LineMetrics.hardBreak` delimiters,
treats CRLF as one delimiter, and represents the terminal metric explicitly.

`commitResult` assigns the new immutable value before deciding whether its
rendering geometry materially changed; reason/source/diagnostic payloads do
not cause a notification by themselves. Renderer failures preserve the native
layout measured before model selection and use stable reasons
`rendererFallback`, `invalidMeasurement`, or
`unsupportedSpanTransformation`.

### Verification

```text
.tooling/flutter/bin/flutter test test/flutter/text_auto_wrap_test.dart test/flutter/span_codec_test.dart test/core test/models  # pass
.tooling/flutter/bin/flutter test                                                        # 191 passed
.tooling/flutter/bin/flutter analyze                                                     # No issues found
git diff --check                                                                         # clean
```

### Files and self-review

Modified `lib/src/flutter/controller.dart`,
`lib/src/flutter/render_text_auto_wrap.dart`, `lib/src/flutter/span_codec.dart`,
`test/flutter/text_auto_wrap_test.dart`, and
`test/flutter/span_codec_test.dart`; no unrelated `.DS_Store` files were
changed. The fixed widget-test font gives stable 10-pixel bidi assertions.
It does not provide a discretionary-ligature glyph fixture (the standard test
font is intentionally minimal); range-contained styled slices nevertheless
remove the cross-boundary-shaping dependency and the bidi regression proves
the former selection-envelope error. Detailed placeholder paint/selection
behavior remains Task 10 scope.
