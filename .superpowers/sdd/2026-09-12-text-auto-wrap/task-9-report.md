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
