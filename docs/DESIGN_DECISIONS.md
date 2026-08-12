# DailyOPIc — DESIGN DECISION LOCK

작성일: 2026-08-08
근거 문서: `docs/PRODUCT.md`, `docs/audit/UI_BASELINE_AUDIT.md`
조사 범위: iOS(`DailyOPIc/DailyOPIc`) + FastAPI(`DailyOPIc-BE/app`) + RevenueCat(READ-ONLY MCP)
상태: **결정 잠금 문서. 코드/외부 리소스 변경 없음. DESIGN.md 미생성.**

이 문서는 UI 리뉴얼 전에 확정해야 하는 8개 기술 선행조건(T1–T8)에 대해
**(a) 코드로 확인된 현재 사실**과 **(b) 디자인 전에 내려야 하는 결정**을 분리한다.
"VERIFIED CURRENT STATE"에 쓰인 것은 전부 파일·라인 근거가 있는 사실이며 추정이 아니다.

---

## T1 — Navigation / session preservation

### VERIFIED CURRENT STATE

**루트 구조 (`Views/AppRootView.swift:6-38`)**

```swift
Group {
    switch environment.launchState {
    case .launching:  SplashView()
    case .failed:     AuthRecoveryView(...)
    case .ready:
        if environment.preferences.isPresentingGuide {
            OPIcGuideView(...)                              // ← MainTabView를 '대체'
        } else if hasCompletedOnboarding, !isPresentingLevelSelection {
            MainTabView(environment: environment)
        } else {
            OnboardingView(environment: environment)        // ← MainTabView를 '대체'
        }
    }
}
```

`Group { switch }`는 분기별로 **다른 뷰 아이덴티티**를 만든다. 따라서 가이드/온보딩이 켜지는 순간
`MainTabView`는 뷰 트리에서 제거된다.

**세션 state의 소유자 (`Views/Screens/Main/MainTabView.swift:5-13`)**

```swift
@State private var practiceViewModel: PracticeViewModel
@State private var mockViewModel: MockExamViewModel
@State private var selectedTab = 0

init(environment:) {
    _practiceViewModel = State(initialValue: PracticeViewModel(environment: environment))
    _mockViewModel = State(initialValue: MockExamViewModel(environment: environment))
}
```

두 ViewModel은 `MainTabView`의 `@State`가 유일한 소유자다. `MainTabView`가 사라지면 즉시 해제된다.
함께 사라지는 것: `questionSet`, `questionIndex`, `analyzedResults`(`PracticeViewModel.swift:68`),
`evaluation`, `pendingRecording`, `usage`, `speech`(녹음 중인 `AVAudioEngine` 포함), `selectedTab`.

**MainTabView를 파괴하는 실제 진입점 2개**

| 경로 | 코드 | 결과 |
|---|---|---|
| 설정 → "도움말 다시 보기" | `SetupView.swift` → `dismiss()` + 0.2s 후 `preferences.beginGuide()` → `AppPreferences.swift:130` `isPresentingGuide = true` | 루트가 `OPIcGuideView`로 교체 |
| 설정 → "난이도 바꾸기" | `SetupView.openGoalLevelOnboarding()` → `preferences.resetOnboarding()` → `AppPreferences.swift:126` `isPresentingLevelSelection = true` | 루트가 `OnboardingView`로 교체 |

**반대로, 파괴하지 않는 경로**: `SetupView` 자체는 탭 내부에서 `.sheet`로 뜨므로 세션을 유지한다.
`PaywallView`도 `.sheet`(`PracticeResultView`, `ProgressScreen`, `MockExamScreen:90`)이므로 유지한다.
즉 **문제는 "설정 진입"이 아니라 "설정 안의 두 액션"이다.** 이는 1차 감사의 표현을 정정한다.

**부분 복구 능력**: `MockExamViewModel`은 서버 세션(`currentMockSession`) + SwiftData 드래프트
(`persistence.saveDraft`, `MockExamViewModel.swift:113-190`)로 재진입 시 상당 부분 복구된다.
`PracticeViewModel`은 **복구 수단이 전혀 없다** — 드래프트 저장 코드가 존재하지 않는다.
데일리 세트는 서버에서 재생성되며(`load()`가 `createPracticeSet` 호출), 이는 토큰 재소모 위험 경로다.

### ROOT PROBLEM

전역 앱 모드(가이드/온보딩)가 **루트 뷰 교체**로 표현되어 있다.
가이드·목표등급 변경은 의미상 "잠깐 위에 뜨는 모달"인데, 구현상으로는 "앱 전체 화면 상태 전환"이다.
상태 소유권이 화면 계층과 일치하지 않는 것이 근본 원인이며, `NavigationStack`/`sheet` 선택 문제는
그 증상일 뿐이다.

### RECOMMENDED DIRECTION

1. **`MainTabView`를 `.ready`의 유일한 자식으로 고정한다.** 가이드/목표등급 변경은 루트 분기가 아니라
   `MainTabView` 위의 **`.fullScreenCover`** 로 제시한다.
   - `sheet`이 아니라 `fullScreenCover`인 이유: 두 화면 모두 (a) 몰입형 온보딩이고 (b) 스와이프 다운으로
     중도 이탈하면 안 되며(목표등급 변경은 광고/서버 상태 변경을 동반) (c) 탭바가 보이면 안 된다.
   - `OPIcGuideView`는 읽기 전용이므로 `sheet`도 가능하지만, 두 화면의 제시 방식을 통일하는 편이
     구현·QA 비용이 낮다.
2. **세션 state를 root보다 오래 살게 만든다.** `PracticeViewModel`/`MockExamViewModel`의 소유자를
   `MainTabView.@State` → `AppEnvironment`의 `let` 프로퍼티로 올린다. `AppEnvironment`는
   `DailyOPIcApp`이 소유하므로 앱 생명주기 전체를 산다.
   - 이 한 번의 이동으로 T1이 구조적으로 해결된다. 이후 어떤 화면을 어떻게 띄우든 세션은 파괴되지 않는다.
   - `@Observable` 클래스이므로 `@State` → `let` 이동에 뷰 코드 변경이 거의 필요 없다.
3. **아키텍처 경계 선언**: "루트 분기는 *인증/부팅 상태*만 표현한다. *제품 모드*는 절대 루트 분기로
   표현하지 않는다." — 이것이 리뉴얼에서 지켜야 할 불변식이다.
4. **`PracticeViewModel`에도 최소 드래프트**를 둔다(현재 세트 id + questionIndex + analyzedResults).
   모의고사와 동일한 `PersistenceService` 패턴을 재사용하면 신규 스키마가 필요 없다.

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | 현행 유지 + 진입 전 "진행 중인 학습이 사라집니다" 경고 다이얼로그 | 데이터 손실을 사용자 책임으로 전가. 최악. |
| B | `NavigationStack` push로 가이드/온보딩 제시 | 탭바가 남고 뒤로가기 제스처로 중도 이탈 가능. 목표등급 변경(광고 소비 동반)에 부적합. |
| C | **`fullScreenCover` + ViewModel을 `AppEnvironment`로 승격** | 권장안. |
| D | `NavigationSplitView`/라우터 도입 | 3탭 앱에 과하다. 이 앱의 문제는 라우팅 부재가 아니라 상태 소유권이다. |

### REQUIRES PRODUCT DECISION

없음. 전부 기술 판단으로 결정 가능하다.

### DESIGN IMPACT

- 데일리 화면은 "언제든 이탈했다 돌아와도 그 문항 그대로"를 전제로 디자인할 수 있다 → 진행률 UI,
  "이어서 하기" 배너, 세트 소진 표시가 모두 신뢰 가능해진다.
- 설정은 "위험한 파괴적 화면"이 아니라 평범한 시트로 디자인해도 된다.
- 가이드/목표등급 변경은 **전체화면 모달 계열**로 시각 언어를 통일한다(탭바 없음, 명시적 닫기·완료 버튼).
- 모달 전용 규칙이 필요: 명시적 닫기 어포던스, `.accessibilityAddTraits(.isModal)`(현재 앱 전체 0건).

### IMPLEMENTATION SCOPE

- `AppRootView.swift`: `.ready` 분기 단순화 + `.fullScreenCover` 2개 부착. (~15줄)
- `AppEnvironment.swift`: ViewModel 2개 소유. (~6줄)
- `MainTabView.swift`: `@State` → `environment.practiceViewModel` 참조. (~6줄)
- `PracticeViewModel`: 드래프트 저장/복원. (~40줄, 선택)
- **API 계약 변경 없음. Firestore 스키마 변경 없음. 서버 변경 없음.**

---

## T2 — MockExam session lifecycle

### VERIFIED CURRENT STATE

**서버 스테이지 머신 (`app/api/routes.py`, `app/services/state.py`)**

```
awaiting_start_ad → generating_front → answering_front
   → awaiting_adjustment_ad → generating_tail → answering_tail
   → awaiting_result_ad → evaluating → completed
```

**questionSet의 실제 출처 (`routes.py:303-331` `_mock_session_response`)**

```python
question_set = None
set_id = record.get("setId")
if set_id:
    stored = await state_store.get_question_set(uid=..., set_id=str(set_id), mode="mock")
    if stored:
        question_set = _question_set_response_from_record(stored, ...)
```

→ **`setId`는 `start` 성공 시점에야 세션 레코드에 기록된다**(`routes.py:1252-1262`
`transition_mock_session(..., updates={"setId": ..., "setHash": ...})`).
즉 `stage == awaiting_start_ad`인 세션은 **정의상 `questionSet == null`이다.** 이것은 버그가 아니라 계약이다.

**클라이언트의 잘못된 가정 (`MockExamViewModel.swift:153-169`)**

```swift
private func enterResume(_ session: MockSession) async {
    var set = session.questionSet
    if set == nil { set = (try? await api.currentMockSession())?.questionSet }
    guard let set else {
        phase = .introduction
        errorMessage = "이어서 진행할 문제를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        return
    }
```

`enterResume`은 **모든 스테이지를 "문제셋이 이미 있는 상태"로 가정**한다.
`awaiting_start_ad` 세션이 들어오면 두 번째 조회도 당연히 `nil`이고, 무의미한 재시도 안내로 끝난다.

**"광고 소비 후 questionSet 없음" 재현 경로 (확정)**

1. 무료 사용자가 "설문 선택하고 시작" → `performStart` (`MockExamViewModel.swift:221-282`)
2. `api.createMockSession()` 성공 → 서버에 `stage=awaiting_start_ad` 세션 **영구 생성**
3. `acquireRewardNonce(.mockStart)` → **리워드 광고 1편 시청 완료** (무료 플랜)
4. `api.startMockSession()`이 실패
   (409 `mock_session_processing` / 네트워크 / AI 문제생성 실패 / 402)
5. `catch` (`:274-281`) → `phase = .introduction`, `errorMessage` 표시.
   **이 catch 블록은 `self.session`을 세팅하지 않는다.** 성공 경로(`:261`)에서만 세팅되기 때문이다.
6. 결과 화면 상태:
   - `canResume` = `session != nil && ...` → **false** → "이어서 하기" 버튼 없음
   - `canResetExam` = `questionSet != nil || !answers.isEmpty` → **false** → 툴바
     **"모의고사 포기" 버튼도 없음** (`MockExamScreen.swift:44-51, 118-121`)
   - 남은 버튼은 "설문 선택하고 시작" 뿐 → 다시 누르면 `createMockSession`이 기존 active 세션을 반환하고
     `stage == awaiting_start_ad`이므로 **또 광고를 본다**
