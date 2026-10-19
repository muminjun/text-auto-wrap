# text_auto_wrap

[English](README.md) | 한국어

Flutter의 일반 텍스트와 리치 텍스트에 모델 기반 의미 단위 줄바꿈을 적용합니다. `TextAutoWrap`은 현재 Flutter 레이아웃 입력으로 텍스트를 측정하고 phrase 경계 후보를 평가합니다. 선택한 레이아웃은 첫 화면 프레임에 바로 렌더링되며, 안전하게 적용할 수 없으면 Flutter의 기본 줄바꿈을 유지합니다.

이 패키지는 Python의 고정 글자 수 줄바꿈과 다릅니다. 실제 shaping된 픽셀 너비를 사용하고, 글자 수가 아니라 원본 텍스트의 유효한 경계에서 추가 줄바꿈을 선택합니다.

> 번들 한국어·영어 제목 프리셋은 **실험적**입니다. 짧은 디스플레이 제목을 위한 소규모 도메인별 출발점일 뿐, 범용 언어 모델이나 프로덕션 정확도 보장이 아닙니다. 앱의 실제 글꼴과 너비로 처음 보는 콘텐츠를 검증하세요. [영어](model_cards/english.md) 및 [한국어](model_cards/korean.md) 모델 카드를 참고하세요.

## 설치

```yaml
dependencies:
  text_auto_wrap: ^0.1.3
```

```dart
import 'package:flutter/material.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';
```

플랫폼별 네이티브 구현이 없는 순수 Dart/Flutter 패키지입니다.

## 일반 텍스트, 리치 텍스트, 인라인 위젯

`model`을 생략하면 `TextAutoWrapModels.auto`를 사용합니다.

```dart
const TextAutoWrap(
  '사용자를 이해하고 더 나은 해결책을 만드는 방법',
  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
);
```

리치 텍스트의 스타일과 인라인 위젯도 유지합니다.

```dart
TextAutoWrap.rich(
  TextSpan(
    children: [
      const TextSpan(
        text: '안정적인 ',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(Icons.verified, size: 18),
      ),
      const TextSpan(text: ' 경험을 출시하는 방법'),
    ],
  ),
);
```

일반 생성자와 rich 생성자는 원본(`String` 또는 `InlineSpan`)만 다르고 같은 레이아웃·모델·전략·진단 옵션을 받습니다. Flutter `Text`와 대응하는 옵션은 `style`, `strutStyle`, `textAlign`, `textDirection`, `locale`, `softWrap`, `overflow`, `textScaler`, `maxLines`, `semanticsLabel`, `textWidthBasis`, `textHeightBehavior`, `selectionColor`입니다. `maxLines`와 `overflow`는 최종 Flutter 렌더링 규칙으로 유지됩니다. `softWrap: false`이면 추가 의미 단위 줄바꿈만 끄고 명시적 개행은 보존합니다.

## 자동 및 명시적 모델

자동 감지는 Unicode에서 Hangul 문자와 Latin 문자로 지정된 코드 포인트를 셉니다. 공백, 문장부호, 숫자, 결합 문자, 다른 스크립트, U+FFFC 위젯 placeholder는 근거에서 제외합니다.

- 지원 문자 근거 중 한 스크립트가 70% 이상이면 해당 프리셋을 선택합니다.
- 70% 미만에서는 일치하는 `ko` 또는 `en` locale이 있고 해당 스크립트 비율이 40% 이상이면 프리셋을 선택할 수 있습니다.
- 지원 문자가 없으면 `unsupportedLanguage`, 해소되지 않은 혼합 텍스트면 `detectTextWrapLanguage`에서 `ambiguousLanguage`를 반환합니다.
- 자동 감지 결과에 모델이 없으면 위젯은 Flutter 기본 줄바꿈을 사용합니다.

문자 수나 locale 영향이 필요하면 감지 결과를 직접 확인하세요.

```dart
final detection = detectTextWrapLanguage(text, Localizations.localeOf(context));
debugPrint(
  'ko=${detection.koreanCount}, en=${detection.englishCount}, '
  'locale=${detection.localeInfluenced}, fallback=${detection.fallbackReason}',
);
```

명시적 선택은 자동 감지를 항상 우회합니다.

```dart
TextAutoWrap(title, model: TextAutoWrapModels.korean);
TextAutoWrap(title, model: TextAutoWrapModels.english);
```

두 번들 프리셋은 공백 경계에서 동작하며 coarse, medium, fine penalty는 각각 `0`, `0.35`, `0.7`이고 예측되지 않은 원본 공백 경계의 penalty는 `1`입니다.

