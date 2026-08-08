# DailyOPIc — IMPLEMENTATION_PLAN.md

**DESIGN.md P0–P8을 프로덕션 안전 로드맵으로 전환한 문서.**

작성일: 2026-08-08
전제 문서: `docs/PRODUCT.md` · `docs/audit/UI_BASELINE_AUDIT.md` · `docs/DESIGN_DECISIONS.md` (Q1–Q9 LOCKED) · `docs/DESIGN.md`
저장소: `DailyOPIc/` (iOS, branch `feat/1`) · `DailyOPIc-BE/` (FastAPI, branch `feat/46`)
상태: **계획 확정. 구현 미시작. 배포 없음. 외부 리소스 변경 없음.**

> **DailyOPIc는 실사용자가 있는 라이브 서비스다.** 이 문서의 모든 결정은
> "동작한다"와 "출시해도 안전하다"를 **서로 다른 게이트**로 취급한다.

---
---

# 1. Release safety principles

## 1.1 두 개의 게이트

| 게이트 | 질문 | 통과 조건 |
|---|---|---|
| **G1 — 동작한다** | 내 머신/시뮬레이터에서 되는가 | 빌드 성공 + 단위 테스트 통과 + 시뮬레이터 수동 확인 |
| **G2 — 출시해도 안전하다** | 지금 설치된 앱과 프로덕션 데이터가 무사한가 | 하위 호환 증명 + 롤백 경로 + 격리 검증 + 리스크 승인 |

**G1 통과가 G2를 함의하지 않는다.** 특히 백엔드는 G1이 로컬 인메모리 스토어에서 통과해도
프로덕션 Firestore 문서 형태와 기존 클라이언트 디코더를 깨뜨릴 수 있다.

## 1.2 불변 규칙 (SP1–SP10)

| # | 규칙 |
|---|---|
| **SP1** | **프로덕션 Cloud Run 서비스를 개발 검증 용도로 먼저 바꾸지 않는다.** 검증은 로컬 → 에뮬레이터 → 무트래픽 candidate revision 순서다. |
| **SP2** | **이미 설치된 앱 버전이 계속 동작해야 한다.** 응답 필드는 **추가만** 하고, 삭제·의미변경·타입변경은 하지 않는다. |
| **SP3** | **Firestore 문서는 하위 호환을 유지한다.** 필드 추가는 optional + 서버 기본값. 기존 문서 백필이 필요하면 별도 리뷰된 마이그레이션으로만 한다. |
| **SP4** | **RevenueCat / AdMob / Firebase App Check·Auth / 상품·엔타이틀먼트·오퍼링 / 실사용 쿼터·사용량 데이터를 개발·테스트 목적으로 변조하지 않는다.** |
| **SP5** | **모든 API 변경은 4가지를 문서에 남긴다** — 하위 호환 / 롤아웃 / 롤백 / 격리 검증. |
| **SP6** | **candidate revision은 데이터 격리가 아니다.** 프로덕션 서비스 계정으로 프로덕션 Firestore를 쓴다. **읽기 전용 스모크(`/health`)에만 쓰고, 쓰기 경로 검증은 에뮬레이터에서 한다.** |
| **SP7** | **명시적 요청 없이 프로덕션 배포하지 않는다.** `main` 푸시가 곧 배포이므로 **`main` 머지 자체가 배포 행위다.** |
| **SP8** | **기능 플래그는 기본 OFF로 들어온다.** 특히 A/B/C 버킷은 임계값 확정 전까지 코드에 있되 꺼져 있다. |
| **SP9** | **한 커밋은 한 관심사.** 구조 변경과 표면 변경을 같은 커밋에 넣지 않는다 (롤백 경계를 만들기 위해). |
| **SP10** | **롤백은 계획의 일부다.** 되돌리는 방법을 모르면 그 변경은 아직 준비되지 않았다. |

## 1.3 "배포"의 정의 (이 저장소 한정 — 검증됨)

`.github/workflows/deploy-cloud-run.yml` 확인 결과:

```
push → main
  ├ test (pytest, 에뮬레이터 테스트 제외)
  ├ firestore-emulator (firebase emulators:exec + pytest)
  └ deploy  (needs: [test, firestore-emulator], if: push)
      ├ docker build/push
      ├ gcloud run deploy --no-traffic --tag candidate-<sha8>   ← 트래픽 0
      ├ curl <candidate-url>/health                              ← 스모크
      └ gcloud run services update-traffic --to-latest           ← 100% 즉시 승격
```

**중요한 두 가지 사실:**

1. **`main` PR은 배포하지 않고 `main` 푸시만 배포한다.** → PR 단계에서 전체 테스트가 무료로 돌아간다. 이것이 우리의 주 검증 채널이다.
2. **승격은 `--to-latest`, 즉 0% → 100% 원샷이다.** 점진적 카나리가 없다. → **배포 리스크는 "머지 시점"에 전부 몰려 있다.** 그래서 백엔드 변경은 반드시 무해한 조각으로 잘라야 한다.

## 1.4 페이월 카피 원칙 (교차검증 결과 반영)

> 사용자 지시: 상위 플랜의 주 가치는 "문제 세트를 더 준다"가 아니라
> **"더 깊고 풍부한 AI 답변 분석"**이어야 한다. 단, **실제 백엔드 계약이 뒷받침하는 범위에서만.**

**교차검증 결과 — `ai.py:1609` 실측:**

```python
strip_long = str(depth) in {"summary", "basic"}
```

| 플랜 | `analysis_depth` | `correctedAnswer` | `sampleAnswer` | `targetGap` |
|---|---|---|---|---|
| free | `summary` | ❌ | ❌ | ❌ |
| **basic (₩2,900)** | `basic` | **❌** | **❌** | **❌** |
| plus (₩4,900) | `detailed` | ✅ | ✅ | ✅ |
| pro (₩7,900) | `focus` | ✅ | ✅ | ✅ |

**세 가지 확정 사실:**

1. **`basic`은 `summary`와 분석 내용이 완전히 동일하다.** 베이직의 실제 가치는
   광고 제거 + 데일리 1→3세트 + 모의고사 매일(체험 아님) + 리프레시 보너스뿐이다.
2. **`focus`(프로)와 `detailed`(플러스)는 실행 경로가 완전히 같다.** `strip_long`이
   유일한 분기다. **"프로는 문항별 코칭"은 현재 구현되지 않았다.**
   → `DESIGN.md §21.3`과 `§25.3`의 "프로: 문항별" 표기는 **이 문서에서 정정한다.**
3. **모의고사 평가는 depth를 완전히 무시한다** (`ai.py:1705` `del depth`).
   모든 플랜이 동일한 모의고사 결과를 받는다.

**따라서 페이월 카피 계약은 다음과 같이 확정한다.**

| | 정직하게 말할 수 있는 것 | 말할 수 없는 것 |
|---|---|---|
| 베이직 | 광고 완전 제거 · 매일 모의고사 · 데일리 3세트 | ~~더 깊은 분석~~ |
| 플러스 | **교정된 답변 + 모범 답안 + 목표 격차 분석** · 광고 없음 | ~~베이직보다 깊은 분석~~ (플러스가 첫 심화 지점) |
| 프로 | 플러스의 모든 분석 + **가장 큰 학습량**(데일리 20 / 모의 5) + 기록 무제한 | ~~문항별 코칭~~ (미구현) |

> **⛔ P6 착수 블로커:** "상위 플랜 = 더 깊은 분석" 위계를 **베이직에도** 적용하려면
> `strip_long`을 `{"summary"}`로 좁혀야 하며, 이는 **무료↔유료 경계를 바꾸는 제품 결정**이다.
> 임의로 하지 않는다. §3 P6의 `REQUIRES PRODUCT DECISION` 참조.
> 프로의 "문항별 코칭"도 마찬가지로 **없는 기능이므로 만들어내지 않는다.**

---

# 2. Dependency graph

## 2.1 그래프

```
              ┌──────────────────────────────────────────┐
              │ P-1  검증 인프라 (신규 · DESIGN.md 미포함) │
              │  공유 xcscheme · local xcconfig · iOS CI   │
              └────────────────────┬─────────────────────┘
                                   │ (모든 iOS 검증의 전제)
              ┌────────────────────▼─────────────────────┐
              │ P0  디자인 토큰 기반                       │
              │  타이포·간격·색·코너·44pt·모달 컨테이너      │
              │  + 【승격】 페이월 Button 접근성 수정        │
              └───┬──────────────────────────┬────────────┘
                  │                          │
    ┌─────────────▼──────────┐   ┌───────────▼───────────┐
    │ P1  세션 보존 아키텍처   │   │ P8a 플랜 매핑 정리     │
    │  VM 소유권 · cover 전환  │   │ 【승격】 P8 → P0 직후  │
    │  드래프트 · 시스템 탭바   │   └───────────┬───────────┘
    └───┬────────────┬───────┘               │
        │            │                       │
┌───────▼──────┐ ┌───▼────────────┐          │
│ P2 모의고사   │ │ P3 말하기       │          │
│  데드엔드     │ │  상태 머신      │          │
│  nonce 재사용 │ │  종료/제출 분리 │          │
│  게이트 UX    │ │  인터럽션 복구  │          │
└───────┬──────┘ └───┬────────────┘          │
        │            │                       │
        │      ┌─────▼──────────┐            │
        │      │ P4 결과 + 명명  │            │
        │      │  밴드 · 세트    │            │
        │      │  A버킷 · B/C off│            │
        │      └─────┬──────────┘            │
        │            │                       │
        │            │      ┌────────────────▼──────────┐
        │            │      │ P6 페이월·광고·통계         │
        │            │      │  ⛔ 카피 결정 대기(§1.4)    │
        │            │      └────────────┬──────────────┘
        │            │                   │
        └────────────┴───────────────────┴──────┐
                                                 │
   ┌═════════════════════════════════════════┐   │
   ║ P5  백엔드 (독립 트랙 · P0와 동시 착수)   ║   │
   ║ 【정정】 DESIGN.md는 P4 이후로 배치했으나  ║   │
   ║  리드타임 때문에 P0와 병렬로 시작해야 함   ║   │
   ║  5a abandon 엔드포인트   → P2 재시작 해제  ║   │
   ║  5b isEstimated          → B버킷·WPM 해제  ║   │
   ║  5c 결정론 confidence    → 5d의 전제       ║   │
   ║  5d A/B/C 임계값 확정    → B/C 플래그 ON   ║   │
   ║  5e C버킷 AI 사전 차단   → 비용 절감       ║   │
   └═════════════════════════════════════════┘   │
                                                 │
                            ┌────────────────────▼────┐
                            │ P7  접근성 마감           │
                            │  (모든 UI 확정 후)        │
                            └────────────┬────────────┘
                                         │
                            ┌────────────▼────────────┐
                            │ P8b  잔여 기술 부채       │
                            └─────────────────────────┘
```

## 2.2 특별 의존성 심사 (요청 항목 전수)