7. 탭을 나갔다 오면 `restoreDraftIfAvailable()`(`:113-133`)이 `currentMockSession()`으로 그 세션을 찾아
   `enterResume`에 넘긴다 → `questionSet == nil` → 위 오류 문구. **여기서는 `session`이 세팅되므로
   `canResume == true`가 되어 "이어서 하기"가 보이지만, 누르면 같은 실패를 반복한다.** 무한 데드엔드.

**리워드 예산에 재시도 여유가 0이다 (`app/services/plans.py:186-207`)**

```python
if purpose in {MOCK_START, MOCK_ADJUSTMENT, MOCK_RESULT}:
    return _MOCK_REWARD_GATES * limits.mock_daily      # free: 3 * 1 = 3
```

그리고 세 용도는 **같은 카운터 `mockRewardCount`를 공유한다**(`state.py:478-492`).
무료 사용자의 하루 리워드 인텐트 총량은 **정확히 3개**이고 시험 완주에 필요한 것도 **정확히 3개**다.
어느 단계든 한 번 실패해 재시도하면 4번째 인텐트가 필요해지고, `create_reward_intent`가
402 `reward_quota_exhausted`를 던진다(`routes.py:1761-1765`). → **평생 1회 체험이 소진 없이 봉인된다.**

**서버는 리워드를 환불한다 (`state.py:1161-1164`, `2145-2149`)**

```python
elif isinstance(source, str) and source.startswith("mock:"):
    ... transaction.update(reward_ref, {"consumed": False})
```

즉 `reserve_mock` 이후 실패하면 nonce의 `consumed`는 되돌아간다.
**그러나 클라이언트가 nonce를 버린다.** `performStart`의 catch는 `rewardNonce`를 보관하지 않으므로
재시도 시 새 인텐트를 만들고 광고를 다시 본다. 서버의 환불 설계가 클라이언트에서 무효화되고 있다.
(대조: 결과 게이트는 `EvaluationRetryContext`(`:7-10, 378-381`)로 nonce를 보관해 재시도한다.
**시작·조정 게이트에만 이 패턴이 빠져 있다.**)

**포기 경로는 존재한다 (1차 감사 정정)**
`resetExam()`(`MockExamViewModel.swift:450-466`)과 툴바 "모의고사 포기"
(`MockExamScreen.swift:44-51`) + `ResetMockExamDialog`가 실재한다.
문제는 **부재가 아니라 노출 조건**(`canResetExam`)이 데드엔드 상태를 커버하지 못하는 것이다.
또한 `resetExam()`은 **로컬만 정리하며 서버 세션을 종료시키는 API가 없다**(라우트 목록에 abandon/delete 없음).
서버 세션은 날짜가 바뀌어야 사라진다(`start_mock_session`이 `record.date != today`면 409 `mock_session_expired`).

**기타 확인 사실**
- `previousQuestion()`은 빈 함수(`:359`) — 모의고사에 뒤로가기가 없다(실전 OPIc와 일치하므로 의도적일 수 있음).
- 180초 타이머(`startAnswerTimer`, `:310-322`)는 만료 시 `toggleRecording()`을 호출해 **자동 제출**한다.
- `restore()`의 `currentIndex = min(answers.count, questions.count - 1)`(`:182`)는 중간 문항 스킵을
  가정하지 않으므로, 답변이 비연속이면 잘못된 문항으로 복귀할 수 있다.

### ROOT PROBLEM

**"세션이 존재한다"와 "문제셋이 존재한다"를 클라이언트가 동일시한다.**
서버 스테이지 머신에는 정당하게 문제셋이 없는 스테이지(`awaiting_start_ad`, `generating_front`)가
있는데, 클라이언트에는 그 스테이지에 대응하는 UI 상태가 없다.
여기에 **재시도 여유가 0인 리워드 예산**과 **nonce 폐기**가 겹쳐, 한 번의 일시적 실패가 영구적 손실이 된다.

### RECOMMENDED DIRECTION

**A. 클라이언트 상태 모델을 서버 스테이지에 1:1로 맞춘다 (UI/클라이언트만으로 해결 가능)**

`enterResume`을 스테이지 기반 라우터로 바꾼다:

| 서버 stage | 클라이언트 도착 지점 |
|---|---|
| `awaiting_start_ad` | 시작 게이트 화면 (**resume이 아님**) — 이미 만들어진 세션을 이어받아 광고/자동검증만 수행 |
| `generating_front` / `generating_tail` | 생성 대기 화면 + 폴링 |
| `answering_front` / `answering_tail` | 답변 화면 |
| `awaiting_adjustment_ad` | 난이도 조정 게이트 |
| `awaiting_result_ad` | 결과 게이트 |
| `evaluating` | 분석 중 |
| `completed` | 결과 |

**B. 실패해도 nonce를 버리지 않는다** — `EvaluationRetryContext` 패턴을 시작·조정 게이트에 확장한다.
서버가 이미 `consumed=false`로 환불하므로 **서버 변경 없이** 재사용 가능하다.
이것만으로 "실패 → 광고 재시청" 사이클의 대부분이 사라진다.

**C. 데드엔드에서 항상 탈출구를 보장한다** — `canResetExam`을
`phase != .completed && (session != nil || questionSet != nil || !answers.isEmpty)`로 넓히고,
`performStart`의 catch에서도 `self.session`을 보관한다.

**D. 서버 계약 변경이 필요한 것 (별도 결정 필요)**
1. `POST /v1/mock-exams/{id}/abandon` — 사용자가 명시적으로 포기할 때 서버 세션을 닫는다.
   현재는 로컬만 지워져 서버·클라이언트 상태가 갈라진다.
2. 리워드 예산 헤드룸 — 실패한 게이트를 카운트에서 제외하거나 상한을 올린다(→ 소유자 질문 Q4).

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | 오류 문구만 개선 | 데드엔드가 남는다. 부적합. |
| B | `awaiting_start_ad`면 클라이언트가 자동으로 start를 재호출 | 무료 사용자에게 광고를 강제 재생시킨다. 위험. |
| C | **스테이지 라우팅 + nonce 보존 + 탈출구 보장** (권장) | 서버 변경 없이 P0 해소. |
| D | 세션 생성을 광고 이후로 미룬다 | 서버 계약 대수술. 멱등성·중복 세션 위험. 비권장. |

### REQUIRES PRODUCT DECISION

- 무료 리워드 예산의 재시도 헤드룸 (→ **Q4**)
- 포기 시 무료 "평생 1회 체험"을 복구할지 (→ **Q9**)

### DESIGN IMPACT

- 모의고사 화면은 **9개 스테이지 각각에 대응하는 화면 상태**를 가져야 한다. 현재 8개 `Phase`로는 부족하다.
  특히 "세션은 있는데 아직 시작 전"(시작 게이트 재진입)과 "생성 중"이 별도 상태로 필요하다.
- **모든 게이트 화면에 3개 버튼**이 있어야 한다: 계속 / 나중에(탭 이탈 안전) / 포기.
- 광고 게이트 진입 전에 **"이 시험에 광고 N회 중 M번째"** 를 명시한다. 무료 사용자가 3회 예산을
  인지하면 중도 이탈로 인한 소실이 줄어든다.
- 진행 상태는 "n/15 문항"이 아니라 **"단계(시작 → 앞 7문항 → 난이도 조정 → 뒤 8문항 → 결과)"** 로
  표현해야 실제 상태 머신과 일치한다.

### IMPLEMENTATION SCOPE

- 클라이언트 전용(권장 A/B/C): `MockExamViewModel` `Phase` 확장 + `enterResume` 재작성 +
  nonce 보존 + `canResetExam` 확장. `MockExamScreen`에 신규 상태 뷰 2개. (~200줄)
- 서버 계약 변경(D): abandon 엔드포인트 신설, `plans.reward_max_for` 조정. **소유자 승인 후 착수.**

---

## T3 — Daily token / quota semantics

### VERIFIED CURRENT STATE

**토큰 1개 = 새 문제 "세트" 1개다. 답변/평가 1회가 아니다.**

- 세트 생성만 쿼터를 차감한다:
  `reserve_practice(uid, date_key, request_id, free_limit)` → `freeUsed += 1` 또는
  `bonusRemaining -= 1`, 소진 시 `UsageLimitExceeded` (`state.py:1046-1078`).
- 평가는 쿼터를 건드리지 않는다: `reserve_request(uid, request_id)`는 멱등성 레코드만 만들고
  `source="none"`이다 (`state.py:1080-1096`).
- 클라이언트도 이 계약을 알고 있다 — `PracticeViewModel.swift:213`:
  `// 토큰 모델: 토큰은 세트를 받을 때 소모되고, 세트 내 평가는 무제한. 여기서 쿼터 확인하지 않음.`
- **결론: 이미 발급된 세트 안의 14문항은 무제한으로 답변·재답변·재평가할 수 있다.**

**한 세트 = 데일리 Q2~Q15 (14문항).** Q1(자기소개)은 데일리 풀에 없다(`validate_daily_pool`).

**일일 리셋**: KST 자정. `_date_key()` = `datetime.now(KST).strftime("%Y%m%d")` (`routes.py:139-150`),
`resetsAt` = 다음 KST 00:00. **디바이스 로컬 타임존이 아니라 서버 KST가 기준이다.**

**플랜별 세트/일 (`plans.py:68-129`)**

| | free | basic | plus | pro |
|---|---|---|---|---|
| `practice_daily` (세트/일) | 1 | 3 | 10 | 20 |
| `practice_ad_bonus` (광고 보너스 세트) | 1 | 0 | 0 | 0 |
| **실효 세트/일** | **2** (광고 1회 포함) | 3 | 10 | 20 |
| `refresh_ad_bonus` | 1 | 10 | 20 | 30 |
| 세트 내 평가 | **무제한** | 무제한 | 무제한 | 무제한 |

**리프레시도 토큰을 쓴다** — 광고가 아니다. `performRefresh`는 곧바로 `refreshPracticeSet`을 호출하고
(`PracticeViewModel.swift:327` `// 토큰 모델: 새 문제 세트 = 토큰 1개. 광고/리워드 없이 바로 요청.`),
쿼터 소진 시에만 무료 플랜이 광고 보너스(`unlockPracticeCredits`, `purpose = .practiceCredits`)로
재시도하고 유료 플랜은 페이월을 띄운다(`:351-377`).

**UI가 "남은 문항"처럼 보이는 이유 — 확정**

`DailyTokenBadge`(`Views/Components/DailyTokenBadge.swift`)는
`count = usage.totalRemaining = dailyAnalysisFreeRemaining + dailyAnalysisRewardRemaining`
(`EvaluationModels.swift:147-150`)을 **"데일리 토큰"** 이라는 라벨로 표시한다.
서버 필드명이 `dailyAnalysisFreeRemaining`("분석" 잔여)이고, 이 컴포넌트의 doc comment 자체가
`/// Compact pill showing how many daily analyses the user has left.` 로 **틀려 있다.**
사용자가 보는 것은 "토큰 0"인데 진행바에는 미답변 문항이 9개 남아 있다 →
**표시 단위(세트)와 사용자 멘탈모델(문항/분석)이 어긋난 것이지, 계산 오류가 아니다.**

**죽은 정책 필드 2개 (확인됨)**
1. `usage.dailyRefreshRemaining`은 디코딩만 되고 **어떤 화면에서도 표시되지 않는다.**
   그리고 `RewardPurpose.practiceRefresh`는 **클라이언트에서 한 번도 요청되지 않는다**
   (전체 Swift 검색 결과: `practiceCredits`, `mockStart`, `mockAdjustment`, `mockResult`,
   `targetLevelChange`만 사용). → `refresh_ad_bonus`(free 1 / basic 10 / plus 20 / pro 30)는
   **현재 아무 효과가 없는 값이다.**
2. `quotaPolicy.historyDays`도 디코딩만 되고 게이팅에 쓰이지 않는다 (→ T6).

