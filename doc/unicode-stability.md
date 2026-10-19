# Unicode 안정성과 Flutter 호환성

이 문서는 문자열 처리 계약, 실패 시 동작, 실제 실행한 SDK 검증과 성능 관측을 설명합니다. 패키지 버전과 최소 Flutter 조건은 변경하지 않았습니다.

## 실제로 재현한 문제

- `1111\n\u00ad\n3333`, 글꼴 크기 10, `letterSpacing: -0.2`: Flutter 3.38.1과 3.47.3에서 줄 폭이 `[39.20000076293945, -0.20000076293945312, 39.20000457763672]`였습니다. 문자열의 길이나 UTF-16 범위가 음수가 된 것이 아니라 native glyph advance가 음수였습니다. 기존 구현은 native layout과 fallback 양쪽에서 이 값을 거부했습니다.
- `trim().isEmpty`만으로 공백을 판단하면 NBSP·NNBSP·BOM을 잘라도 되는 공백으로 취급했습니다. Word Joiner 주변 및 NBSP에 결합 문자가 붙은 경우에도 문자 모드 후보가 생성됐습니다.
- 사용자 calculator가 잘못된 측정 범위를 전달해도 callback 호출 전에 차단되지 않았으며, styled span 측정 slice는 grapheme 내부를 허용했습니다.
- 잘못된 native 경계·음수 인덱스·진행하지 않는 경계·누락된 metrics를 주입하면 기존 adapter에서 진단 측정과 fallback이 함께 실패하거나 잘못된 geometry를 만들 수 있었습니다. 실제 엔진 문제 재현과 이 방어 계약의 fault injection은 구분합니다.
- 구버전 CanvasKit은 soft wrap 시작 위치를 이전 줄의 끝으로도 판정합니다. 이는 실제 Chrome 테스트에서도 정상적인 semantic wrapping을 방해했습니다.

## 처리 계약

원문을 삭제·치환·NFC/NFKC 정규화하지 않습니다. UTF-16 code unit 오프셋과 Unicode scalar, grapheme cluster를 구분합니다. 후보는 내부 grapheme 경계이고, 측정 범위는 `0 <= start <= end <= source.length`를 만족해야 합니다. 정상적인 빈 줄과 폭 0은 허용합니다.