| 항목 | 올바른 위치 | 선행 조건 | 판정 |
|---|---|---|---|
| **design tokens / Dynamic Type** | **P0** | P-1 (검증 수단) | ✅ DESIGN.md 순서 유지 |
| **session preservation architecture** | **P1** | P0 (컴포넌트 계약) | ✅ 유지 |
| **system tab/navigation shell** | **P1** | P1의 VM 소유권 이동과 **동일 커밋 금지**, 같은 단계 별도 커밋 | ✅ 유지 |
| **paywall Button accessibility fix** | **P0** ← *P6에서 승격* | 없음 (독립) | 🔁 **순서 변경** |
| **mock exam nonce reuse** | **P2** | P1 (VM 소유권) | ✅ 유지 |
| **mock exam abandon backend endpoint** | **P5a** ← *P5 내 최우선* | 없음 (독립) | 🔁 **P0와 병렬 착수** |
| **recording state machine** | **P3** | P0, P1 | ✅ 유지 |
| **recording termination separation** | **P3** | 상태 머신과 **동일 단계, 후속 커밋** | ✅ 유지 |
| **interruption recovery** | **P3** | 상태 머신 **선행** (interrupted가 상태이므로) | ✅ 유지 |
| **A/B/C evaluation policy** | **UI는 P4 / 활성화는 P5d 이후** | 5b + 5c + 5d | ⚠️ **분리 필수** |
| **isEstimated** | **P5b** | 없음 (독립, 필드 추가) | 🔁 **조기 착수** |
| **deterministic confidence policy** | **P5c** | 5b (신호 필요) | ✅ 유지 |
| **paywall redesign** | **P6** | P0, P8a, **+ §1.4 제품 결정** | ⛔ **블로킹 의존성 추가** |
| **ad relocation** | **P6** | **P1의 시스템 탭바 복귀** | ⚠️ **숨은 의존성 명시** |
| **statistics redesign** | **P6** | P4 (밴드 표시 규칙) | ✅ 유지 |
| **accessibility final pass** | **P7** | P0–P6 전부 | ✅ 유지 |
| **plan mapping cleanup** | **P8a** ← *P8에서 승격* | 없음 (독립) | 🔁 **P6 이전으로** |

## 2.3 DESIGN.md 순서 중 **그대로 구현하면 안 되는 것** (4건)

### 🔁 정정 1 — 페이월 `Button` 전환을 P6에 두지 않는다

**DESIGN.md P6-30 → P0으로 승격.**

- **이유:** `PaywallView.swift:109-113`의 `.onTapGesture`는 VoiceOver·풀 키보드 접근·스위치 제어
  사용자가 **구독을 완료할 수 없게 만드는 현재 진행형 결함**이다. 매출과 App Store 접근성
  심사 양쪽에 걸린다. 의존성은 0이고 변경 범위는 한 파일이다.
- **P6까지 미루면** 페이월 전면 재설계(카피 결정 대기 중)에 묶여 무기한 지연된다.

### 🔁 정정 2 — 백엔드(P5)를 P4 뒤에 놓지 않는다

**DESIGN.md는 P5를 P4 다음으로 적었으나, P0와 병렬로 착수한다.**

- **이유:** 백엔드 리드타임 = PR → CI(에뮬레이터 포함) → 머지 → candidate → 승격 → **기존
  클라이언트 무해 확인 기간**. 여기에 `isEstimated` 없이는 B 버킷 판정도 WPM 표시도 불가능하다.
- 순차로 하면 P4에서 만든 B/C UI가 P5 전체 사이클이 끝날 때까지 죽어 있다.
- **P5a(abandon)와 P5b(isEstimated)는 다른 어떤 것에도 의존하지 않는 순수 추가**이므로
  지금 당장 시작할 수 있는 유일한 백엔드 작업이다.

### ⚠️ 정정 3 — A/B/C를 "P4의 한 항목"으로 다루지 않는다

**UI 구현(P4)과 정책 활성화(P5d 이후)를 별도 릴리스로 분리한다.**

- DESIGN.md도 "플래그 비활성 출시"를 언급했으나 로드맵상 한 줄로 묶여 있어 오해 여지가 있다.
- **P4에서 나가는 것:** B/C 화면, 문구, VoiceOver, 통계 제외 로직 — 전부 `false`인 플래그 뒤.
- **P5d 이후에 나가는 것:** 플래그 ON 1줄.
- 이렇게 해야 임계값이 틀렸을 때 **앱 재심사 없이** 되돌릴 수 있다.

### 🔁 정정 4 — 플랜 매핑 정리를 P8까지 미루지 않는다

**DESIGN.md P8-42 → P8a로 분리해 P6 이전에 배치.**

- **이유:** P6 페이월 재설계가 플랜 매핑을 소비한다. 매핑이 틀린 상태로 페이월을 다시 그리면
  **같은 파일을 두 번 만진다.**
- `StoreService.highestPlan`은 `lower.contains(candidate.rawValue)` 부분 문자열 검사라
  베이직 패키지(`$rc_monthly`)를 `productIdentifier = opic_basic_monthly` 우연으로만 잡는다.
  RevenueCat에서 패키지 식별자를 바꾸는 순간 **무료로 강등**된다.

## 2.4 신규 선행 단계 — P-1 (DESIGN.md에 없음)

**검증된 사실:** `DailyOPIc.xcodeproj`에 **공유 스킴이 하나도 없다.**
스킴은 `xcuserdata/`(gitignore 대상)에만 존재한다.

→ **현재 상태로는 `xcodebuild test`를 재현 가능하게 돌릴 수 없고, iOS CI도 만들 수 없다.**
→ 모든 단계의 "Validation before release"가 이 한 가지에 막혀 있다.
→ **P-1을 첫 슬라이스로 세운다.**

---

# 3. P0–P8 implementation roadmap

---

## P-1 — 검증 인프라 (신규 선행 단계)

### Objective
이후 모든 단계가 "출시해도 안전하다"를 증명할 수 있는 재현 가능한 검증 수단을 만든다.
제품 동작은 **한 줄도 바꾸지 않는다.**

### Repository
`DailyOPIc` (+ `DailyOPIc-BE`는 문서만)

### Exact areas likely to change
| 대상 | 성격 |
|---|---|
| `DailyOPIc.xcodeproj/xcshareddata/xcschemes/DailyOPIc.xcscheme` | **신규** (공유 스킴) |
| `Config/Local.xcconfig.template` | **신규** (로컬 백엔드 지시용 템플릿. `.gitignore`가 이미 `Config/*.local.xcconfig` 제외) |
| `.github/workflows/ios-tests.yml` | **신규** (build + `xcodebuild test`) |
| `DailyOPIcTests/` | 기존 23개 Swift Testing 테스트 확인만 |

> `Config/Debug.xcconfig`의 `DAILYOPIC_API_BASE_URL`이 **현재 프로덕션 Cloud Run을 가리킨다.**
> 파일 자체는 건드리지 않고, `.local.xcconfig` 오버라이드 경로를 문서화한다. (SP1)

### Dependencies
없음.

### Production risk
**LOW** — 프로덕션 코드 경로가 없다. 스킴 공유는 빌드 산출물에 영향을 주지 않는다.
유일한 주의: 공유 스킴의 기본 xcconfig가 `Debug`이므로 **개발자가 실수로 프로덕션 백엔드에
쓰기 요청을 보낼 수 있다.** → 템플릿과 README로 로컬 오버라이드를 기본 절차로 만든다.

### Compatibility requirements
해당 없음 (런타임 변경 없음).

### Validation before release
- `xcodebuild -project DailyOPIc.xcodeproj -scheme DailyOPIc -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` 성공
- `xcodebuild test` 로 기존 23개 테스트 전부 통과
- 새 clone에서 스킴이 보이는지 확인

### Isolated backend validation
해당 없음.

### Rollback boundary
파일 3개 추가뿐. `git revert` 단일 커밋.

### Commit boundary
```
chore(ci): share DailyOPIc xcscheme for reproducible test runs
chore(config): add local backend xcconfig template and document override
ci(ios): add build and unit test workflow
```

### Done criteria
- [ ] 공유 스킴이 커밋되어 있고 새 clone에서 `xcodebuild -list`에 나타난다
- [ ] `xcodebuild test`가 23/23 통과
- [ ] CI가 PR에서 자동 실행되고 초록색
- [ ] `Config/*.local.xcconfig`로 로컬 백엔드 지시 절차가 문서화됨

---

## P0 — 디자인 토큰 기반

### Objective
컴포넌트를 만들기 전에 잠가야 하는 것을 잠근다: Dynamic Type 대응, 4pt 그리드,
WCAG 통과 색, `.continuous` 코너, 44pt 보장, 공통 모달 계약.
**+ 페이월 구매 버튼 접근성 결함 수정 (P6에서 승격).**

### Repository
`DailyOPIc`

### Exact areas likely to change
| 파일 | 변경 |
|---|---|
| `Resources/Fonts/AppTypography.swift` | 절대 크기 7종 → iOS 텍스트 스타일 7종 (§6.3 1:1 매핑) |
| `Resources/Fonts/AppTypography.swift` (`AppSpacing`) | 6/10/16/22/28 → 4/8/16/24/32/48 |
| `Resources/Fonts/AppTypography.swift` (`AppRadius`) | 12/16/22/28 → control 12 / card 16 / sheet 24 |
| `Resources/Colors/AppPalette.swift` | `secondaryInk` 라이트 `#6B7280`→`#5B6472` · `danger` 라이트 `#EF4444`→`#DC2626` · **`actionOnPrimary` 신규**(라이트 흰색/다크 `#111827`) |
| `Views/Components/PrimaryButton.swift` | 로딩 중 접근성 이름 보존 + 44pt 보장 + `.continuous` |
| `Views/Components/` (신규) | `ModalContainer` — `.isModal` + 닫기 + 단일 스크림 |
| `Views/Screens/Paywall/PaywallView.swift` | **`.onTapGesture` → `Button`** (`:109-113`) |
| `system(size:` 24개 호출부 | 토큰 경유로 교체 |

### Dependencies
P-1.

### Production risk
**MEDIUM**

구체적으로 무엇이 사용자에게 갈 수 있는가:
- **타이포:** §6.3 매핑표대로 기본 Dynamic Type 크기에서 픽셀 동일하다. 단
  **AX 크기에서는 레이아웃이 실제로 달라진다** — 이것이 의도이지만, 잘림/겹침이 새로 생길 수 있다.
- **간격:** `sm` 10→8, `lg` 22→24로 바뀌면 **모든 화면의 여백이 미세하게 이동**한다.
  기능 회귀는 아니나 시각 회귀 검토가 필요하다.
- **색:** 3개 토큰이 어두워진다. 브랜드 액센트(`primary`)는 **바꾸지 않는다.**
- **페이월 `Button` 전환:** 매출 경로다. `.buttonStyle(.plain)`으로 시각 동일성을 유지하되
  탭 영역이 카드 전체로 유지되는지 반드시 확인한다.

### Compatibility requirements
- 서버 API 무관.
- 영속 데이터 무관.
- **App Store 심사:** 접근성 개선이므로 반려 위험은 감소한다.

### Validation before release
| 종류 | 내용 |
|---|---|
| Swift 단위 | 기존 23개 회귀 + **신규**: 색 토큰 대비비 계산 테스트(4.5:1 단언), 44pt 최소 프레임 테스트 |
| Xcode 빌드 | Debug/Release 양쪽 warning 0 증가 |
| 시뮬레이터 | iPhone 17 Pro |
| **Dynamic Type** | `xcrun simctl ui <udid> content_size {extra-small, large, xxx-large, accessibility-medium, accessibility-extra-extra-extra-large}` × 11화면 스크린샷 |
| **Light/Dark** | `xcrun simctl ui <udid> appearance {light,dark}` × 11화면 |
| 접근성 | Accessibility Inspector Audit — **페이월에서 구매 버튼이 VoiceOver로 도달·활성화되는지 실제 확인** (구매는 하지 않음, 시트 표시까지만) |
| 회귀 | 기본 크기 스크린샷 diff = 시각 변화 없음 |