**PRODUCT.md vs plans.py 충돌 (실제 production contract 확인 결과)**

| 항목 | PRODUCT.md | `plans.py` | **실제 동작** |
|---|---|---|---|
| 취약 유형 분석 | 전 플랜 무료 | free/basic = `NONE`, plus = `BASIC`, pro = `ADVANCED` | **무료** (클라이언트가 `weaknessAnalysis`로 게이팅하지 않음) |
| 주간 리포트 | 전 플랜 무료 | pro만 `True` | **무료** (클라이언트 게이팅 없음) |
| 예상 등급 추이 | 전 플랜 무료 | free = `LIMITED` | **무료** (클라이언트 게이팅 없음) |
| 학습 기록 기간 | 로컬 기준, 미잠금 | 7/30/30/None | **미잠금** (로컬 SwiftData 기준) |

→ **실제 production contract는 PRODUCT.md 쪽이다.** `plans.py`의 해당 필드들은 서버가 계산해
`/v1/capabilities`로 내려보내지만 **클라이언트가 소비하지 않는다.** 다만 서버가 실제로 강제하는 것이
하나 있다: `analysis_depth`는 AI 생성 자체를 바꾼다 — summary/basic 깊이에서는 서버가
`correctedAnswer`/`sampleAnswer`/`targetGap`을 **아예 생성하지 않는다**(`ai.py:1669-1676`).
즉 **결과 잠금은 진짜이고, 스마트 기능 잠금은 서류상으로만 존재한다.**

### ROOT PROBLEM

단위 하나가 세 층에서 다른 이름으로 불린다: 서버 `dailyAnalysis*`(분석), UI "데일리 토큰"(토큰),
실제 의미 "새 문제 세트". "토큰"은 게임 재화 은유라 **소진 = 학습 불가**로 읽히지만,
실제로는 **소진 = 새 세트만 못 받음, 지금 세트는 계속 무제한 학습 가능**이다.
가장 중요한 사실(세트 내 무제한)이 UI 어디에도 없다.

### RECOMMENDED DIRECTION

1. **"토큰"이라는 단어를 전면 폐기한다.** 표시 단위를 **"오늘의 새 문제 세트"** 로 통일한다.
   - 홈: `오늘의 새 문제 · 2/2 남음` (또는 소진 시 `오늘의 새 문제를 다 썼어요`)
   - 반드시 병기: `지금 세트의 14문항은 계속 연습할 수 있어요`
2. **두 개의 게이지를 분리해 보여준다.**
   - 세트 게이지(플랜 한도, 하루 리셋) — 희소 자원
   - 세트 진행도(14문항 중 n개 분석 완료) — 무제한 자원
   현재 진행바 칩은 후자만 있고 "무제한"이라는 사실이 전달되지 않는다.
3. **게이팅 문구를 원인 기준으로 쓴다.** "토큰이 없습니다"가 아니라
   "오늘 새 문제 세트를 다 썼어요 — 광고를 보면 1세트 더 받을 수 있어요 / 내일 00시에 초기화돼요".
   리셋 시각은 **KST 기준임을 명시**한다(해외 사용자 혼선 방지).
4. **페이월의 플랜 차이는 "세트/일" 축으로 표현한다.** 현재 페이월 문구
   `데일리 새 문제 세트 하루 N회`는 이미 정확하다 — 홈이 페이월을 따라가야 한다.
5. **죽은 필드를 UI에 노출하지 않는다.** `dailyRefreshRemaining`, `historyDays`는
   실제로 강제되기 전까지 디자인 입력으로 쓰지 않는다.

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | "토큰" 유지 + 툴팁 설명 | 은유 자체가 틀렸다. 설명으로 덮을 수 없다. |
| B | **"새 문제 세트" 단위 + 세트 내 무제한 명시** (권장) | 서버 계약과 정확히 일치. |
| C | "분석 N회" 단위 | **서버 계약과 정반대다.** 평가는 무제한이므로 명백한 허위 표시. 금지. |

### REQUIRES PRODUCT DECISION

- 세트 내 무제한 평가 계약을 리뉴얼에서도 유지할지 (→ **Q3**)
- 스마트 기능을 `plans.py`대로 티어링할지, PRODUCT.md대로 전 플랜 무료 유지할지 (→ **Q7**)

### DESIGN IMPACT

- 홈 상단 배지가 **가장 중요한 카피 표면**이 된다. 여기 한 줄이 "토큰"이면 리뉴얼 전체가 오해된다.
- 진행바 칩(현재 22–24pt, 44pt 미달)은 "세트 내 무제한"을 표현하는 주 컴포넌트로 승격되므로
  터치 타깃·상태 표현(미답변/분석완료/현재)을 다시 설계해야 한다.
- 소진 상태는 **막다른 화면이 아니라 선택지 화면**이다(광고 보너스 / 업그레이드 / 현재 세트 계속).
- 유료 플랜에는 광고 보너스가 없으므로(`practice_ad_bonus = 0`) 소진 화면의 선택지가 달라진다.
  플랜별로 2가지 소진 화면이 필요하다.

### IMPLEMENTATION SCOPE

- 카피·컴포넌트 교체(`DailyTokenBadge` → 세트 배지), 소진 상태 뷰 2종.
- **서버 변경 없음. API 변경 없음.** `UsageStatus`는 이미 필요한 값을 전부 담고 있다.
- Q7이 "티어링 집행"으로 결정되면 클라이언트 게이팅 + 서버 검증이 추가로 필요하다(별도 범위).

---

## T4 — AI evaluation confidence policy

### VERIFIED CURRENT STATE

**서버가 실제로 계산하는 객관 신호는 4개뿐이다 (`app/services/audio.py`)**

```python
AudioMetrics(
    durationSeconds  = ffprobe format=duration,
    speakingSeconds  = duration - silence,
    silenceRatio     = silence / duration,          # ffmpeg silencedetect=noise=-40dB:d=0.5
    wordsPerMinute   = words / speaking * 60,       # words = re.findall(r"\b[A-Za-z']+\b", transcript)
)
```

- 오디오 파일이 없으면 **전부 전사 길이에서 역산한 추정치**다
  (`estimated = max(1.0, words / 130 * 60)`, `silenceRatio = 0`) — `audio.py:29-36`.
  이 경우 `silenceRatio`와 `wordsPerMinute`는 측정값이 아니다.
- ffprobe/ffmpeg 실패 시에도 조용히 같은 추정치로 폴백한다(`audio.py:69-70, 105-106`).
  **응답에는 "측정됨"과 "추정됨"을 구분하는 필드가 없다.**
- 발음/음소 분석은 존재하지 않는다. 프롬프트도 이를 금지한다:
  `"Use delivery metrics only for fluency, never claim phoneme-level pronunciation analysis."`

**`confidence`는 계산된 값이 아니다. LLM이 자유롭게 채우는 필드다.**

- `AIPracticeResult.confidence: ConfidenceBand` (`ai.py:173`), `ConfidenceBand = low|medium|high`
  (`models/api.py:87-90`).
- **평가 지시문 전체에 `confidence`를 어떻게 정하라는 문장이 단 한 줄도 없다**
  (`ai.py:1637-1660` 전문 확인). 루브릭 5차원에는 상세한 앵커가 있지만 confidence에는 없다.
- 서버는 이 값을 **검증하지도, 보정하지도, 후처리하지도 않는다.** `result_dump`에 그대로 실려 나간다.
- 목업 모드(`self._mock`)에서는 항상 `ConfidenceBand.MEDIUM` 하드코딩(`ai.py:1614`).

**3단어 답변이 높은 예상 등급을 받는 경로 — 전 구간 확정**

1. **입력 게이트 없음.** 최소 단어 수/최소 발화 시간 검증이 클라이언트·서버 어디에도 없다.
   `SpeechRecognitionService.stop()`은 전사가 **빈 문자열일 때만** `SpeechError.noSpeech`를 던진다
   (`SpeechRecognitionService.swift:183-187`). "Yes I do."는 통과한다.
2. **등급 하한이 IL로 고정돼 있다.** `_clamp_min_level`(`ai.py:59-62`)이 NL/NM/NH를 전부 IL로 올린다.
   → **어떤 답변도 IL 미만을 받을 수 없다.**
3. **프롬프트가 상향 편향돼 있다.** `"Do not grade below IL; if borderline between two bands,
   choose the higher one."`(`ai.py:1650`)
4. **confidence에 근거가 없다.** 위 3단계를 거쳐 나온 `IL` 등급에 LLM이 임의로 `high`를 붙이면
   UI는 그대로 "신뢰도 높음"을 표시한다.
5. **루브릭 → 점수 변환이 5단계 이산값이다.** `RUBRIC_SCORE_BY_BAND = {foundation:20,
   developing:40, functional:60, strong:80, advanced:95}` (`ai.py:66-72`).
   → 통계 화면의 "취약 유형 분석" 항목들이 전부 `20`으로 동일하게 보인 것은 계산 오류가 아니라
   **모든 차원이 `foundation` 밴드였기 때문**이다. 점수가 아니라 밴드로 표시해야 정직하다.

### ROOT PROBLEM

**`confidence`는 신뢰도가 아니라 LLM의 자기 보고(self-report)다.**
실제로 신뢰도를 판단할 수 있는 객관 신호(발화 길이·단어 수·무음 비율·WPM·측정 vs 추정 여부)는
서버에 이미 존재하는데 confidence 결정에 **전혀 연결되어 있지 않다.**
게다가 IL 하한과 상향 편향 지시가 겹쳐, "평가할 것이 거의 없는 답변"과 "실제로 IL인 답변"이
출력상 구분 불가능하다.

### RECOMMENDED DIRECTION

**현재 데이터만으로 계산 가능한 3버킷을 서버에서 결정론적으로 산출한다.**
아래 신호는 전부 이미 존재한다. **새 점수·새 임계값을 발명하지 않는다** — 분류 기준은
소유자 승인 대상으로 남기고, 여기서는 *어떤 신호로 나눌 수 있는가*만 확정한다.

| 버킷 | 사용 가능한 신호 (전부 기존 데이터) | UI 취급 |
|---|---|---|
| **A. 평가 가능** | 단어 수·`speakingSeconds`가 충분, `silenceRatio` 정상, 오디오 메트릭이 **측정값**(추정 폴백 아님) | 등급 + 5차원 루브릭 + 피드백 전부 표시 |
| **B. 평가 신뢰 낮음** | 단어 수·발화 시간이 경계, 또는 `silenceRatio`가 높음, 또는 오디오 메트릭이 **추정 폴백** | 등급을 **참고치**로 강등 표시 + 왜 낮은지 명시 + "더 길게 답해보기" 유도. 등급 추이 통계에서는 제외 |
| **C. 평가 불가 · 다시 말하기 필요** | 전사 공백, 단어 수 극소, `speakingSeconds`가 최소 미만, STT 실패/중단 | **등급을 아예 표시하지 않는다.** 다시 녹음 유도만. 이력에 저장하지 않음 |

**현재 데이터로 즉시 가능한 것**
- 단어 수: `re.findall(r"\b[A-Za-z']+\b", transcript)` — `audio.py:28`에 이미 있다.
- `speakingSeconds`, `silenceRatio`, `wordsPerMinute` — `AudioMetrics`에 이미 있고 응답에도 실린다.
- 클라이언트는 `evaluation.audioMetrics`를 이미 받고 있으므로 **서버 변경 없이도 B/C 판정을
  클라이언트에서 표시만 할 수 있다**(단기 처방).

**새 백엔드 정책이 필요한 것**
1. **`AudioMetrics`에 `isEstimated: bool` 추가.** 지금은 측정 실패와 정상 측정이 구분 불가능하다.
   이것이 없으면 B 버킷 판정의 절반이 불가능하다. **가장 우선순위 높은 서버 변경.**
