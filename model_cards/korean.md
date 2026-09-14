# Korean title preset model card

## Status and scope

**Experimental.** `TextAutoWrapModels.korean` is a domain-specific starting point for short Korean display titles and headings, usually rendered in one to three lines. It is not a general Korean language model and does not guarantee production accuracy.

The preset expects normal break opportunities at ASCII spaces. It is not designed for body copy, arbitrary HTML, vertical writing, or inserting character breaks inside overlong identifiers. The default `BalanceStrategy(tolerance: .12)` or a product-specific selector can choose among its candidates.

This card describes the preset shipped in `text_auto_wrap` 0.1.0. Pin the package version when reproducible output matters; model weights, penalties, schema, or rendering inputs can change results between versions.

## Model and training evidence

The preset contains three cumulative BudouX-format levels. Broader levels include boundaries from stricter levels. An unpredicted source-space boundary remains available with penalty `1`.

| Level | Penalty | Upstream training boundaries | Upstream positive scale |
| --- | ---: | ---: | ---: |
| coarse | 0 | 100 | 4 |
| medium | 0.35 | 165 | 2 |
| fine | 0.7 | 313 | 1 |

The pinned upstream card reports 100 independently authored Korean article-title examples containing 664 candidate spaces. One blind reviewer assigned meaning-oriented protected/fine/medium/coarse pseudo-labels; these labels are not human ground truth. Positive scales were selected using an 80-title fit and 20-title density-calibration split, after which deployed weights were refit on all 100 titles.

Upstream reports descriptive cumulative F1 values of `0.650`, `0.543`, and `0.837` on those same 20 calibration titles. Because the calibration split also influenced scale selection, these are pipeline diagnostics, not unbiased accuracy estimates or claims about this Flutter port. The cumulative semantic-only preset was chosen upstream through local blind layout comparisons.

Pinned upstream model SHA-256 values:

- coarse: `7c8e0102945002aa4cea946d8afb71295d10810315cc61ea63679ac224fc93a2`
- medium: `5aca4c2cb38b5659af68080c98f5e88771e2371cf5bdd1a91dd07ea0ccfe4edd`
- fine: `170bc8868c263f90b87bf8cc780cc23803eaf3f5368071918a19bee2aac1bb54`

## Port behavior

The upstream integer feature weights and entry order are preserved in immutable Dart tables. `text_auto_wrap` translates the inference code, adapts the predictor API, and maps an upstream whitespace-run start to this package's legal UTF-16 whitespace-run-end boundary. The preset does not create a Korean word-internal boundary.

Final layout is not a model prediction alone. Flutter measures current fonts, styles, direction, scaling, constraints, and placeholders; the package then compares calculated layouts with native wrapping. Automatic language detection, safety ceilings, or guarded renderer fallback can leave native wrapping unchanged.

## Known limitations

- The corpus is small and represents one title-writing style.
- Labels from one reviewer may encode subjective grouping preferences.
- BudouX relies on local character features. Meaning-oriented training labels do not give it complete syntactic or semantic understanding.
- Font, width, rendering engine, punctuation, English identifiers, and normalization can change the final layout.
- The reported calibration values are not a final held-out benchmark.
- This Dart/Flutter port has not added a new accuracy evaluation, so it makes no broader accuracy claim.

Before production use, evaluate the frozen package version on unseen titles rendered with the application's real fonts and widths. Consider a separately trained and validated model when higher accuracy or a different domain is required.

## Data, privacy, and attribution

The runtime package contains only the three weight tables and preset metadata. It does not include the source titles, IDs, API keys, review results, or allowlists described by the upstream card.

Source: [`semantic-wrap` Korean model card](https://github.com/woohyun-park/semantic-wrap/blob/54ed67688aa5292f14970cae10bbabd9a11f1b5d/packages/ko/MODEL_CARD.md), Copyright 2026 Woohyun Park, Apache-2.0. The inference implementation is BudouX-compatible; the applicable Google LLC and upstream notices are retained in [NOTICE](../NOTICE) and [LICENSE](../LICENSE).