> **SP4 준수:** 페이월 검증은 **StoreKit 구매를 실행하지 않는다.** 버튼 도달 가능성과
> 구매 시트 호출까지만 확인하고 즉시 취소한다.

### Isolated backend validation
해당 없음 (백엔드 무관).

### Rollback boundary
커밋 단위로 되돌릴 수 있다. 토큰 파일 2개 + 컴포넌트가 분리되어 있으므로
**색만 되돌리기 / 간격만 되돌리기**가 가능하다. TestFlight 빌드 단위 롤백.

### Commit boundary
```
refactor(design-system): migrate AppTypography to Dynamic Type text styles
refactor(design-system): align AppSpacing to 4pt grid
fix(design-system): raise secondaryInk and danger contrast to WCAG AA
feat(design-system): add actionOnPrimary token for dark mode button labels
refactor(design-system): adopt continuous corner style across components
fix(a11y): preserve PrimaryButton accessibility label while loading
feat(design-system): add ModalContainer enforcing isModal and dismiss affordance
fix(paywall): make tier selection an accessible Button instead of tap gesture
```

### Done criteria
- [ ] `grep -c "system(size:"` == 0 (토큰 외부)
- [ ] `relativeTo:` 또는 텍스트 스타일 미사용 폰트 0건
- [ ] Accessibility Inspector Contrast: 라이트/다크 각각 위반 0건
- [ ] AX5에서 11개 화면 텍스트 잘림 0건, 가로 스크롤 0건
- [ ] 기본 Dynamic Type 크기 스크린샷 diff 시각 변화 0
- [ ] VoiceOver로 페이월 3개 플랜 전부 선택 가능

---

## P1 — 세션 보존 아키텍처

### Objective
"사용자의 노력은 사라지지 않는다"(P3 원칙)를 구조로 보장한다.
ViewModel 소유권을 `AppEnvironment`로 올리고, 가이드·온보딩을 루트 교체에서 cover로 바꾼다.

### Repository
`DailyOPIc`

### Exact areas likely to change
| 파일 | 변경 |
|---|---|
| `Services/AppEnvironment.swift` | `practiceViewModel` / `mockViewModel` 저장 프로퍼티 추가 |
| `Views/Screens/Main/MainTabView.swift` | `@State` VM 소유 제거 → 환경에서 참조 |
| `Views/AppRootView.swift` | 가이드·온보딩 분기 제거 → `.fullScreenCover` 2개 |
| `ViewModels/PracticeViewModel.swift` | 드래프트 저장/복원 훅 |
| `Services/Persistence/` | `PracticeDraftRecord` (SwiftData) — `MockDraftRecord` 패턴 재사용 |
| `Views/Screens/Main/MainTabView.swift` | 커스텀 플로팅 탭바 → 시스템 `TabView` |
| `Views/Screens/Setup/SetupView.swift` | `dismiss()` + 0.2초 `resetOnboarding()` → cover 제시 |

### Dependencies
P0 (컴포넌트 계약 확정).

### Production risk
**HIGH** — 이번 리뉴얼에서 **가장 위험한 단계**다.

구체적으로 무엇이 사용자에게 갈 수 있는가:
- **앱 시작 경로를 바꾼다.** `AppRootView` 분기가 잘못되면 **런치 직후 빈 화면 또는 크래시**다.
- **`AppEnvironment`가 VM을 소유하면 생명주기가 앱 전체로 늘어난다.** 메모리 누수·좀비 상태·
  이전 세션 잔존이 새로 생길 수 있다.
- **SwiftData 스키마 추가**(`PracticeDraftRecord`) — 아래 호환성 항목 참조.
- **온보딩 경로 변경:** 신규 사용자 첫 실행이 막히면 **신규 유입이 0이 된다.** 최우선 검증 대상.

### Compatibility requirements
| 축 | 요구 |
|---|---|
| 서버 API | 변경 없음 |
| **SwiftData** | `PracticeDraftRecord`는 **신규 모델 추가**다. 기존 `PracticeHistoryRecord` / `MockHistoryRecord` / `MockDraftRecord`는 **필드 변경 금지.** 신규 모델 추가는 SwiftData 경량 마이그레이션 범위 안이지만, **기존 기록 보존을 실기기 업그레이드 시나리오로 반드시 확인한다.** |
| `AppPreferences` | `resetOnboarding` / `beginGuide` / `finishGuide` 의미를 바꾸지 않는다. 호출 지점만 바꾼다. **v1 완료 사용자가 가이드를 다시 강제당하면 안 된다** — 기존 테스트 `completedV1UserMigratesWithoutForcedGuide`가 이미 이를 지킨다 |

### Validation before release
| 종류 | 내용 |
|---|---|
| Swift 단위 | `completedV1UserMigratesWithoutForcedGuide`, `guideProgressAndSkipRemainReenterable`, `onboardingAndMockSurveyPersist` 회귀 필수 |
| **신규 Swift 테스트** | 드래프트 저장/복원 라운드트립, 기존 SwiftData 기록이 신규 모델 추가 후에도 읽히는지 |
| 시뮬레이터 시나리오 | ① 신규 설치 → 온보딩 완주 ② 기존 사용자 업그레이드 → 가이드 강제 안 됨 ③ 데일리 진행 중 → 설정 → 난이도 변경 cover → 복귀 시 세션 유지 ④ 데일리 진행 중 → 도움말 → 복귀 ⑤ 탭 전환 왕복 ⑥ 앱 강제 종료 → 재실행 → 드래프트 복원 |
| **업그레이드 검증** | 이전 빌드 설치 → 데이터 생성 → 신규 빌드 덮어쓰기 설치 → **기록 보존 확인** |
| 접근성 | cover 2종에 `.isModal` + 닫기 존재 |

### Isolated backend validation
해당 없음. **단, 시뮬레이터 검증은 `Config/*.local.xcconfig`로 로컬 FastAPI를 가리키게 한다** (SP1·SP4 — 프로덕션 쿼터를 검증에 소모하지 않기 위해).

### Rollback boundary
**커밋을 4개로 쪼개 각각 독립 롤백 가능하게 만든다.**
가장 위험한 `AppRootView` 변경을 단독 커밋으로 분리해 그것만 되돌릴 수 있게 한다.
릴리스 단위로는 TestFlight 빌드 롤백.

### Commit boundary
```
refactor(session): move practice and mock view models into AppEnvironment
refactor(navigation): present guide and onboarding as fullScreenCover
feat(session): persist practice draft for crash and relaunch recovery
refactor(navigation): restore system TabView and remove floating tab bar
test(session): cover draft round-trip and legacy record preservation
```

### Done criteria
- [ ] 데일리 진행 중 설정/도움말/난이도 변경 왕복 후 **세션 100% 유지**
- [ ] 앱 강제 종료 후 재실행 시 드래프트 복원
- [ ] 이전 빌드에서 만든 기록이 신규 빌드에서 전부 읽힘
- [ ] 신규 설치 온보딩 완주 성공
- [ ] 기존 v1 완료 사용자에게 가이드가 강제되지 않음
- [ ] 배너가 탭바에 가려지지 않음

---

## P2 — 모의고사 데드엔드 해소

### Objective
서버 stage 9개와 화면을 1:1로 매핑해 "이어서 하기"와 "포기"가 동시에 사라지는 상태를 없앤다.
리워드 nonce를 실패 시 재사용하고, 광고 게이트에 예산을 사전 고지한다.

### Repository
`DailyOPIc` (P2 범위 내 백엔드 변경 **없음**. 당일 재시작은 P5a 대기)

### Exact areas likely to change
| 파일 | 변경 |
|---|---|
| `ViewModels/MockExamViewModel.swift` | `enterResume` (`:153-169`) stage 기반 라우팅 · `performStart` (`:221-282`) catch에서 `self.session` 보존 · `acquireRewardNonce` 재사용 컨텍스트 (`EvaluationRetryContext` 패턴 이식) · `canResetExam` 조건을 "서버 세션 존재"로 |
| `Views/Screens/Main/MockExam/MockExamScreen.swift` | stage별 화면 분기 |
| `Views/Screens/Main/MockExam/` (신규) | 광고 게이트 화면 컴포넌트 (3개 게이트 공용) |
| `Services/Ads/AdService.swift` | `State`(`loading/presenting/verifying/failed`)를 UI로 노출 |
| `Views/Components/` | `ResetMockExamDialog` → `.confirmationDialog` |

### Dependencies
P1 (VM 소유권 · cover 전환).

### Production risk
**MEDIUM-HIGH**

구체적으로 무엇이 사용자에게 갈 수 있는가:
- **리워드 nonce 재사용이 SSV 경로를 건드린다.** 서버는 `fail_request`에서 nonce를
  un-consume하지만(`state.py:1161-1164`, `:2145-2149`), 클라이언트가 잘못 재사용하면
  **광고 예산이 조기 소진되거나 게이트가 영구히 막힐 수 있다.**
- **무료 사용자의 하루 리워드 인텐트는 정확히 3개**이고 모의고사 완주에 필요한 것도 정확히 3개다
  (`plans.py:_MOCK_REWARD_GATES = 3`). **여유가 0이다.** 재사용 로직 버그 = 그날 모의고사 불가.
- **AdMob 동작 자체는 바꾸지 않는다** (SP4). 상태 표시만 추가한다.

### Compatibility requirements
| 축 | 요구 |
|---|---|
| 서버 API | **변경 없음.** 기존 `create_reward_intent`(`routes.py:1728`) 응답을 그대로 쓴다 |
| **stage 라우팅** | 서버가 **미래에 새 stage를 추가해도** 클라이언트가 크래시하지 않아야 한다 → `default:` 케이스에서 안전한 폴백(인트로 + 포기 가능) 필수. 기존 테스트 `unknownServerStatusesDecodeSafely` 정신을 유지 |
| SwiftData | `MockDraftRecord` 스키마 **변경 금지** |

### Validation before release
| 종류 | 내용 |
|---|---|
| Swift 단위 | **신규**: 9개 stage × 라우팅 결정 테이블 테스트 (순수 함수로 추출해 테스트 가능하게) · 알 수 없는 stage 폴백 테스트 · nonce 재사용 컨텍스트 보존 테스트 |
| 로컬 API | **로컬 FastAPI**에서 9개 stage를 인위적으로 만들어 각각 진입 (SP1) |
| 시뮬레이터 | 각 stage에서 ① 진입 ② 탭 이탈 ③ 복귀 ④ 포기 가능 여부 |
| **핵심 회귀** | `awaiting_start_ad` + `questionSet == null` 상태에서 **포기 버튼이 보이는가** |
| 광고 | 테스트 광고 단위로만 확인. **프로덕션 광고 단위로 리워드를 소모하지 않는다** (SP4) |

### Isolated backend validation
백엔드 코드 변경은 없지만 **검증용 stage 생성이 필요하다.**
→ **로컬 FastAPI + Firestore 에뮬레이터**로 9개 stage를 만든다.
→ **프로덕션 서비스에 모의고사 세션을 만들어 검증하지 않는다** (SP1·SP4).

### Rollback boundary
`MockExamViewModel` 변경이 대부분이므로 파일 단위 revert가 깨끗하다.
nonce 재사용은 **별도 커밋**으로 분리해 그것만 되돌릴 수 있게 한다.