2. **`confidence` 산출을 LLM에서 서버 결정론으로 이관.** LLM 필드는 유지하되 응답 값은 서버가 덮어쓴다.
   임계값 자체는 소유자 승인 후 확정하고, 코드에는 단일 상수 테이블로 둔다.
3. **C 버킷은 AI 호출 전에 차단한다.** 평가 요청 자체를 400으로 반려하면 OpenAI 비용도 절감된다.
   현재는 3단어 답변에도 정상 요금이 발생한다.
4. **IL 하한(`_clamp_min_level`)은 유지하되 C 버킷과 분리한다.** "IL이다"와 "평가할 수 없다"는
   다른 진술이다. 지금은 후자가 전자로 위장돼 있다.

**점수 표시 정정(즉시 가능)**: 5차원을 `20/40/60/80/95` 숫자로 보여주지 않는다.
원본이 `foundation…advanced` 5밴드이므로 **밴드 라벨로 표시**한다. 숫자는 정밀도를 허위로 암시한다.

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | 현행 유지(LLM confidence 그대로) | 3단어 = "신뢰도 높음". 제품 신뢰 훼손. 부적합. |
| B | 프롬프트에 confidence 기준 문장 추가 | 비결정론적. 같은 입력에 다른 값. 회귀 테스트 불가. 비권장. |
| C | **서버 결정론 3버킷 + `isEstimated` 추가** (권장) | 테스트 가능·설명 가능·비용 절감. |
| D | 별도 품질 판정 LLM 호출 추가 | 비용 2배, 여전히 비결정론적. 비권장. |

### REQUIRES PRODUCT DECISION

- C 버킷(평가 불가)에서 결과를 **완전히 막을지**, 경고와 함께 보여줄지 (→ **Q2**)
- A/B/C 경계 임계값 자체 (Q2 결정 후 데이터 기반으로 별도 확정 — 지금 임의로 정하지 않는다)

### DESIGN IMPACT

- 결과 화면은 **1개가 아니라 3개**다. C 버킷은 "결과 화면"이 아니라 "다시 말하기 화면"이다.
- 등급 배지 옆에 신뢰 상태가 **색이 아닌 라벨+아이콘**으로 붙어야 한다(색 단독 신호 금지).
- B 버킷은 "실패"가 아니라 "더 말하면 정확해져요"라는 **코칭 톤**으로 설계해야 이탈이 줄어든다.
- 통계 화면의 등급 추이는 A 버킷만 집계한다 → 빈 상태·부분 집계 상태 디자인이 필요하다.
- 5차원을 밴드 라벨로 바꾸면 레이더/막대 차트 대신 **밴드 스케일 컴포넌트**가 필요하다.
- `disclaimer`("학습용 AI 예상치")는 이미 서버가 내려주며 계속 노출해야 한다.

### IMPLEMENTATION SCOPE

- 단기(클라이언트 전용): `audioMetrics`로 B/C 표시. (~60줄, 서버 변경 없음)
- 정식: `models/api.py`에 `isEstimated` 추가, `ai.py`에 결정론적 confidence, `routes.py`에 C 버킷 반려.
  (~120줄) — **응답 필드 추가이므로 하위 호환. 기존 앱 버전에 영향 없음.**

---

## T5 — Recording termination policy

### VERIFIED CURRENT STATE

**무음 감지도, 최대 녹음 시간도 구현되어 있지 않다.**
`SpeechRecognitionService.swift` 전문(268줄)을 확인한 결과 타이머·무음 임계값·자동 종료 로직이 없다.
`start()`는 `AVAudioEngine`을 켜고 `installTap`으로 무한히 버퍼를 흘려보낼 뿐이다.

**현재 존재하는 종료 트리거는 3개뿐이다**

| # | 트리거 | 코드 | 사용자에게 보이는 것 |
|---|---|---|---|
| 1 | 수동 정지 | `toggleRecording()` → `speech.stop()` | 정지 즉시 **자동 제출·분석 시작** |
| 2 | 180초 타임아웃 (**모의고사 전용**) | `MockExamViewModel.startAnswerTimer()` `:310-322` | 자동 정지 + 자동 저장 |
| 3 | 오디오 인터럽션 | `handleInterruption` `:231-238` | **아무것도 안 보인다** (아래) |

**데일리(Practice)에는 시간 제한이 전혀 없다.** `PracticeViewModel`에 타이머가 없다.

**"사용자 선언 없이 제출"의 정확한 정체**
`PracticeViewModel.toggleRecording()` (`:177-194`):
```swift
if speech.isListening {
    pendingRecording = try await speech.stop()
    try await evaluatePendingRecording()      // ← 정지와 제출 사이에 확인 단계가 없다
}
```
정지 버튼 = 제출 버튼이다. 전사를 확인하거나 다시 말할 기회가 없다.
(모의고사도 동일 — `saveAnswer()`가 즉시 호출되고 `previousQuestion()`은 빈 함수다.)

**인터럽션이 조용히 녹음을 파괴한다**
```swift
@objc private func handleInterruption(_ notification: Notification) {
    guard isListening else { return }
    interruptionReason = "통화 또는 다른 오디오로 ..."
    recordingState = .interrupted
    errorMessage = interruptionReason
    cancel()                    // ← 오디오 파일 삭제, 전사 초기화
    recordingState = .interrupted
}
```
- `AVAudioSessionInterruptionType`(`.began` / `.ended`)을 **읽지 않는다.**
  인터럽션 종료 알림에도 동일하게 반응한다.
- `interruptionReason`의 **소비처가 앱 전체에 0곳이다.** `errorMessage`도 뷰가 구독하지 않는다.
- 뷰는 `speech.isListening`(Bool)만 본다 — `PracticeScreen` 5곳, `MockExamScreen` 4곳.
- **결과: 통화가 오면 녹음이 사라지고 버튼만 조용히 원위치한다. 사용자는 이유를 알 수 없다.**

**6개 상태가 Bool 하나로 붕괴돼 있다**
`RecordingState { idle, recording, processing, interrupted, failed }` +
`PermissionState { unknown, granted, denied }`가 정의돼 있으나 UI는 `isListening`만 읽는다.
`permissionState == .denied`에 대응하는 화면이 없다 — 마이크 권한을 거부하면 버튼을 눌러도
에러 문자열만 스치고 복구 경로(설정 앱 링크)가 없다.

**STT의 숨은 종료**: `SFSpeechAudioBufferRecognitionRequest`는 무음이 지속되면 자체적으로
`isFinal` 결과를 낸 뒤 태스크를 종료한다. 그 이후 `installTap`은 계속 오디오를 파일에 쓰지만
`request.append(buffer)`는 무의미해진다. → **오디오는 길게 녹음되는데 전사는 어느 순간부터
늘지 않는다.** 이 상태를 감지하는 코드도, 사용자에게 알리는 UI도 없다.

### ROOT PROBLEM

말하기 앱인데 **말하기 상태를 표현하는 어휘가 `isListening: Bool` 하나다.**
정지·제출·중단·실패·권한거부가 전부 "버튼이 원래대로 돌아감"이라는 동일한 시각 신호로 붕괴한다.
자동 종료 정책의 부재보다 **상태 관측 가능성의 부재**가 더 근본적인 문제다.

### RECOMMENDED DIRECTION

**정책: D. 하이브리드 — 단, "자동 정지"와 "자동 제출"을 분리한다.**

| 트리거 | 동작 | 근거 |
|---|---|---|
| 수동 정지 | `recording → finishing` | 사용자 의도가 항상 최우선 |
| 최대 시간 도달 | 자동 정지 + **명시적 안내** ("제한 시간에 도달했어요") | 모의고사 180초는 이미 구현·검증됨. 데일리에도 상한 필요(무한 녹음 = 업로드 실패·비용 위험) |
| 무음 지속 | **자동 정지하지 않는다.** "아직 듣고 있어요" 힌트만 표시 | 학습자는 문장 사이에 길게 멈춘다. 무음 자동 정지는 오탐이 치명적 |
| 인터럽션 `.began` | `recording → interrupted`, **오디오 보존** | 지금은 삭제하고 있다 |
| 인터럽션 `.ended` | 사용자에게 "이어서 녹음" 제안 | 현재 `.began`과 구분 없음 |

**핵심: 정지 ≠ 제출.** `finishing` 이후 **전사 확인 단계**를 넣고 사용자가 "분석하기"를 눌러야
평가가 시작되게 한다. 세트 내 평가는 무제한이므로(T3) **재녹음에 비용이 들지 않는다** —
이 정책을 도입할 수 있는 이유가 여기 있다.

**제안 상태 모델 (8상태)**

```
ready ──start──▶ recording ──user stop / max time──▶ finishing
                    │                                    │
                    │ interruption(.began)               ▼
                    ▼                                processing        (STT 마무리 + m4a 압축)
                interrupted ──resume──▶ recording       │
                    │                                    ▼
                    │ discard                     (전사 확인 · 다시 말하기 / 분석하기)
                    ▼                                    │
                  ready                                  ▼
                                                    analyzing ──▶ result
                                                        │
                                                        ▼
                                                      error ──retry──▶ analyzing
```

- `ready`: 권한 확인 완료, 시작 가능. **권한 거부는 `ready`가 아니라 별도 `permissionDenied` 표면**
  (설정 앱 딥링크 포함).
- `recording`: 경과 시간 + 남은 시간 + 실시간 부분 전사 표시.
- `finishing`: 정지는 됐지만 STT 최종 결과 대기(현재 코드의 `Task.sleep(250ms)` 구간).
- `processing`: m4a 압축(`compressToM4A`) — 현재 진행 표시 없음.
- `interrupted`: **오디오 보존** + 원인 표시 + "이어서 / 버리고 다시".
- `analyzing` / `result` / `error`: 기존과 동일하되 재시도 경로 명시.

기존 `RecordingState` enum이 이미 `idle/recording/processing/interrupted/failed`를 갖고 있으므로
**모델 확장이 아니라 뷰가 그것을 읽게 만드는 것이 작업의 본체다.**

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | 수동 정지만 | 무한 녹음 방지 불가. 데일리에 상한이 없는 현재 상태 유지. 부적합. |
| B | 무음 자동 정지 | 학습자 특성상 오탐 치명적. 구현도 전무(신규 DSP 필요). 비권장. |
| C | 최대 시간 자동 정지만 | 절반의 해결. 인터럽션·권한거부 문제는 그대로. |
| D | **하이브리드 + 정지/제출 분리** (권장) | 기존 구현(180초 타이머)을 재사용하고, 비용 없이 재녹음 허용. |

### REQUIRES PRODUCT DECISION

- 위 정책 채택 여부와 **데일리 최대 녹음 시간** (→ **Q1**)
- 전사 확인 단계를 넣을지(= 정지와 제출 분리) — Q1에 포함

### DESIGN IMPACT

- 녹음 버튼은 **토글 하나가 아니라 상태 기계의 표면**이 된다. 8상태 각각의 시각·문구·햅틱·접근성
  발표(announcement)를 정의해야 한다.
- `recording` 중 **남은 시간**이 필요하다(색 단독 금지, 숫자 + 라벨).
- `interrupted`는 **오류가 아니라 복구 가능 상태**로 디자인한다. 현재는 존재조차 안 보인다.
- 권한 거부 전용 화면이 신규로 필요하다(현재 없음).
- Reduce Motion: 녹음 펄스 애니메이션은 `RecordingButton`이 이미 대응 중 — 신규 상태에도 확장.

### IMPLEMENTATION SCOPE

