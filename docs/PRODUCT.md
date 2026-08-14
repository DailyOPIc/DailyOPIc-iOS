# PRODUCT.md — DailyOPIc(데일리오픽)

이 문서는 UI 리뉴얼 및 이후 작업의 제품 기준선이다.
**[VERIFIED]** 표시는 실제 코드에서 확인한 사실이고, **[방향]** 은 제품 의사결정,
**[미확인/미구현]** 은 아직 코드에 없거나 확인되지 않은 것이다.
확인되지 않은 것을 디자인 편의를 위해 사실처럼 쓰지 않는다.

문서 위치 주의: 이 파일은 `DailyOPIc`(iOS)와 `DailyOPIc-BE`(서버) 두 git 저장소의 **상위 폴더**에 있어
버전 관리되지 않는다. 커밋 대상으로 삼으려면 두 저장소 중 하나로 옮겨야 한다.

---

## 1. 브랜드 · 언어 · 출시 상태

- 공식 영문 브랜드명: **DailyOPIc**. 한국 사용자 표시명: **데일리오픽**.
  문서에서는 "DailyOPIc(데일리오픽)"으로 통일해도 된다. [방향]
- 앱 내 표기는 한국어. 페이월 타이틀도 "데일리오픽 프리미엄"이다. [VERIFIED]
  (`Views/Screens/Paywall/PaywallView.swift`)
- **언어: 한국어 단일 UI를 유지한다.** [방향]
  코드에는 `.lproj`/String Catalog가 없고 `String(localized:)`·`NSLocalizedString` 사용도 0건 —
  모든 카피가 Swift 소스에 하드코딩된 한국어다. [VERIFIED]
  이번 리뉴얼에서 영어 로케일 추가는 목표가 아니다. 다만 새 카피를 쓸 때
  향후 추출이 가능하도록 문자열을 뷰 로직과 뒤섞지 않는다.