### Commit boundary
```
fix(mock-exam): route resume by server stage instead of question set presence
fix(mock-exam): retain session when start fails so resume and abandon stay reachable
feat(mock-exam): reuse reward nonce after a failed gate attempt
feat(mock-exam): surface ad gate progress and remaining daily ad budget
refactor(mock-exam): replace reset dialog with confirmationDialog
test(mock-exam): cover stage routing table and unknown stage fallback
```

### Done criteria
- [ ] 9개 stage 전부에서 진행 또는 포기가 **항상** 가능
- [ ] 시작 실패 후에도 `canResume` 또는 `canResetExam` 중 하나 이상 true
- [ ] 광고 로드 실패 후 재시도가 **광고를 다시 보게 하지 않음**
- [ ] 알 수 없는 stage에서 크래시 없음
- [ ] "광고 3편 중 N번째"가 게이트마다 정확히 표시

---

## P3 — 말하기 상태 머신

### Objective
`isListening` Bool 하나로 붕괴된 8상태를 복원하고, 종료와 제출을 분리하며(Q1 LOCKED),
인터럽션에서 오디오를 보존한다.

### Repository
`DailyOPIc`

### Exact areas likely to change
| 파일 | 변경 |
|---|---|
| `Services/Speech/SpeechRecognitionService.swift` | `handleInterruption` (`:231-238`)에서 `AVAudioSessionInterruptionType` 분기 · `cancel()` 호출 제거하고 오디오·전사 보존 · 재개 API 추가 |
| `Services/Speech/SpeechRecognitionService.swift` | `RecordingState` 5케이스 → DESIGN §16 8상태 정합 |
| `ViewModels/PracticeViewModel.swift` | 180초 타이머(모의고사 패턴 이식) · `stop()` 후 즉시 제출 제거 |
| `Views/Components/RecordingButton.swift` | 8상태 렌더링 + Reduce Motion |
| `Views/Screens/Main/Practice/` (신규) | 답변 확인 카드 · 권한 거부 전용 화면 |

### Dependencies
P0, P1.

### Production risk
**HIGH** — 앱의 유일한 핵심 기능이다.

구체적으로 무엇이 사용자에게 갈 수 있는가:
- **`AVAudioSession` / `AVAudioEngine` 변경은 실기기에서만 진짜로 드러난다.**
  시뮬레이터는 실제 인터럽션(전화·시리·다른 앱 오디오)을 재현하지 못한다.
- **인터럽션에서 오디오를 보존하려면 `cancel()`을 빼야 하는데, 잘못하면 오디오 파일 핸들·
  탭이 누수되어 다음 녹음이 아예 실패한다.**
- **종료/제출 분리는 사용자 습관을 바꾼다.** 기존 사용자가 "정지 = 제출"로 학습돼 있으므로
  확인 카드에서 멈춰 있으면 "분석이 안 된다"는 문의가 늘 수 있다 → 문구로 방어.
- 180초 타이머 도입 시 **기존에 3분 넘게 말하던 사용자의 답변이 잘린다.** Q1 LOCKED 결정이지만
  안내 문구가 없으면 버그로 인식된다.

### Compatibility requirements
| 축 | 요구 |
|---|---|
| 서버 API | 변경 없음. `AudioValidationError`의 최대 길이 제한과 180초가 충돌하지 않는지 확인 |
| 권한 | `Info.plist` 사용 설명 문구는 **바꾸지 않는다** (바꾸면 심사 재검토 대상) |
| SwiftData | 무관 |

### Validation before release
| 종류 | 내용 |
|---|---|
| Swift 단위 | **신규**: 상태 전이 테이블 테스트(8상태 × 이벤트) — 서비스에서 순수 상태 머신을 분리해 오디오 없이 테스트 |
| 시뮬레이터 | 녹음 → 확인 카드 → 다시 녹음 → 분석하기 루프 5회 |
| **실기기 필수** | ① 녹음 중 전화 수신 → `interrupted` → 이어서 녹음 ② 시리 호출 ③ 다른 앱 오디오 ④ 180초 완주 ⑤ 권한 거부 → 설정 → 복귀 |
| 접근성 | VoiceOver로 8상태 전부 발표되는지 · 남은 시간 `accessibilityValue` · 60/30/10초 발표 |
| 회귀 | 녹음 → 분석 → 결과가 여전히 성공 |

> **실기기 검증 없이 P3을 출시하지 않는다.** 시뮬레이터 통과는 G1일 뿐 G2가 아니다.

### Isolated backend validation
평가 요청은 **로컬 FastAPI + `MOCK_AI=true`**로 검증한다. 프로덕션 AI 호출을 소모하지 않는다 (SP4).

### Rollback boundary
`SpeechRecognitionService` 변경(인터럽션)과 UI 변경(상태 머신)을 **별도 커밋**으로 분리한다.
오디오 계층에 문제가 생기면 서비스 커밋만 되돌린다.

### Commit boundary
```
fix(speech): distinguish interruption began and ended and preserve captured audio
feat(speech): expose full recording state machine instead of isListening
feat(speaking): add maximum recording duration with explicit end notice
feat(speaking): separate recording end from submission with a review step
feat(speaking): add microphone permission recovery screen
test(speaking): cover recording state transition table
```

### Done criteria
- [ ] 전화 수신 후 **오디오와 전사가 남아 있고** 이어서 녹음 가능 (실기기)
- [ ] 180초 도달 시 자동 종료 + 명시적 안내
- [ ] 종료 후 확인 카드에서 다시 녹음이 무료임이 표시됨
- [ ] 8상태 각각 고유 라벨 + VoiceOver 발표
- [ ] 권한 거부 후 설정 왕복으로 복구 가능
- [ ] 연속 5회 녹음에서 오디오 세션 누수 없음

---

## P4 — 결과 신뢰도 + 명명 정리

### Objective
루브릭 숫자를 밴드로 바꿔 fake precision을 제거하고, "토큰"을 "새 문제 세트"로 교체한다.
A 버킷 결과 화면을 재구성하고, **B/C 버킷 UI는 만들되 플래그로 꺼서 출시한다.**

### Repository
`DailyOPIc`

### Exact areas likely to change
| 파일 | 변경 |
|---|---|
| `Views/Screens/Main/Practice/PracticeResultView.swift` | 밴드 표시 · A 버킷 재구성 · `analysis_depth` nil 처리 |
| `Views/Components/DailyTokenBadge.swift` | → `DailySetBadge` 개명 + 문구 + 잘못된 doc comment 수정 |
| `Models/EvaluationModels.swift` | 밴드 표현 타입 (숫자 변환 제거) · **`AudioMetrics.isEstimated` optional 디코딩 선반영** |
| `Views/Screens/Main/Practice/` (신규) | B 버킷 화면 · C 버킷 화면 (플래그 뒤) |
| `Views/Screens/Main/Practice/` (신규) | 세트 소진 화면 2종 (무료/유료 분기) |
| (신규) 플래그 | `AnswerConfidenceBucketsEnabled` — **기본 `false`** |

### Dependencies
P0. (P3와 병렬 가능하나 결과 화면이 말하기 흐름의 종점이므로 P3 뒤 권장)

### Production risk
**MEDIUM**

구체적으로 무엇이 사용자에게 갈 수 있는가:
- **숫자 점수를 없애면 "내 점수가 사라졌다"는 인식이 생길 수 있다.** 밴드 라벨이
  명확해야 한다. (감사에서 전 항목 "20"으로 보였던 것은 전 차원 `foundation`이었기 때문이며,
  숫자 제거로 이 오해 자체가 사라진다)
- **"토큰" → "세트" 개명은 순수 표시 변경**이지만, 사용자가 학습한 용어를 바꾼다.
- **`isEstimated` optional 디코딩을 미리 넣어두면** P5b가 나중에 나가도 클라이언트 재배포가
  필요 없다. **필드가 없을 때 `nil`로 안전 디코딩되는지 반드시 테스트한다.**
- **B/C 플래그가 실수로 켜져 나가면** 임계값 없이 등급이 숨겨진다 → 플래그 기본값 테스트 필수.

### Compatibility requirements
| 축 | 요구 |
|---|---|
| 서버 API | **변경 없음.** `isEstimated`는 **optional 추가 필드로 선디코딩**한다 (SP2 반대 방향 대비) |
| **디코딩** | 기존 테스트 `renamedResponseFieldsDecodeLegacyPayloadsDuringDeployment`, `evaluationRubricV2DecodesWithoutUsingNumericScoreAsPrimaryUI` 회귀 필수 |
| SwiftData | 기존 `PracticeHistoryRecord`에 저장된 **숫자 점수 기록을 밴드로 읽을 수 있어야 한다.** 저장 형식을 바꾸지 않고 표시만 바꾼다 |

### Validation before release
| 종류 | 내용 |
|---|---|
| Swift 단위 | 밴드 매핑 테스트(5밴드) · `isEstimated` 부재 시 nil 디코딩 · **플래그 기본값 false 단언** · 기존 기록 표시 |
| 시뮬레이터 | A 버킷 결과 전체 · 세트 소진 무료/유료 각각 · 플래그 ON 상태에서 B/C 화면(내부 확인용) |
| 접근성 | 밴드가 점 개수만이 아니라 라벨로도 전달되는지 · VoiceOver "5단계 중 3단계" |
| 회귀 | 과거 기록 열람 시 크래시 없음 |

### Isolated backend validation
`MOCK_AI=true` 로컬 FastAPI로 A/B/C 각각에 해당하는 응답을 수동 구성해 렌더링 확인.
**프로덕션 평가를 소모하지 않는다** (SP4).

### Rollback boundary
표시 계층 변경이므로 revert가 안전하다. 플래그가 있어 **B/C는 코드를 되돌리지 않고 끌 수 있다.**

### Commit boundary
```
refactor(evaluation): render rubric as five discrete bands instead of numeric scores
refactor(practice): rename daily token to question set across UI and copy
feat(practice): add plan-aware set exhaustion screens
feat(evaluation): decode optional isEstimated audio metric for forward compatibility
feat(evaluation): add low-confidence and invalid-answer screens behind a disabled flag
test(evaluation): cover band mapping, flag default, and legacy record rendering
```

### Done criteria
- [ ] 결과·통계 어디에도 100점 척도 숫자가 없음
- [ ] "토큰"·"크레딧"·"분석 횟수" 문자열 0건
- [ ] 세트 소진 시 무료/유료가 서로 다른 선택지를 봄
- [ ] `isEstimated` 없는 응답이 정상 디코딩됨
- [ ] 릴리스 빌드에서 B/C 플래그가 `false`
- [ ] 과거 기록 전부 열람 가능

---

## P5 — 백엔드 (독립 트랙 · **P0와 동시 착수**)

### Objective
DESIGN.md가 남긴 4개 하드 블로커를 해소한다. **각 항목은 서로 독립적이므로 별도 PR·별도 배포로 나간다.**

### Repository
`DailyOPIc-BE` (+ `DailyOPIc`는 소비 시점에만)

### 하위 슬라이스

| # | 내용 | 성격 | 선행 |
|---|---|---|---|
| **P5a** | `POST /v1/mock-exams/{id}/abandon` 신설 | **순수 추가** (신규 엔드포인트) | 없음 |
| **P5b** | `AudioMetrics.isEstimated` 응답 필드 추가 | **순수 추가** (optional 필드) | 없음 |
| **P5c** | `confidence` 산출을 LLM → 서버 결정론으로 이관 | **의미 변경** ⚠️ | P5b |
| **P5d** | A/B/C 임계값 확정 | **정책 신설** | P5b, P5c |
| **P5e** | C 버킷 AI 호출 사전 차단 | **동작 변경** ⚠️ | P5d |

