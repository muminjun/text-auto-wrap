# Phrase benchmark and device measurement

The opt-in harness runs all 30 app phrases, widths 120/200/320, and text scales
1.0/1.3/1.5/2.0 in **one Flutter test process** (360 conditions). Its calculator
mirrors the application's optimal-at-most-24-candidates / greedy-above-24 policy
and 256 callback-request ceiling. It does not change the application.

```sh
~/fvm/versions/3.47.3/bin/flutter test benchmark/app_phrase_benchmark_test.dart \
  --dart-define=TAW_BENCH=true \
  --dart-define=TAW_REPS=5 --dart-define=TAW_ROUNDS=3 \
  --dart-define=TAW_FONT=/absolute/path/to/PretendardVariable.ttf \
  --reporter expanded
```

Each round repeats each condition five times. A cold sample starts with empty
shared renderer caches and a new renderer; cache clearing is outside the timed
interval. Recreate makes another renderer at identical inputs. New width changes
the recreated renderer from A to A+40; resize-back returns it to A. Timings include
`pumpWidget` and frame work in Flutter's debug test VM (assertions run after the stopwatch stops), rather than
isolated shaping or device release frame times. Warm-up uses every phrase with a
distinct suffix before the rounds. Font/model/JIT initialization is therefore
excluded from the definition of a cold phrase.

`TAWROW` JSON reports each condition's mean, median, standard deviation, minimum,
and p90 in microseconds; source ranges, breaks, lines, and widths; physical range
measurements; calculator callback requests; and limit counts. Timings and counters
are separate: a cached physical measurement still spends one callback request in
the application's calculator.

## Comparing output

Set `--dart-define=TAW_ORACLE=true` on the reference tree to record its calculator
without the 256-request ceiling **outside timed samples**. Save stdout to a log,
then pass `--dart-define=TAW_REFERENCE=/absolute/path/reference.log` to the improved
tree. Every completed calculation must equal the reference's unbounded layout;
a remaining limited calculation must equal its bounded native fallback. Assertions
also compare cold, recreated, and A→B→A layouts within each condition.

For 0.1.2, copy the harness and the two `test/support/app_phrase_*.dart` helpers (keeping
their relative paths) into an isolated temporary package and add
only a no-op `static void clearSharedCaches() {}` to `RenderTextAutoWrap`; that
release has no shared caches. This is harness instrumentation, not a layout
change. Use the same Flutter SDK, font, arguments, and machine for all versions.
Do not run CPU-heavy verification concurrently with timed benchmark processes.

## Local comparison, 2026-10-19

Apple M4 Pro (arm64), macOS 27.0.1, Flutter 3.47.3 / Dart 3.13.3, real Pretendard
Variable, 14px, height 1.5, letter spacing −0.2. Each variant ran three rounds,
five repetitions per condition: 5,400 observations per scenario per variant.
Cells below are the mean of each round's mean of the 360 condition medians,
± sample standard deviation of those three round means (milliseconds).

| Scenario | 0.1.2 | Stability + original performance patch | Final 0.1.3 | Final / 0.1.2 |
| --- | ---: | ---: | ---: | ---: |
| First unseen phrase, empty layout caches | 0.996 ± 0.010 | 0.999 ± 0.111 | 0.804 ± 0.089 | 0.81 |
| New renderer, same inputs | 0.977 ± 0.029 | 0.149 ± 0.079 | 0.121 ± 0.064 | 0.12 |
| Same phrase, new width | 0.802 ± 0.013 | 0.217 ± 0.072 | 0.218 ± 0.064 | 0.27 |
| Width A→B→A | 0.793 ± 0.010 | 0.102 ± 0.055 | 0.091 ± 0.048 | 0.11 |

The earlier 18% first-layout slowdown did not reproduce with explicitly empty
caches: the original performance patch was within the observed variation of
0.1.2. After review, custom calculators also retain their full validation path even on
fitting single-line text. The final build avoids extra inference work at positions the space model
cannot consume, and avoids recursively hashing every subtree again at each
ancestor. Recreate and resize-back gains remain. New-width time remains within the observed variation of the original performance
patch and substantially below 0.1.2. Exact pruning may need new ranges at the new
width instead of eagerly shaping all of them at the first width. These debug measurements do not establish
release-device latency or a statistical performance guarantee.

| Cold phrase metric | 0.1.2 / original performance patch | Final 0.1.3 |
| --- | ---: | ---: |
| Medium phrase physical measurements | 28.09 / 28.02 | 21.02 |
| Long phrase physical measurements | 185.20 | 173.42 |
| Long phrase callback requests | 185.60 | 173.73 |
| Long phrase limit rate | 40.0% (24/60 conditions) | 31.7% (19/60 conditions) |

The limit rate dropped 8.3 percentage points (20.8% relative). Default calculation
still accepts non-monotonic widths: only transitions whose line count is already
provably dominated are skipped. The optional monotonic-width mode is **not**
enabled by the renderer or benchmark.

Across all 360 conditions, 356 bounded layouts remain identical to 0.1.2. Four
formerly limited conditions now select semantic breaks instead of native fallback:
`long:0:1.0:320.0`, `long:3:1.0:320.0`, `long:3:1.3:320.0`, and
`long:3:1.5:320.0`. All four equal the unbounded 0.1.2 reference exactly, including
source ranges and shaped widths. No condition that previously completed changed.
All 1,080 condition-round reference assertions and 5,400 per-scenario repeat
checks passed. A fifth former limit completes but still selects the native layout.

## Application and device follow-up

The application can benefit without changing its calculator after adopting 0.1.3.
Its remaining ceiling counts callback requests, including repeated or cached
ranges. A separately reviewed application change could memoize `(start, end)`
within one calculation before counting misses, including final selected-layout
measurement. Keep the 256 ceiling and use an exact-layout reference test. Do not
opt into monotonic widths globally for arbitrary scripts, negative letter spacing,
rich text, or custom measurements.

Before claiming device frame-time improvements, profile the actual application
on a phone and tablet with its real font, text scales, and widths. Repeat cold
launches, report median/p90 and frame misses, and compare to the same app using
plain `Text` and 0.1.2. Browser/Wasm shaping and iOS engine behavior also require
platform verification; the local VM benchmark does not cover them.