## 커스텀 predictor와 strategy

Predictor는 엄격한 오름차순 UTF-16 offset을 반환해야 합니다. 각 offset은 모델 `BoundaryMode`가 허용하는 내부 경계여야 합니다. `spaces`는 연속 공백 묶음의 끝, `characters`는 Unicode grapheme 경계를 허용합니다.

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

기본값은 `lowestPenalty()`와 `optimalLayouts()`입니다. `consensus`, `greedy`, `nearbyLayouts` 또는 커스텀 `PredictionAggregator`, `LayoutCalculator`, `LayoutSelector` 구현으로 각 단계를 바꿀 수 있습니다. 엔진을 직접 호출할 때 잘못된 커스텀 설정은 typed `TextWrapException`을 던집니다. 위젯은 렌더링을 보호하기 위해 원본 문단으로 fallback합니다.

## 저수준 엔진과 측정 계약

한 번 선택할 때는 `selectTextWrap`, 여러 너비에서 prediction과 aggregation을 재사용할 때는 `createTextWrapPlan`을 사용합니다.

```dart
final plan = createTextWrapPlan(
  text: source,
  model: TextAutoWrapModels.korean,
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

`measureRange(start, end)`는 원본 문자열의 반열린 UTF-16 범위를 받습니다. 현재 렌더링 너비를 유한하고 음수가 아닌 `double`로 반환해야 합니다. 너비는 가산적이거나 단조롭다고 가정하지 않습니다. shaping, bidi 텍스트, 스타일, 텍스트 배율, placeholder 때문에 각 slice의 너비가 달라질 수 있습니다. 리치 텍스트 adapter는 대응하는 스타일 span slice와 실제 placeholder 크기를 측정해야 합니다. 명시적 hard newline 구분자는 보존되며 줄 내용으로 callback에 전달되지 않습니다.

null이 아닌 `measurementCacheKey`는 모든 측정 입력을 식별할 때만 전달하세요. 스타일, 방향, 배율, placeholder 또는 너비 의존 callback이 바뀌면 key도 바꿔야 합니다. Key를 생략하면 호출 간 범위 캐시를 사용하지 않습니다. 엔진 직접 호출에서 잘못된 너비, offset, 모델 설정 또는 측정값은 typed exception을 던집니다.

## Controller와 진단

`TextAutoWrapController.result`는 최근의 immutable `TextWrapResult`입니다. Renderer는 layout 중 값을 할당하고, reentrant build를 피하도록 listener 알림을 프레임 끝까지 미룹니다.

```dart
final controller = TextAutoWrapController();

TextAutoWrap(
  title,
  controller: controller,
  model: TextAutoWrapModels.korean,
);

ListenableBuilder(
  listenable: controller,
  builder: (context, _) {
    final result = controller.result;
    return Text(
      result == null
          ? 'layout 대기 중'
          : '${result.reason}: ${result.breakOffsets}',
    );
  },
);