### Exact areas likely to change
| 슬라이스 | 파일 |
|---|---|
| P5a | `app/api/routes.py` (신규 라우트) · `app/services/state.py` (세션 종료 전이) · `app/models/api.py` · `tests/test_mock_sessions.py` |
| P5b | `app/services/audio.py` (`AudioMetrics` 데이터클래스 + 추정 폴백 경로 3곳) · `app/models/api.py` · `tests/` 신규 |
| P5c | `app/services/ai.py` (`confidence` 산출 이관, 프롬프트에서 제거) · `tests/test_evaluation_calibration.py` |
| P5d | `app/services/audio.py` 또는 신규 `app/services/answer_quality.py` · 신규 테스트 |
| P5e | `app/api/routes.py` 평가 진입점 (`:2005` 부근) |

### Dependencies
P5a·P5b는 없음. P5c는 P5b. P5d는 P5b+P5c. P5e는 P5d.

### Production risk

| 슬라이스 | 리스크 | 구체적 영향 |
|---|---|---|
| **P5a** | **LOW** | 신규 경로. 기존 클라이언트는 호출하지 않는다. **단 `state.py`의 stage 전이 테이블을 건드리므로 기존 전이가 깨질 수 있다** → 에뮬레이터 테스트 필수 |
| **P5b** | **LOW** | optional 필드 추가. 기존 iOS는 무시한다. **JSON 응답 크기만 증가** |
| **P5c** | **HIGH** | `confidence` **값의 의미가 바뀐다.** 이미 배포된 앱이 이 값을 어떻게 쓰는지 확인 필요 — 현재 표시만 하지만, 값 분포가 급변하면 사용자 체감이 바뀐다 |
| **P5d** | **HIGH** | 새 정책. 잘못된 임계값 = **정상 답변이 C로 거부됨** = 서비스 사용 불가 |
| **P5e** | **MEDIUM** | AI 호출을 건너뛴다. 오탐 시 사용자가 평가를 못 받는다. **비용은 줄지만 오탐의 대가가 크다** |

### Compatibility requirements

| 축 | 요구 |
|---|---|
| **현재 배포된 iOS 클라이언트** | P5a: 신규 경로 → 영향 0 / P5b: 미지의 필드 무시 → **Swift `Codable`이 미지 키를 무시하는지 확인 필요** (기본 동작상 무시함, 테스트로 고정) / P5c: 값 의미 변경 → **현 클라이언트가 `confidence`로 무엇을 하는지 반드시 재확인 후 진행** / P5d·P5e: 새 `resultStatus`/`warnings` 값이 나올 수 있음 → 기존 테스트 `unknownServerStatusesDecodeSafely`가 방어 |
| **신규 클라이언트** | P4에서 `isEstimated`를 optional로 선디코딩해 두었으므로 순서 무관 |
| **영속 데이터 (Firestore)** | P5a: 세션 문서에 종료 상태 추가 — **기존 문서에 없는 필드는 읽을 때 기본값 적용** (SP3) / 나머지: 문서 스키마 변경 없음 / **백필 마이그레이션 없음** |

### Validation before release

| 층 | 수단 | 근거 |
|---|---|---|
| 단위 | `pytest -q` — `tests/conftest.py`가 `FirestoreStateStore` → `InMemoryStateStore`로 monkeypatch하고 App Check `verify_token`을 no-op로 스텁 | 기존 인프라 |
| **트랜잭션/동시성** | `firebase emulators:exec --only firestore 'GCLOUD_PROJECT=dailyopic-test pytest -q tests/test_firestore_emulator.py'` | 기존 인프라. **실제 Firestore 트랜잭션 의미론을 프로덕션 데이터 없이 검증** |
| **계약** | 신규 계약 테스트: 응답 스키마에 필드가 **추가만** 되고 제거/타입변경이 없음을 스냅샷으로 고정 | 신설 필요 |
| 로컬 E2E | `uvicorn app.main:app` + 시뮬레이터를 `Config/*.local.xcconfig`로 지시 | SP1 |
| CI | PR → `main`은 **배포하지 않고 테스트만** 돈다 | 검증된 워크플로 |

### Isolated backend validation (프로덕션 트래픽 무영향 검증 방법)

**4단계로 격리한다. 아래 순서를 건너뛰지 않는다.**

```
L1  로컬 인메모리      pytest                          데이터 격리 ✅  트래픽 격리 ✅
L2  로컬 에뮬레이터    firebase emulators:exec         데이터 격리 ✅  트래픽 격리 ✅
L3  PR CI             GitHub Actions (배포 안 함)      데이터 격리 ✅  트래픽 격리 ✅
L4  candidate revision --no-traffic --tag candidate-*  데이터 격리 ❌  트래픽 격리 ✅
```

**⚠️ L4의 한계를 명확히 한다 (SP6).**
`deploy-cloud-run.yml`의 candidate revision은 **프로덕션 서비스 계정
(`dailyopic-cloudrun@opicmobile-45cd5`)으로 프로덕션 Firestore에 붙는다.**
따라서:

- ✅ **허용:** `/health` 스모크, 부팅 성공 확인, 설정 검증(`Settings` validator 통과), 읽기 전용 경로
- ⛔ **금지:** candidate URL에 대고 쓰기 경로(세션 생성·평가·리워드) 호출 — **프로덕션 데이터를 오염시킨다**
- **쓰기 경로 검증은 전부 L2(에뮬레이터)에서 끝낸다.**

**진짜 데이터 격리가 필요해지면** (P5d 임계값 튜닝처럼 실데이터 분포가 필요한 경우):
`app_env` Literal에 **`staging`이 이미 정의돼 있다**(`config.py`). 별도 Firebase 프로젝트 +
별도 Cloud Run 서비스로 staging을 세우는 것이 정공법이다. **이 문서는 그 필요성만 기록하고
어떤 리소스도 생성하지 않는다.** 착수 전 별도 승인을 받는다.

**App Check 고려사항**
- 테스트는 `conftest.py`가 `verify_token`을 no-op로 스텁하므로 App Check와 무관하게 돈다.
- **프로덕션 App Check 강제를 약화시키지 않는다** (SP4).
- 시뮬레이터 로컬 검증은 기존 debug token 방식을 그대로 쓴다. **새 토큰을 프로덕션 Firebase에
  추가로 등록하지 않는다.**

**시크릿/설정 분리**
- `.env`는 gitignore되어 있고 `MOCK_AI` / `OPENAI_*` / `FIREBASE_PROJECT_ID` /
  `ADMOB_*` / 쿼터 3종만 담는다.
- `REVENUECAT_WEBHOOK_AUTH` / `REVENUECAT_SECRET_API_KEY`는 **Cloud Run 환경변수로만** 주입된다 —
  로컬에 복사하지 않는다.
- `Settings` validator가 `app_env == "production"`에서 `MOCK_AI=true`와 Google 샘플 광고 단위를
  **거부한다.** 이 가드를 약화시키지 않는다.

### Rollback boundary
- **슬라이스마다 별도 PR·별도 머지.** 한 PR = 한 배포 = 한 롤백 단위.
- Cloud Run은 리비전 기반이므로 **직전 리비전으로 트래픽을 되돌리는 것이 즉시 롤백**이다:
  `gcloud run services update-traffic <SERVICE> --to-revisions <prev>=100`
- **P5c·P5d·P5e는 서버 측 기능 플래그(설정값) 뒤에 넣는다.** `config.py`에 이미
  `question_generation_v2_enabled` / `evaluation_rubric_v2_enabled` / `mock_session_v2_enabled` 같은
  **플래그 관례가 존재한다.** 동일 패턴으로 `deterministic_confidence_enabled`,
  `answer_quality_gate_enabled`를 추가하면 **재배포 없이 환경변수로 끌 수 있다.**

### Commit boundary
```
feat(api): add mock exam abandon endpoint
test(state): cover mock session abandon transition on firestore emulator

feat(audio): report whether duration metrics are measured or estimated
test(audio): cover isEstimated across ffprobe success and fallback paths

refactor(ai): derive confidence deterministically on the server
feat(config): add deterministic_confidence_enabled flag defaulting to off

feat(evaluation): add answer quality bucket policy behind a disabled flag
test(evaluation): cover A B C bucket boundaries with recorded fixtures

perf(evaluation): skip AI call for answers rejected by the quality gate
```

### Done criteria
- [ ] `pytest -q` 전체 통과
- [ ] 에뮬레이터 테스트 전체 통과
- [ ] **응답 스키마 계약 테스트: 제거·타입변경 0건, 추가만**
- [ ] 현재 배포된 iOS 빌드로 로컬 서버를 향해 전 여정 정상 동작 (**하위 호환 실증**)
- [ ] P5c·P5d·P5e가 전부 플래그 OFF로 배포됨
- [ ] 각 PR이 독립적으로 revert 가능

---

## P6 — 페이월 · 광고 · 통계

### Objective
페이월을 의사결정 화면으로 재구성하고, 광고 배치를 확정하며, 통계를 밴드 표현으로 정리한다.

### Repository
`DailyOPIc`

### ⛔ 착수 전 필수 제품 결정 (§1.4)

| # | 질문 | 옵션 |
|---|---|---|
| **D1** | 베이직(₩2,900)이 무료와 **분석 내용이 동일**한 현 상태를 유지할 것인가? | **A.** 유지 → 베이직 카피는 "광고 제거 + 매일 모의고사 + 3세트"로 정직하게 / **B.** `strip_long`을 `{"summary"}`로 좁혀 베이직도 교정·모범답안 제공 → **무료↔유료 경계 변경, 백엔드 작업 + 원가 증가** |
| **D2** | 프로의 "문항별 코칭"은 **미구현**이다. | **A.** 페이월에서 삭제 (권장) / **B.** 구현 (신규 기능 = 이번 범위 밖) |

> **D1·D2가 결정되기 전에는 P6의 페이월 카피를 작성하지 않는다.**
> 광고·통계 하위 슬라이스는 이 결정과 무관하므로 **먼저 진행할 수 있다.**

### Exact areas likely to change
| 파일 | 변경 |
|---|---|
| `Views/Screens/Paywall/PaywallView.swift` | 4카드 동등 → 추천 1개 + 비교표 4축 · 삭제 5종 · 진입 맥락별 문구 |
| `Views/Components/BannerAdView.swift` | 자기 높이 소유 · 미노출 시 `EmptyView` (`.frame(height: 50)` 호출부 제거) |
| `Views/Screens/Main/Practice/` | 배너 제거 |
| `Views/Screens/Main/Progress/ProgressScreen.swift` | 밴드 표시 · 빈 상태 · B 버킷 제외 각주 |
| `Views/Screens/Splash/` + ATT 호출부 | ATT 요청을 첫 광고 노출 직전으로 이동 |
| `Views/Screens/Setup/SetupView.swift` · `OnboardingView` | 플랜별 광고 문구 분기 통합 |

### Dependencies
P0, **P8a (플랜 매핑)**, P1(탭바 — 배너 가림 해소), P4(밴드), **+ D1·D2 결정**.

### Production risk
**MEDIUM-HIGH** — 매출 경로 2개(구독·광고)를 동시에 건드린다.