- `SpeechRecognitionService`: 인터럽션 타입 분기 + 오디오 보존 + 최대시간 타이머. (~60줄)
- `PracticeViewModel`/`MockExamViewModel`: `stop()`과 `evaluate()` 분리. (~40줄)
- `RecordingButton` + 녹음 영역: 8상태 렌더링. (~150줄)
- 권한 거부 화면 신규. (~60줄)
- **서버 변경 없음.**

---

## T6 — RevenueCat / Paywall contract

### VERIFIED CURRENT STATE (RevenueCat MCP, READ-ONLY 조회)

**프로젝트**: `Daily Opic` (`proja9f1eafc`) / 앱 `appb472d563ec` / bundle `com.mark.opicmobile`

**상품 3개 — 전부 월 구독, 그 외 상품 없음**

| product id | store identifier | 기간 | 무료 체험 | 유예기간 |
|---|---|---|---|---|
| `prod40dcf63e8f` | `opic_basic_monthly` | P1M | **없음** | **없음** |
| `prod33c73c4c6f` | `opic_plus_monthly` | P1M | **없음** | **없음** |
| `prodac433b739e` | `opic_pro_monthly` | P1M | **없음** | **없음** |

**엔타이틀먼트 3개**: `basic` / `plus` / `pro` — 각각 동명 상품 1개씩 연결. 전부 active.

**오퍼링 1개**: `default` ("DailyOPIc Plans", `is_current: true`, **`paywall_id: null`**)

| 패키지 | lookup_key | position | 상품 |
|---|---|---|---|
| `pkge41f3a3e2d0` | `pro_monthly` | 0 | opic_pro_monthly |
| `pkgec41bc24860` | `plus_monthly` | 1 | opic_plus_monthly |
| `pkge93ccd424ef` | **`$rc_monthly`** | 2 | opic_basic_monthly |

**현지화 가격 (KRW/KR 조회 결과)**: basic ₩2,900 · plus ₩4,900 · pro ₩7,900 —
`PlanEntitlement.monthlyPriceKRW` 및 PRODUCT.md와 **완전 일치**. 표시 가격 하드코딩 문제는 없다.
페이월은 `package.storeProduct.localizedPriceString`을 쓴다(`StoreService.swift:141`).

**클라이언트 매핑 검증 (`StoreService.highestPlan`)**
```swift
for raw in identifiers { let lower = raw.lowercased()
    for candidate in PlanEntitlement.allCases where candidate != .free {
        if lower.contains(candidate.rawValue), candidate > best { best = candidate } } }
```
- 패키지→플랜은 `[package.identifier, productIdentifier]` 양쪽을 본다.
  basic 패키지의 `identifier`는 **`$rc_monthly`로 "basic"을 포함하지 않지만**,
  `productIdentifier = opic_basic_monthly`가 매칭되어 정상 동작한다.
  **즉 basic 플랜은 상품 ID에만 의존하고 있어 취약하다** — 상품 ID가 바뀌면 조용히 `free`로 떨어진다.
- 엔타이틀먼트→플랜은 `info.entitlements.active.keys` = `basic|plus|pro` → 정확히 매칭.

**서버 매핑 (`plans.py:144-150`)**
```python
_ENTITLEMENT_TO_PLAN = {"basic": BASIC, "plus": PLUS, "pro": PRO,
                        "premium": PRO, "exam_pass": PRO}
```
- `premium`, `exam_pass`는 **RevenueCat 대시보드에 존재하지 않는다.** 서버만 아는 별칭이다.
- 클라이언트 `highestPlan`은 `"exam_pass"`를 매칭하지 못한다(`contains("pro")` 실패) → **`free`로 판정**.
  서버는 `pro`. **클라이언트/서버 불일치가 잠재해 있다.** 현재는 해당 엔타이틀먼트가 존재하지 않아
  발현되지 않지만, PRODUCT.md가 언급하는 "시험 대비 패스"를 만드는 순간 즉시 버그가 된다.
- 최종 권위는 서버 `/v1/capabilities`이나, `AppEnvironment.currentPlan`(`:26-31`)은
  `store.isConfigured`면 **로컬 엔타이틀먼트를 우선**한다 → 불일치 시 UI가 잘못된 플랜을 보여준다.

**페이월 구현 (`Views/Screens/Paywall/PaywallView.swift`)**
- **RevenueCat 호스티드 페이월 미사용**(`paywall_id: null`). 100% 커스텀 SwiftUI.
- 티어 카드 4개(free/basic/plus/pro), free 카드는 비구매 대상.
- **구매 트리거가 `Button`이 아니라 `.onTapGesture`다** (`:109-113`).
  → VoiceOver에 버튼 트레이트가 없고, Full Keyboard Access·스위치 제어로 도달할 수 없다.
  **접근성 사용자는 구독할 수 없다.** (P0)
- 복원(`restore`), 구독 관리(`manageSubscriptions`, 유료만), 개인정보처리방침, EULA,
  자동갱신 고지는 **모두 존재하고 올바르다** (`:134-171`). App Store 심사 요건 충족.
- `promoBadge: "오픈 기념 할인"`이 basic에만 하드코딩돼 있다(`:248-249`).
  **RevenueCat에는 어떤 할인/오퍼도 설정돼 있지 않다.** 실제 가격은 정가 ₩2,900이다.
- **주 CTA가 없다.** 4장 모두 동등한 카드이고 `탭하여 시작하기 →`가 3장에 동일하게 붙는다.

**페이월이 광고하는 것 vs 실제로 강제되는 것**

| 페이월 문구 | 실제 | 판정 |
|---|---|---|
| 데일리 새 문제 세트 하루 1/3/10/20회 | `practice_daily` 그대로 | ✅ 정확 |
| 모의고사 최초 1회 / 1·3·5회 | `mock_daily` + `mock_is_trial` 그대로 | ✅ 정확 |
| 광고 완전 제거(basic+) | `ads_enabled=False` → `BannerAdView`가 숨김 | ✅ 정확 |
| 결과: 예상등급/개선점/교정·모범답안/문항별 | `analysis_depth`가 **AI 생성 자체를 제어** (`ai.py:1669-1676`) | ✅ 정확 |
| **학습 기록 최근 7일 / 30일 / 전체** | `historyDays`는 디코딩만 되고 **게이팅에 사용되지 않음**. 통계 기간 필터는 로컬 SwiftData 기준으로 전 플랜 동일 | ❌ **강제되지 않는 혜택을 광고 중** |
| 무료 카드 "광고 있음"에 ✓ 체크 아이콘 | 단점을 혜택 기호로 표시 | ❌ 시각 언어 오류 |

또한 `PaywallTier.free`는 `"데일리 새 문제 세트 하루 1회 (+광고 보너스 1회)"`로 광고 보너스를 명시하는데,
유료 티어에는 `practice_ad_bonus = 0`이라는 사실이 표시되지 않는다(문제는 아니나 비교 축이 비대칭).

### ROOT PROBLEM

세 가지가 겹쳐 있다.
1. **접근성**: 구매 액션이 시맨틱 컨트롤이 아니다 → 구독 불가능한 사용자 집단이 존재한다.
2. **정직성**: 페이월이 강제되지 않는 혜택(기록 기간)과 존재하지 않는 프로모션(오픈 기념 할인)을 광고한다.
3. **의사결정 지원 부재**: 4개 동등 카드 + 주 CTA 없음 → 사용자가 무엇을 골라야 하는지 알 수 없다.

### RECOMMENDED DIRECTION

1. **`.onTapGesture` → `Button`으로 교체한다.** 논쟁의 여지가 없다. 최우선.
   카드 전체를 `Button` 레이블로 감싸고 `.buttonStyle(.plain)`을 적용하면 시각은 동일하다.
2. **페이월 혜택 목록은 "서버가 실제로 강제하는 것"만 나열한다.**
   `historyDays`는 강제되기 전까지 제거한다(→ Q6에서 어느 방향으로 정할지 결정).
3. **"오픈 기념 할인" 배지는 RevenueCat에 실제 오퍼가 없으면 제거한다.**
   가격 표시와 프로모션 문구는 반드시 스토어 데이터에서 파생시킨다.
4. **비교 축을 4개로 고정한다**: 새 문제 세트/일 · 모의고사/일 · 결과 상세도 · 광고.
   이 4개가 서버가 실제로 강제하는 전부다.
5. **추천 플랜 1개를 시각적으로 승격한다**(주 CTA). `basic`이 광고 제거 + 매일 모의고사를
   ₩2,900에 제공하므로 가치 변곡점이다.
6. **`highestPlan`의 부분 문자열 매칭을 명시적 매핑 테이블로 교체한다.**
   `$rc_monthly` 사례가 이미 우연에 의존하고 있고, `exam_pass` 불일치가 잠재해 있다.
   서버 `_ENTITLEMENT_TO_PLAN`과 동일한 키 집합을 클라이언트에도 둔다.
7. **무료 체험이 없다는 사실을 디자인 전제로 삼는다.** `trial_duration: null` — 세 상품 모두.
   "무료로 시작하기" 류의 문구를 쓸 수 없다.

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | RevenueCat 호스티드 페이월로 이전 | 접근성·현지화를 RC가 처리. 다만 4티어 커스텀 비교표 표현력이 제한되고 기존 디자인 자산을 버린다. 이번 리뉴얼 범위 밖. |
| B | **커스텀 유지 + Button화 + 혜택 정합화** (권장) | 최소 변경으로 P0 해소. |
| C | 티어를 2개(무료/프리미엄)로 축소 | 상품 구조 변경 = 스토어 작업 동반. "새 상품 만들지 마라" 제약 위반 소지. 비권장. |

### REQUIRES PRODUCT DECISION

- 학습 기록 기간을 실제로 잠글지, 페이월 문구를 뺄지 (→ **Q6**)
- 스마트 기능(등급 추이·취약 유형·주간 리포트) 티어링 (→ **Q7**)
- "시험 대비 패스"(`exam_pass`)를 리뉴얼 범위에 넣을지 (→ **Q8**)

### DESIGN IMPACT

- 페이월은 **카드 4장 나열이 아니라 의사결정 화면**으로 재설계한다: 현재 플랜 → 추천 1개 →
  나머지 비교표.
- 모든 구매 액션은 시맨틱 버튼이며 44×44pt 이상 + 로딩 중에도 접근성 이름을 유지해야 한다
  (현재 `PrimaryButton`은 로딩 시 이름이 사라진다).
- 가격·프로모션·기간은 전부 스토어 데이터 바인딩. 하드코딩 문자열 금지.
- 페이월 진입점이 4곳(`PracticeResultView`, `ProgressScreen`, `MockExamScreen`, `PracticeViewModel`
  쿼터 소진)이므로 **진입 맥락에 따라 상단 문구가 달라지는 구조**가 필요하다.

### IMPLEMENTATION SCOPE

- `PaywallView`: Button 전환 + 혜택 목록 정리 + 주 CTA. (~120줄)
- `StoreService.highestPlan`: 명시적 매핑. (~15줄)
- **RevenueCat 대시보드 변경 없음. 신규 상품·가격 생성 없음.**
- Q6이 "집행"으로 결정되면 클라이언트 기간 필터 게이팅 + 서버 검증 추가(별도 범위).

---

## T7 — Ads policy

### VERIFIED CURRENT POLICY

**배너 광고 — 정확히 3곳**

| 화면 | 위치 | 코드 |
|---|---|---|
| 데일리 | `ScrollView` 최하단, 문항 카드·녹음 UI 아래 | `PracticeScreen.swift:131` |
| 모의고사 인트로 | `ScrollView` 최하단 | `MockExamScreen.swift:179` |
| 통계 | `ScrollView` 최하단 | `ProgressScreen.swift:100` |

- 크기: `AdSizeBanner` (320×50), 프레임 `height: 50` 고정.
- **모의고사 답변 중 화면·결과 화면·설정·페이월·온보딩에는 배너가 없다.**
- 노출 조건: `environment.showsAds && ads.canRequestAds`
  (`BannerAdView.swift:15`). `showsAds`는 `capabilities.quotaPolicy.adsEnabled`(서버 권위) 우선.