// State.dispose()에서 소유한 controller를 정리합니다.
controller.dispose();
```

결과에는 원본 범위, 줄, 너비, 삽입한 break offset, overflow, 의미 단위 줄바꿈 적용 여부, stable reason, 선택적인 단계·캐시 진단이 들어 있습니다.

위젯 결과의 `ranges`, `lines`, `widths`는 최종 표시 레이아웃이며 추가 개행 주변의 원문 공백을 보존합니다. `diagnostics.calculatedLayouts`는 후보 평가를 위해 선택한 경계 공백을 제외한 계산 레이아웃입니다. 따라서 계산 범위·너비와 최종 위젯 결과는 다를 수 있습니다. 계산 결과가 기본 줄바꿈과 같은 break offset을 재사용하면 `applied: false`이며, 바뀌지 않은 기본 레이아웃의 범위·너비를 보고합니다.

| Reason | 의미 |
| --- | --- |
| `calculatedSelected` | 계산한 의미 단위 레이아웃을 선택했습니다. |
| `nativeSelected` / `nativeNoModelImprovement` | Flutter 기본 줄바꿈이 선택에서 이겼습니다. |
| `unsupportedLanguage` | 자동 감지가 번들 모델을 고르지 못했습니다. `detectTextWrapLanguage`로 미지원 스크립트와 모호한 혼합을 구분할 수 있습니다. |
| `softWrapDisabled` | `softWrap` 설정 때문에 추가 break가 꺼졌습니다. |
| `unusableWidth` | 너비가 unbounded, non-finite 또는 0 이하입니다. |
| `calculationLimit` | 결정론적인 작업 상한에 도달했습니다. |
| `unmeasurablePlaceholder` | `WidgetSpan` 크기 또는 필수 baseline을 일관되게 측정할 수 없습니다. |
| `unsupportedSpanTransformation` | 커스텀 `InlineSpan` 상태를 잃지 않고 변환할 수 없습니다. |
| `invalidRuntimeMeasurement` / `rendererFallback` | 런타임 측정 또는 보호된 renderer 작업이 실패했습니다. |
| `layoutGuard` / `nativeLayoutGuard` / `<query>Guard` | 의미 단위 단계 밖의 실패를 최종 보호 장치가 흡수했습니다. 문단 layout 또는 `computeDryLayoutGuard`, `paintGuard`, `hitTestChildrenGuard` 같은 부모 조회가 대상입니다. |

Reason은 사용자에게 보여 주는 번역 문자열이 아니라 진단값으로 다루세요. 커스텀 selector는 앱 전용 reason을 반환할 수 있습니다.

Fallback 결과에는 유효성이 확인된 Flutter 기본 범위·너비가 들어 있습니다. 이미 실패한 native 진단 측정은 같은 layout에서 반복하지 않습니다. 기본 geometry를 안전하게 표현할 수 없으면 `controller.result`를 `null`로 비우고 원본 span을 Flutter 문단에 그대로 전달합니다. `controller.failures`에서 실패 단계·reason·예외·스택을 확인할 수 있으며, 다음 layout 성공 시 실패 기록이 지워집니다. Listener 알림은 프레임 끝에 전달합니다. `null` 결과를 빈 문자열이나 너비 0으로 해석하지 마세요. 의미 단위 단계가 실패하면 원문으로 문단을 다시 layout하고 `layoutGuard` 실패를 기록합니다. Flutter 기본 문단도 원문을 layout하지 못하면 예외를 던지는 대신 `nativeLayoutGuard` 실패를 기록하고 해당 텍스트만 최소 크기의 비활성 상태(그리기·hit 대상 없음)가 되어 부모 layout은 끝까지 진행됩니다.

## Unicode, 성능, 접근성

Unicode 16.0 `Line_Break=GL/WJ` 속성의 줄바꿈 방지 문자는 원시 Grapheme 경계와 별도로 보호합니다. NBSP, Word Joiner, BOM 등을 일반 공백으로 자르거나 제거하지 않으며 원문을 정규화하지 않습니다. 이는 UAX #14 전체 구현은 아닙니다. Soft Hyphen·Bidi·개행의 최종 표시는 Flutter가 담당하고, 계산 결과가 실제 표시와 다르면 원문 기본 렌더링을 유지합니다.

음수 자간에서는 UTF-16 범위가 정상이어도 Flutter의 glyph advance가 음수가 될 수 있습니다. Adapter는 이 유한한 음수 advance를 차지하는 너비 0으로 표현합니다. 유한하지 않은 측정값·잘못된 범위·사용자 `measureRange`가 반환한 음수는 계속 오류로 처리합니다. SDK별 제한과 재현 가능한 검증은 [Unicode 안정성](doc/unicode-stability.md)을 참고하세요.

모든 offset은 Dart `String`, Flutter `TextPosition`, `TextRange`와 같은 UTF-16 기준입니다. 후보는 Unicode grapheme 경계로 검증하므로 surrogate pair, 결합 sequence, emoji modifier, ZWJ sequence, U+FFFC placeholder token 내부를 나누지 않습니다. 기존 CR, LF, CRLF, VT, FF, NEL, U+2028, U+2029 문단 구분자는 보존됩니다. 해당 문자의 엔진 표시가 계산과 다르면 원문 native 표시를 유지합니다.

동기식 exact-first layout 작업량은 제한됩니다. 0.1.0은 후보가 4,096개를 초과하거나 optimizer state 작업이 16,384회에 도달하면 전체를 fallback하며 일부 계산 결과를 노출하지 않습니다. 재사용 plan은 현재 non-null cache key에 대해 측정 범위를 최대 65,536개 유지합니다. Renderer cache key에는 텍스트/span metadata, effective style, 너비, 방향, locale, scaler, strut, 줄 제한, strategy/model, placeholder 크기가 포함됩니다. 이 상한은 결정론적 안전장치이지 latency 보장이 아니며 공개 조정 옵션도 아닙니다. 대표 콘텐츠와 글꼴로 대상 기기에서 benchmark하세요.

측정 입력이 같으면 검증된 문단을 재사용하므로, 부모가 최소 높이만 바꾸는 반복 배치에서도 문단을 다시 구성하지 않습니다. Intrinsic/Dry 조회는 원문을 기준으로 유지합니다. 커스텀 span이 인스턴스 교체 없이 내부 상태를 바꾸면 renderer에 `markNeedsLayout()`을 호출해야 하며, 이때 사전 측정과 실제 그리기 geometry를 함께 갱신합니다. Renderer benchmark에는 반복 Intrinsic 행, 표, 이미지 선택지 그리드, RichText 목록, 1.5배 인라인 위젯, 세 번 배치하는 부모가 포함됩니다.

추가 break를 넣을 때 중첩 `TextSpan` metadata, recognizer, mouse cursor, locale, spell-out metadata, semantics label/identifier, `WidgetSpan` child identity와 alignment를 보존합니다. 선택 기능은 Flutter selection registrar와 계속 연동됩니다. `semanticsLabel`은 `Text`와 같은 override 역할입니다. 안전한 변환 또는 placeholder 측정이 불가능하면 원본 span tree의 기본 줄바꿈을 유지합니다. 지원할 각 앱 환경에서 screen reader, text scaling, selection, bidi 콘텐츠, interactive span을 테스트하세요.

## 예제와 저작자 표시

실시간 controller 진단이 포함된 반응형 예제를 실행합니다.

```sh
cd example
flutter run -d chrome
```

이 프로젝트는 Apache-2.0 라이선스입니다. [`semantic-wrap`](https://github.com/woohyun-park/semantic-wrap)의 commit `54ed67688aa5292f14970cae10bbabd9a11f1b5d`를 수정하여 Dart/Flutter로 포팅했으며, BudouX 호환 inference 구현과 실험적 영어·한국어 weight를 포함합니다. 정확한 저작자 표시와 제한 사항은 [NOTICE](NOTICE), [LICENSE](LICENSE), 모델 카드를 확인하세요.

의미 단위 처리는 UTF-16 65,536 단위, Span occurrence 16,384개, root를 0으로 세는 깊이 1,024까지 제한합니다. 제한을 넘으면 모델·후보 탐색을 생략하고 원문을 Flutter에 전달합니다. Widget 경로에서는 중복 진단 shaping도 생략하므로 `controller.result`가 `null`일 수 있고 `failures`에 `TextWrapInputLimitException`이 기록됩니다. Core `calculate()`·`predict()`·`aggregate()`는 입력 길이 초과 시 독립적인 `TextWrapInputLimitException`을 던집니다. `select()`는 유효한 native layout을 받았다면 `inputLimit` 이유로 재사용하고 calculation-limit 기록은 남기지 않으며, native layout이 없으면 같은 예외를 던집니다. 기존 계산 상한 enum과 invalid-input 예외의 exhaustive switch는 유지됩니다. Flutter 자체가 원문을 표시하는 비용은 이 제한으로 제거되지 않습니다.

ZWJ 바로 뒤, 숫자 묶음 내부와 주요 괄호의 안쪽에는 의미 단위 개행을 추가하지 않습니다. GL/WJ 양옆 보호는 일반 공백 앞 예외까지 허용하는 Unicode 기본 규칙보다 보수적입니다. 전체 UAX #14 준수를 보장하지 않습니다. Controller를 공유하면 가장 최근 commit이 최종 결과가 되므로 독립적인 관측에는 위젯별 Controller를 사용하세요.

## 0.1.3 성능 옵션

동일한 일반 `TextSpan` 트리는 검증된 선택 결과 최대 64개와 계획 최대 32개를 공유합니다.
대상 원문은 UTF-16 1,024단위 이하이며, recognizer·hover 콜백·`WidgetSpan`·커스텀 span은
제외됩니다. 글꼴이나 플랫폼 locale이 바뀌면 공유 캐시를 비웁니다. 폭이 달라도 placeholder
크기 등 실제 측정 입력이 같으면 범위 너비를 재사용합니다. 커스텀 predictor·calculator·selector는
설정 객체의 정체성·동등성이 유지되는 동안 같은 입력에 같은 결과를 반환해야 합니다. 외부 설정이
바뀌면 기존 캐시 키 객체를 변경하는 대신 새 model·strategy를 전달하세요. 직접 호출하는
`TextWrapPlan.calculate`·`select`는 커스텀 calculator를 실행하고 검증 오류를 전달합니다.

`optimalLayouts(assumeMonotonicWidths: true)`와
`greedy(assumeMonotonicWidths: true)`는 범위가 길어질 때 너비가 줄지 않는 측정기에만 쓰는
선택 옵션입니다. 다른 측정기에서는 결과가 달라질 수 있으며 기본값은 꺼져 있습니다.
반복 조건·분산·레이아웃 동일성 비교는 [성능 벤치마크](doc/performance-benchmark.md)를 참고하세요.