- **신규 앱이 아니라 App Store 운영 중인 기존 서비스의 업데이트다.** [방향]
  `MARKETING_VERSION = 2.0.10`, `CURRENT_PROJECT_VERSION = 17`,
  번들 ID `com.mark.opicmobile`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`. [VERIFIED]
  (`DailyOPIc.xcodeproj/project.pbxproj`)
- 기존 사용자·기존 production behavior가 존재한다. 업데이트 후 학습 기록/구독/사용량/주요 기능이
  깨지면 안 된다. [방향]

---

## 2. 주 사용자와 사용 맥락 [방향]

- OPIc 등급이 필요한 한국인 학습자. 특히 **대학생 · 취업준비생 · 직장인**.
  (앱의 설문 옵션도 학생/직장인/구직으로 되어 있다 — `Models/BackgroundProfile.swift` [VERIFIED])
- 학원·스터디가 아니라 **혼자 모바일로 짧게 반복 연습**하는 상황이 핵심.
  하루 10~20분, 부담 없이 반복하는 경험이 중요하다.
- 주요 목표 등급은 **IM2~IH 중심**이되 특정 등급에 앱을 한정하지 않는다.
  AL 목표 사용자도 자연스럽게 쓸 수 있어야 한다.
  (서버 등급 체계는 NL~AL 전체를 다루고, 예상 등급에는 IL 하한 클램프가 있다. [VERIFIED])
- **시험 직전 모의고사 앱이 아니라, 평소 매일 말하기를 지속하는 학습 서비스**다.

---

## 3. 포지셔닝 / 대체 불가능한 지점 [방향]

핵심 포지셔닝:

> **매일 실제로 말하고, AI 피드백을 받아 OPIc 실력을 개선하는 모바일 스피킹 학습 앱**

우선순위 순서(이 순서가 화면 설계의 우선순위이기도 하다):

1. 앱을 열면 **바로 문제를 받고 실제로 말하게** 만드는 낮은 진입장벽
2. 사용자의 **실제 음성 답변을 STT로 처리**하고 AI가 분석
3. **예상 등급 / 잘한 점 / 개선점 / 참고 답안**으로 즉시 피드백
4. OPIc 시험 맥락에 맞는 문제와 모의고사 경험
5. 이를 **매일 반복**할 수 있는 모바일 학습 루틴

주의:
- 실제 OPIc 시험 흐름 반영은 중요하지만, **구현된 범위 이상으로 "실제 시험을 완벽히 재현한다"고
  포지셔닝하지 않는다.** 구현된 시험 구조는 §5에 VERIFIED로만 적었다.
- 가격/가성비는 **보조적 장점**이다. 가장 중요한 차별점은
  **실제 발화 → AI 분석 → 다시 말하기의 반복 학습 경험**이다.

---

## 4. 앱 구조 (현재 구현) [VERIFIED]

- iOS SwiftUI 단일 앱. 진입: `DailyOPIcApp` → `AppRootView`.
  런치 상태에 따라 `SplashView` / `AuthRecoveryView` / 온보딩 / 메인. (`Views/AppRootView.swift`)
- **탭 3개** (`Views/Screens/Main/MainTabView.swift`):
  - `데일리` (mic.fill) — 일일 연습
  - `모의고사` (list.number) — 15문항 모의고사
  - `통계` (chart.bar.fill) — 학습 기록/인사이트
- 설정은 탭이 아니라 데일리 화면 툴바의 시트(`SetupView`)로 진입.
  같은 툴바에 가이드 진입(`GuideEntryButton`)과 왕관(구독/페이월) 버튼이 있다.
- 온보딩(`OnboardingView`): ① "오픽이 처음이신가요?" → ② 선택 시 `OPIcGuideView` 안내 →
  ③ **자가 진단 난이도(SelfAssessmentLevel 1~6) 선택**. 각 단계 카드에 예상 등급 범위와 답변 예시 문장 노출.
- 인증: **Firebase 익명 인증**(`signInAnonymously`) + App Check(App Attest / Debug provider).
  로그인/로그아웃 UI 없음. 고객 지원용으로 `SetupView`에 사용자 식별 ID 복사 기능 제공.
- 학습 기록 저장: **SwiftData 로컬 저장**(`PracticeHistoryRecord`, `MockHistoryRecord`, `MockDraftRecord`).
  통계 탭 문구도 "이 기기에 저장된 나의 연습 기록이에요" — **기기 간 동기화 없음**.
- 서버: FastAPI(`DailyOPIc-BE`), 상태는 Firestore, AI는 OpenAI(`openai_model` 설정값),
  결제 상태는 RevenueCat 웹훅 → `userProfiles.entitlement`.

---

## 5. OPIc 시험 맥락 구현 범위 [VERIFIED]

여기 적힌 것만 사실이다. 이 밖의 시험 재현(예: 실제 OPIc의 Self Assessment 재현,
시험 안내 음성, 시험 시간 총량 등)은 **구현되어 있지 않다.**

### 배경 설문(Survey)
- `BackgroundSurvey`: `status`(학생/직장인/구직/해당없음), `residence`(혼자/가족/룸메이트/기숙사/기타),
  `leisure`/`hobbies`/`sports`/`travel` 다중 선택. **최소 3개 토픽 선택 필수**(서버·클라 양쪽 검증).
  (`Models/BackgroundProfile.swift`, `app/models/api.py`)
- 설문 입력 UI는 **모의고사 플로우 안의 `.survey` 단계**에 있다(`MockExamViewModel.Phase.survey`).
  온보딩에는 설문 단계가 없다.
- 데일리 문제 생성은 저장된 설문을 재사용하고, 없으면 `BackgroundSurvey.defaultSurvey`
  (학생/가족/영화·음악·카페)로 요청한다. (`PracticeViewModel.performLoad()`)
- 서버는 설문 토픽을 문제 생성 프롬프트에 넣어 개인화한다.

### 자가 진단 난이도
- 실제 OPIc의 Self Assessment를 그대로 재현한 것이 아니라 **1~6단계 자가 선택**이며,
  각 단계에 예상 등급 범위 텍스트가 붙는다. (`SelfAssessmentLevel`, `OnboardingView`)
- 난이도 변경은 **하루 1회**. 무료는 리워드 광고 시청, 유료 플랜은 서버 auto-verify로 광고 없이 변경.
  한도 초과 시 "난이도 변경은 하루 한 번만 가능해요" 안내 + 홈으로 돌아가기.
  (`OnboardingView.submitSelection`, `plans.reward_max_for(TARGET_LEVEL_CHANGE) == 1`)
- ⚠️ **카피 불일치(리뉴얼 시 수정 대상)**: `SetupView`와 `OnboardingView.guidanceText`는 플랜과 무관하게
  "변경하려면 광고를 끝까지 봐야 해요"라고 고정 표기한다. 확인 다이얼로그(`TargetLevelConfirmationDialog`)는
  유료 플랜을 정확히 구분("무료로 바꾸기")한다. 유료 사용자에게 잘못된 안내가 노출되는 상태다.

### 모의고사 (15문항)
- 서버 `validate_mock_blueprint`가 강제하는 구조:
  - Q1 = introduction
  - Q2~Q10 = survey 기반, **3문항씩 3개 콤보**(Q2-4 / Q5-7 / Q8-10), 각 콤보는 같은 topicId·comboId
  - Q11~Q12 = roleplay
  - Q13 = unexpected, Q14 = comparison, Q15 = advanced
- **시험 중 난이도 조정 1회**: 앞부분(front) 답변 후(`requiresAdjustmentAfter`, 기본 7문항)
  easier / same / harder 선택 → 뒷부분(tail) 문제를 그 난이도로 생성.
  (`MockExamViewModel` phase `.adjustment`, 서버 `adjust_mock_session`)
- 문항당 타이머 **180초**(`remainingSeconds = 180`).
- 세션 단계: `awaiting_start_ad → generating_front → answering_front → awaiting_adjustment_ad →
  generating_tail → answering_tail → awaiting_result_ad → evaluating → completed`.
  무료 플랜은 start/adjustment/result 3개 광고 게이트, 유료는 auto-verify로 광고 없이 통과.
- 진행 중 세션 복원 가능(`currentMockSession`, "이어서 하기").

### 데일리 연습
- 데일리 문제 세트는 **Q2~Q15의 14문항 풀**이며 **introduction(자기소개) 문항을 포함하지 않는다**
  (`validate_daily_pool`). 진행바에 표시되는 번호는 인덱스가 아니라 **실제 문항 번호 Q2~Q15**다.
- **토큰 = 하루에 받을 수 있는 "새 문제 세트" 수.** 세트 생성(초기 로드 + 리프레시)에서 1토큰 소모,
  **세트 안에서의 평가(분석)는 무제한**(`reserve_request`, 쿼터 미차감).
  (`routes.py` `reserve_practice` vs `reserve_request`)
- 리프레시는 광고가 아니라 토큰 소모이며, 다이얼로그에서 easier/same/harder를 고를 수 있다
  (`DailyRefreshDialog`).
- 문항 간 앞뒤 이동 가능하며, 이미 분석한 문항은 저장된 결과를 다시 볼 수 있다(`analyzedResults`).

---

## 6. 발화 → 분석 파이프라인 [VERIFIED]

- **STT는 온디바이스 Apple Speech**(`SFSpeechRecognizer(locale: en-US)`), 부분 인식 결과 스트리밍,
  구두점 자동 삽입(`addsPunctuation`), `.record` 카테고리 + `.default` 모드.
  마이크·음성인식 권한 필요. (`Services/Speech/SpeechRecognitionService.swift`)
- 녹음 원본 오디오는 파일로 저장되어 평가 요청에 함께 업로드되고, 서버가 **ffprobe/ffmpeg로
  발화 길이·무음 비율·WPM(`AudioMetrics`)** 을 계산한다. (`app/services/audio.py`)
- 문제 프롬프트 읽어주기는 **AVSpeechSynthesizer(en-US) TTS**. (`Services/Audio/PromptPlaybackService.swift`)
- 데일리 평가 결과(`PracticeEvaluation`): `predictedLevel`, `confidence`, 5개 점수
  (taskFulfillment / grammar / vocabulary / discourse / fluency), `strengths`, `improvements`,
  `correctedAnswer`, `targetGap`, `sampleAnswer`, `rubrics`, `audioMetrics`, `disclaimer`.
- 모의고사 결과(`MockEvaluation`): 위 항목 + `overallFeedback` + **문항별 피드백/모범답안(perQuestion, 1~15)**.
- 예상 등급에는 **IL 하한 클램프**가 있다(`_clamp_min_level`).

---

## 7. 구독 · 사용량 정책 (production behavior — 임의 변경 금지) [VERIFIED]

서버 `app/services/plans.py`가 **단일 진실 소스**이고, 클라이언트는 `/v1/capabilities`의
`plan` + `quotaPolicy`로 UI를 게이팅한다. 최종 판정은 항상 서버다.

### 7.1 데일리 토큰 (제품 정의)

**데일리 토큰 1개 = 새로운 Daily 문제 세트 1개.**

- 토큰은 **세트를 받을 때** 1개 소모된다. 하루 첫 세트 생성과 리프레시(새 문제 받기 ·
  난이도 조정)가 모두 여기에 해당한다. (`routes.py` `create_practice_set` /
  `refresh_practice_set` → `reserve_practice`)
- 한 번 시작한 세트 안에서는 **답변 기록 · 채점(평가) · 결과 열람에 토큰이 들지 않는다.**
  세트 내 평가 횟수는 제한이 없다.
- **모의고사는 데일리 토큰과 별개**다. 플랜별 모의고사 횟수로만 제한된다.
- UI 문구는 항상 "데일리 토큰"이다. `quota` · `credit` · `practice_credit` ·
  `reward intent` · `reserve_practice` 같은 구현 용어는 사용자에게 노출하지 않는다.
  반대로 백엔드 식별자를 마케팅 용어로 개명하지도 않는다.

### 7.2 플랜별 실제 강제 한도

| | 무료(free) | 베이직(basic) | 플러스(plus) | 프로(pro) |
|---|---|---|---|---|
| 현재 실판매가(월) | 0 | ₩2,900 | ₩4,900 | ₩7,900 |
| 데일리 토큰/일 | 1 (+광고 보너스 1) | 3 | 10 | 20 |
| 모의고사 | **평생 최초 1회 체험** | 1회/일 | 3회/일 | 5회/일 |
| 모의고사 광고 게이트 | 있음(3회) | 없음 | 없음 | 없음 |
| 광고 노출 | 있음 | 없음 | 없음 | 없음 |
| 분석 depth | `summary` | `full` | `full` | `full` |
| 취약점 복습 세트 (`review_set`) | ✗ | ✗ | ✗ | 서버만 허용 (앱 진입점 없음) |
| `history_days` (capabilities 값) | 7 | 30 | 30 | 전체 |

- 가격은 **`package.storeProduct.localizedPriceString`(RevenueCat)에서만** 온다.
  클라이언트에 원화 상수를 두지 않는다(`PlanEntitlement.monthlyPriceKRW`는 삭제됨).
- 시험 대비 패스는 `exam_pass` 엔타이틀먼트 → **pro 동급**으로 매핑된다(신규 발급 없음).
- **결과 화면 잠금은 무료↔유료 한 곳뿐**이다(`ResultUnlock.showsCoaching = plan.isPaid`).
  교정 답안 · 모범 답안 · 목표 갭이 유료 전용이고, 유료 플랜끼리는 분석 내용이 같다.
  서버도 depth가 `summary`면 이 셋을 **생성하지 않는다**(AI 비용 절감).

### 7.3 강제되지 않는 항목 — 페이월에서 광고하지 않는다

| 항목 | 상태 | 페이월 노출 |
|---|---|---|
| 학습 기록 보관 기간 (7일/30일/전체) | `historyDays`가 capabilities에 있으나 **서버에 기록 조회 API 자체가 없다**. 기록은 기기 로컬 SwiftData이며 `trimPracticeHistory`가 전 플랜 동일하게 최근 50건만 남긴다 | **제거됨** |
| 취약점 복습 세트 | 서버 `/v1/question-sets/review`는 프로 전용으로 강제되지만, **앱이 이 엔드포인트를 호출하는 화면이 없다** | **제거됨** |
| 리프레시 리워드 상한 (`refresh_ad_bonus`) | 리프레시는 이제 데일리 토큰을 소모하고 광고 리워드를 쓰지 않는다. 별도 혜택이 아니다 | 노출 안 함 |

이 세 항목은 backlog다. 앱에서 실제로 도달 가능해지는 시점에 페이월 문구로 되살린다.
`DailyOPIcTests/PaywallTests.swift`의 `copyNeverPromisesUnenforcedBenefits`가 회귀를 막는다.
- **스마트 기능(예상 등급 추이 · 취약 유형 분석 · 주간 리포트)은 전 플랜 무료 공개**다.
  `StudyInsightsSection`의 세 카드 모두 `locked: false`이고, 페이월에도 그렇게 명시되어 있다.
  **리뉴얼에서 이걸 다시 잠그지 않는다.**
- 결제: RevenueCat SPM 패키지가 **현재 프로젝트에 실제로 연결되어 있다**
  (`XCRemoteSwiftPackageReference "purchases-ios"` + `RevenueCat in Frameworks`).
  RevenueCat App User ID = Firebase uid.
- 웹훅: EXPIRATION·REFUND만 즉시 free 강등. CANCELLATION·BILLING_ISSUE는 `expiresAt`까지 유지.
- 플랜 변경 즉시 반영: 포그라운드 복귀(`scenePhase == .active`) 및 `plan` 변경 시 usage/capabilities 재조회.
- 통계 탭의 기간 필터(최근 7일 / 30일 / 전체)는 **로컬 기록 기준이며 플랜으로 잠기지 않는다.**
  `historyDays`는 capabilities 모델에 디코딩만 되어 있고 클라이언트 게이팅에 쓰이지 않는다.

---

## 8. 서버에 있으나 앱에 노출되지 않은 것 [VERIFIED · 미노출]

- `POST /v1/question-sets/review` (**취약점 복습 세트**, `focusDimension` 기반, pro 전용 `review_set` 플래그):
  서버에 구현되어 있으나 **iOS 코드에서 호출하는 곳이 없다.**
  → 리뉴얼에서 "있는 기능"으로 디자인하지 않는다. 새로 노출하려면 별도 의사결정이 필요하다.
- `mock_comparison`(모의고사 비교)은 플랜 플래그만 있는 v2 준비값이며 화면이 없다.

---

## 9. 접근성 — 기본 품질 기준 [방향]

접근성은 별도 기능이 아니라 **SwiftUI 구현의 기본 요구사항**이다. 최소 기준:

- VoiceOver: 의미 있는 accessibility label/value/hint, 장식용 요소는 숨김
- Dynamic Type: 큰 글자에서 잘리거나 겹치지 않을 것 (`fixedSize(horizontal:vertical:)` 적극 사용)
- 충분한 contrast (라이트/다크 모두)
- Reduce Motion 고려 — 애니메이션/로딩 인디케이터 대체 경로
- 충분한 touch target (최소 44×44pt)
- Light Mode / Dark Mode 모두 지원

현재 상태 [VERIFIED]:
- 색상은 이미 라이트/다크 동적 대응(`Resources/Colors/AppPalette.swift`가 dynamic UIColor provider 사용).
- `accessibilityReduceMotion`은 4개 파일에서만 사용(`OPIcGuideView`, `AILoadingOverlay`,
  `RecordingButton`, `AppLoadingIndicator`).
- accessibility label/value/hint 계열 호출은 앱 전체 **16건 / 7개 파일**뿐이다.
  → **접근성은 현재 부분 적용 상태이며, 리뉴얼의 실질적인 개선 대상이다.**

---

## 10. 리뉴얼에서 지켜야 할 원칙 [방향]

지킬 것:
1. 기존 기능과 production behavior를 **우선 보존**한다.
2. 데이터 구조(SwiftData 스키마, Firestore 필드, API 계약)를 UI 작업 편의로 바꾸지 않는다.
   기존 사용자의 로컬 학습 기록이 마이그레이션 없이 살아남아야 한다.
3. 구독/사용량/광고 정책(§7)을 임의로 바꾸지 않는다. 바꿔야 한다면 서버 `plans.py`와 함께,
   별도 의사결정으로 진행한다.
4. 접근성은 기본값으로 적용한다(§9).

바꿔도 되는 것:
- 화면 레이아웃, 정보 위계, 카피, 컴포넌트, 내비게이션 흐름, 시각 언어 — **UI/UX는 전반적으로 개선 가능**.
- 특히 §5에 적힌 카피 불일치(난이도 변경 광고 문구)는 고쳐야 한다.

하지 말 것:
- 현재 구현되지 않은 기능을 디자인을 위해 만들어내기(특히 §8 항목).
- 한국어 UI를 억지로 다국어 구조로 전환하기.
- 실제 OPIc 시험을 완전 재현한다고 표기·암시하기.

---

## 11. 열린 질문 (결정 필요) [미확인]

1. 이 PRODUCT.md의 최종 위치 — 현재 위치는 두 git 저장소 밖이라 버전 관리되지 않는다.
2. 취약점 복습 세트(§8)를 이번 리뉴얼에서 노출할지 여부.
3. 학습 기록이 기기 로컬 전용인 점을 UI에서 어디까지 명시할지(기기 변경 시 기록 유실).
4. 난이도 변경 카피 수정 시 무료/유료 분기를 어디까지 문구로 드러낼지.

---

## 12. 페이월 V2 (Paywall V2) [구현됨 · G1]

`Views/Screens/Paywall/PaywallView.swift` + `PaywallPlan.swift`.

### 12.1 해결한 문제

이전 페이월은 네 개의 큰 티어 카드를 세로로 늘어놓고 사용자가 직접 값을 비교해
가치를 계산하게 하는 **사양서**였다. V2는 여섯 개 질문에 순서대로 답한다.

1. 데일리 토큰이 뭔가 → 2. 몇 개 받나 → 3. 어떤 플랜이 나에게 맞나
→ 4. 그 플랜의 의미 있는 혜택은 → 5. 얼마인가 → 6. 어떻게 구독하나

### 12.2 정보 구조

```
헤더            데일리오픽 프리미엄 / "내 학습량에 맞는 플랜을 선택하세요." / 현재 플랜 배지
데일리 토큰 설명  토큰 1개 = 새로운 Daily 문제 세트 1개
                한 번 시작한 세트의 답변·채점에는 추가 토큰 없음 / 모의고사는 별개
