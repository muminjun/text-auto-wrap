# English title preset model card

## Status and scope

**Experimental.** `TextAutoWrapModels.english` is a domain-specific starting point for short English display titles and headings, usually rendered in one to three lines. It is not a general English language model and does not guarantee production accuracy.

The preset expects normal break opportunities at ASCII spaces. It is not designed for body copy, hyphenation, arbitrary HTML, vertical writing, or inserting breaks inside English words. The default `BalanceStrategy(tolerance: .12)` or a product-specific selector can choose among its candidates.

This card describes the preset shipped in `text_auto_wrap` 0.1.0. Pin the package version when reproducible output matters; model weights, penalties, schema, or rendering inputs can change results between versions.

## Model and training evidence

The preset contains three cumulative BudouX-format levels. Broader levels include boundaries from stricter levels. An unpredicted source-space boundary remains available with penalty `1`.

| Level | Penalty | Upstream training boundaries | Upstream positive scale |
| --- | ---: | ---: | ---: |
| coarse | 0 | 100 | 4 |
| medium | 0.35 | 160 | 4 |
| fine | 0.7 | 257 | 2 |

The pinned upstream card reports 100 English title examples written for the experiment, containing 897 candidate spaces. One AI-assisted labeling pass assigned meaning-oriented protected/fine/medium/coarse pseudo-labels; these labels are not human ground truth. Positive scales were selected using an 80-title fit and 20-title calibration split, after which deployed weights were refit on all 100 titles.

Upstream reports descriptive cumulative F1 values of `0.412`, `0.486`, and `0.583` on those same 20 calibration titles. Because the calibration split also influenced scale selection, these are pipeline diagnostics, not unbiased accuracy estimates or claims about this Flutter port.

Pinned upstream model SHA-256 values:

- coarse: `e57521ae39f0a7216137963062fd6d0ca90f7d2af243e4c946ca3056675ea4e9`
- medium: `3661905c25d998b26ca6fcd60ffaa88e90a813dcd1fe84234fae5fabb3799027`
- fine: `a8bf497a49a6f1452d49c07ce54fd08387fea3a709363b0851255a9836ab61f2`

## Port behavior

The upstream integer feature weights and entry order are preserved in immutable Dart tables. `text_auto_wrap` translates the inference code, adapts the predictor API, and maps an upstream whitespace-run start to this package's legal UTF-16 whitespace-run-end boundary. The preset does not create a word-internal boundary.

Final layout is not a model prediction alone. Flutter measures current fonts, styles, direction, scaling, constraints, and placeholders; the package then compares calculated layouts with native wrapping. Automatic language detection, safety ceilings, or guarded renderer fallback can leave native wrapping unchanged.

## Known limitations

- The corpus is small and represents one title-writing style.
- A single AI-assisted labeling pass may encode subjective grouping preferences.
- BudouX relies on local character features; it does not parse English syntax or meaning.
- Font, width, rendering engine, punctuation, and normalization can change the final layout.
- The preset offers neither hyphenation nor word-internal breaks.
- The reported calibration values are not a final held-out benchmark.
- This Dart/Flutter port has not added a new accuracy evaluation, so it makes no broader accuracy claim.

Before production use, evaluate the frozen package version on unseen titles rendered with the application's real fonts and widths. Consider a separately trained and validated model when higher accuracy or a different domain is required.

## Data, privacy, and attribution

The runtime package contains only the three weight tables and preset metadata. It does not include the source titles, review results, or allowlists described by the upstream card.

Source: [`semantic-wrap` English model card](https://github.com/woohyun-park/semantic-wrap/blob/54ed67688aa5292f14970cae10bbabd9a11f1b5d/packages/en/MODEL_CARD.md), Copyright 2026 Woohyun Park, Apache-2.0. The inference implementation is BudouX-compatible; the applicable Google LLC and upstream notices are retained in [NOTICE](../NOTICE) and [LICENSE](../LICENSE).
