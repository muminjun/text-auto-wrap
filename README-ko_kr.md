# text_auto_wrap

[English](README.md) | 한국어

Flutter의 일반 텍스트와 리치 텍스트에 모델 기반 의미 단위 줄바꿈을 적용합니다. `TextAutoWrap`은 현재 Flutter 레이아웃 입력으로 텍스트를 측정하고 phrase 경계 후보를 평가합니다. 선택한 레이아웃은 첫 화면 프레임에 바로 렌더링되며, 안전하게 적용할 수 없으면 Flutter의 기본 줄바꿈을 유지합니다.

이 패키지는 Python의 고정 글자 수 줄바꿈과 다릅니다. 실제 shaping된 픽셀 너비를 사용하고, 글자 수가 아니라 원본 텍스트의 유효한 경계에서 추가 줄바꿈을 선택합니다.

> 번들 한국어·영어 제목 프리셋은 **실험적**입니다. 짧은 디스플레이 제목을 위한 소규모 도메인별 출발점일 뿐, 범용 언어 모델이나 프로덕션 정확도 보장이 아닙니다. 앱의 실제 글꼴과 너비로 처음 보는 콘텐츠를 검증하세요. [영어](model_cards/english.md) 및 [한국어](model_cards/korean.md) 모델 카드를 참고하세요.

## 설치

```yaml
dependencies:
  text_auto_wrap: ^0.1.0
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
| `invalidMeasurement` / `rendererFallback` | 런타임 측정 또는 보호된 renderer 작업이 실패했습니다. |

Reason은 사용자에게 보여 주는 번역 문자열이 아니라 진단값으로 다루세요. 커스텀 selector는 앱 전용 reason을 반환할 수 있습니다.

## Unicode, 성능, 접근성

모든 offset은 Dart `String`, Flutter `TextPosition`, `TextRange`와 같은 UTF-16 기준입니다. 후보는 Unicode grapheme 경계로 검증하므로 surrogate pair, 결합 sequence, emoji modifier, ZWJ sequence, U+FFFC placeholder token 내부를 나누지 않습니다. 기존 CR, LF, CRLF, U+2028, U+2029 문단 구분자는 보존됩니다.

동기식 exact-first layout 작업량은 제한됩니다. 0.1.0은 후보가 4,096개를 초과하거나 optimizer state 작업이 16,384회에 도달하면 전체를 fallback하며 일부 계산 결과를 노출하지 않습니다. 재사용 plan은 현재 non-null cache key에 대해 측정 범위를 최대 65,536개 유지합니다. Renderer cache key에는 텍스트/span metadata, effective style, 너비, 방향, locale, scaler, strut, 줄 제한, strategy/model, placeholder 크기가 포함됩니다. 이 상한은 결정론적 안전장치이지 latency 보장이 아니며 공개 조정 옵션도 아닙니다. 대표 콘텐츠와 글꼴로 대상 기기에서 benchmark하세요.

추가 break를 넣을 때 중첩 `TextSpan` metadata, recognizer, mouse cursor, locale, spell-out metadata, semantics label/identifier, `WidgetSpan` child identity와 alignment를 보존합니다. 선택 기능은 Flutter selection registrar와 계속 연동됩니다. `semanticsLabel`은 `Text`와 같은 override 역할입니다. 안전한 변환 또는 placeholder 측정이 불가능하면 원본 span tree의 기본 줄바꿈을 유지합니다. 지원할 각 앱 환경에서 screen reader, text scaling, selection, bidi 콘텐츠, interactive span을 테스트하세요.

## 예제와 저작자 표시

실시간 controller 진단이 포함된 반응형 예제를 실행합니다.

```sh
cd example
flutter run -d chrome
```

이 프로젝트는 Apache-2.0 라이선스입니다. [`semantic-wrap`](https://github.com/woohyun-park/semantic-wrap)의 commit `54ed67688aa5292f14970cae10bbabd9a11f1b5d`를 수정하여 Dart/Flutter로 포팅했으며, BudouX 호환 inference 구현과 실험적 영어·한국어 weight를 포함합니다. 정확한 저작자 표시와 제한 사항은 [NOTICE](NOTICE), [LICENSE](LICENSE), 모델 카드를 확인하세요.