구체적으로 무엇이 사용자에게 갈 수 있는가:
- **페이월 재구성은 전환율에 직접 영향을 준다.** 되돌릴 수 있게 커밋을 분리한다.
- **데일리 배너 제거는 광고 수익을 즉시 감소시킨다** (Q5 LOCKED 결정이지만 측정 필요).
- **ATT 요청 시점 이동은 추적 동의율을 바꾼다** → 광고 단가에 영향. **정책이 아니라 타이밍만
  바꾸는 것이며, UMP 동의 로직은 손대지 않는다** (SP4).
- **RevenueCat 상품·오퍼링·엔타이틀먼트는 읽기만 한다** (SP4).

### Compatibility requirements
| 축 | 요구 |
|---|---|
| RevenueCat | **읽기 전용.** 가격은 `package.storeProduct.localizedPriceString`에서만 가져온다. `PlanEntitlement.monthlyPriceKRW`를 표시에 쓰지 않는다 |
| 서버 API | 변경 없음. `analysisDepth`(`routes.py:110`)를 표시 게이팅에 그대로 사용 |
| AdMob | **광고 단위·정책 무변경.** 배치와 높이 소유권만 변경 |
| 심사 | 자동 갱신 고지·복원·약관은 **현재 구현을 유지**한다 (심사 요건 충족 상태) |

### Validation before release
| 종류 | 내용 |
|---|---|
| Swift 단위 | 플랜별 페이월 카피 결정 테이블 · 유료 플랜에서 배너 높이 0 단언 |
| 시뮬레이터 | 4개 진입점별 페이월 문구 · 무료/유료 각각의 배너 유무 · 통계 빈 상태 |
| **RevenueCat** | MCP **읽기 전용**으로 상품·패키지·가격이 카피와 일치하는지 대조 |
| 접근성 | 페이월 VoiceOver 순서(현재 플랜 → 추천 → 비교표 → 복원·약관) |
| 광고 | **테스트 광고 단위로만.** 프로덕션 노출·리워드 소모 금지 (SP4) |
| 회귀 | 구매 복원 동작 · 구독 관리 진입 |

### Isolated backend validation
백엔드 변경 없음. 플랜별 화면은 **로컬 FastAPI에서 `capabilities` 응답을 플랜별로 바꿔** 검증한다.
**실제 구독을 구매하거나 엔타이틀먼트를 부여해 검증하지 않는다** (SP4).

### Rollback boundary
페이월 / 배너 / ATT / 통계를 **4개 독립 커밋**으로 분리한다.
수익 지표가 나빠지면 해당 커밋만 되돌린다.

### Commit boundary
```
refactor(paywall): restructure tiers into one recommendation and a comparison table
fix(paywall): remove unenforced history limits and nonexistent promotion badge
fix(ads): let BannerAdView own its height and collapse for paid plans
refactor(ads): move banner out of the daily speaking flow
refactor(ads): request ATT immediately before first ad instead of at launch
refactor(statistics): render rubric bands and add empty states
fix(settings): branch ad guidance copy by plan
```

### Done criteria
- [ ] 페이월에 강제되지 않는 혜택 문구 0건 (기록 기간·할인 배지·`exam_pass`·문항별 코칭)
- [ ] 카피가 `plans.py` + `ai.py` 실동작과 100% 일치
- [ ] 유료 플랜에서 배너 자리 높이 = 0
- [ ] 데일리 말하기 화면에 배너 없음
- [ ] 통계에 100점 척도 숫자 없음
- [ ] RevenueCat 리소스 변경 0건 (감사 로그로 확인)

---

## P7 — 접근성 마감

### Objective
`DESIGN.md §9`의 A1–A13을 Definition of Done으로 전수 검증하고 미달 항목을 마감한다.

### Repository
`DailyOPIc`

### Exact areas likely to change
전 화면. 특히:
| 대상 | 변경 |
|---|---|
| 인터랙티브 요소 전수 | `accessibilityLabel` / `Value` / `Hint` 보강 (현재 14건 / 10파일) |
| 모달 전수 | `.isModal` (현재 **0건**) — P0의 `ModalContainer` 경유로 일괄 |
| 비동기 경로 | `AccessibilityNotification` (현재 **0건**) |
| `SavedSurveyDialog` · `TargetLevelConfirmationDialog` | → `.confirmationDialog` |
| Reduce Motion | 신규 8상태로 확장 |

### Dependencies
P0–P6 전부 (UI가 확정돼야 라벨을 붙일 수 있다).

### Production risk
**LOW-MEDIUM** — 대부분 접근성 수정자 추가이며 시각·동작 변화가 없다.
단 커스텀 다이얼로그 → `.confirmationDialog` 전환은 **동작 변경**이므로 파괴적 액션 경로를
다시 확인한다.

### Compatibility requirements
없음 (표시 계층).

### Validation before release
| 종류 | 내용 |
|---|---|
| 자동 | Accessibility Inspector **Audit** 전 화면 위반 0 |
| 수동 | VoiceOver로 **8개 여정 완주** — 이것이 이 단계의 본체다 |
| Dynamic Type | AX5 전 화면 |
| **실기기** | VoiceOver 실동작은 시뮬레이터와 다르다. **실기기 1회 필수** |
| Reduce Motion | On/Off 각각 전체 주행 |

### Rollback boundary
화면 단위 커밋. 개별 revert 안전.

### Commit boundary
```
feat(a11y): add VoiceOver labels and values across interactive elements
feat(a11y): announce async state changes for recording, analysis, and ads
refactor(a11y): replace remaining custom dialogs with confirmationDialog
feat(a11y): extend reduced motion handling to the recording state machine
test(a11y): assert modal trait and label presence on shared components
```

### Done criteria
- [ ] A1–A13 **전부** 통과 (§9 표 기준)
- [ ] Inspector Audit 위반 0
- [ ] VoiceOver 8여정 완주 (실기기)
- [ ] `.onTapGesture` 주요 액션 0건
- [ ] `.isModal` 누락 모달 0건

---

## P8 — 기술 부채

### P8a — 플랜 매핑 정리 (**P6 이전으로 승격**)

**Objective** — 클라이언트/서버 플랜 매핑 불일치를 제거한다.

**Repository** — `DailyOPIc`

**Exact areas** — `Services/Store/StoreService.swift:203-218` (`highestPlan` / `plan(for:)`) · `Models/PlanEntitlement.swift`

**Dependencies** — P0.

**Production risk** — **MEDIUM.** 플랜 판정은 **모든 게이팅의 입력**이다. 잘못되면 유료
사용자가 무료로 강등되거나 그 반대가 된다. 단 **최종 권위는 서버 `/v1/capabilities`**이므로
클라이언트 오판의 폭발 반경은 표시 계층에 한정된다.

**변경 내용** — 부분 문자열 검사(`lower.contains(candidate.rawValue)`)를 **명시적 매핑
테이블**로 교체하고 `plans.py:_ENTITLEMENT_TO_PLAN`과 **동일한 키 집합**(`basic` / `plus` /
`pro` / `premium` / `exam_pass`)을 갖게 한다. 패키지는 `productIdentifier` 명시 매핑을 쓴다
(`$rc_monthly` → basic).

**Validation** — 신규 Swift 테스트: 5개 엔타이틀먼트 키 → 플랜 매핑 · `$rc_monthly` 패키지 →
basic · 알 수 없는 키 → free 강등 · 다중 엔타이틀먼트 시 최고 플랜 선택.

**Commit**
```
fix(plans): map entitlements and packages explicitly instead of substring matching
test(plans): cover entitlement mapping parity with backend plan table
```

**Done** — [ ] 서버 키 집합과 1:1 · [ ] 패키지 식별자 변경에도 강건 · [ ] 테스트 통과

---

### P8b — 잔여 정리

**Objective** — 사문화된 상태·미사용 값·미해결 한계를 정리한다.

**Repository** — `DailyOPIc`

**Exact areas**
- `interruptionReason` 등 소비처 0인 published 상태 정리 (P3에서 소비되면 자동 해소)
- `dailyRefreshRemaining` UI 노출 제거 (`practiceRefresh` 호출부 0건)
- `historyDays` 미사용 디코딩 정리
- STT 조기 종료 감지 — **별도 과제로 기록만.** 이번 범위 밖

**Production risk** — **LOW.** 죽은 코드 제거.

**Commit**
```
chore(practice): remove unused refresh quota and history window from UI
chore(speech): drop published state with no consumers
```

**Done** — [ ] 사문화 값 UI 노출 0건 · [ ] 빌드 warning 증가 0

---

# 4. Frontend / backend boundaries

## 4.1 경계 원칙

```
┌──────────────────────────┐        ┌──────────────────────────┐
│ DailyOPIc (iOS)          │        │ DailyOPIc-BE (FastAPI)   │
│                          │        │                          │
│ 표현 · 상태 보존 · 접근성 │◀──────▶│ 권위 · 쿼터 · 평가 정책   │
│                          │  HTTP  │                          │
│ 게이팅의 "표시"           │        │ 게이팅의 "강제"           │
└──────────────────────────┘        └──────────────────────────┘
```

| 관심사 | 소유 | 근거 |
|---|---|---|
| 플랜 판정의 **최종 권위** | **BE** (`/v1/capabilities`) | `plans.py`가 단일 진실 소스 |
| 플랜 판정의 **즉시성** | iOS (RevenueCat 로컬) | 구매 직후 반응성. 불일치 시 서버로 수렴 |
| 쿼터 차감 | **BE** (`reserve_practice`) | 클라이언트는 잔량을 표시만 |
| 세트 내 무제한 평가 | **BE** (`reserve_request`) | 클라이언트가 이 사실을 **문구로** 전달 |
| 리워드 검증 | **BE** (SSV + nonce) | 클라이언트는 nonce 운반만 |
| 세션 stage | **BE** | 클라이언트는 stage → 화면 매핑만 |
| 답변 품질 버킷(A/B/C) | **BE** (P5d) | 임계값을 클라이언트에 두면 버전마다 갈린다 |
| 녹음·전사·오디오 | **iOS** | 서버는 결과만 받는다 |
| 상태 보존 | **iOS** | 서버는 세션만, 화면 복원은 클라이언트 책임 |
| 광고 노출·배치 | **iOS** | 서버는 `ads_enabled`만 |
| 접근성 | **iOS** 전적 | — |

## 4.2 이 경계에서 나오는 규칙

1. **클라이언트는 정책을 재구현하지 않는다.** A/B/C 임계값을 iOS에 하드코딩하면 앱 버전마다
   판정이 갈린다 → **버킷 결과는 서버가 내려주고 클라이언트는 렌더링만 한다.**
2. **클라이언트는 서버가 강제하지 않는 것을 게이팅하지 않는다.** `historyDays`가 그 사례다 (Q6 LOCKED).
3. **서버는 표현을 결정하지 않는다.** 밴드 → 한국어 라벨 변환은 클라이언트 몫이다.
4. **서버 응답 필드는 추가만 한다** (SP2). 클라이언트는 미지 필드를 무시하고, 부재 필드를
   optional로 받는다.

---

# 5. Backend compatibility strategy

## 5.1 응답 진화 규칙