플랜 셀렉터      베이직 · 플러스 · 프로 (칩 3개 가로 배치, 하나만 선택)
선택 플랜 상세    선택된 유료 플랜 하나만 이름 · 포지셔닝 · 현지화 가격 · 혜택 4줄
무료 플랜        컴팩트 1블록, 구매 CTA 없음. 현재 플랜이면 "현재 이용 중" 표시
모든 플랜 비교    DisclosureGroup(기본 접힘) — 토큰 · AI 분석 · 모의고사 · 광고 4행
푸터            구독 관리(유료만) · 구매 복원(항상) · 개인정보 · EULA · 자동갱신 고지
sticky CTA      safeAreaInset(.bottom) — "<플랜명> 시작하기"
```

- 선택 상태는 **색만으로 표시하지 않는다**: 체크 기호 + 2pt 테두리 + 굵기 변화 +
  `.isSelected` accessibility trait.
- 비교표는 4열 그리드가 아니라 항목별 세로 스택이다. 작은 iPhone 폭 + 큰 Dynamic Type에서
  4열은 반드시 깨진다.
- 미래에 개인화 추천 블록을 얹을 수 있도록 셀렉터/상세가 분리돼 있다. **지금은 계산하지 않는다.**

### 12.3 포지셔닝 문구 (상시 · 기간 한정 아님)

| 플랜 | 포지셔닝 |
|---|---|
| 무료 | 가볍게 시작해 보기 |
| 베이직 | 매일 꾸준히 준비 |
| 플러스 | 시험 전 집중 준비 |
| 프로 | 가장 많이 연습하기 |

프로의 "약점까지 관리"는 §7.3 대로 앱 진입점이 없어 **쓰지 않는다.**

### 12.4 삭제한 문구

- "오픈 기념 할인" 배지, "오픈 초기 특가 진행 중 — 지금 가장 저렴하게 시작하세요."
  → RevenueCat에 오퍼·할인·무료 체험이 **하나도 설정돼 있지 않다.** 정가 판매다.
- 학습 기록 보관 기간(7일/30일/전체) 4줄 → §7.3.
- 클라이언트 가격 상수 `PlanEntitlement.monthlyPriceKRW` → 삭제.

`PaywallTests.copyContainsNoFakePromotionOrUrgency`가 회귀를 막는다.

### 12.5 페이월 진입점 (`PaywallSource`)

| 소스 | rawValue | 진입 위치 |
|---|---|---|
| `.settings` | `settings` | `PracticeScreen` 툴바 왕관 버튼 |
| `.tokenExhausted` | `token_exhausted` | `PracticeViewModel.handleRefreshQuotaExhausted` (유료 소진 · 광고 보너스까지 소진) |
| `.resultLocked` | `result_locked` | `PracticeResultView` 잠금 섹션 |
| `.mockLimit` | `mock_limit` | `MockExamScreen` 모의고사 한도 안내 |

현재 앱의 페이월 진입점은 이 넷이 전부이며 **모두 커버된다.**
`.calendarLocked`는 캘린더 출시 시 추가한다(지금 만들지 않는다).

---

## 13. 구매 퍼널 계측 (G0) [구현됨]

**새 분석 벤더를 붙이지 않았다.** 이 앱에 연결된 Firebase 제품은 Core · Auth · AppCheck
뿐이고 **FirebaseAnalytics는 링크돼 있지 않다.** 이미 쓰고 있는 구조화 OSLog
(`Services/Analytics/AppTelemetry.swift`)에 이벤트를 추가했다. 매출 지표는 RevenueCat
대시보드가 이미 갖고 있으므로 중복 구축하지 않는다.

| 이벤트 | 파라미터 |
|---|---|
| `paywall_view` | `source` |
| `plan_selected` | `plan`, `source` |
| `purchase_started` | `plan`, `source` |
| `purchase_success` | `plan`, `source` |
| `purchase_failed` | `plan`, `source`, `error_category` |
| `restore_started` | — |
| `restore_success` | `plan` |
| `restore_failed` | `error_category` |

- `error_category`는 `PurchaseErrorCategory` 고정 집합(`cancelled` · `not_configured` ·
  `no_active_subscription` · `unknown`)이다. 원본 오류 문자열은 스토어·네트워크 자유 텍스트라
  스키마가 되지 않으므로 로그에 남기지 않는다.
- **절대 로그하지 않는 것**: 전사(transcript) · 오디오 · 사용자 답변 · UID(전체/부분) ·
  기타 개인정보. 파라미터는 전부 고정 enum이다.
- 한계: OSLog는 원격 수집이 되지 않는다. 실제 퍼널 전환율이 필요해지면 별도 PR에서
  수집 백엔드를 결정한다. 지금 반쪽짜리 수집기를 만들지 않는다.

---

## 14. 향후 가격 (문서화만 · 아직 적용 금지) [계획]

캘린더 출시 이후 목표 가격:

| 플랜 | 현재 실판매가 | 목표가 |
|---|---|---|
| 베이직 | ₩2,900 | **₩3,900** |
| 플러스 | ₩4,900 | **₩6,900** |
| 프로 | ₩7,900 | **₩9,900** |

- **App Store Connect · RevenueCat 상품을 아직 바꾸지 않았다.**
- 페이월은 **StoreKit/RevenueCat이 실제로 반환하는 현지화 가격만** 표시한다.
  스토어가 아직 옛 가격을 반환하면 옛 가격이 보이는 게 맞다. 가짜 미래 가격을
  하드코딩하지 않는다.
- **기존 구독자 그랜드파더링이 선호 정책**이다(가격 인상 시 기존 구독자는 기존가 유지).
  StoreKit 자동 갱신 구독의 가격 인상은 기존 구독자에게 동의 절차가 필요하므로,
  마이그레이션은 별도 PR(G7)에서 설계한다.

---

## 15. 로드맵 · 이번 PR 범위 [계획]

| 단계 | 내용 | 상태 |
|---|---|---|
| **G0** | 구매 퍼널 계측 | **이번 PR 완료** |
| **G1** | 페이월 V2 | **이번 PR 완료** |
| G2 | 캘린더 기반(Calendar Foundation) | 다음 PR · **이번 PR에서 착수 금지** |
| G3 | 적응형 캘린더 플래너 | 이후 |
| G4 | 캘린더 플랜 게이팅 | 이후 |
| G5 | 알림 | 이후 |
| G6 | 네이티브 App Store 평점 요청 | 이후 |
| G7 | 가격 마이그레이션(§14) | 이후 |
| G8 | 캘린더 인텔리전스 V2 | 이후 |

### 15.1 향후 캘린더 플랜 게이팅 (계획일 뿐 · 구현 없음)

| 플랜 | 캘린더 |
|---|---|
| 무료 | 기본 캘린더 |
| 베이직 | 개인화 일정 · 결석일 재계획 |
| 플러스 | 적응형 플랜 · 모의고사 스케줄링 · 시험일 역산 계획 |
| 프로 | 취약점 플래너 · 취약점 복습 스케줄링 · 주간 학습 인텔리전스 |

**이 표는 로드맵 문서 전용이다.** 페이월에 캘린더를 혜택으로 노출하지 않으며,
`PaywallTests.copyNeverPromisesUnenforcedBenefits`가 "캘린더"·"일정" 문구를 차단한다.

### 15.2 이번 PR에서 명시적으로 제외한 것

캘린더 탭 · 캘린더 온보딩 · 캘린더 영속화 · 예측 엔진 · 학습 시간 계산 ·
결석일 재조정 · 학습량 재분배 · 적응형 플랜 · 취약점 플래너 · 캘린더 플랜 잠금 ·
푸시 알림 · App Store 평점 요청 · 신규 StoreKit 가격 · RevenueCat 상품 변경 ·
App Store Connect 변경 · 그랜드파더링 마이그레이션 · 주간 AI 리포트.