- **유료 플랜은 `Color.clear`를 렌더링하는데 호출부가 `.frame(height: 50)`을 강제하므로
  50pt 빈 공간이 그대로 남는다.** 광고를 제거한 사용자에게 광고 자리만 남는다.
- 3개 화면 모두 배너가 스크롤 최하단 + 플로팅 탭바 아래라 **상시 절반 이상 가려진다**(SIM 확인).

**리워드 광고 — 정확히 5개 트리거, 6개 purpose 중 1개는 미사용**

| purpose | 트리거 | 호출부 | 무료 | 유료 |
|---|---|---|---|---|
| `mock_start` | 모의고사 시작 | `MockExamViewModel:248` | 광고 시청 | **auto-verify(광고 없음)** |
| `mock_adjustment` | 7문항 후 난이도 조정 | `MockExamViewModel:514` | 광고 시청 | auto-verify |
| `mock_result` | 결과 확인 | `MockExamViewModel:383` | 광고 시청 | auto-verify |
| `target_level_change` | 목표 등급 변경 | `OnboardingView:288` | 광고 시청 | auto-verify |
| `practice_credits` | 데일리 세트 소진 후 보너스 | `PracticeViewModel:261` | 광고 시청 | **402 반려 → 페이월** |
| `practice_refresh` | — | **호출부 없음** | — | — |

- auto-verify 판정: `plans.reward_auto_verify()` (`plans.py:170-183`) — 유료 플랜은 위 5개 중
  `practice_credits`를 제외한 4개를 광고 없이 통과.
- `practice_credits`의 유료 상한은 0(`practice_ad_bonus = 0`)이므로 `create_reward_intent`가
  402 `reward_not_available_for_plan`을 반환한다(`routes.py:1739-1747`) → 페이월 유도. 의도된 설계.
- **`practice_refresh`는 클라이언트가 한 번도 요청하지 않는다** → `refresh_ad_bonus`
  (free 1 / basic 10 / plus 20 / pro 30)와 `usage.dailyRefreshRemaining`은 **사문화된 값**이다.

**모의고사 광고 게이트 = 3회, 예산도 정확히 3회**
`_MOCK_REWARD_GATES = 3`, `reward_max_for(free, MOCK_*) = 3 * mock_daily(1) = 3`,
세 purpose가 카운터 `mockRewardCount` 공유(`state.py:478-492`).
→ **재시도 여유 0** (T2 참조).

**목표 등급 변경 = 전 플랜 하루 1회**
`reward_max_for(*, TARGET_LEVEL_CHANGE) = 1` (`plans.py:205-206`), 무료는 광고·유료는 auto-verify.
그런데 `_counts_toward_daily_reward_quota`는 이 purpose를 제외한다(`state.py:474-476`) —
카운터는 `targetLevelChangeRewardCount`로 별도 관리된다.

**동의·추적**: UMP 동의 → `ConsentForm.loadAndPresentIfRequired` → **ATT 요청**
(`AdService.prepare()`) 순으로 **앱 최초 실행 시 스플래시 단계에서** 진행된다.
사용자가 앱의 가치를 보기 전에 추적 허용을 묻는다. `canRequestAds`가 false면 배너·리워드 모두 불가.

### UX PROBLEM

1. **유료 사용자에게 50pt 빈 광고 자리가 남는다.** "광고 완전 제거"를 구매한 직후의 경험으로 최악.
2. **무료 모의고사에 재시도 여유가 없다.** 광고 1편을 본 뒤 네트워크 오류 한 번이면
   평생 1회 체험이 봉인된다(T2 데드엔드의 절반이 이 예산 설계에서 온다).
3. **광고 예산이 사전에 고지되지 않는다.** "총 3편"이라는 사실을 시작 전에 알려주지 않아,
   중도 이탈이 곧 손실이 된다.
4. **유료/무료 분기 안내가 틀려 있다.** `SetupView`와 `OnboardingView.guidanceText`가
   플랜과 무관하게 **"변경하려면 광고를 끝까지 봐야 해요"** 를 표시한다.
   유료 사용자는 실제로는 광고 없이 즉시 변경되는데 광고를 봐야 한다고 안내받는다.
   (`TargetLevelConfirmationDialog`만 "무료로 바꾸기"로 올바르게 분기한다.)
5. **배너가 상시 가려진다** — 3개 화면 모두 플로팅 탭바 아래. 사용자에게도 광고주에게도 손해다.
6. **ATT를 너무 이르게 요청한다** — 첫 실행 스플래시. 허용률이 구조적으로 낮아진다.
7. **`dailyRefreshRemaining`이 사문화**되어 플랜 표에 있는 리프레시 광고 상한이 아무 의미가 없다.

### DESIGN DECISION NEEDED

**정책 자체는 임의로 바꾸지 않는다.** 아래 두 가지만 소유자 결정 대상이다.
- 배너 노출 위치(특히 답변·녹음 중 화면 유지 여부) → **Q5**
- 무료 모의고사 리워드 예산의 재시도 헤드룸 → **Q4**

**정책 변경 없이 지금 확정 가능한 것 (전부 표현·전달 문제)**
- 유료 플랜에서는 `.frame(height: 50)`을 제거해 **빈 공간을 남기지 않는다.**
- 리워드 게이트 진입 전 **"광고 3편 중 n번째"** 를 명시한다.
- 유료 사용자에게는 "광고 없이 바로 진행됩니다"로 문구를 분기한다(문구 버그 수정).
- 리워드 광고 전후에 **명시적 상태 화면**을 둔다(불러오는 중 / 시청 중 / 검증 중 / 실패·재시도).
  현재 `AdService.State`에 `loading/presenting/verifying/failed`가 이미 있으나 UI가 쓰지 않는다.
- ATT 요청 시점을 첫 광고 노출 직전으로 옮긴다(정책 변경 아님, 타이밍 조정).
- 사문화된 `dailyRefreshRemaining`을 UI에 노출하지 않는다.

### REQUIRES PRODUCT DECISION

→ **Q4**(리워드 예산 헤드룸), **Q5**(배너 노출 위치)

### DESIGN IMPACT

- 광고는 **화면의 잔여물이 아니라 명시적 슬롯**으로 설계한다. 슬롯이 없는 플랜에서는 레이아웃이
  광고 높이만큼 자연스럽게 줄어야 한다.
- 리워드 게이트는 4상태(로딩/시청/검증/실패) 화면이 필요하다.
- 무료/유료 카피가 **동일 컴포넌트에서 분기**해야 한다 — 현재 3곳에 흩어져 한 곳만 맞다.
- 광고 예산 표시("3편 중 1편")는 모의고사 진행 UI의 일부가 된다.

### IMPLEMENTATION SCOPE

- `BannerAdView`가 자체 높이를 소유(호출부 `.frame` 제거). (~10줄)
- 리워드 게이트 상태 UI. (~100줄)
- 카피 분기 통합(`SetupView`, `OnboardingView`, `TargetLevelConfirmationDialog`). (~30줄)
- ATT 타이밍 이동. (~10줄)
- **AdMob 설정·광고 단위·정책 변경 없음.**

---

## T8 — Accessibility target

### VERIFIED CURRENT STATE

| 지표 | 현재 값 | 근거 |
|---|---|---|
| `accessibilityLabel/Value/Hint/AddTraits` 총 호출 | **14건 / 10개 파일** | 전체 Swift 검색 |
| `.accessibilityAddTraits(.isModal)` | **0건** (커스텀 오버레이 6개 존재) | `grep isModal` |
| VoiceOver 알림(`AccessibilityNotification`) | **0건** | 전체 검색 |
| `accessibilityReduceMotion` 사용 | **4개 파일** (`OPIcGuideView`, `AILoadingOverlay`, `RecordingButton`, `AppLoadingIndicator`) | |
| `Font.system(size:)` 절대 크기 | **24건** | |
| `relativeTo:` (Dynamic Type 대응) | **0건** | `AppTypography` 7종 전부 절대 크기 |
| `.onTapGesture`로 구현된 액션 | **7건** (페이월 구매 포함) | |
| 배포 타깃 | iOS 17.0 | `IPHONEOS_DEPLOYMENT_TARGET` |
| 색상 | 라이트/다크 동적 대응 완료 | `AppPalette` (UIColor provider) |

SIM 확인된 실패: AX5(`accessibility-extra-extra-extra-large`)에서 데일리 마이크 버튼이
화면 밖으로 밀려나고, 등급 텍스트 `IL`이 주변 라벨보다 작게 렌더링된다.
다크 모드 accent 대비 3.22:1 (본문 기준 4.5:1 미달).

### ROOT PROBLEM

접근성이 "나중에 라벨을 붙이는 일"로 취급되어 왔다. 그러나 실패한 항목들
(Dynamic Type, 시맨틱 컨트롤, 모달 포커스)은 **레이아웃과 컴포넌트 선택 시점에 결정되는 것**이라
리뉴얼 이후에 붙일 수 없다. 그리고 이 앱은 **말하기 앱**이므로 시각장애 사용자와의 적합도가 특히 높다 —
접근성 실패의 기회비용이 일반 앱보다 크다.

### RECOMMENDED DIRECTION

**리뉴얼의 완료 정의(Definition of Done)에 아래 12개 기준을 포함한다.
각 항목은 실제로 검증 가능한 절차와 통과 조건을 갖는다.**

| # | 항목 | 통과 조건 (측정 가능) | 검증 방법 |
|---|---|---|---|
| **A1** | VoiceOver 라벨 | 모든 인터랙티브 요소가 비어 있지 않은 label을 갖는다. 아이콘 전용 버튼은 label 필수. **"버튼", "이미지" 같은 타입명만 읽히는 요소 0개** | Accessibility Inspector Audit + 8개 여정 VoiceOver 수동 주행 |
| **A2** | VoiceOver 순서 | 읽기 순서가 시각적 순서와 일치. 커스텀 오버레이 표시 중 배경 요소로 스와이프 이동 불가 | 각 화면 스와이프 전체 순회 |
| **A3** | 시맨틱 컨트롤 | 액션이 `Button`/`Toggle`/`Picker` 등 시맨틱 컨트롤로 구현. **`.onTapGesture`로 구현된 주요 액션 0건** (현재 7건, 페이월 구매 포함) | `grep onTapGesture` + Inspector 트레이트 확인 |
| **A4** | Dynamic Type | `xSmall`~`AX5` 전 구간에서 (a) 텍스트 잘림 없음 (b) 주요 액션이 화면 안 (c) 가로 스크롤 없음. `AppTypography` 7종이 전부 `relativeTo:` 기반 | `simctl ui <udid> content_size` 7단계 × 11개 화면 스크린샷 |
| **A5** | AX 최대 크기 우선순위 | AX3 이상에서 보조 정보는 접히거나 스크롤되어도, **녹음 버튼·주 CTA·닫기 버튼은 항상 접근 가능** | AX5에서 각 화면 주 액션 탭 가능 여부 |
| **A6** | 터치 타깃 | 모든 탭 가능 요소 ≥ 44×44pt. 진행바 칩(현재 22–24pt) 포함. 인접 타깃 간 간격 ≥ 8pt | Inspector 프레임 측정 + 칩·툴바 버튼 실측 |
| **A7** | 명도 대비 | 본문/아이콘 ≥ 4.5:1, 대형 텍스트(≥18pt bold 또는 ≥24pt) ≥ 3:1, **라이트·다크 양쪽에서**. 현재 다크 accent 3.22:1 실패 | Inspector Contrast + `AppPalette` 전 토큰 조합표 |
| **A8** | 색 단독 신호 금지 | 상태(녹음 중/신뢰도/타이머 경고/플랜 현재값)를 색으로만 표현하지 않는다 — 아이콘 또는 텍스트 병기 | 그레이스케일 렌더링에서 상태 구분 가능 여부 |
| **A9** | Reduce Motion | 활성화 시 장식성 애니메이션(스플래시, 문항 전환 슬라이드, 녹음 펄스, 로딩) 제거 또는 크로스페이드 대체. **화면 전환이 상태를 잃지 않는다** | 설정 On/Off 각 1회 전체 주행 |
| **A10** | 모달 포커스 | 모든 커스텀 오버레이·다이얼로그(현재 6개)에 `.accessibilityAddTraits(.isModal)`. 배경 요소 접근 차단. **명시적 닫기 어포던스** 존재 | VoiceOver로 오버레이 표시 중 배경 도달 시도 |
| **A11** | 로딩·진행 알림 | 비동기 작업 시작/완료 시 VoiceOver 발표(`AccessibilityNotification.Announcement`). 로딩 중 버튼이 **접근성 이름을 잃지 않는다** (현재 `PrimaryButton`이 잃음). 진행률은 `accessibilityValue`로 노출 | 문제 생성·분석·광고 검증 3개 경로 VoiceOver 주행 |
| **A12** | 타이머 알림 | 모의고사 180초 타이머가 `accessibilityValue`로 남은 시간을 제공하고, 임계 시점(60/30/10초)에 발표. **색 변화 단독 경고 금지** | 1문항 VoiceOver 완주 |
| **A13** | 라이트/다크 | 11개 화면 × 2모드에서 대비·가독성·자산 표현 동일 수준. 하드코딩 `Color.white`/`.black`이 대비를 깨는 곳 0건 | `simctl ui appearance` 양쪽 스크린샷 비교 |