| 변경 | 허용 | 조건 |
|---|---|---|
| optional 필드 **추가** | ✅ | 기존 클라이언트가 무시. 계약 테스트로 고정 |
| 필드 **제거** | ⛔ | 어떤 경우에도 금지 |
| 필드 **타입 변경** | ⛔ | 금지. 새 필드를 추가하고 구 필드를 유지 |
| 필드 **의미 변경** | ⚠️ | P5c(`confidence`)가 유일 사례. **플래그 뒤에서 단계적으로** |
| enum 값 **추가** | ✅ | 클라이언트가 미지 값을 안전 디코딩한다는 테스트가 있을 때만 (`unknownServerStatusesDecodeSafely`) |
| enum 값 **제거** | ⛔ | 금지 |
| 신규 엔드포인트 | ✅ | 기존 클라이언트는 호출하지 않음 |
| 기존 엔드포인트 동작 변경 | ⚠️ | 하위 호환 증명 + 플래그 필수 |

## 5.2 Firestore 진화 규칙

- **필드 추가는 optional + 읽기 시 기본값.** 기존 문서에 없어도 서버가 안전하게 처리한다.
- **백필 마이그레이션은 별도 리뷰 문서 없이는 하지 않는다** (SP3).
- `state.py`의 인메모리 트윈과 Firestore 구현이 **동일 의미론**을 유지해야 한다 —
  에뮬레이터 테스트가 이를 지킨다.
- **기존 사용량·쿼터·리워드 문서를 개발 목적으로 삭제·수정하지 않는다** (SP4).

## 5.3 클라이언트 하위 호환 실증 방법

**"기존 앱이 계속 동작한다"를 주장이 아니라 실험으로 증명한다.**

```
1. 현재 App Store 릴리스와 동일한 커밋으로 iOS 빌드 (git tag 기준)
2. Config/*.local.xcconfig 로 로컬 FastAPI(신규 백엔드 코드) 지시
3. 8개 여정 전부 주행
4. 크래시 0 · 디코딩 실패 0 · 기능 회귀 0 이면 통과
```

이것을 **모든 백엔드 PR의 체크리스트 항목**으로 만든다.

## 5.4 서버 기능 플래그 관례 (기존 패턴 재사용)

`config.py`에 이미 존재:
`question_generation_v2_enabled` / `evaluation_rubric_v2_enabled` / `mock_session_v2_enabled` / `practice_refresh_enabled`

→ **P5c·P5d·P5e도 동일 패턴으로 넣는다.**
→ 환경변수로 끌 수 있으므로 **재배포 없이 롤백**이 가능하다. 이것이 P5의 주 안전장치다.

---

# 6. Testing matrix

| 단계 | Swift 단위 | pytest | 에뮬레이터 | 계약 | 시뮬레이터 | **실기기** | 접근성 | 하위호환 실증 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **P-1** | ✅ (회귀) | — | — | — | ✅ | — | — | — |
| **P0** | ✅ | — | — | — | ✅✅ | — | **✅✅** | — |
| **P1** | ✅✅ | — | — | — | ✅✅ | ✅ (업그레이드) | ✅ | — |
| **P2** | ✅✅ | — | — | — | ✅✅ | — | ✅ | — |
| **P3** | ✅ | — | — | — | ✅ | **✅✅ 필수** | ✅✅ | — |
| **P4** | ✅✅ | — | — | — | ✅ | — | ✅ | ✅ |
| **P5** | — | **✅✅** | **✅✅** | **✅✅** | ✅ | — | — | **✅✅ 필수** |
| **P6** | ✅ | — | — | — | ✅✅ | — | ✅ | — |
| **P7** | ✅ | — | — | — | ✅ | **✅✅ 필수** | **✅✅** | — |
| **P8a** | ✅✅ | — | — | — | ✅ | — | — | — |
| **P8b** | ✅ | — | — | — | ✅ | — | — | — |

`✅✅` = 이 단계의 주 검증 수단 / `✅` = 필요 / `—` = 해당 없음

## 6.1 현재 테스트 자산 (검증됨)

| 자산 | 상태 |
|---|---|
| `DailyOPIcTests/DailyOPIcTests.swift` | **Swift Testing** 프레임워크, 23개 테스트. 모델·디코딩·에러 분류 중심 |
| `DailyOPIcUITests/` | 템플릿 수준 (실질 없음) |
| **공유 스킴** | **없음** ← P-1이 해소 |
| iOS CI | **없음** ← P-1이 해소 |
| `DailyOPIc-BE/tests/` | 17개 테스트 파일 + `conftest.py`(인메모리 스토어 + App Check 스텁) + `fixtures/` |
| Firestore 에뮬레이터 | `firebase.json` 포트 8088 + `test_firestore_emulator.py` + CI 잡 |
| BE CI | PR = 테스트, push to main = 테스트 + candidate 배포 + 승격 |

## 6.2 신설이 필요한 테스트

| 테스트 | 단계 | 이유 |
|---|---|---|
| 색 대비비 단언 | P0 | 토큰 회귀 방지 |
| 44pt 최소 프레임 | P0 | 컴포넌트 계약 고정 |
| 드래프트 라운드트립 + 레거시 기록 보존 | P1 | SwiftData 마이그레이션 안전 |
| stage 라우팅 결정 테이블 | P2 | 9 stage × 진입/이탈 |
| 녹음 상태 전이 테이블 | P3 | 오디오 없이 순수 검증 |
| 밴드 매핑 · 플래그 기본값 | P4 | fake precision 재발 방지 |
| **응답 스키마 계약 스냅샷** | P5 | SP2 자동 강제 |
| `isEstimated` 폴백 경로 | P5b | ffprobe 성공/실패 양쪽 |
| A/B/C 경계 픽스처 | P5d | 임계값 회귀 |
| 엔타이틀먼트 매핑 패리티 | P8a | 서버 키 집합과 동기 |

---

# 7. Simulator / device verification matrix

## 7.1 시뮬레이터 (기본 검증)

**기준 기기: iPhone 17 Pro** (세션 기본값)

| 축 | 값 |
|---|---|
| Dynamic Type | `extra-small` / `large` / `xxx-large` / `accessibility-medium` / `accessibility-extra-extra-extra-large` |
| Appearance | `light` / `dark` |
| Reduce Motion | On / Off |
| 화면 | 11개 (스플래시·온보딩·가이드·데일리·결과·모의고사 인트로·게이트·답변·모의결과·통계·설정·페이월) |
| 플랜 | free / basic / plus / pro (**로컬 서버의 capabilities 응답으로 전환**) |

```
xcrun simctl ui <udid> content_size <size>
xcrun simctl ui <udid> appearance <light|dark>
```

## 7.2 실기기 (필수 구간)

**시뮬레이터로 대체 불가능한 것만 실기기로 한다.**

| 항목 | 단계 | 이유 |
|---|---|---|
| **오디오 인터럽션** (전화·시리·타 앱) | **P3** | 시뮬레이터가 재현 못 함 |
| **마이크·음성 인식 권한 실동작** | P3 | 권한 다이얼로그·설정 왕복 |
| **VoiceOver 실주행** | **P7** | 시뮬레이터 VoiceOver는 실동작과 다름 |
| **업그레이드 설치 시 SwiftData 보존** | **P1** | 실제 앱 교체 시나리오 |
| 햅틱 | P3 | 시뮬레이터 미지원 |
| 실제 광고 로드 | (선택) | **테스트 광고 단위로만.** 프로덕션 단위 소모 금지 (SP4) |

## 7.3 검증 계정·데이터 원칙

- 시뮬레이터 검증은 **로컬 FastAPI**를 향한다 (`Config/*.local.xcconfig`).
- **프로덕션 백엔드에 대고 반복 검증하지 않는다** — 익명 사용자 문서와 쿼터가 실제로 쌓인다 (SP4).
- **StoreKit 구매를 실제로 실행하지 않는다.** 페이월은 시트 표시까지만 확인한다.
- **RevenueCat에 테스트 엔타이틀먼트를 부여하지 않는다.** 플랜별 화면은 **로컬 서버의
  `capabilities` 응답을 바꿔서** 검증한다.

---

# 8. Production-safe rollout strategy

## 8.1 iOS 롤아웃

```
로컬 빌드 → PR CI (build + test) → 머지 → TestFlight 내부 → TestFlight 외부(선택)
  → App Store 심사 → 단계적 출시(Phased Release ON) → 100%
```

| 규칙 | 내용 |
|---|---|
| **단계적 출시 필수** | App Store Connect의 **Phased Release를 켠다.** 7일에 걸쳐 확산되므로 P1·P3처럼 리스크 HIGH인 릴리스에서 조기 중단이 가능하다 |
| **TestFlight 게이트** | P1·P3은 **TestFlight 내부 최소 2일** 후 심사 제출 |
| **묶음 금지** | P1(세션)과 P3(녹음)을 **같은 릴리스에 넣지 않는다.** 둘 다 HIGH이고 증상이 겹쳐 원인 분리가 불가능해진다 |
| **플래그 우선** | 되돌릴 수 있는 것은 코드가 아니라 플래그로 만든다 (B/C 버킷) |

## 8.2 백엔드 롤아웃

```
로컬 pytest → 로컬 에뮬레이터 → PR CI(테스트만) → 머지 to main
  → [자동] candidate revision (트래픽 0) → /health 스모크
  → [자동] update-traffic --to-latest (0% → 100%)
```

**⚠️ 이 파이프라인의 구조적 한계: 승격이 원샷 100%다.** 카나리 구간이 없다.

**따라서 백엔드 안전은 "배포 방식"이 아니라 "변경 크기"로 확보한다.**

| 규칙 | 내용 |
|---|---|
| **한 PR = 한 관심사** | P5a~P5e를 절대 묶지 않는다 |
| **플래그 OFF로 먼저 배포** | 코드가 프로덕션에 있되 동작하지 않는 상태를 먼저 만든다. 배포와 활성화를 분리한다 |
| **활성화는 환경변수로** | Cloud Run 환경변수 변경 = 새 리비전이지만 코드 변경 없음 → **되돌리기가 즉시** |
| **머지 타이밍** | 사용량이 낮은 시간대. KST 자정 리셋(`_date_key()`) 직후는 피한다 |
| **머지 직후 관찰** | `/health` + Cloud Run 로그 + 오류율. 이상 시 즉시 §9 롤백 |

## 8.3 릴리스 묶음 권장

| 릴리스 | 포함 | 리스크 |
|---|---|---|
| **R1** | P-1 + P0 (+ 페이월 Button) | MEDIUM |
| **R2** | P1 | **HIGH** — 단독 |
| **R3** | P2 + P8a | MEDIUM |
| **R4** | P3 | **HIGH** — 단독 |
| **R5** | P4 (B/C 플래그 OFF) | MEDIUM |
| **R6** | P6 (D1·D2 결정 후) | MEDIUM-HIGH |
| **R7** | P7 + P8b + B/C 플래그 ON | LOW-MEDIUM |
| **BE-1..5** | P5a~P5e 각각 독립 | 슬라이스별 |

---

# 9. Rollback strategy

## 9.1 계층별 롤백 수단

| 계층 | 수단 | 소요 | 비고 |
|---|---|---|---|
| **서버 기능 플래그** | Cloud Run 환경변수 변경 | 분 | **가장 빠름.** P5c·P5d·P5e의 주 수단 |
| **Cloud Run 리비전** | `gcloud run services update-traffic <SVC> --to-revisions <prev>=100` | 분 | 코드 롤백. 리비전은 자동 보존됨 |
| **백엔드 커밋** | PR revert → main → 자동 재배포 | 십수 분 | 리비전 롤백 후 정리용 |
| **클라이언트 플래그** | (앱 내 원격 플래그 없음) | — | **⚠️ 현재 원격 킬스위치가 없다** |
| **App Store 단계적 출시** | Phased Release 일시 중지 | 시간 | 확산만 멈춘다. 이미 받은 사용자는 그대로 |
| **iOS 이전 버전** | 새 빌드 심사 재제출 | **1–3일** | **가장 느림** |