Unicode 16.0의 `Line_Break=GL/WJ` 26개 범위를 보호합니다. NBSP·figure space·nonbreaking hyphen·Word Joiner·BOM뿐 아니라 Tibetan·Mongolian·보충 평면 glue도 포함합니다. 결합 문자가 붙어도 해당 cluster의 보호를 유지합니다. 이는 [공식 Unicode 속성](https://www.unicode.org/Public/16.0.0/ucd/LineBreak.txt)을 사용하는 제한적인 soft-break 정책이며, [UAX #14](https://www.unicode.org/reports/tr14/) 전체 구현을 의미하지 않습니다.

Native의 유한한 음수 advance는 adapter에서 차지하는 너비 0으로 표현합니다. 이 처리는 재현된 glyph advance에 대한 adapter 계약입니다. 유효하지 않은 인덱스·역전 범위·grapheme 내부 경계·NaN/Infinity, 사용자 `measureRange`의 음수 값은 계속 거부합니다. 경계가 확인되기 전에 `substring`이나 사용자 측정 callback에 넘기지 않습니다.

Native 범위는 raw bounds와 진행 여부를 먼저 검사하고, CRLF delimiter를 제외한 뒤 layout factory에서 grapheme 유효성을 한 번 확인합니다. CanvasKit의 알려진 inclusive soft-wrap 끝점에는 현재 줄 안쪽의 위치와 upstream affinity로 한 번만 보정 조회합니다. 실패한 전체 native 측정은 같은 layout에서 반복하지 않습니다.

## 복구와 관측

의미 단위 계산이 실패해도 이미 유효한 native layout이 있으면 재사용합니다. Native 진단 geometry까지 유효하지 않으면 원본 span을 최종 `RenderParagraph`에 전달하며, 계산 결과와 선택 캐시를 비웁니다. 이때 `controller.result == null`은 geometry 부재이며 빈 문자열·너비 0을 뜻하지 않습니다.

`controller.failures`는 최근 layout의 `TextWrapFailure` 목록입니다. 각 항목의 `stage`, `reason`, `error`, `stackTrace`로 semantic 계산 실패와 native 진단 실패를 구분합니다. 알림은 프레임 끝에 전달하며, 같은 오류의 반복은 알림 루프를 만들지 않습니다. 이후 layout 성공 시 실패 기록이 사라집니다. 기본 렌더링 자체가 원문을 layout하지 못해도 해당 텍스트만 비활성 상태(`nativeLayoutGuard` 실패 기록)로 두고 부모 layout은 끝까지 진행합니다.

```dart
controller.addListener(() {
  final result = controller.result;
  for (final failure in controller.failures) {
    // 앱의 관측 시스템에서 필요에 따라 수집합니다.
    debugPrint('${failure.stage}: ${failure.reason}');
  }
  // result가 null이어도 원문은 native paragraph에 전달됐을 수 있습니다.
});
```

## SDK와 엔진 제한

[Flutter PR #185152](https://github.com/flutter/flutter/pull/185152)의 Hyphens 지원과 [PR #192664](https://github.com/flutter/flutter/pull/192664)의 Web affinity 수정은 3.47.3·3.47.4에 포함되지 않습니다. 두 수정이 모두 포함된 첫 태그는 `3.50.0-0.1.pre`입니다. Merge commit에 대한 [Hyphens ancestry](https://github.com/flutter/flutter/compare/3c5450855c160b5e752a9bf04d7da3dc3a305e34...3.50.0-0.1.pre), [affinity ancestry](https://github.com/flutter/flutter/compare/468422c9a87287005c9ba94cfb73ff5a59f50810...3.50.0-0.1.pre)와 이전 `3.49.0-0.2.pre`의 소스로 확인했습니다. 해당 prerelease에서의 실제 실행 검증은 하지 않았습니다.

다음은 native 엔진의 한계이며 문자열을 바꾸어 감추지 않습니다.

- 고립 surrogate 등 잘못된 UTF-16은 일부 native 엔진에서 `ArgumentError`로 거부됩니다. Web은 받아들이더라도 사용할 수 없는 source offset을 반환할 수 있습니다. Native 렌더링 자체가 실패하는 입력까지 복구를 보장하지 않습니다.
- 매우 좁은 폭에서는 엔진이 결합 cluster 내부를 emergency-wrap할 수 있습니다. 원문 native 렌더링은 유지하되 패키지는 유효하지 않은 grapheme geometry를 공개하지 않습니다.
- Bare CR은 확인한 엔진에서 LF와 같은 hard break로 표시되지 않습니다. CR을 hard break로 계산한 결과가 실제 paint와 다르면 원문 native 표시를 선택합니다.
- Flutter 3.38.1은 개행 뒤 variation selector를 이전 표시 줄에 묶기도 합니다. Chrome CanvasKit은 NUL 뒤 개행을 같은 표시 줄에 포함하기도 합니다. 테스트는 직접 측정한 native geometry와 원문 보존을 확인하며 가상의 빈 줄을 만들지 않습니다.
- Soft Hyphen의 최종 glyph 표시는 Flutter에 맡깁니다. 소스의 U+00AD를 보존하며, native soft wrap과 개행 삽입 뒤 geometry를 비교하는 회귀 테스트를 포함합니다.

앱 저장소나 typography는 수정하지 않았습니다. `AppText`에서 제어 문자를 일괄 제거하거나 모든 Unicode를 기본 렌더링으로 우회할 필요가 없습니다. 관측 시 원문에 민감 정보가 포함될 수 있으므로 실패 분류와 SDK·폰트·폭·배율·자간을 우선 기록하는 편이 좋습니다.

## 후속 점검: 수명주기·수치 계산·잘린 레이아웃

Unicode 이외의 경로를 추가 점검하면서 다음 네 가지를 재현하고 수정했습니다.

- **Controller 알림 유실**: 프레임 알림 전 동일 결과를 새 owner가 기록하거나 detach/reattach하면, 이전 callback 취소와 함께 아직 전달하지 않은 변경도 사라졌습니다. 전달 대기 변경과 callback 예약 상태를 분리했습니다. 같은 변경의 중복 알림 억제와 listener 재진입도 검증했습니다.
- **모델 수치 overflow**: 개별 BudouX 가중치가 모두 유한해도 합계나 feature score가 Infinity/NaN이 되어 예측이 조용히 달라질 수 있었습니다. 잘못된 계산을 그대로 사용하지 않고 `InvalidModelConfigurationException`으로 분류합니다. 정상 모델의 산술 순서는 바꾸지 않았습니다.
- **말줄임표의 정상 빈 범위**: 좁은 폭의 ellipsis layout은 표시할 원문이 없어 `(start, end) == (0, 0)`을 반환할 수 있습니다. 실제 truncation이 확인된 마지막 ellipsis 줄에서만 이를 허용합니다. 일반적인 비진행 경계는 계속 거부합니다.
- **계산 범위와 표시 범위 차이**: CR 직후 soft wrap이 겹치면 표시 줄에 CR이 포함되어도 syntactic delimiter 스캔은 이를 제외했습니다. 최종 painter의 실제 native 경계를 원문 오프셋으로 복원하고, 계산한 각 줄의 내용을 덮는지 확인한 뒤 기록합니다. 추가 painter를 생성하지 않습니다.

관련 회귀 테스트는 `controller_failure_test.dart`, `budoux_parser_test.dart`, `renderer_edge_test.dart`에 있습니다. CR의 native/Web 표시 차이는 독립적인 실제 `TextPainter`와 비교하며, 두 backend 모두 정상 fixture에서 `applied=true`를 요구합니다.

## 추가 점검: 최적화·intrinsic 폭·span 측정·오류 알림

다음 문제는 이전 704개 테스트를 통과하는 상태에서 새로 재현했습니다.

- `abc`의 두 후보 penalty가 각각 `1e308`이면 각 값이 유한해도 합산 비용이 Infinity였습니다. 공개 layout 비용은 유한성을 검증합니다. 탐색 중 overflow가 발생한 더 긴 경로나 최종 Pareto에서 지배되는 경로 때문에 유한한 최적 결과를 거부하지 않는 회귀 입력도 포함합니다.
- `nearbyLayouts`의 매우 큰 radius는 VM 정수의 `index + radius`를 overflow시켜 정상 baseline을 포함한 모든 결과를 없앴습니다. 실제 후보 개수를 넘는 이웃 거리는 동일한 후보 집합이므로 그 범위 안에서 인덱스를 계산합니다. 후보·state 상한은 올리지 않았습니다. Pareto 처리 순서를 변경하는 과정에서 탈락할 최종 경로의 기존 budget 집계가 빠지는 회귀도 별도 85자 비단조 폭 입력으로 확인했습니다. 모든 최종 경로를 이전과 같이 먼저 집계하고, 남은 경로를 이중 집계하지 않도록 바로잡았습니다.
- `abcdef`, font size 10, offset 3의 의미 단위 개행을 적용한 뒤 `IntrinsicWidth` 부모의 padding만 변경하면 폭이 60에서 30으로 줄었습니다. 이전에 삽입한 개행을 다음 intrinsic 폭 계산의 입력으로 재사용한 것이 원인이었습니다. 최소·최대 intrinsic 폭은 원문을 측정하며, 반복 WidgetSpan occurrence도 원래 순서대로 측정합니다. 실제 선택·paint span은 유지합니다.
- own text `ab`, `semanticsLabel`, child text `cdef`인 TextSpan에서 child-only 범위를 측정하면 `text: null`과 label이 함께 복사되어 Flutter assertion이 발생했습니다. 측정용 ancestor에 빈 own text를 유지해 스타일과 유효한 span 구조를 보존합니다. 원문·접근성 label·최종 span을 삭제하지 않습니다.
- Controller가 같은 invalid value를 가진 RangeError의 허용 범위 또는 IndexError의 길이가 달라져도 같은 오류로 취급해 알림을 생략했습니다. 범위 변경은 알리고 동일한 오류 재생성은 계속 억제합니다.

`test/core/optimizer_oracle_test.dart`는 seed `0x50415245`로 600개의 짧은 입력을 만듭니다. 각 입력의 모든 개행 후보 부분집합을 독립적으로 열거하고 임의의 비단조 range width·폭 0·hard break에 대해 최소 줄 수와 비용/균형 Pareto 집합을 비교합니다. 기대 범위와 비용은 production layout builder로 만들지 않습니다. 이는 해당 짧은 입력과 수치 범위의 검증이며 전체 입력 공간에 대한 최적성 증명은 아닙니다.

이번에 추가한 테스트는 18개입니다. `layout_test.dart`의 overflow·큰 radius·유한 최적 경로, `optimizer_oracle_test.dart`의 독립 전수 비교, `intrinsic_stability_test.dart`의 폭/부모 재배치/반복 WidgetSpan, `span_contract_test.dart`의 부분 측정/실제 applied 결과, `controller_error_contract_test.dart`의 오류 범위 변경/동일 오류 억제를 포함합니다. 각 수정의 최초 반례에서 실패를 확인한 뒤 관련 테스트를 통과시켰습니다.

Controller 소유권·detach/reattach·listener 재진입, cache generation과 부분 측정 실패 뒤 복구, maxLines·ellipsis·clip·fade·softWrap, baseline·반복 WidgetSpan·rich metadata·selection/hit testing 경로도 조사했습니다. 위에서 구체적으로 재현한 사항 이외의 추가 결함은 확인하지 못했습니다. 기존 offset 기반 선택 API는 effective span 기준이며 삽입 개행을 원문의 문자로 바꾸어 보고하지 않습니다.

## 추가 조사: speculative 측정과 실제 renderer 재부착

기존 수정에 이어 다음 두 결함을 새 실패 테스트로 재현했습니다.

- **높이·dry geometry의 이력 의존성**: `abcdef`, font size 10, offset 3의 개행을 적용한 뒤 폭 100으로 dry layout을 질의하면 원문의 `Size(60, 10)` 대신 `Size(30, 20)`을 반환했습니다. 같은 원인으로 min/max intrinsic 높이도 달라졌고, `abc` 10px + `def` 30px span의 dry baseline은 22.5에서 7.5로 변했습니다. `computeMinIntrinsicHeight`, `computeMaxIntrinsicHeight`, `computeDryLayout`, `computeDryBaseline`에서 원문용 painter와 자식의 dry size/baseline을 사용합니다. 최종 선택·paint span을 바꾸지 않고 painter를 해제합니다. speculative 측정은 최초 layout 전과 같은 원문 기반 추정이며, 선택된 의미 단위 개행의 실제 높이와 항상 일치한다는 보장은 아닙니다.
- **실제 clean renderer 재부착의 알림 유실**: `abcdef` → `abc\ndef`의 정상 결과를 기록하고 프레임 알림 전에 detach/attach하면, renderer가 clean하여 새 layout 없이 유지되는 경우 취소된 알림이 재예약되지 않았습니다. Controller 내부의 대기 변경 보존만으로는 renderer의 재연결을 처리할 수 없었습니다. `attach`에서 보관된 결과 또는 실패 상태를 기존 controller 경로에 재전달합니다. 동일 상태의 이미 전달된 알림은 계속 억제합니다.

수정 파일은 `lib/src/flutter/render_text_auto_wrap.dart`이며 회귀 테스트는 `test/flutter/layout_history_contract_test.dart`, `test/flutter/controller_reentrancy_test.dart`에 있습니다. 높이와 baseline의 기대값은 패키지의 layout builder 대신 독립 `RenderParagraph`/`RichText` 및 고정 수치를 사용합니다. 실제 `IntrinsicHeight` 부모 재배치, 반복 baseline WidgetSpan, scaler, overflow별 native 비교와 실제 `RenderView`/`PipelineOwner` 재부착 경로를 포함합니다. 정상 의미 단위 fixture는 `applied=true`를 요구합니다.

Optimizer에는 새 결함을 확인하지 못했습니다. `test/core/whitespace_optimizer_oracle_test.dart`는 seed `0x57535043`의 공백·탭·LF 입력 3,000개와 `a`, 결합 문자, ZWJ emoji, 공백, CRLF 토큰 길이 1~4의 모든 780개 문자열을 조사합니다. 독립적인 개행 후보 부분집합 열거로 fitting 해가 있는 입력의 최소 줄 수, 비용/균형 Pareto 집합, 동률 중복, 실제 source range/cut와 측정 endpoint를 비교합니다. fitting 해가 없는 입력의 overflow 선택을 이 새 oracle이 검증하지는 않습니다. 기존 overflow·budget 테스트와 600개 oracle도 유지합니다. 이는 제한된 corpus의 검증이며 전체 입력의 최적성 증명이 아닙니다.

Custom predictor/aggregator/calculator/selector 계약, 측정 캐시 generation, 연속 source/style/width 변경 경로도 기존 구현과 테스트를 확인했습니다. 위 두 결함 이외에 이 조사에서 구체적으로 재현한 추가 결함은 없습니다. 임의의 사용자 callback 동작, 모든 폰트·locale·RTL 조합, 매우 큰 span tree 전체를 보장하지 않습니다.

## 이번 후속 수정의 검증 결과

앞선 722개 snapshot에 위 회귀 11개와 확장 oracle 1개를 추가했습니다. 2026-10-18 최종 production 코드의 실제 실행 결과입니다.

| SDK / backend | 통과 | 기존 SDK 의존 skip | 실패 |
| --- | ---: | ---: | ---: |
| Flutter 3.47.4 / VM | 734 | 0 | 0 |
| Flutter 3.47.4 / Chrome CanvasKit | 734 | 0 | 0 |
| Flutter 3.47.3 / VM | 734 | 0 | 0 |
| Flutter 3.38.1 / VM | 728 | 6 | 0 |

Core 단독은 140개 통과했습니다. `flutter analyze`, 전체 formatting 검사, `git diff --check`, bootstrap 검증을 통과했고 예제 Web 빌드도 성공했습니다. 3.47.3·3.38.1은 새 격리 복사본에서 실행했으며 `lib`/`test`가 루트와 byte 단위로 같음을 확인했습니다. 기존 6개 SDK 의존 skip 외 신규 skip은 없습니다. 예제 Web 빌드의 기존 CupertinoIcons 경고는 남아 있고 Wasm은 dry run만 성공했습니다.

최초 조사용 전체 실행에서는 작성 중인 새 dry size/baseline 테스트 2개가 예상 수치 차이로 실패했고, 수정 후 위 전체 실행에서 통과했습니다. 실제 renderer 재부착 알림도 수정 전 0회/기대 1회 실패를 확인한 뒤 수정했습니다. Fault injection으로 원문과 source map이 불일치하는 span을 주입한 실패 상태 테스트는 복구 계약 검증이며 엔진 결함 재현으로 분류하지 않습니다.

이번 전체 검증의 일부 실행은 동시 작업과 큰 wall-clock 지연을 포함했습니다. 해당 전체 테스트의 시간을 성능 비교 표본으로 사용하지 않습니다. 성능 비교는 별도 순차 실행으로 분리했습니다.

## 검증 방법

2026-10-18 추가 다섯 가지 수정까지 반영한 production snapshot의 실제 전체 테스트 결과입니다. 이번 수정 전 상태의 기본 SDK VM 704개 통과도 먼저 재확인했습니다.

| SDK / backend | 통과 | 기존 SDK 의존 skip | 실패 |
| --- | ---: | ---: | ---: |
| Flutter 3.47.4 / VM | 722 | 0 | 0 |
| Flutter 3.47.4 / Chrome CanvasKit | 722 | 0 | 0 |
| Flutter 3.47.3 / VM | 722 | 0 | 0 |
| Flutter 3.38.1 / VM | 716 | 6 | 0 |

3.38.1의 6개 skip은 기존 ambient spacing override API 의존 테스트이며, 이번 변경으로 추가하거나 실패를 피하려고 skip한 테스트는 없습니다. 별도 SDK는 `/tmp`의 격리된 checkout에서 실행했습니다. 분석과 formatting 검사도 통과했습니다. GitHub Actions에 전체 Chrome 테스트 단계를 추가했으며, 원격 CI 자체는 실행하지 않았습니다.

예제의 `flutter build web`도 성공했습니다. 이 실행에는 CupertinoIcons font family를 찾지 못했다는 비치명적 경고가 있었으며, Wasm dry run은 성공했지만 실제 Wasm 실행·실기기 렌더링·수동 스크린리더 동작까지 검증한 것은 아닙니다.

- `flutter test`: core·모델·renderer·span·접근성·controller·캐시·벤치마크 검증.
- `flutter test --platform chrome`: 동일 계약의 Web 검증. 공용 벤치마크 harness는 `test/support`에 있어 Web test compiler에서도 로드됩니다.
- `flutter analyze`
- `dart format --output=none --set-exit-if-changed lib test benchmark example`
- `bash test/bootstrap_flutter_test.sh`

`test/flutter/unicode_fuzz_test.dart`는 seed `0x554e4943`를 고정합니다. 실패 시 case 번호와 UTF-16 code unit 배열로 재현할 수 있습니다. 96개의 교체·resize 조합과 40개의 nested span/WidgetSpan 조합을 실행합니다. Native geometry 부재를 허용하는 경우에는 별도의 실제 `TextPainter`가 같은 잘못된 경계를 반환하는지 확인합니다. 31개 Unicode fixture와 16개 WidgetSpan fixture는 `applied=true`와 실제 표시 geometry 일치를 요구합니다. Native가 거부하는 비정상 UTF-16은 정상 적용 fixture와 구분해 직접 검증합니다.

## 성능 관측

아래 시간 표본은 최초 Unicode 수정의 비교입니다. 기준은 HEAD `06fcb872`, 후보는 해당 Unicode 수정 snapshot이며 동일한 Flutter 3.47.4 debug widget test에서 행당 20회 실행했습니다. 총 12개 cold/warm 행의 후보 수·측정 횟수·캐시 hit·fallback reason이 모두 같았습니다. 전체 harness 관측 시간은 약 42초와 40초였습니다. 각각 한 번의 비교 표본이므로 성능 향상을 입증하는 수치는 아닙니다.

아래 재현 명령으로 최초 수정의 최종본도 다시 실행했습니다. 예제 Web 빌드와 동시에 실행한 이 표본은 45초였고, 12개 행의 시간 이외 모든 관측값이 기준과 같았습니다. 단일 debug 실행 시간을 성능 보장으로 해석하지 않습니다. 2026-10-18 후속 네 가지 수정 뒤에도 같은 20회 명령을 재실행해 통과했으며(약 40초), 12개 행의 후보 수·측정 횟수·캐시 hit·fallback reason이 기준과 모두 같았습니다.

| 시나리오 | Cold 이전 → 이후 (µs) | Warm 이전 → 이후 (µs) |
| --- | ---: | ---: |
| 짧은 텍스트 | 70,474 → 55,536 | 12,760 → 8,504 |
| 중간 텍스트 | 229,989 → 138,287 | 21,450 → 12,434 |
| 긴 텍스트 | 16,324,331 → 15,904,430 | 832,649 → 819,122 |
| 중첩 span | 17,345,851 → 16,522,557 | 879,756 → 864,675 |
| Placeholder | 454,084 → 449,969 | 41,609 → 38,705 |
| 최대 후보 시나리오 | 5,424,136 → 5,391,970 | 284,716 → 272,476 |

재현 명령:

```sh
flutter test test/flutter/layout_benchmark_test.dart \
  --dart-define=TEXT_AUTO_WRAP_BENCHMARK_ITERATIONS=20 \
  --dart-define=TEXT_AUTO_WRAP_BENCHMARK_REPORT=true \
  --reporter expanded
```

추가 다섯 가지 수정과 최종 경로 budget 집계 보정까지 반영한 뒤에도 행당 20회 벤치마크를 완료했습니다. 총 12개 행의 후보 수·측정 횟수·캐시 hit·fallback reason과 나머지 비시간 필드는 `06fcb872` 기준 자료와 모두 같았습니다. 기준 복사본의 production 파일 19개도 해당 commit과 byte 단위로 일치함을 확인했습니다.

이번 20회 실행의 행별 시간 합계는 396.239초였고, 이전 기준 표본의 합계는 41.922초였습니다. 동시에 진행한 Chrome 테스트·Web 빌드와 실행 환경이 달라 이 차이를 곧바로 패키지 회귀나 환경 영향으로 단정하지 않았습니다. 동일 Flutter 3.47.4·동일 harness·동일 dependency lockfile로 격리한 기준 코드와 최종 코드를 **2회씩 순차 재실행**했습니다. 두 실행 모두 통과했고, 12개 행의 비시간 필드가 전부 같았으며 시간 합계는 기준 31.686초, 최종 31.070초였습니다. 이 한 쌍에서는 총 시간 악화를 관측하지 않았지만 속도 향상이나 모든 환경의 성능 동등성을 입증하지 않습니다. 반복적인 profile 측정은 별도로 필요합니다.

추가 점검 중 첫 20회 벤치마크는 계산 상한 집계 회귀를 바로잡고 최종 코드로 다시 검증하기 위해 SIGINT로 중단했습니다. 중단 시 Flutter test runner가 `Cannot close sink while adding stream` / `Cannot add event while adding stream` 종료 오류를 출력했습니다. 이 미완료 실행은 성능 표본이나 패키지 결함 재현으로 사용하지 않습니다.

의미 단위 개행 적용 뒤의 intrinsic 폭 질의는 원문용 painter를 만들고 해제합니다. 기존 벤치마크는 IntrinsicWidth 부모의 반복 질의 비용을 별도로 측정하지 않으므로, 그 경로까지 비용이 동일하다고 보장하지 않습니다.

계산 상한(후보 4,096개·state 16,384개·현재 cache key의 range 65,536개)은 올리지 않았습니다. Plan과 encoded span의 grapheme endpoint는 재사용하며, native factory의 검증과 중복되는 grapheme segmentation은 추가하지 않습니다. 실제 단말의 폰트·입력·접근성 배율·렌더링 backend에 대한 profile 측정과 앱 통합 smoke test는 배포 전에 별도로 수행해야 합니다.


## 이번 후속 수정의 순차 성능 관측

전체 SDK·Chrome 테스트와 Web 빌드가 끝난 뒤, Flutter 3.47.4에서 기준 `06fcb872`와 최종 코드를 행당 20회씩 순차 실행했습니다. 기준 production Dart 파일은 해당 commit과 일치하며, 두 실행은 현재 lockfile과 동일한 벤치마크 harness를 사용했습니다. 두 실행 모두 통과했고 총 12개 행의 시간 외 모든 필드(후보 수·측정 횟수·캐시 hit·fallback 등)가 같았습니다.

행별 관측 시간 합계는 기준 **264.452초**, 최종 **241.672초**였습니다. 기준 실행에는 진행 상태를 확인하기 위한 1초 native stack sampling이 포함됩니다. 단일 debug 표본이고 실행 환경도 이전 기록과 다르므로 성능 향상이나 동등성의 증거로 해석하지 않습니다. 로그와 행 자료는 `/tmp/text-auto-wrap-followup-benchmark-{baseline,final}.{log,rows.json}`에 저장했습니다.

별도 격리 fixture에서 `abcdef`의 의미 단위 개행을 적용한 뒤 폭 100/80/120을 번갈아 300회 질의했습니다. 각 회에 min/max intrinsic height, dry layout, dry baseline의 `compute*`를 직접 호출해 RenderBox의 질의 캐시를 우회한 1,200회 계산입니다. 이번 두 production 추가 부분만 제거한 수정 전 복사본과 최종 복사본을 순차 실행했고 둘 다 fixture 검증을 통과했습니다. 관측 시간은 **22.705ms → 117.729ms**로 늘었습니다. 수정 전 높이 20이 수정 후 원문 기준 10으로 바뀌어 합계 checksum도 20,250 → 11,250으로 달라졌습니다. 별도 원문 painter 생성·해제의 비용을 숨기지 않으며, 이 한 쌍으로 비용 상한을 보장하지 않습니다. 실제 부모의 질의 캐시를 포함한 앱 성능과 복잡한 span/폰트 조합의 반복 질의 비용은 미검증입니다.

이 임시 관측 fixture는 저장소 테스트 수에 포함하지 않았습니다. 로그는 `/tmp/text-auto-wrap-followup-query-{before,after}.log`, fixture 복사본의 공통 경로는 `/tmp/text-auto-wrap-followup-path`에 남겼습니다.


## 추가 조사: 근사 동률 선택과 Web 오류 알림

기존 미커밋 변경을 유지한 상태에서 기본 Flutter 3.47.4 VM의 734개 테스트 통과를 먼저 재확인했습니다. 브랜치 `fix/soft-hyphen-handling`, HEAD `06fcb8720426d75937028d2059dd5232b8292454`, 버전 `0.1.1`을 유지했습니다. 상위 경로와 저장소의 적용 가능한 `AGENTS.md`도 다시 검색했으며 찾지 못했습니다. 이번에 새로 재현한 결함은 다음 두 가지입니다.

- **근사 동률 selector의 순서 의존성**: 원문 `abcd`, 두 줄 폭 `[1, 1]`, `(개행 offset, 비용)`이 `(3, 0)`, `(2, 0.75e-9)`, `(1, 1.5e-9)`인 후보를 여섯 순서로 전달하면 기존 `BalanceStrategy`는 개행 1·2·3을 모두 선택했습니다. 후보끼리 비용 차이가 `1e-9` 이내인지 비교하는 관계가 비추이적이어서 정렬 comparator가 순환했습니다. 비용이 같고 imbalance가 `0`, `0.75e-9`, `1.5e-9`인 경우에도 같은 원인을 재현했습니다. `lib/src/core/selection.dart`는 최소 비용 + epsilon, 그 집합의 최소 imbalance + epsilon을 공통 기준으로 필터링한 뒤 기존 native·개행 순서로 비교합니다. epsilon 크기, 최소 줄 수, tolerance와 native 개선 조건은 유지합니다. 근사 동률이 사슬처럼 이어지는 집합의 선택 정책은 이제 공통 최솟값 기준으로 명확해집니다. 이것은 optimizer의 Pareto 탐색이나 budget 변경이 아닙니다.
- **Chrome의 NaN 오류 반복 알림**: `abcdef`의 custom predictor가 매번 `ArgumentError.value(double.nan, 'score', 'must be finite')`를 던지고 폭만 `100 → 110 → 100`으로 바뀌는 실제 renderer 경로에서 같은 실패의 두 번째 알림이 발생했습니다. VM에서는 기존 identity 검사로 중복 알림이 억제됐지만 Web에서는 NaN identity와 `==`가 모두 false였습니다. `lib/src/flutter/controller.dart`에서 숫자 오류 값끼리 비교할 때 양쪽이 NaN인 경우도 동등하게 취급합니다. 실패를 숨기지 않고 원문 native 표시와 failure snapshot을 유지합니다. 오류 값이 유한한 `7`로 바뀔 때는 알리고 정상 모델 복구도 알립니다.

`test/core/selector_determinism_test.dart`의 비용·균형 순환 테스트 2개는 수정 전 selector를 넣은 격리 복사본에서 실패했고 수정 후 통과했습니다. 나머지 2개는 subnormal `1e-320`·큰 유한 비용 `1e308`과 기존 native 개선 epsilon 경계를 유지하는 회귀 검사입니다. 여섯 순열의 기대 offset은 고정값 2이며 production selector로 기대값을 만들지 않습니다. `test/flutter/controller_nan_failure_test.dart`는 수정 전 Chrome에서 폭 100의 알림 1회, 폭 110의 알림 2회(기대 1회)를 확인했습니다. 정상 복구는 `applied=true`, `['abc', 'def']`를 요구합니다. Custom predictor의 예외는 지원하는 실패 관측 경로의 입력이며 native 엔진 결함 재현이 아닙니다.

### 반례를 찾지 못한 추가 조사

- `test/core/overflow_strategy_oracle_test.dart`: seed `0x4f564552`, `a`·공백·탭·LF·CRLF의 2~8개 토큰으로 1,800개 입력을 구성했습니다. 900개는 모든 측정 폭이 가용 폭보다 커서 fitting 해가 없습니다. 독립 source scanner로 전체 입력의 greedy·radius 0 nearby, non-fitting 900개의 optimal fallback의 range·cut·width·overflow를 비교합니다. 폭 0·`1e-320`·`1e308`, whitespace overlap, hard break 미측정과 cache의 동일 range 중복 callback도 확인합니다. 이는 구현된 greedy fallback 계약 검증이며 overflow의 전역 최적성이나 양수 radius nearby 완전성 증명이 아닙니다.
- `test/core/extension_recovery_contract_test.dart`: predictor 부분 실패의 snapshot atomicity, aggregator 재시도와 prediction 재사용, 다른 key의 중첩 측정 실패·복구, selector의 중첩 성공 뒤 외부 실패·복구, candidate metadata 네 필드의 계약 위반 거부를 8개 테스트로 검증합니다. 동일 값의 새 candidate 객체는 허용하고 정상 복구는 `applied=true`를 요구합니다. 무한 자기호출 callback, 같은 key를 유지하면서 측정 의미를 바꾸는 호출자 계약 위반, range cache eviction 경계 전체는 이 새 corpus에 포함하지 않습니다.
- `test/flutter/span_followup_oracle_test.dart`: `a`, 결합문자, emoji, 공유 WidgetSpan, literal U+FFFC의 길이 4 모든 625개 조합과 각 10개 비어 있지 않은 토큰 범위, 총 6,250개 측정을 독립 flat native TextSpan과 비교합니다. labeled ancestor·locale·spellOut, span 사이에 나뉜 결합 cluster, placeholder occurrence·원문 보존·전체 token cut 삽입을 확인합니다. 깊은 tree, 임의 custom InlineSpan과 모든 폰트 조합은 보장하지 않습니다.
- 임시 native 비교에서 recognizer와 sibling semanticsLabel·locale의 동시 변경 시 접근성 label은 `TextAutoWrap.rich`와 독립 `Text.rich` 모두 갱신됐습니다. 실제 잘못된 geometry는 재현하지 못해 방어 코드를 추가하지 않았습니다. 조사 fixture의 surrogate pair를 서로 다른 TextSpan 문자열로 쪼갰을 때는 source native ParagraphBuilder도 잘못된 UTF-16로 거부했습니다. 이는 패키지 결함으로 분류하지 않습니다.

이번 production 변경은 selector와 숫자 오류 동등성에 한정됩니다. 새로운 source painter cache, 문자 삭제·정규화, 무조건 fallback, 광범위 catch, SDK 최소 조건·계산 상한 변경은 도입하지 않았습니다. 이전 speculative 측정의 원문 painter 생성·해제 비용 관측(22.705ms → 117.729ms)은 그대로 유효한 과거 표본으로 보존하며, 이번 selector 수정의 성능 표본과 섞지 않습니다.

Controller 관련 focused Chrome 실행은 20개 통과·종료 코드 0이었으며, 종료 중 Chromium SIGTERM 응답 지연으로 SIGKILL을 시도한다는 runner 경고가 있었습니다. 테스트 assertion 실패나 패키지 결함으로 분류하지 않습니다. NaN 조사 fixture의 최초 필수 `fallbackPenalty` 누락 컴파일 오류도 테스트 작성 오류로 구분하며 수정 전 패키지 반례 증거에 포함하지 않습니다.

### 이번 최종 snapshot 검증

2026-10-18 이번 회귀·확장 테스트 15개를 추가한 최종 `lib`/`test` snapshot의 실제 결과입니다. 모든 명령의 종료 코드는 0입니다.

| SDK / backend | 통과 | 기존 SDK 의존 skip | 실패 |
| --- | ---: | ---: | ---: |
| Flutter 3.47.4 / VM | 749 | 0 | 0 |
| Flutter 3.47.4 / Chrome CanvasKit | 749 | 0 | 0 |
| Flutter 3.47.3 / VM | 749 | 0 | 0 |
| Flutter 3.38.1 / VM | 743 | 6 | 0 |

Core 단독 153개, `flutter analyze`, formatting 검사(62개 파일, 변경 0), `git diff --check`, bootstrap 검증을 통과했습니다. 예제 Web 빌드와 Wasm dry run도 성공했고 기존 CupertinoIcons 폰트 경고는 남아 있습니다. 추가 SDK는 이번에 만든 별도 복사본에서 실행했으며 루트 package config의 Flutter 경로는 `.tooling/flutter/packages/flutter`로 유지했습니다. VM·SDK·Web 전체 검증에는 동시 실행과 큰 wall-clock 지연이 포함됐으므로 그 실행 시간을 성능 표본으로 사용하지 않습니다.

최종 로그는 `/tmp/taw-new-final-{vm,chrome,sdk3473,sdk3381,core,analyze,web}.log`, `/tmp/taw-new-bootstrap.log`에 있습니다. 추가 SDK 복사본과 이번 session 이전 production snapshot의 공통 경로는 `/tmp/taw-new-session-path`에 기록했습니다. 이름만으로 이후 수정 코드의 검증 결과로 재사용하지 않습니다. 실제 Wasm 실행·실기기·수동 스크린리더는 이번에도 검증하지 않았습니다. 기존 문서의 비정상 UTF-16·native emergency wrap·CR/backend geometry 한계는 그대로 남아 있습니다.

### 이번 순차 성능 관측과 추가 비용

모든 전체 테스트·Chrome·SDK 컴파일·Web 빌드가 완료된 뒤 Flutter 3.47.4, 현재 lockfile과 동일 benchmark harness로 최초 기준 `06fcb872`와 최종 코드를 각각 행당 20회 순차 실행했습니다. 두 명령 모두 종료 코드 0이었고, 12개 행의 후보 수·측정 수·cache hit·fallback reason을 포함한 모든 비시간 필드가 같았습니다. 기준 production 파일은 HEAD와 byte 단위로 일치함을 확인했습니다.

행별 시간 합계는 **227.685002초 → 224.122680초**였습니다. 기준 실행 중 formatting 검사 1회(관측 0.76초)가 겹쳤습니다. 이는 단일 debug 표본이며 성능 향상·동등성이나 과거 표본과 직접적인 회귀 원인 비교의 근거가 아닙니다. `/tmp/taw-new-benchmark-{baseline,final}.{log,rows.json}`에 원자료를 남겼습니다.

별도로 전체 harness까지 끝난 뒤 동일 Dart 3.13.3 JIT에서 selector만 순차 관측했습니다. 모든 후보의 비용과 imbalance가 같고 개행 offset만 다른 입력으로, 생성과 100회 warmup을 제외하고 아래 횟수만큼 선택했습니다. 이전 selector는 HEAD와 이번 세션 시작 시 코드가 같으며, 동일 임시 script를 기준/최종 package config로 각각 실행했습니다. 각 실행은 종료 코드 0이고 선택 offset 1의 checksum도 반복 횟수와 일치했습니다.

| 동률 후보 수 | 반복 선택 횟수 | 수정 전 총 시간(ms) | 수정 후 총 시간(ms) |
| --- | ---: | ---: | ---: |
| 8 | 10,000 | 101.402 | 131.109 |
| 128 | 2,000 | 630.674 | 792.154 |
| 1,024 | 300 | 1,164.283 | 1,493.147 |

새 공통 최소값 필터의 O(n) 순회와 임시 목록이 추가되며, 이 동률 fixture에서 비용 증가를 실제로 관측했습니다. 일반 renderer harness의 시간만으로 이 증가를 감추거나 성능이 동등하다고 설명하지 않습니다. 이 한 쌍은 Flutter 최종 layout의 비용 상한·실제 앱 성능·모든 후보 분포의 결과를 보장하지 않습니다. 임시 fixture와 원자료는 `/tmp/taw-new-session-path` 아래 `selector_observation.dart`, `/tmp/taw-new-selector-{before,after}.log`에 있으며 저장소의 749개 테스트 수에 포함하지 않습니다. 새로운 측정 cache는 도입하지 않았고 이전 speculative painter 비용을 개선했다고 주장하지 않습니다.

## 외부 리뷰 후속 개선 (2026-10-18)

기존 749개 검증 기록은 당시 snapshot의 기록입니다. 아래 변경 이후의 실행 결과와 섞어 읽지 않습니다.

### 경계와 입력 상한

- `가\u200D나`의 offset 2를 허용하던 것을 재현하고 ZWJ 직후 후보를 차단했습니다. ZWSP 뒤의 기회는 유지합니다. 숫자 묶음과 주요 ASCII·전각·CJK 괄호 안쪽도 보호합니다. 숫자는 ASCII·Arabic-Indic·Extended Arabic-Indic·전각 숫자와 해당 소수/그룹 구분자를 대상으로 합니다. 전체 Unicode 숫자 클래스나 UAX #14 전체를 구현했다는 뜻은 아닙니다.
- CR/LF/CRLF/VT/FF/NEL/LS/PS를 공통 함수로 분류하여 core 문단, native geometry, span 개행 삽입 및 native 비용 계산에 사용합니다. VM에서 NEL은 실제 hard break로 표시되지 않았습니다. 엔진에 없는 줄을 만들지 않고 검증된 native 범위로 복구합니다. VT·FF는 해당 엔진의 실제 빈 줄·후행 개행과 대조합니다.
- Native emergency wrapping이 만든 숫자 내부 경계를 의미 단위 후보로 다시 기록하지 않습니다. 공백 전용 모델에서도 일반 grapheme 경계의 native 비용은 계속 계산하므로 한국어 프리셋의 기존 선택 계약을 유지합니다.
- UTF-16 길이 65,536 초과는 예측/aggregation/calculator 전에 처리합니다. `calculate()`와 명시적 `predict()`/`aggregate()`는 독립 `TextWrapInputLimitException`을 던집니다. `select()`는 검증된 native layout이 제공된 경우에만 `inputLimit` 이유로 그 geometry를 재사용하고 `calculationLimit`은 null로 둡니다. Native layout이 없으면 같은 typed 예외를 던집니다. 기존 `LayoutCalculationLimitKind`의 두 값과 sealed `TextWrapException` 하위 타입은 유지합니다. Widget은 원문을 유지하고 중복 native 진단 shaping을 생략하여 `result == null`과 typed failure를 공개합니다. `softWrap: false` 등 native 전용 경로에도 같은 진단 상한을 적용합니다.
- Span 전처리는 occurrence 16,384개, 깊이 1,024(root 0)에서 제한합니다. 17,000개 sibling 및 2,000단계 중첩을 typed limit으로 중단하는 테스트와 기존 600단계·4,000개 Span 정상 렌더링 테스트를 함께 둡니다. Native Flutter 자체의 재귀·shaping 비용과 한계까지 제거하는 상한은 아닙니다.
- GL/WJ 주변의 기존 보수적 보호는 유지합니다. 일반 공백 뒤 GL 예외까지 허용하는 Unicode 기본 동작과 의도적으로 다릅니다. 단순 크래시 수정과 전체 Unicode 줄바꿈 준수를 구분합니다.

### 측정·캐시·관측

원문 전용 painter와 최대 8개 constraint별 측정 결과를 재사용합니다. Style/locale/direction/scaler/strut/height behavior/overflow/maxLines 및 occurrence별 WidgetSpan dry size/baseline을 비교하며 시스템 폰트 변경, 명시적 layout 무효화, 해제 시 캐시를 비웁니다. Painter 생성이나 layout 실패 뒤에는 다음 질의에서 다시 시도할 수 있습니다. 실제 선택·paint span과 Controller 결과는 speculative 질의로 바꾸지 않습니다.

동일 측정 key의 부모 높이 변경은 이미 geometry 검증한 effective paragraph를 재사용합니다. Mutable custom span은 명시적으로 layout이 무효화되면 plan의 range cache와 선택 캐시도 무효화합니다. Frame 내 성공→실패→성공과 반복 실패, 여러 writer의 commit/detach는 최종 snapshot과 중복 알림을 검증합니다. 공유 Controller는 마지막 commit을 관측하는 계약이며 위젯별 독립 결과에는 각각의 Controller를 사용합니다.

음수 자간 `-0.2`, `-1`, `-8`과 `1111\n\u00AD\n3333`, `가\u00AD나`, soft hyphen 반복, `A\u200DB`의 12개 조합에서 native `Text`와 raw RGBA를 비교합니다. 같은 엔진끼리의 비교는 독립적인 glyph correctness 증명이 아니며, source range·경계의 독립 고정값 테스트와 함께 사용합니다.

### Profile 관측

재현용 `benchmark/source_measurement_profile.dart`는 RenderBox 외부 질의 캐시를 우회해 매 표본 1,200회 source `compute*`를 호출합니다. Flutter 3.47.4, Chrome 155, Web Profile의 CPU CanvasKit에서 앱 저장소의 Pretendard Variable을 로드했습니다. Font size 10, height 1.5, 자간 -0.2, weight variation 400, liga/clig 해제이며 폭 100/80/120을 번갈아 측정합니다.

별도 복사본에서 원문 metric 수집을 그대로 두고 캐시만 비활성화한 경우와 활성화한 경우를 순차 실행했습니다. 각 7개 표본의 중앙값은 **19.0ms → 0.5ms**였고 양쪽의 checksum은 독립 `RenderParagraph`와 같은 `26137.651920318604`였습니다. 모두 `applied=true`, failure 0이며 캡처에서 `abc`/`def`의 실제 두 줄 표시를 확인했습니다. 원자료는 [source-query-profile.json](validation/source-query-profile.json)에 보관합니다.

이는 따뜻한 캐시의 짧은 문자열에 대한 제한적인 측정입니다. 종전 22.705ms/117.729ms debug 표본과 같은 환경의 재실행도, 앱 프레임 시간이나 긴 RichText 전체의 개선 보장도 아닙니다. 실제 모바일 기기·앱 전체·수동 스크린리더 검증은 별도입니다. 로컬 `fnb-app-v2` checkout에는 `AppText`나 이 패키지 의존성이 없어 그 프로젝트 전체 화면을 연결해 검증했다고 주장하지 않습니다.


## 실제 표시·선택·폰트 경로 추가 조사 (2026-10-19)

직전 749개 snapshot 이후의 미커밋 변경을 보존하고, 독립 영역의 agent를 병렬 투입했습니다. 동시에 다른 로컬 작업의 변경도 확인되어 덮어쓰지 않고 최종 통합 snapshot을 다시 검증합니다. 아래 네 건은 이번 조사에서 각각 수정 전 실패를 확인한 문제입니다. 기존 세션의 결함을 새 발견으로 집계하지 않습니다.

1. **동등한 rich source의 이동에서 선택 영역 소실**: `uvwxyz`를 `uvw\nxyz`로 표시하고 전체 범위 `[0,7]`를 선택한 뒤, 같은 GlobalKey의 renderer를 x=0에서 x=100으로 이동하면서 동등한 새 span tree를 전달했습니다. 독립 `Text.rich`는 선택을 유지하지만 패키지는 `[0,0]`으로 축소했습니다. `sourceText` setter가 동등성 확인 전에 원문 paragraph로 교체하며 선택 fragment를 폐기했습니다. 새 source 객체 identity는 항상 보존하되 동등한 tree라면 현재 effective paragraph를 유지합니다. 변경된 source/style/recognizer/semanticsLabel/locale/spellOut/controller 갱신도 별도로 native 결과와 비교합니다.
2. **깊은 span 동등성 비교의 중복 순회**: 깊이 80의 동등한 tree에서 native style 동등성 비교는 81회인데 패키지는 3,321회였습니다. 각 노드에서 native recursive equality를 호출한 뒤 다시 자식 전체를 재귀 비교했기 때문입니다. 일반 `TextSpan`의 모든 동등성 필드와 locale/spellOut을 반복 stack으로 한 번씩 비교합니다. Custom subclass의 자체 equality는 유지합니다. 회귀 검사는 162회 이하를 요구하며 실제 정상 renderer의 `applied=true`도 검증합니다. `_inlineSpanHash`가 실제 경로의 원인이라는 증거는 없어 이를 수정하지 않았습니다.
3. **source-query painter 생성 실패 뒤 재시도 불가**: 정상 `applied=true` renderer의 custom span validation이 다음 painter 생성에서 한 번만 실패하도록 주입했습니다. 첫 예외 이후 같은 dry query를 재시도하면 `_sourceQueryPainter!`에서 null 오류가 발생했습니다. Cache key가 painter 생성보다 먼저 저장됐기 때문입니다. Painter 생성 성공 뒤에만 key를 저장하도록 순서를 수정했습니다. 첫 실패는 그대로 전달하고, 재시도는 원문 `Size(60,10)` 및 정상 layout으로 복구하며 기존 effective/result를 오염시키지 않습니다. 이는 custom 실패 주입의 복구 계약이며 실제 엔진 결함 재현이 아닙니다.
4. **추가 입력 상한의 공개 exhaustive switch 호환성 회귀**: 통합 과정에서 `LayoutCalculationLimitKind.inputLength`와 sealed `TextWrapException`의 새 하위 타입이 기존 exhaustive switch를 컴파일 불가로 만드는 것을 확인했습니다. 기존 enum 두 값과 invalid-input 예외 네 타입은 유지하고 `TextWrapInputLimitException implements Exception`을 독립 resource 예외로 둡니다. 기존 형태의 두 switch를 그대로 컴파일하는 회귀 검사를 추가했습니다. 길이 상한에서는 user callback 전에 typed 예외를 전달하며, 검증된 native layout을 받은 `select()`만 원문 geometry를 재사용하고 허위 state budget 집계를 만들지 않습니다.

수정 전 실패 로그는 `/tmp/taw-render-selection-red.log`, `/tmp/taw-render-complexity-equality-red.log`, `/tmp/taw-render-query-red.log`, `/tmp/taw-public-contract-red.log`입니다. 각각 selection/native 불일치, 비교 횟수 3,321, null 재시도 오류, exhaustive switch 컴파일 오류를 구분합니다. 회귀 테스트를 삭제하거나 skip해 해결하지 않았습니다.

### 추가 반례가 없었던 실행 범위

- `paint_contract_test.dart` 18개: LTR/RTL × clip/fade/visible/ellipsis × 실제 truncation 유무 16개와 동적 WidgetSpan 두 fixture입니다. 독립적으로 개행을 지정한 `Text.rich`의 raw RGBA, 비어 있지 않은 표시 픽셀, recognizer tap, occurrence별 child 위치를 비교합니다. 정상 8개 조합은 `applied=true`를 요구합니다. 서로 다른 엔진끼리의 동일 픽셀을 요구하거나 모든 glyph의 정확성을 증명하지 않습니다.
- `font_loading_contract_test.dart`: 직접 만든 TTF를 실제 FontLoader로 등록합니다. `abcdef`의 native 폭 60→30과 적용된 두 줄 폭 30→15, 실제 font 변경 통지 및 range cache 무효화 후의 native geometry를 확인합니다. Web tester의 고정 test font/무시된 platform message 설정은 테스트 구간에만 해제하고 복원합니다. Web의 실제 font 등록 프레임도 기다립니다.
- `locale_rendering_contract_test.dart`: 직접 만든 Turkish `locl` TTF와 `TextStyle.locale` 변경으로 실제 shaping 차이를 만들고, 전체 caret offset과 size를 새 native paragraph와 비교합니다. `TextSpan.locale` 자체로 shaping을 가정하지 않습니다. Chrome의 native advance 양자화는 native-vs-native 비교로 유지합니다.
- `source_query_cache_contract_test.dart` 2개: 일곱 speculative compute 경로를 fresh `RenderParagraph`와 비교합니다. Layout 전 align/direction/scaler/locale/strut/heightBehavior/widthBasis/maxLines/overflow/softWrap/source/style 변경, 10개 bounds와 재방문으로 8-entry eviction, 공유 WidgetSpan의 두 occurrence별 dry size/baseline 변경을 포함합니다. 실제 size, effective paragraph, result/controller snapshot은 유지해야 합니다. 모든 사용자 정의 equality와 비결정적 callback까지 포괄하지 않습니다.
- `span_complexity_contract_test.dart`: 정상 깊이 600, sibling 4,000개, 공유 WidgetSpan metadata/recognizer와 폭 변경을 검증합니다. 별도로 sibling 17,000개와 깊이 2,000의 semantic 전처리는 typed resource 예외로 중단합니다. 조사용 codec probe는 VM 24,000단계·Chrome 2,000단계를 완료했지만 native TextPainter 자체의 VM 32,000단계·Chrome 3,000단계 재귀 실패도 관측했습니다. 이 수치를 지원 한계나 패키지 결함으로 해석하지 않습니다.
- `long_input_lifecycle_test.dart`: `a\r\n` 18,000회 + `z`(UTF-16 54,001개)에서 optimal/greedy/nearby가 기존 state budget 16,384를 넘는 16,385번째 작업을 typed limit으로 반환하고 측정 callback은 호출하지 않습니다. 이어 짧은 입력은 정상 계산됩니다. 전체 긴 본문의 최적성·상수 시간 보장이 아닙니다.

UTF-16 65,536, span occurrence 16,384 및 깊이 1,024의 **새 전처리 상한은 이번 통합 변경**입니다. 기존 candidate 4,096·state 16,384·range cache 65,536은 올리지 않았습니다. 상한을 넘으면 원문 native 표시를 유지하지만 의미 단위 개행과 진단 geometry는 제공하지 못할 수 있습니다. SDK 최소 조건과 버전 0.1.1은 유지합니다. 문자 삭제·정규화나 정상 fixture의 무조건 fallback은 도입하지 않습니다.

### 2026-10-19 최종 통합 snapshot 검증

최종 `lib`/`test` snapshot으로 다시 실행한 결과입니다. 앞선 816개 중간 snapshot 실행을 현재 결과로 재사용하지 않았습니다. 모든 아래 명령의 종료 코드는 0입니다.

| SDK / backend | 통과 | SDK 의존 skip | 실패 |
| --- | ---: | ---: | ---: |
| Flutter 3.47.4 / VM | 827 | 0 | 0 |
| Flutter 3.47.4 / Chrome CanvasKit | 827 | 0 | 0 |
| Flutter 3.47.4 / 실제 Chrome Wasm | 827 | 0 | 0 |
| Flutter 3.47.3 / VM | 827 | 0 | 0 |
| Flutter 3.47.3 / Chrome CanvasKit | 827 | 0 | 0 |
| Flutter 3.38.1 / VM | 821 | 6 | 0 |

Core 단독 165개, `flutter analyze`, formatting(전체 suite 시점 81개·최종 선택적 파일 추가 후 82개, 모두 변경 0), `git diff --check`, bootstrap, 예제 Web 빌드를 통과했습니다. 실제 Wasm은 `flutter test --platform chrome --wasm`의 전체 실행이며 단순 빌드 dry run과 구분합니다. CI에도 같은 전체 Wasm 실행을 추가했습니다. 기존 CupertinoIcons 폰트 경고는 남아 있습니다. 이번 SDK별 복사본의 `lib`/`test`는 루트와 byte 단위로 일치하며 root package config는 기본 `.tooling/flutter`를 유지합니다. 전체 검증의 동시 실행 시간은 성능 표본으로 사용하지 않습니다.

로그는 `/tmp/taw-render-final2-{vm,chrome,wasm,sdk3473,sdk3381,core,analyze,format,bootstrap,web}.log`입니다. Snapshot manifest와 추가 SDK 복사본은 `/tmp/taw-render-path`가 가리키는 경로 아래에 있습니다. 버전 0.1.1, HEAD, 브랜치를 유지하고 커밋·푸시·PR·배포·앱 코드 변경을 수행하지 않았습니다. `.DS_Store`와 기존 미커밋 변경을 보존했습니다.

실제 Wasm 미검증이라는 이전 기록은 과거 snapshot의 한계이며 이번 실행으로 검증 범위를 넓혔습니다. 비정상 UTF-16, native emergency wrapping의 glue 분리, 엔진별 CR/NEL·양자화 차이, native 깊은 재귀 한계는 여전히 구분합니다. 실제 모바일 기기, OS별 모든 폰트와 GPU backend, 수동 스크린리더, 앱 전체 화면은 검증하지 않았습니다. 전체 입력에 대한 무결함을 주장하지 않습니다.

### 앱 SDK Chrome과 실제 Pretendard 추가 검증

Flutter 3.47.3 Chrome CanvasKit에서도 전체 **827개 통과, 실패·skip 0**을 확인했습니다. `/tmp/taw-review-sdk3473-complete4-chrome.log`가 최종 로그입니다. 검증 복사본의 `lib`/`test`는 파일 끝의 검증용 주석만 제외하면 루트의 bytes와 모두 일치함을 확인했습니다. 이 실행의 임시 package config/asset 경로 오류와 앞선 snapshot의 실패는 최종 통과 결과에 섞지 않습니다.

실제 폰트 회귀 fixture는 일반 synthetic-font suite와 별도로 실행합니다. 저장소에 외부 앱 폰트를 복제하거나 런타임 의존성을 추가하지 않습니다.

```sh
python3 tool/serve_test_font.py /path/to/PretendardVariable.ttf
# 다른 터미널
.tooling/flutter/bin/flutter test test/real_font_review.dart --platform chrome
```

다른 포트나 폰트 서버를 쓰면 `--dart-define=TAW_FONT_URL=http://127.0.0.1:PORT/font.ttf`를 지정합니다. 서버는 loopback에서 지정한 폰트 하나만 제공하며 브라우저 테스트용 CORS 헤더를 보냅니다.

`fnb-app-v2`의 실제 Pretendard Variable 파일, font size 16, height 1.5, weight variation 400, liga/clig 해제를 사용합니다. 첫 fixture는 음수 자간 3종×문자열 4종의 12개 raw RGBA 비교입니다. 두 번째는 한국어·숫자·괄호를 포함한 문자열의 배율 1.5, 의미 단위 개행, semantics label, 전체 선택 및 clipboard 전달값을 폭 300→280→320→300에서 확인합니다. Clipboard는 Flutter platform channel에 전달한 payload를 검증하며 실제 OS clipboard 수동 조작과 구분합니다. Semantics handle은 fixture 종료 전에 해제합니다. 전체 앱의 수동 화면 검증을 대신하지 않습니다.

실제 폰트 opt-in fixture **2개 모두 통과**했습니다(첫 fixture 안의 픽셀 비교는 12개 조합). 재현 가능한 저장소 파일은 `test/real_font_review.dart`, `tool/serve_test_font.py`이고 로그는 `/tmp/taw-review-realfont-complete.log`입니다. 임시 fixture의 asset 경로·package root 설정과 semantics handle 해제 시점 문제를 정리한 뒤 통과한 실행만 최종 결과로 기록합니다. 새 서버가 반환한 폰트 bytes 및 CORS 헤더도 원본 파일과 대조했습니다.

최종 추가 분석은 경고·info 없이 통과했고, formatting은 tool과 opt-in fixture를 포함해 82개 파일·변경 0이었습니다. 예제 Web 빌드도 성공했으며 기존 CupertinoIcons 폰트 경고는 남습니다. 전체 backend별 실행 결과와 production SHA-256은 [review-summary.json](validation/review-summary.json)에 보관합니다. 최종 자동 검증 이후 production/test/benchmark snapshot 변경이 없음을 확인했습니다. 이 opt-in 파일은 일반 `_test.dart` 검색 대상에 포함되지 않으며 전체 827개 수에 더하지 않습니다.

### 반복 원문 질의 비용의 새 관측

별도 격리 복사본에서 이번 조사 시작 시의 production(749개 snapshot)과 최종 production을 같은 fixture로 순차 실행했습니다. 이전 수정으로 양쪽 모두 올바른 원문 geometry를 계산하는 상태입니다. `abcdef`, fontSize 10, offset 3의 의미 단위 개행을 적용한 뒤 폭 100/80/120을 번갈아 300회 질의하며, 매회 min/max intrinsic height·dry layout·dry baseline의 `compute*`를 직접 호출했습니다. RenderBox 질의 cache를 우회한 1,200회이며 별도의 warmup은 하지 않았습니다.

두 실행 모두 종료 코드 0이고, 독립 원문 `RenderParagraph`와 literal 기대값의 checksum **11,250**으로 일치했습니다. 관측 시간은 **16.976ms → 4.641ms**입니다. 실행 중 다른 Flutter test/build 프로세스의 겹침은 1초 간격 감시에서 관측하지 못했습니다. 이는 짧은 동일 문자열의 반복 질의에 대한 단일 debug 표본이며 성능 향상·동등성·latency 상한을 보장하지 않습니다. 이전 22.705ms/117.729ms, 외부 Profile 중앙값 19.0ms/0.5ms와 환경·fixture를 섞어 회귀 원인을 단정하지 않습니다.

새 cache는 원문 `TextPainter` 1개와 최대 8개 bounds metric을 수명주기 내 유지하는 메모리 비용이 추가됩니다. 무효화·실패·dispose에서 해제하지만 heap byte 상한이나 실제 앱 프레임 비용은 이번 관측으로 측정하지 않았습니다. 로그는 `/tmp/taw-render-benchmark-query-{before,final}.log`이고 임시 fixture는 저장소 827개 테스트에 포함하지 않았습니다. 격리 복사본 준비 중 누락된 package metadata와 불완전한 saved-file overlay로 발생한 runner/컴파일 실패는 복사본을 바로잡고 재실행했으며, 패키지 반례나 완료된 성능 표본으로 사용하지 않았습니다.

### 동일 harness의 최종 순차 20회 비교

전체 VM/Chrome/Wasm/SDK 테스트와 Web 빌드 뒤, 최초 기준 `06fcb872`와 최종 production을 Flutter 3.47.4·동일 lockfile·동일 기존 12행 harness로 행당 20회 순차 실행했습니다. 기준 production은 commit과 byte 단위로 일치하며 최종 복사본도 루트 production과 일치합니다. 두 명령의 종료 코드는 0이고, 후보 수·측정 횟수·cache hit·fallback reason 등 **12개 행의 모든 비시간 필드가 같습니다**.

최종 채택한 시간 합계는 **39.682244초 → 40.853128초**입니다. 1초 간격 감시에서 다른 Flutter test/build 프로세스의 겹침은 관측하지 못했습니다. 이 단일 debug 표본에서는 시간이 증가했고, 이를 숨기거나 개선·동등성으로 설명하지 않습니다. 표본 한 쌍으로 회귀 원인·일반 latency·실제 앱 성능을 단정하지 않습니다. 이전 세션의 227/224초 및 264/241초 표본과도 직접 비교하지 않습니다. 최초 예비 실행은 중간에 다른 로컬 Chrome 테스트가 시작되어 최종 비교에서 제외하고, 두 실행을 다시 완료했습니다.

새로운 24행 harness도 행당 20회, 종료 코드 0으로 통과했습니다. 12개 renderer를 포함하는 새 부모 fixture의 시간 합계는 **43.750575초**이며 기존 12행 합계와 직접 비교하지 않습니다. 원자료는 `/tmp/taw-render-benchmark-clean-{head,final}.{log,rows.json}` 및 `/tmp/taw-render-benchmark-expanded.{log,rows.json}`에 있습니다.

전체 suite 이후 다른 로컬 작업에서 추가된 `test/real_font_review.dart`는 외부 실폰트 서버를 명시적으로 지정하는 선택적 Web 검증 파일입니다. 기본 자동 탐색 대상인 `*_test.dart`가 아니므로 위 827개에 포함하지 않습니다. 이 agent의 최종 실폰트 실행 결과로도 집계하지 않습니다. Production·자동 탐색 회귀 테스트·harness는 전체 검증 snapshot과 계속 일치하며, 추가 파일까지 SDK 복사본에 동기화하고 analyze/format을 다시 검사했습니다. 새로운 기본 suite skip을 추가하지 않았습니다.