**우선순위**: A3 → A4 → A6 → A10 → A7 → A11 → 나머지.
A3(시맨틱 컨트롤)과 A4(Dynamic Type)는 **컴포넌트 설계 시점에 결정**되므로 리뉴얼 착수 전에
디자인 시스템 수준에서 잠가야 한다.

**디자인 시스템에 넣어야 할 구조적 결정 2개**
1. `AppTypography`를 `Font.system(size:relativeTo:)` 또는 iOS 표준 텍스트 스타일 기반으로 재정의한다.
   현재 7종 전부 절대 크기 → A4는 이 변경 없이 통과 불가능하다.
2. 모든 탭 가능 컴포넌트에 최소 44pt 보장을 **컴포넌트 자체가** 책임진다
   (`.frame(minWidth: 44, minHeight: 44)` + `contentShape`). 호출부에 맡기면 반드시 새어나간다.

### ALTERNATIVES

| 안 | 내용 | 평가 |
|---|---|---|
| A | WCAG AA 전면 준수 선언 | 검증 절차가 웹 기준이라 네이티브에 그대로 안 맞는다. 선언만 남고 검증이 안 된다. |
| B | **위 13개 항목 + 화면별 통과 조건** (권장) | 전부 시뮬레이터/Inspector로 실측 가능. 회귀 방지 가능. |
| C | VoiceOver·Dynamic Type만 | A6(터치 타깃)·A10(모달)이 빠지면 리뉴얼 후 재작업이 발생한다. |

### REQUIRES PRODUCT DECISION

없음. 전부 기술 기준이며 즉시 채택 가능하다.
(단, 접근성 기준 충족을 위해 시각적 밀도가 낮아지는 트레이드오프는 디자인 단계에서 조율한다.)

### DESIGN IMPACT

- **타이포 스케일을 Dynamic Type 기반으로 다시 만들어야 한다** — 리뉴얼의 첫 번째 작업.
- 44pt 최소 타깃은 진행바 칩·툴바·페이월 카드·설정 행의 레이아웃 밀도를 직접 결정한다.
- AX3 이상에서의 **레이아웃 재배치 규칙**(가로 → 세로 스택 전환 기준)이 컴포넌트 스펙에 필요하다.
- 다크 모드 accent를 4.5:1 이상으로 재조정해야 하므로 **팔레트 자체가 바뀐다**.
- 커스텀 오버레이 6개에 공통 모달 컨테이너를 도입해 `.isModal` + 닫기 어포던스 + 스크림 불투명도를
  한 곳에서 보장한다(현재 스크림 값이 0.28/0.32/0.34로 제각각).

### IMPLEMENTATION SCOPE

- `AppTypography` 재정의 + 전 화면 반영. (~24개 호출 지점)
- 공통 모달 컨테이너 컴포넌트 신규. (~60줄)
- `PrimaryButton` 로딩 시 접근성 이름 보존. (~10줄)
- 타이머·로딩 발표. (~40줄)
- `AppPalette` 다크 accent 조정.
- **서버 변경 없음.**

---

# Decisions — LOCKED (2026-08-08 제품 소유자 승인 완료)

아래 9개는 **전부 승인되어 잠겼다.** `DESIGN.md`와 이후 구현은 이 결정을 전제로 한다.
변경하려면 이 문서를 먼저 고쳐야 한다.

| # | 주제 | 확정 |
|---|---|---|
| Q1 | 녹음 종료 정책 | **D** — 180초 자동 종료 · 무음 자동 종료 없음 · 종료/분석 분리 · 재녹음 가능 |
| Q2 | 평가 품질 정책 | **D** — A/B/C 3버킷. **임계값은 DESIGN 단계에서 만들지 않는다** |
| Q3 | 세트 내 평가 무제한 | **A** — 유지. 재녹음·재평가에 토큰/쿼터 소모 없음 |
| Q4 | 무료 모의고사 리워드 예산 | **A** — 하루 3개 상한 유지, nonce 재사용으로 해결. 광고 정책 불변 |
| Q5 | 배너 광고 위치 | **B** — 데일리 발화 흐름에서 제거. 결과/통계/모의고사 인트로 우선 |
| Q6 | 페이월 학습 기록 문구 | **B** — 삭제 |
| Q7 | 스마트 기능 티어링 | **A** — 전 플랜 무료 유지 |
| Q8 | `exam_pass` | **A** — 범위 제외. 매핑 불일치는 기술 부채로 기록 |
| Q9 | 모의고사 중도 포기 | **B** — 서버 세션 종료 + 당일 재시작 허용, 광고 예산 복구 없음 |

---

**Q1. 녹음 종료 정책을 무엇으로 확정할까?** — ✅ **LOCKED: D**

> 확정 내용: 최대 180초에서 자동 종료 / 무음 자동 종료 없음 / "녹음 종료"와 "분석하기" 분리 /
> 녹음 종료 후 전사(transcript) 상태를 확인하고 **다시 녹음할 수 있어야 한다.**

(현재: 데일리는 시간 제한 없음 / 모의고사만 180초 자동 정지 + 자동 제출. 무음 감지는 미구현.)

A. 수동 정지만. 데일리에도 시간 제한을 두지 않는다.
B. 최대 시간 자동 정지만 추가한다. 정지하면 지금처럼 즉시 자동 제출한다.
C. 하이브리드(최대 시간 자동 정지 + 무음 자동 정지). 정지하면 즉시 자동 제출한다.
D. 하이브리드하되 **무음 자동 정지는 넣지 않고**, 정지와 제출을 분리해 전사 확인 후 사용자가 "분석하기"를 누른다. 데일리 상한은 모의고사와 같은 180초.

Recommended: D
Reason: 학습자는 문장 사이에 길게 멈추므로 무음 자동 정지는 오탐이 치명적이고, 구현도 전무해 신규 DSP가 필요하다. 반면 최대 시간 상한은 모의고사에 이미 구현·검증돼 있어 재사용할 수 있고 무한 녹음으로 인한 업로드 실패를 막는다. 정지와 제출을 분리하는 것이 핵심인데, **세트 내 평가가 무제한이므로 재녹음에 추가 비용이 전혀 들지 않는다**(T3에서 확인). 지금은 정지 버튼이 곧 제출 버튼이라 사용자가 실수를 되돌릴 수 없다.

---

**Q2. AI가 평가하기에 답변이 너무 부족할 때(예: 3단어) 어떻게 처리할까?** — ✅ **LOCKED: D**

> 확정 내용: A(평가 가능) / B(신뢰 낮음) / C(평가 불가·다시 말하기) 3단계 구조를 사용한다.
> **제약 1 — `DESIGN.md` 단계에서 임의의 단어 수·WPM·무음 비율 임계값을 만들어내지 않는다.**
> **제약 2 —** 임계값은 구현 단계에서 실제 backend signal과 테스트 케이스를 근거로 별도 확정한다.
> **제약 3 —** B/C 상태에서는 **근거 없이 높은 예상 등급을 보여주지 않는다.**

(현재: 최소 길이 검증이 없고, IL 하한 클램프 + "애매하면 상위 밴드" 프롬프트 + LLM 자율 confidence가 겹쳐 3단어 답변도 "IL / 신뢰도 높음"으로 표시된다.)

A. 현행 유지. 짧은 답변도 등급과 신뢰도를 그대로 표시한다.
B. 등급은 표시하되 "신뢰 낮음" 경고와 이유를 붙이고, 등급 추이 통계에서는 제외한다.
C. 등급을 아예 표시하지 않고 "다시 말하기"만 유도한다. 이력에도 저장하지 않고 AI 호출도 하지 않는다.
D. 3버킷 운영 — 충분하면 A처럼, 경계면 B처럼, 명백히 부족하면 C처럼 처리한다.

Recommended: D
Reason: 세 상황은 사용자에게 서로 다른 의미이므로 하나의 처리로 묶으면 어느 쪽이든 손해다. 판정에 필요한 신호(단어 수·발화 시간·무음 비율·WPM)는 이미 서버 `AudioMetrics`에 전부 있어 새 점수를 발명할 필요가 없다. 명백히 부족한 답변을 AI 호출 전에 차단하면 OpenAI 비용도 절감된다(현재는 3단어에도 정상 요금 발생). 다만 A/B/C 경계값은 실제 데이터를 본 뒤 정해야 하므로, 이 질문에서는 **정책 구조만 승인**하고 임계값은 별도로 확정한다.

---

**Q3. "한 세트 안에서 평가 무제한" 계약을 리뉴얼에서도 유지할까?** — ✅ **LOCKED: A**

> 확정 내용: 유지한다. **다시 말하기·재평가에 추가 토큰 또는 쿼터를 소모하지 않는다.**

(현재: 토큰 1개 = 새 문제 세트 1개. 세트 안 14문항은 무제한 답변·재답변·재평가 가능. `reserve_practice`는 차감하고 `reserve_request`는 차감하지 않는다.)

A. 유지한다. 토큰은 계속 "새 문제 세트" 단위로만 소모된다.
B. 세트당 평가 횟수 상한을 둔다(예: 세트당 20회).
C. 평가 1회 = 토큰 1개로 과금 단위를 바꾼다.

Recommended: A
Reason: 이 계약이 제품의 가장 큰 강점이고, Q1(재녹음 허용)과 Q2(다시 말하기 유도)가 성립하는 전제다. B/C를 택하면 "부족한 답변은 다시 말하세요"라는 안내가 곧 "돈을 더 내세요"가 되어 학습 유도와 정면충돌한다. C는 서버 계약을 뒤집는 변경이라 기존 사용자에게 사실상 다운그레이드다. 현재 UI가 이 강점을 전혀 표현하지 않고 있을 뿐이므로, 계약은 유지하고 **표현만 고치는 것**이 옳다.

---

**Q4. 무료 모의고사의 리워드 광고 예산에 재시도 여유를 줄까?** — ✅ **LOCKED: A**