## 9.2 여기서 나오는 결론

> **iOS 롤백은 사실상 불가능에 가깝다.** 심사 재제출에 1–3일이 걸린다.
> 그래서 iOS 쪽 안전은 **롤백이 아니라 사전 검증과 단계적 출시**로 확보해야 한다.
> 반대로 **백엔드는 분 단위 롤백이 가능하다.**
>
> → **위험한 판단은 가능하면 서버 쪽에 둔다.** A/B/C 버킷 판정을 서버가 하는 이유(§4.2)가 이것이다.

## 9.3 롤백 경계 (커밋 설계 원칙)

각 단계의 커밋은 **독립 revert 가능**해야 한다:

- 구조 변경과 표면 변경을 같은 커밋에 넣지 않는다 (SP9)
- 가장 위험한 변경(`AppRootView`, `SpeechRecognitionService` 인터럽션)은 **단독 커밋**
- 백엔드는 **슬라이스 = PR = 리비전 = 롤백 단위**

## 9.4 사후 조치

롤백 시 남기는 것: 무엇이 깨졌는가 / 어느 검증이 놓쳤는가 / 그 검증을 어느 매트릭스에 추가하는가.
**같은 유형이 두 번 나면 그것은 프로세스 결함이다.**

---

# 10. Commit strategy

## 10.1 Conventional Commit 규약

```
<type>(<scope>): <subject>
```

### Type

`feat` 새 동작 / `fix` 결함 수정 / `refactor` 동작 불변 구조 변경 /
`perf` 성능 / `test` 테스트만 / `docs` 문서만 / `chore` 빌드·도구 / `ci` 파이프라인

### Scope (이 프로젝트 확정 목록)

| Scope | 영역 |
|---|---|
| `design-system` | 토큰, 공용 컴포넌트 |
| `navigation` | 루트 분기, 탭, cover, sheet |
| `session` | ViewModel 소유권, 드래프트, 상태 보존 |
| `speaking` | 데일리 말하기 흐름 UI |
| `speech` | `SpeechRecognitionService` (오디오·STT 계층) |
| `mock-exam` | 모의고사 |
| `evaluation` | 결과·루브릭·버킷 |
| `practice` | 데일리 홈·문항·쿼터 표시 |
| `paywall` | 페이월 |
| `plans` | 플랜 매핑·엔타이틀먼트 |
| `ads` | 배너·리워드·ATT |
| `statistics` | 통계 |
| `settings` | 설정 |
| `a11y` | 접근성 전용 |
| `api` | BE 라우트·응답 모델 |
| `state` | BE 상태 저장소 |
| `audio` | BE 오디오 지표 |
| `ai` | BE 평가·프롬프트 |
| `config` | BE 설정·플래그 |

## 10.2 커밋 크기 규칙

1. **한 커밋 = 한 관심사.** 두 가지를 설명해야 하면 두 커밋이다.
2. **각 커밋에서 빌드가 통과한다.** 중간에 깨지는 커밋을 남기지 않는다.
3. **테스트는 대상 변경과 같은 커밋 또는 바로 다음 커밋.**
4. **파일 이름 변경은 단독 커밋** (`DailyTokenBadge` → `DailySetBadge`).
5. **위험한 변경은 단독 커밋** (§9.3).

## 10.3 브랜치 · PR

- 현재 iOS는 `feat/1`, BE는 `feat/46`. 단계별 브랜치를 판다: `feat/p0-design-tokens` 등
- **BE PR은 `main`을 대상으로 하되 머지 = 배포임을 항상 인지한다** (SP7)
- PR 설명에 §3의 해당 단계 **Done criteria 체크리스트를 그대로 복사**한다
- 백엔드 PR에는 **§5.3 하위 호환 실증 결과**를 첨부한다

---

# 11. Definition of done per phase

| 단계 | 통과 = 다음을 **전부** 만족 |
|---|---|
| **P-1** | 공유 스킴 커밋 · `xcodebuild test` 23/23 · CI 초록 · 로컬 백엔드 오버라이드 문서화 |
| **P0** | `system(size:` 0건 · 대비 위반 0건(라이트/다크) · AX5 잘림 0건 · 기본 크기 시각 회귀 0 · VoiceOver로 페이월 플랜 선택 가능 |
| **P1** | 설정/도움말/난이도 왕복 후 세션 유지 · 강제 종료 후 드래프트 복원 · 이전 빌드 기록 100% 보존 · 신규 온보딩 완주 · v1 사용자 가이드 미강제 · 배너 미가림 |
| **P2** | 9 stage 전부 진행 또는 포기 가능 · 시작 실패 후 탈출 가능 · 광고 재시도가 재시청 유발 안 함 · 미지 stage 무크래시 · 예산 표시 정확 |
| **P3** | (실기기) 인터럽션 후 오디오·전사 보존 + 이어서 녹음 · 180초 자동 종료 + 안내 · 확인 카드에서 무료 재녹음 명시 · 8상태 VoiceOver 발표 · 권한 복구 · 5연속 녹음 누수 0 |
| **P4** | 100점 척도 0건 · "토큰" 문자열 0건 · 소진 화면 플랜별 분기 · `isEstimated` 부재 디코딩 성공 · **릴리스 빌드에서 B/C 플래그 false** · 과거 기록 열람 가능 |
| **P5** | `pytest` 전체 통과 · 에뮬레이터 전체 통과 · **계약 테스트: 필드 추가만** · **현재 릴리스 iOS 빌드로 전 여정 정상**(하위 호환 실증) · 신규 정책 전부 플래그 OFF 배포 · PR별 독립 revert 가능 |
| **P6** | 강제되지 않는 혜택 문구 0건 · 카피가 `plans.py`+`ai.py` 실동작과 일치 · 유료 배너 높이 0 · 데일리 배너 없음 · 통계 숫자 없음 · **RevenueCat 변경 0건** |
| **P7** | A1–A13 전부 통과 · Inspector Audit 0 · (실기기) VoiceOver 8여정 완주 · `.onTapGesture` 주요 액션 0 · `.isModal` 누락 0 |
| **P8a** | 서버 키 집합과 1:1 매핑 · 패키지 식별자 변경에 강건 · 패리티 테스트 통과 |
| **P8b** | 사문화 값 UI 노출 0 · warning 증가 0 |

---

# 12. Recommended first implementation slice

## 12.1 왜 이것이 첫 슬라이스인가

**현재 상태로는 어떤 변경도 "출시해도 안전하다"를 증명할 수 없다.**

- `DailyOPIc.xcodeproj`에 **공유 스킴이 없다** (`xcuserdata/`에만 존재, gitignore 대상)
  → `xcodebuild test`를 재현 가능하게 돌릴 수 없다 → iOS CI를 만들 수 없다
- `Config/Debug.xcconfig`의 `DAILYOPIC_API_BASE_URL`이 **프로덕션 Cloud Run을 가리킨다**
  → 개발 중 시뮬레이터가 프로덕션 쿼터를 소모한다 (SP4 위반 위험)

**검증 수단이 없는 상태에서 P0을 시작하면, P0의 "회귀 0" 주장을 증명할 방법이 없다.**

그래서 첫 슬라이스는 **P-1 전체 + P0의 첫 조각(타이포)**으로 잡는다.
타이포를 첫 제품 변경으로 고르는 이유: §6.3에서 **현재 7종 크기가 iOS 텍스트 스타일 기본
크기와 정확히 일치함이 검증**됐으므로, 기본 Dynamic Type 크기에서 **시각적 회귀가 구조적으로 0**이다.
즉 "새로 만든 검증 파이프라인이 제대로 도는가"를 확인하기에 가장 좋은 첫 변경이다.

## 12.2 슬라이스 구성 (커밋 4개)

```
1. chore(ci): share DailyOPIc xcscheme for reproducible test runs
2. chore(config): add local backend xcconfig template and document override
3. ci(ios): add build and unit test workflow
4. refactor(design-system): migrate AppTypography to Dynamic Type text styles
```

**4번은 앞 3개가 초록색이 된 뒤에만 커밋한다.**

---

# 부록 A. 이 계획이 근거로 삼은 신규 검증 사실

| 사실 | 출처 | 영향 |
|---|---|---|
| `DailyOPIc.xcodeproj`에 **공유 스킴 0개** | `find ... -name "*.xcscheme"` 결과 없음 | P-1 신설 |
| iOS **CI 없음** (`.github` 부재) | 디렉터리 확인 | P-1 신설 |
| iOS 테스트 = **Swift Testing 23개** (모델·디코딩 중심) | `DailyOPIcTests.swift` | 회귀 기반 존재 |
| `Config/Debug.xcconfig`가 **프로덕션 백엔드** 지시 | 파일 내용 | SP4 위험, 로컬 오버라이드 필요 |
| `.gitignore`가 `Config/*.local.xcconfig` 제외 | 파일 내용 | 오버라이드 메커니즘이 **이미 의도돼 있음** |
| BE CI: PR = 테스트만, push main = 배포 | `deploy-cloud-run.yml` | PR이 주 검증 채널 |
| BE 배포: `--no-traffic --tag candidate-*` → `/health` → `--to-latest` | 동일 | 격리는 트래픽만, **데이터 격리 아님** |
| 승격이 **0%→100% 원샷**, 카나리 없음 | `update-traffic --to-latest` | 변경 크기로 안전 확보 |
| `conftest.py`가 `FirestoreStateStore`→`InMemoryStateStore` monkeypatch + App Check 스텁 | `tests/conftest.py` | L1 격리 수단 |
| Firestore 에뮬레이터 CI 잡 존재 (포트 8088) | `firebase.json`, 워크플로 | **L2 격리 수단** |
| `config.py`에 `app_env: Literal[..., "staging", ...]` **이미 존재** | `app/config.py` | staging 신설 시 코드 변경 최소 |
| `config.py`에 `*_v2_enabled` 플래그 관례 존재 | 동일 | P5 플래그 패턴 재사용 |
| production에서 `MOCK_AI=true` 및 Google 샘플 광고 단위를 **validator가 거부** | 동일 | 안전 가드, 약화 금지 |
| **`strip_long = depth in {"summary","basic"}`** | `ai.py:1609` | **베이직 = 무료와 분석 동일** |
| **`focus` ≡ `detailed`** (분기 없음) | `ai.py` 전체 | **"문항별 코칭" 미구현** |
| **모의고사 평가가 `del depth`** | `ai.py:1705` | 모든 플랜 동일 모의 결과 |
| `StoreService.highestPlan`이 `lower.contains(...)` 부분 문자열 | `StoreService.swift:207-218` | P8a 승격 근거 |
| BE `.env`에 RevenueCat 시크릿 **없음** (Cloud Run 주입) | `.env` 키 목록 | 시크릿 분리 양호 |

---

# 부록 B. 이 단계에서 하지 않은 것

- Cloud Run / staging 리소스 **생성하지 않음**
- Firebase / RevenueCat / AdMob / App Store **조회 외 변경 없음**
- Swift / Python 프로덕션 코드 **한 줄도 수정 안 함**
- 배포 **없음**
- `git` 커밋 · 브랜치 · PR **생성 없음**