> 확정 내용: 하루 3개 상한 정책을 유지한다. 실패 시 서버가 반환한 nonce를 클라이언트가 재사용하도록
> 한다. **광고 정책 자체는 이번 리뉴얼에서 변경하지 않는다.**

(현재: 무료는 하루 리워드 인텐트 총 3개. 시험 완주에 필요한 것도 정확히 3개. 시작 게이트에서 네트워크 오류가 한 번 나면 4번째 인텐트가 402로 막혀 평생 1회 체험이 봉인된다. 서버는 nonce를 환불하지만 클라이언트가 버린다.)

A. 현행 유지(3개). 클라이언트가 nonce를 재사용하도록만 고쳐 대부분의 실패를 흡수한다.
B. 실패한 게이트는 카운터에서 제외한다(성공한 게이트만 집계).
C. 상한을 여유 있게 올린다(예: 5개).

Recommended: A
Reason: 서버는 이미 실패 시 `consumed=false`로 nonce를 환불하도록 설계돼 있고(`state.py:1161-1164`), 결과 게이트는 `EvaluationRetryContext`로 nonce를 보관해 재사용한다. **시작·조정 게이트에만 이 패턴이 빠져 있는 것이 진짜 원인**이다. 클라이언트를 고치면 광고 정책을 전혀 건드리지 않고 데드엔드가 사라진다. B는 서버 카운터 로직 변경이라 리스크 대비 이득이 작고, C는 무료 사용자의 광고 노출 총량을 늘리는 정책 변경이다. A로 고친 뒤에도 봉인 사례가 관측되면 그때 B를 검토한다.

---

**Q5. 배너 광고를 어디에 노출할까?** — ✅ **LOCKED: B**

> 확정 내용: **데일리 Speaking/Practice의 핵심 발화 흐름에서는 배너 광고를 제거한다.**
> 배너는 학습 흐름을 직접 방해하지 않는 영역(결과 · 통계 · 모의고사 인트로)을 우선한다.
> **실제 배치 좌표는 `DESIGN.md`에서 safe area · tab bar · hierarchy와 함께 최종 정의한다.**

(현재: 데일리 학습 화면, 모의고사 인트로, 통계 — 3곳 모두 스크롤 최하단. 플로팅 탭바에 상시 절반 이상 가려진다. 모의고사 답변 중과 결과 화면에는 없다.)

A. 현행 3곳 유지. 가려짐 문제만 레이아웃으로 해결한다.
B. 답변·녹음이 일어나는 데일리 학습 화면에서는 배너를 빼고, 결과·통계·모의고사 인트로에만 노출한다.
C. 배너를 전부 제거하고 리워드 광고만 운영한다.

Recommended: B
Reason: 데일리 학습 화면은 이 앱에서 유일하게 집중이 필요한 화면이고, 지금도 탭바에 가려 노출 가치가 거의 없다(광고주에게도 손해). 결과·통계는 사용자가 스크롤하며 머무는 화면이라 실제 뷰어빌리티가 높고 학습을 방해하지 않는다. C는 무료 플랜 수익을 리워드 광고에만 의존시키는 큰 BM 변경이라 이번 리뉴얼 범위를 넘는다. **어느 안을 택하든 유료 플랜의 50pt 빈 공간 제거는 정책 변경이 아니므로 즉시 수정한다.**

---

**Q6. 페이월의 "학습 기록 최근 7일 / 30일 / 전체"를 어떻게 할까?** — ✅ **LOCKED: B**

> 확정 내용: 삭제한다. **현재 실제로 제한하지 않는 기능을 유료 혜택처럼 표시하지 않는다.**

(현재: 서버 `plans.py`는 `history_days`를 7/30/30/전체로 정의하고 `/v1/capabilities`로 내려보내지만, 클라이언트는 디코딩만 하고 게이팅에 쓰지 않는다. 통계 기간 필터는 로컬 SwiftData 기준으로 전 플랜 동일하게 동작한다. 즉 **강제되지 않는 혜택을 광고 중**이다.)

A. 서버 정책대로 실제로 잠근다. 무료는 최근 7일만 볼 수 있게 한다.
B. 페이월에서 이 항목을 삭제한다. 기록은 전 플랜 무제한으로 유지한다.
C. 로컬 기록은 무제한으로 두고, "기록 보관·복원"을 유료 혜택으로 재정의한다.

Recommended: B
Reason: 지금 상태는 페이월이 사실과 다른 약속을 하고 있어 그대로 둘 수 없다. A는 **기존 사용자에게서 이미 쓰던 기능을 회수**하는 것이라 리뉴얼 직후 평점 리스크가 크고, 기록이 로컬 SwiftData에만 있어 "7일 초과분을 숨기지만 기기에는 남아 있는" 이상한 상태가 된다. C는 매력적이지만 서버 기록 동기화가 필요해 이번 범위를 크게 넘는다(현재 크로스 디바이스 동기화 자체가 없다). B는 즉시 정직해지고, 대신 실제로 강제되는 4개 축(세트/일, 모의고사/일, 결과 상세도, 광고)이 더 선명해진다.

---

**Q7. 스마트 기능(예상 등급 추이 · 취약 유형 분석 · 주간 리포트)을 플랜별로 잠글까?** — ✅ **LOCKED: A**

> 확정 내용: 전 플랜 무료를 유지한다(등급 추이 · 취약 유형 · 주간 리포트).
> **유료 차별화는 실제 backend에서 강제되는 `analysis_depth`와 실제 제공 기능을 기준으로 표현한다.**

(현재: `plans.py`는 티어링을 정의한다 — 취약 유형 분석은 plus 이상, 주간 리포트는 pro 전용. 그러나 클라이언트가 이 필드들을 게이팅에 쓰지 않아 **실제로는 전 플랜 무료**다. PRODUCT.md도 "무료 유지"라고 적고 있다.)

A. 전 플랜 무료를 유지한다. `plans.py`의 해당 필드는 미사용으로 명시한다.
B. `plans.py` 정의대로 잠근다.
C. 일부만 잠근다(예: 주간 리포트만 유료).

Recommended: A
Reason: 실제 production contract는 "무료"이고, 사용자는 이미 그렇게 쓰고 있다. Q6과 같은 이유로 **회수는 리뉴얼에서 가장 비싼 행동**이다. 게다가 이 기능들의 가치는 누적 학습 데이터에서 나오므로, 무료 사용자에게 열어두는 것이 오히려 "더 하려면 세트가 더 필요하다"는 자연스러운 업그레이드 동기를 만든다. 유료 차별화는 이미 `analysis_depth`가 실제로 강제하고 있다 — 서버가 하위 티어에서는 교정·모범답안·목표갭을 **생성조차 하지 않는다**. 이 축 하나로 충분하다.

---

**Q8. "시험 대비 패스"(`exam_pass`)를 이번 리뉴얼 범위에 넣을까?** — ✅ **LOCKED: A**

> 확정 내용: 이번 리뉴얼 범위에서 제외한다. RevenueCat에 실제 구매 가능한 상품이 없으므로
> **Paywall이나 사용자-facing UI에 추가하지 않는다.**
> 단 client/backend의 plan mapping 불일치는 **기술 부채로 기록**하고 구현 단계 정리 대상에 포함한다.

(현재: 서버 `plans.py`는 `exam_pass` → pro 매핑을 갖고 있고 PRODUCT.md도 언급하지만, **RevenueCat에는 해당 상품도 엔타이틀먼트도 존재하지 않는다.** 구매 불가능하다. 게다가 클라이언트 매핑 로직은 `exam_pass`를 `free`로 판정해 서버와 어긋난다.)

A. 이번 범위에서 제외한다. 페이월은 월 구독 3종만 표현한다.
B. 상품을 신설하고 페이월에 포함한다.
C. 페이월에는 넣지 않되 "출시 예정"으로 안내한다.

Recommended: A
Reason: 존재하지 않는 상품을 디자인에 넣으면 리뉴얼이 스토어 작업에 묶인다. RevenueCat 조회 결과 현재 판매 가능한 것은 월 구독 3종뿐이고, 무료 체험·유예기간도 설정돼 있지 않다. 디자인은 실제로 팔 수 있는 것만 표현해야 한다. C는 구매할 수 없는 항목으로 페이월 밀도만 높인다. **다만 A를 택하더라도 클라이언트/서버 플랜 매핑 불일치는 잠재 버그이므로 명시적 매핑 테이블로 교체한다**(T6 권장 6번) — 나중에 상품을 만들 때 조용히 터지는 것을 막는다.

---

**Q9. 사용자가 모의고사를 중도 포기하면 무료 "평생 1회 체험"을 돌려줄까?** — ✅ **LOCKED: B**

> 확정 내용: abandon 시 서버 세션을 명시적으로 종료하고, **같은 날 다시 시작 가능**하게 한다.
> 이미 소비한 reward ad budget은 복구하지 않는다.
> **backend abandon endpoint 신설을 구현 범위로 기록한다.**

(현재: 체험 소모 여부는 **완료된 세션 수** 기준(`count_completed_mock_sessions`)이므로 포기해도 체험은 남는다. 그러나 서버 세션을 닫는 API가 없어 포기는 로컬만 정리되고, 서버 세션은 그날 자정까지 살아 있어 재시작이 막힌다. 리워드 예산 3개도 이미 소모된 상태로 남는다.)

A. 현행 유지. 포기해도 체험은 남지만 **오늘은 다시 시작할 수 없다**.
B. 포기 시 서버 세션을 닫아 **같은 날 다시 시작할 수 있게** 한다. 소모된 광고 예산은 복구하지 않는다.
C. 포기 시 세션과 광고 예산을 모두 초기화해 완전히 처음부터 다시 하게 한다.

Recommended: B
Reason: A는 "포기"라는 버튼이 실제로는 아무것도 되돌리지 않으면서 오늘의 재도전만 막는 최악의 조합이다. C는 광고 예산을 무제한 리셋할 수 있게 되어 리워드 광고 어뷰징 경로가 열린다. B는 사용자에게 명확한 회복 경로를 주면서 광고 예산은 하루 상한으로 계속 보호한다. 다만 B는 **서버에 abandon 엔드포인트 신설이 필요하므로 이번 리뉴얼과 별도 백엔드 작업으로 잡아야 한다** — 그 전까지는 T2 권장안(스테이지 라우팅 + nonce 보존 + 탈출구 보장)만으로도 데드엔드 자체는 해소된다.

---

## 문서 상태

- **2026-08-08: Q1–Q9 전부 제품 소유자 승인 완료 → LOCKED.** 이 문서는 이제 결정 기록이자 계약이다.
- Q3·Q6·Q7·Q8은 "기존 사용자에게서 무언가를 회수할 것인가"를 묻는 질문이었고,
  **네 개 모두 회수하지 않는 방향으로 확정**됐다.
- 후속 문서: `DESIGN.md` (UX/UI source of truth) — 이 문서의 LOCKED 결정만을 전제로 작성한다.

### 구현 범위로 이월된 항목 (DESIGN.md 범위 밖, 별도 작업)

| 항목 | 출처 | 성격 |
|---|---|---|
| `POST /v1/mock-exams/{id}/abandon` 신설 | Q9 | **backend 신규 엔드포인트** |
| A/B/C 버킷 임계값 확정 | Q2 | 실제 signal + 테스트 케이스 기반, **DESIGN.md에서 만들지 않음** |
| `AudioMetrics.isEstimated` 필드 추가 | T4 | backend 응답 필드 추가(하위 호환) |
| `confidence` 산출을 LLM → 서버 결정론으로 이관 | T4 | backend 정책 |
| client/backend plan mapping 불일치 정리(`exam_pass`/`premium`) | Q8 | **기술 부채 등록** |
| 시작·조정 게이트의 reward nonce 재사용 | Q4 | 클라이언트 전용 수정 |
