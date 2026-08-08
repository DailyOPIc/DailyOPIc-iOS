# Graph Report - DailyOPIc  (2026-08-08)

## Corpus Check
- 86 files · ~140,498 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1777 nodes · 3094 edges · 139 communities (138 shown, 1 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 268 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9fea03f9`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- APIClient
- StoreService
- SpeechRecognitionService
- graphify Pipeline
- Sendable
- StudyInsightsSection
- MockExamScreen.swift
- String
- CodingKeys
- PracticeViewModel
- MockExamViewModel
- RecordingState
- BackgroundSurvey
- PRODUCT.md — DailyOPIc(데일리오픽)
- JSONValue
- DailyOPIc-BE FastAPI Backend
- AppConfiguration
- View
- AsyncOperationKind
- OPIcLevel
- SelfAssessmentLevel
- GuideTopic
- Foundation
- PrimaryButton
- JSONCoding
- AuthenticationService
- FirebaseBootstrap
- DailyOPIcTests
- AppPreferences
- AppLoadingIndicator
- ProgressScreen
- DailyOPIcUITests
- 7. 발견한 실제 UX 버그
- .resetExam
- AppPalette
- P5 — 백엔드 (독립 트랙 · **P0와 동시 착수**)
- PromptPlaybackService
- PlanEntitlement
- AdService
- DESIGN.md
- GoogleBannerView
- DifficultyAdjustment
- MockExamScreen
- .recorder
- P6 — 페이월 · 광고 · 통계
- SetupView
- AppEnvironment
- P-1 — 검증 인프라 (신규 선행 단계)
- Phase
- AdError
- RewardedAdPresentationDelegate
- MockHistoryDetailView
- SpeechRecognitionService.swift
- 6. Design tokens
- DailyOPIcApp
- FlowTags
- State
- MockSessionStage
- 4. 화면별 상태 감사
- DailyRefreshDialog
- RewardPurpose
- P0 — 디자인 토큰 기반
- P1 — 세션 보존 아키텍처
- AuthenticationService.swift
- ErrorBanner
- AdService.swift
- 16.2 상태별 UI 사양
- 33. Implementation order
- D + Microphone Lockup Brand Mark
- GuideState
- ExamSection
- .subscript
- QuestionStyle
- UI BASELINE AUDIT — DailyOPIc (iOS)
- Step
- 18. Low-confidence / invalid-answer UX
- 19. Daily Home hierarchy
- 1. Product design principles
- 25. Paywall
- 32. Migration strategy from current UI
- T1 — Navigation / session preservation
- T2 — MockExam session lifecycle
- T3 — Daily token / quota semantics
- T4 — AI evaluation confidence policy
- T5 — Recording termination policy
- T6 — RevenueCat / Paywall contract
- T8 — Accessibility target
- 5. 접근성 감사
- 6. 일관성 감사
- 10. Layout shell
- 14.1 문항 네비게이션 (데일리 · 14문항)
- 22. Mock Exam
- 23. Statistics
- T7 — Ads policy
- P2 — 모의고사 데드엔드 해소
- 13. Card hierarchy
- 17. Recording termination UX
- 20. Practice screen
- 21. Result screen
- 24. Settings
- 27. Advertising rules
- 28. Motion principles
- 29. VoiceOver behavior
- 31. Anti-patterns
- P3 — 말하기 상태 머신
- 11. 1차 audit 대비 변경 내역
- 3. 주요 사용자 여정 — 실제 조작 기준 `[SIM]`
- 8. 우선순위별 정리
- 11. Navigation / sheet / modal patterns
- 15. Loading / empty / error patterns
- 26. Subscription / restore / manage
- 30. Touch target rules
- 4. Navigation architecture
- 5. Session preservation rules
- 7. Dynamic Type strategy
- 8. Light / Dark Mode strategy
- DailyOPIc — DESIGN DECISION LOCK
- SwiftUI
- 10. 이번 단계에서도 확인하지 못한 것
- 1. 현재 빌드 / 실행 상태
- 3. Information architecture
- DailyOPIcTests.swift
- P4 — 결과 신뢰도 + 명명 정리
- P7 — 접근성 마감
- HistoryItem
- 2.3 DESIGN.md 순서 중 **그대로 구현하면 안 되는 것** (4건)
- PracticeHistoryRecord
- IMPLEMENTATION_PLAN.md
- PersistenceService
- RecordedAnswer
- 10. Commit strategy
- 1. Release safety principles
- 5. Backend compatibility strategy
- 9. Rollback strategy
- 3. P0–P8 implementation roadmap
- 7. Simulator / device verification matrix
- 8. Production-safe rollout strategy
- 4. Frontend / backend boundaries
- 6. Testing matrix

## God Nodes (most connected - your core abstractions)
1. `MockExamViewModel` - 71 edges
2. `PracticeViewModel` - 66 edges
3. `OPIcLevel` - 59 edges
4. `AppPreferences` - 41 edges
5. `SelfAssessmentLevel` - 36 edges
6. `APIClient` - 36 edges
7. `QuestionSet` - 35 edges
8. `AppEnvironment` - 31 edges
9. `DifficultyAdjustment` - 30 edges
10. `GeneratedQuestion` - 29 edges

## Surprising Connections (you probably didn't know these)
- `Reserved Onboarding Video Assets` --conceptually_related_to--> `Whisper Video/Audio Transcription`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md → .claude/skills/graphify/references/transcribe.md
- `App Check Debug Provider for Simulator` --semantically_similar_to--> `GAD_TEST_DEVICE_IDS Invalid Traffic Guard`  [INFERRED] [semantically similar]
  DailyOPIc/Resources/Firebase/README.md → README.md
- `Reserved Onboarding Video Assets` --conceptually_related_to--> `DailyOPIc iOS App`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md → README.md
- `.currentQuestion` --references--> `QuestionSet`  [INFERRED]
  DailyOPIc/ViewModels/MockExamViewModel.swift → DailyOPIc/Models/QuestionModels.swift
- `.body` --calls--> `AppLoadingIndicator`  [INFERRED]
  DailyOPIc/Views/Components/AILoadingOverlay.swift → DailyOPIc/Views/Components/AppLoadingIndicator.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **graphify Extraction and Build Pipeline** — _claude_skills_graphify_skill_graphify, _claude_skills_graphify_skill_ast_structural_extraction, _claude_skills_graphify_skill_semantic_extraction, _claude_skills_graphify_skill_semantic_extraction_cache, _claude_skills_graphify_skill_community_detection, _claude_skills_graphify_skill_graph_health_check, _claude_skills_graphify_skill_manifest [EXTRACTED 1.00]
- **DailyOPIc Request Authentication Flow** — readme_keychain_uuid_identity, readme_firebase_app_check, dailyopic_resources_firebase_readme_app_attest, dailyopic_resources_firebase_readme_app_check_debug_provider, dailyopic_resources_firebase_readme_google_service_info_plist, readme_dailyopic_be_backend [EXTRACTED 1.00]
- **AdMob Rewarded SSV End-to-End Test Setup** — readme_admob_rewarded_ssv, readme_cloudflare_tunnel_debug_url, readme_api_base_url_resolution, readme_admob_ad_unit_ids, readme_gad_test_device_ids, readme_xcconfig_injection [EXTRACTED 1.00]
- **AppIcon appearance variants (light / dark / tinted) rendering one brand mark** — dailyopic_assets_xcassets_appicon_appiconset_ic_dailyopic_light, dailyopic_assets_xcassets_appicon_appiconset_ic_dailyopic_dark, dailyopic_assets_xcassets_appicon_appiconset_ic_dailyopic_tinted, dailyopic_assets_xcassets_appicon_appiconset_d_microphone_lockup_mark [EXTRACTED 1.00]

## Communities (139 total, 1 thin omitted)

### Community 0 - "APIClient"
Cohesion: 0.07
Nodes (33): async, APIClient, .rewardVerificationTimeoutMessage, APIClientError, .code, .errorDescription, invalidResponse, .isAIUnavailable (+25 more)

### Community 1 - "StoreService"
Cohesion: 0.06
Nodes (38): AppUserIDProvider, CustomerInfo, AppRadius, AppSpacing, AppTypography, CGFloat, StoreError, .errorDescription (+30 more)

### Community 2 - "SpeechRecognitionService"
Cohesion: 0.18
Nodes (10): AVAudioFile, SpeechRecognitionService, SpeechRecordingResult, Bool, URL, Notification, SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask (+2 more)

### Community 3 - "graphify Pipeline"
Cohesion: 0.06
Nodes (45): graphify Skill Trigger Registration, Watch Debounce Window, URL Ingest into Corpus, Watch Mode Auto-Rebuild, FalkorDB Cypher Export, graphify MCP Stdio Server, Neo4j Cypher Export, Token Reduction Benchmark (+37 more)

### Community 4 - "Sendable"
Cohesion: 0.09
Nodes (48): Codable, Answer, AudioMetrics, Capabilities, ConfidenceBand, high, .label, low (+40 more)

### Community 5 - "StudyInsightsSection"
Cohesion: 0.09
Nodes (31): Content, DimensionAverage, PlanEntitlement, .weaknessTier, StudyInsights, Date, Int, String (+23 more)

### Community 6 - "MockExamScreen.swift"
Cohesion: 0.11
Nodes (27): CGPoint, CGRect, CGSize, Arrangement, FlexibleChips, .body, FlowLayout, Item (+19 more)

### Community 7 - "String"
Cohesion: 0.19
Nodes (14): GeneratedQuestion, .id, MockSession, QuestionSet, .debugTopicIDs, QuestionSetStatus, awaitingAdjustment, complete (+6 more)

### Community 8 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKey, CodingKeys, afterAdjust, beforeAdjust, changed, legacyEffectiveLevel, legacyInitialLevel, legacyPreviousInitialLevel (+19 more)

### Community 9 - "PracticeViewModel"
Cohesion: 0.06
Nodes (35): AnalyzedResult, Phase, analyzing, completed, idle, loading, PracticeViewModel, .analyzedNumbers (+27 more)

### Community 10 - "MockExamViewModel"
Cohesion: 0.09
Nodes (25): EvaluationRetryContext, MockExamViewModel, .canResume, .canRetryEvaluation, .currentQuestion, .expectedQuestionCount, .initialLevel, .mockAvailable (+17 more)

### Community 11 - "RecordingState"
Cohesion: 0.12
Nodes (17): PermissionState, denied, granted, unknown, RecordingState, failed, idle, interrupted (+9 more)

### Community 12 - "BackgroundSurvey"
Cohesion: 0.16
Nodes (13): BackgroundProfile, BackgroundSurvey, .isValid, .selectedTopicCount, SurveyOption, .id, Bool, Int (+5 more)

### Community 13 - "PRODUCT.md — DailyOPIc(데일리오픽)"
Cohesion: 0.12
Nodes (16): 10. 리뉴얼에서 지켜야 할 원칙 [방향], 11. 열린 질문 (결정 필요) [미확인], 1. 브랜드 · 언어 · 출시 상태, 2. 주 사용자와 사용 맥락 [방향], 3. 포지셔닝 / 대체 불가능한 지점 [방향], 4. 앱 구조 (현재 구현) [VERIFIED], 5. OPIc 시험 맥락 구현 범위 [VERIFIED], 6. 발화 → 분석 파이프라인 [VERIFIED] (+8 more)

### Community 14 - "JSONValue"
Cohesion: 0.10
Nodes (17): CustomStringConvertible, JSONValue, array, bool, null, number, string, RewardStatus (+9 more)

### Community 15 - "DailyOPIc-BE FastAPI Backend"
Cohesion: 0.11
Nodes (23): App Attest Attestation Provider, App Check Debug Provider for Simulator, Firestore Server-Only Access Boundary, GoogleService-Info.plist Placement, App Attest production Environment Entitlement, Reserved Onboarding Video Assets, AdMob Banner and Rewarded Unit IDs, AdMob Rewarded SSV Callback (+15 more)

### Community 16 - "AppConfiguration"
Cohesion: 0.17
Nodes (18): AppConfiguration, .apiBaseURL, .apiBaseURLSource, .bannerAdUnitID, .gadTestDeviceIdentifiers, .privacyPolicyURL, .resolvedAPIBaseURL, .revenueCatAPIKey (+10 more)

### Community 17 - "View"
Cohesion: 0.10
Nodes (28): Alignment, FeedbackSection, .body, LevelResultCard, .body, LockedFeedbackSection, .body, ResultUnlock (+20 more)

### Community 18 - "AsyncOperationKind"
Cohesion: 0.07
Nodes (26): AsyncOperationKind, dataLoading, difficultyAdjustment, mockResult, questionGeneration, retry, speechAnalysis, .title (+18 more)

### Community 19 - "OPIcLevel"
Cohesion: 0.13
Nodes (15): .predictedLevel, .targetLevel, OPIcLevel, AL, .description, .id, IH, IL (+7 more)

### Community 20 - "SelfAssessmentLevel"
Cohesion: 0.08
Nodes (30): SelfAssessmentLevel, .estimatedRange, .expectedTargetLevel, .id, level1, level2, level3, level4 (+22 more)

### Community 21 - "GuideTopic"
Cohesion: 0.15
Nodes (18): GuidePage, GuideReaderView, .body, .pages, GuideTopic, exam, .icon, .id (+10 more)

### Community 22 - "Foundation"
Cohesion: 0.23
Nodes (4): JSONDecoder.DateDecodingStrategy, Foundation, Observation, RevenueCat

### Community 23 - "PrimaryButton"
Cohesion: 0.15
Nodes (12): ButtonStyle, Configuration, PressableButtonStyle, PrimaryButton, .body, String, Void, .body (+4 more)

### Community 24 - "JSONCoding"
Cohesion: 0.23
Nodes (14): MockDraftRecord, .answers, .questionSet, .targetLevel, MockHistoryRecord, .answers, .evaluation, .questionSet (+6 more)

### Community 25 - "AuthenticationService"
Cohesion: 0.26
Nodes (8): AuthenticationService, AuthError, appCheckUnavailable, .errorDescription, firebaseAuthUnavailable, installationIDUnavailable, Bool, String

### Community 26 - "FirebaseBootstrap"
Cohesion: 0.19
Nodes (10): Any, Bool, FirebaseBootstrap, .buildConfiguration, .runtimeTarget, .shouldForceRefreshAppCheckToken, Bool, String (+2 more)

### Community 27 - "DailyOPIcTests"
Cohesion: 0.16
Nodes (3): DailyOPIcTests, Int, String

### Community 28 - "AppPreferences"
Cohesion: 0.12
Nodes (16): AppPreferences, .backgroundProfile, .guideState, .hasCompletedOnboarding, .initialLevel, .isInitialLevelSyncPending, .isNewToOPIc, .lastGuidePage (+8 more)

### Community 29 - "AppLoadingIndicator"
Cohesion: 0.17
Nodes (10): AppLoadingIndicator, .body, CGFloat, Color, DifficultyAdjustmentDialog, .body, Bool, String (+2 more)

### Community 30 - "ProgressScreen"
Cohesion: 0.13
Nodes (14): ProgressScreen, .corruptRecordCount, .currentPlan, .cutoff, .distribution, .distributionView, .insights, .latestLevel (+6 more)

### Community 31 - "DailyOPIcUITests"
Cohesion: 0.14
Nodes (6): DailyOPIcUITests, DailyOPIcUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool, XCTest, XCTestCase

### Community 32 - "7. 발견한 실제 UX 버그"
Cohesion: 0.12
Nodes (17): 7-10. 문항 네비게이션 chip 22~24pt — **P1** `[SIM]`+`[CODE]`, 7-11. 설정에 구독 관리·복원·EULA·문의 채널이 없다 — **P1** `[SIM]`+`[CODE]` 🆕, 7-12. 취약 유형 분석이 값을 전달하지 않는다 — **P2** `[SIM]` 🆕, 7-13. 다크 모드 accent 대비 — **P2** `[SIM]`+계산, 7-14. ATT를 가치 전달 전에 요청 — **P2** `[SIM]`, 7-15. AuthRecoveryView가 원인을 오도 — **P2** `[SIM]` (1차 P1에서 강등), 7-16. 타이머 만료 후 데드엔드 가능성 — **P3** `[UNVERIFIED]` (1차 P2에서 강등), 7-1. 도움말을 열면 진행 중인 학습 세션이 파괴된다 — **P0** `[SIM]`+`[CODE]` 🆕 (+9 more)

### Community 33 - ".resetExam"
Cohesion: 0.17
Nodes (4): AudioFileService, Int, String, URL

### Community 34 - "AppPalette"
Cohesion: 0.18
Nodes (9): AppPalette, Color, Double, AnswerPanel, .body, Bool, String, .body (+1 more)

### Community 35 - "P5 — 백엔드 (독립 트랙 · **P0와 동시 착수**)"
Cohesion: 0.15
Nodes (13): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation (프로덕션 트래픽 무영향 검증 방법), Objective, P5 — 백엔드 (독립 트랙 · **P0와 동시 착수**) (+5 more)

### Community 36 - "PromptPlaybackService"
Cohesion: 0.17
Nodes (8): AVSpeechSynthesizer, AVSpeechSynthesizerDelegate, AVSpeechUtterance, PromptPlaybackService, Int, Set, String, ObservableObject

### Community 37 - "PlanEntitlement"
Cohesion: 0.14
Nodes (12): Comparable, PlanEntitlement, basic, .displayName, free, .isPaid, .monthlyPriceKRW, plus (+4 more)

### Community 38 - "AdService"
Cohesion: 0.20
Nodes (7): ConsentStatus, AdService, String, FormStatus, PrivacyOptionsRequirementStatus, RequestParameters, RewardedAd

### Community 39 - "DESIGN.md"
Cohesion: 0.13
Nodes (14): 12.1 4단계, 12.2 공통 규칙, 12.3 녹음 버튼 (특수), 12. Button hierarchy, 2.1 주 여정 — 데일리 말하기 (하루 1회, 5–10분), 2.2 부 여정 — 모의고사 (실전 시뮬레이션), 2.3 보조 여정, 2. Core user journey (+6 more)

### Community 40 - "GoogleBannerView"
Cohesion: 0.38
Nodes (5): BannerView, Context, .body, GoogleBannerView, UIViewRepresentable

### Community 41 - "DifficultyAdjustment"
Cohesion: 0.12
Nodes (16): CaseIterable, PerQuestionFeedback, .id, DifficultyAdjustment, easier, harder, .id, same (+8 more)

### Community 42 - "MockExamScreen"
Cohesion: 0.19
Nodes (5): MockExamScreen, .body, .canResetExam, .introduction, .mockUpsell

### Community 43 - ".recorder"
Cohesion: 0.11
Nodes (15): Bool, PromptPlayButton, .title, Bool, String, Void, QuestionCard, RecordingButton (+7 more)

### Community 44 - "P6 — 페이월 · 광고 · 통계"
Cohesion: 0.15
Nodes (13): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P6 — 페이월 · 광고 · 통계 (+5 more)

### Community 45 - "SetupView"
Cohesion: 0.31
Nodes (5): SetupAlert, SetupView, .appUserID, .body, String

### Community 46 - "AppEnvironment"
Cohesion: 0.15
Nodes (10): AppEnvironment, .currentPlan, .showsAds, LaunchState, failed, launching, ready, Bool (+2 more)

### Community 47 - "P-1 — 검증 인프라 (신규 선행 단계)"
Cohesion: 0.17
Nodes (12): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P-1 — 검증 인프라 (신규 선행 단계) (+4 more)

### Community 48 - "Phase"
Cohesion: 0.22
Nodes (9): Phase, adjustment, analyzing, answering, completed, introduction, loading, readyForReward (+1 more)

### Community 49 - "AdError"
Cohesion: 0.29
Nodes (7): AdError, busy, .errorDescription, notEarned, privacyOptionsNotRequired, privacyOptionsUnavailable, unavailable

### Community 50 - "RewardedAdPresentationDelegate"
Cohesion: 0.33
Nodes (6): RewardedAdPresentationDelegate, Bool, Error, Void, FullScreenContentDelegate, FullScreenPresentingAd

### Community 51 - "MockHistoryDetailView"
Cohesion: 0.40
Nodes (5): MockHistoryDetailView, .body, PracticeHistoryDetailView, .body, .records

### Community 52 - "SpeechRecognitionService.swift"
Cohesion: 0.50
Nodes (3): AVFoundation, Combine, Speech

### Community 53 - "6. Design tokens"
Cohesion: 0.14
Nodes (14): 6.1 원칙, 6.2 Semantic colors, 6.3 Typography, 6.4 Spacing, 6.5 Radius, 6.6 Elevation / Material, 6. Design tokens, Material 사용 규칙 (+6 more)

### Community 54 - "DailyOPIcApp"
Cohesion: 0.15
Nodes (12): App, AppDelegate, DailyOPIcApp, .body, StorageRecoveryView, .body, String, .body (+4 more)

### Community 55 - "FlowTags"
Cohesion: 0.38
Nodes (6): .body, FlowTags, .body, String, TagChip, .body

### Community 56 - "State"
Cohesion: 0.17
Nodes (9): State, failed, idle, loading, presenting, ready, verifying, MainTabView (+1 more)

### Community 57 - "MockSessionStage"
Cohesion: 0.13
Nodes (13): MockSessionStage, answeringFront, answeringTail, awaitingAdjustmentAd, awaitingResultAd, awaitingStartAd, completed, evaluating (+5 more)

### Community 58 - "4. 화면별 상태 감사"
Cohesion: 0.17
Nodes (12): 4.10 OPIcGuideView `[SIM]` — 신규 관찰, 4.11 커스텀 오버레이 `[SIM]`+`[CODE]`, 4.1 SplashView `[SIM]`, 4.2 ATT 프롬프트 `[SIM]`, 4.3 AuthRecoveryView `[SIM]` (1차 관찰, 이번엔 재현 안 됨), 4.4 PracticeScreen `[SIM]` — **1차 `[CODE]` → 승격**, 4.5 PracticeResultView / HistoryDetailView `[SIM]` — **1차 `[CODE]` → 승격**, 4.6 MockExamScreen `[SIM]` — **1차 `[CODE]` → 승격, 판정 악화** (+4 more)

### Community 59 - "DailyRefreshDialog"
Cohesion: 0.43
Nodes (5): DailyRefreshDialog, .body, Bool, String, Void

### Community 60 - "RewardPurpose"
Cohesion: 0.18
Nodes (9): object, RewardIntentRequest, RewardPurpose, mockAdjustment, mockResult, mockStart, practiceCredits, practiceRefresh (+1 more)

### Community 61 - "P0 — 디자인 토큰 기반"
Cohesion: 0.17
Nodes (12): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P0 — 디자인 토큰 기반 (+4 more)

### Community 62 - "P1 — 세션 보존 아키텍처"
Cohesion: 0.17
Nodes (12): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P1 — 세션 보존 아키텍처 (+4 more)

### Community 63 - "AuthenticationService.swift"
Cohesion: 0.33
Nodes (5): DeviceCheck, FirebaseAppCheck, FirebaseAuth, FirebaseCore, Security

### Community 64 - "ErrorBanner"
Cohesion: 0.29
Nodes (6): BannerAdView, ErrorBanner, .body, String, Void, .body

### Community 65 - "AdService.swift"
Cohesion: 0.18
Nodes (9): AppTrackingTransparency, UIViewController, UIApplication, .topViewController, UIViewController, UIApplication, .topViewController, GoogleMobileAds (+1 more)

### Community 66 - "16.2 상태별 UI 사양"
Cohesion: 0.17
Nodes (12): 16.1 상태 다이어그램, 16.2 상태별 UI 사양, 16.3 상태 전이 시 공통 규칙, 16. Speaking state machine UI, `analyzing`, `error`, `finishing`, `interrupted` (+4 more)

### Community 67 - "33. Implementation order"
Cohesion: 0.20
Nodes (10): 33. Implementation order, P0 — 기반 (다른 모든 것의 전제), P1 — 세션 보존 (P3 원칙 실현), P2 — 모의고사 데드엔드 해소, P3 — 말하기 상태 머신, P4 — 결과 신뢰도 + 명명 정리, P5 — 백엔드 (별도 트랙 · 병렬 가능), P6 — 페이월 · 광고 · 통계 (+2 more)

### Community 68 - "D + Microphone Lockup Brand Mark"
Cohesion: 0.60
Nodes (5): D + Microphone Lockup Brand Mark, DailyOPIc App Icon (Dark Appearance), DailyOPIc App Icon (Light Appearance), DailyOPIc App Icon (Tinted / Monochrome Appearance), iOS 18 Appearance-Variant App Icon Set

### Community 69 - "GuideState"
Cohesion: 0.25
Nodes (6): GuideState, completed, inProgress, skipped, unseen, UserDefaults

### Community 70 - "ExamSection"
Cohesion: 0.22
Nodes (9): ExamSection, advanced, comparison, introduction, .label, practice, roleplay, survey (+1 more)

### Community 71 - ".subscript"
Cohesion: 0.50
Nodes (3): Array, Element, Index

### Community 72 - "QuestionStyle"
Cohesion: 0.22
Nodes (9): QuestionStyle, comparison, description, .label, opinion, pastExperience, problemSolving, roleplay (+1 more)

### Community 73 - "UI BASELINE AUDIT — DailyOPIc (iOS)"
Cohesion: 0.25
Nodes (7): 2. 검증에 사용한 시뮬레이터, 9.1 재설계 착수 전에 정리되어야 할 기술적 선결 조건, 9. 다음 디자인 단계에서 반드시 해결해야 할 것 (10개), UI BASELINE AUDIT — DailyOPIc (iOS), 부록: 이번 audit에서 변경한 것, 이 개정판이 1차와 다른 점, 증거 표기 규칙

### Community 74 - "Step"
Cohesion: 0.50
Nodes (4): Step, firstQuestion, guide, level

### Community 75 - "18. Low-confidence / invalid-answer UX"
Cohesion: 0.25
Nodes (8): 18.1 확정 제약 (다시 명시), 18.2 버킷별 UI, 18.3 5차원 루브릭 표시 (fake precision 제거), 18.4 disclaimer, 18. Low-confidence / invalid-answer UX, A. 평가 가능, B. 신뢰 낮음, C. 평가 불가 · 다시 말하기 필요

### Community 76 - "19. Daily Home hierarchy"
Cohesion: 0.25
Nodes (8): 19.1 화면 목적, 19.2 정보 위계 (위 → 아래), 19.3 오늘의 상태 표시 (T3 명명 확정), 19.4 세트 소진 상태 (오류가 아니라 선택지), 19.5 표시하지 않는 것, 19. Daily Home hierarchy, 무료 플랜, 유료 플랜

### Community 77 - "1. Product design principles"
Cohesion: 0.25
Nodes (8): 1. Product design principles, P1. Speaking first — 말하기가 화면의 주인이다, P2. Trustworthy over impressive — 모르는 것은 모른다고 말한다, P3. Nothing is lost — 사용자의 노력은 사라지지 않는다, P4. Always an exit — 막다른 화면을 만들지 않는다, P5. Calm surface — 조용한 화면이 집중을 만든다, P6. One primary action — 화면마다 주 행동은 하나, P7. Accessible by construction — 나중에 붙일 수 없는 것부터 정한다

### Community 78 - "25. Paywall"
Cohesion: 0.25
Nodes (8): 25.1 현재 상품 사실 (RevenueCat 조회 · 변경 없음), 25.2 구조 (의사결정 화면으로 재설계), 25.3 비교 축 4개 (서버가 실제로 강제하는 것만), 25.4 삭제하는 것, 25.5 필수 수정 (P0), 25.6 가격·문구 바인딩, 25.7 진입 맥락별 상단 문구, 25. Paywall

### Community 79 - "32. Migration strategy from current UI"
Cohesion: 0.25
Nodes (8): 32.1 원칙, 32.2 재사용 / 교체 / 폐기, 32.3 위험 구간과 완화, 32.4 하지 않는 것, 32. Migration strategy from current UI, 🔧 교체 (구조 유지, 구현 변경), ✅ 그대로 유지 (건드리지 않는다), 🗑 폐기

### Community 80 - "T1 — Navigation / session preservation"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T1 — Navigation / session preservation, VERIFIED CURRENT STATE

### Community 81 - "T2 — MockExam session lifecycle"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T2 — MockExam session lifecycle, VERIFIED CURRENT STATE

### Community 82 - "T3 — Daily token / quota semantics"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T3 — Daily token / quota semantics, VERIFIED CURRENT STATE

### Community 83 - "T4 — AI evaluation confidence policy"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T4 — AI evaluation confidence policy, VERIFIED CURRENT STATE

### Community 84 - "T5 — Recording termination policy"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T5 — Recording termination policy, VERIFIED CURRENT STATE

### Community 85 - "T6 — RevenueCat / Paywall contract"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T6 — RevenueCat / Paywall contract, VERIFIED CURRENT STATE (RevenueCat MCP, READ-ONLY 조회)

### Community 86 - "T8 — Accessibility target"
Cohesion: 0.25
Nodes (8): ALTERNATIVES, DESIGN IMPACT, IMPLEMENTATION SCOPE, RECOMMENDED DIRECTION, REQUIRES PRODUCT DECISION, ROOT PROBLEM, T8 — Accessibility target, VERIFIED CURRENT STATE

### Community 87 - "5. 접근성 감사"
Cohesion: 0.29
Nodes (7): 5.1 Dynamic Type — **전면 실패** `[SIM]`+`[CODE]`, 5.2 터치 타깃, 5.3 VoiceOver / 레이블, 5.4 Reduce Motion, 5.5 색 대비, 5.6 색상 단독 정보 전달, 5. 접근성 감사

### Community 88 - "6. 일관성 감사"
Cohesion: 0.29
Nodes (7): 6.1 디자인 토큰 드리프트 `[CODE]`, 6.2 모달·네비게이션 패턴 `[SIM]`+`[CODE]`, 6.3 오버레이/헤더의 스크롤 처리 — **전 화면 공통 결함** `[SIM]`, 6.4 전사(transcript) 표현 불일치 `[CODE]`, 6.5 로컬라이제이션 혼재 `[SIM]`, 6.6 죽은 코드 `[CODE]`, 6. 일관성 감사

### Community 89 - "10. Layout shell"
Cohesion: 0.29
Nodes (7): 10.1 화면 골격, 10.2 Safe area, 10.3 Tab bar, 10.4 Fixed controls (고정 액션 영역), 10.5 Scroll behavior, 10.6 Ads placement (Q5 LOCKED 확정 배치), 10. Layout shell

### Community 90 - "14.1 문항 네비게이션 (데일리 · 14문항)"
Cohesion: 0.29
Nodes (7): 14.1 문항 네비게이션 (데일리 · 14문항), 14.2 태그 (읽기 전용 메타), 14.3 선택 칩 (설문 · 목표 등급), 14. Chips / tags / question navigation, 상태 표현 (색 단독 금지 — A8), 스펙, 이 컴포넌트가 전달해야 하는 핵심 메시지

### Community 91 - "22. Mock Exam"
Cohesion: 0.29
Nodes (7): 22.1 서버 stage ↔ 화면 1:1 매핑 (T2 핵심 수정), 22.2 광고 게이트 화면 (3개 공통 사양), 22.3 진행 표시, 22.4 답변 화면, 22.5 포기 (Q9 LOCKED), 22.6 결과, 22. Mock Exam

### Community 92 - "23. Statistics"
Cohesion: 0.29
Nodes (7): 23.1 구성 (전부 현재 제공 중 · Q7 LOCKED로 전 플랜 무료), 23.2 예상 등급 추이, 23.3 취약 유형, 23.4 주간 리포트, 23.5 학습 기록, 23.6 배너 광고, 23. Statistics

### Community 93 - "T7 — Ads policy"
Cohesion: 0.29
Nodes (7): DESIGN DECISION NEEDED, DESIGN IMPACT, IMPLEMENTATION SCOPE, REQUIRES PRODUCT DECISION, T7 — Ads policy, UX PROBLEM, VERIFIED CURRENT POLICY

### Community 94 - "P2 — 모의고사 데드엔드 해소"
Cohesion: 0.17
Nodes (12): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P2 — 모의고사 데드엔드 해소 (+4 more)

### Community 95 - "13. Card hierarchy"
Cohesion: 0.33
Nodes (6): 13.1 카드를 쓰지 않는 기본값, 13.2 카드를 쓰는 조건 (전부 만족할 때만), 13.3 카드 스펙, 13.4 카드 중첩 금지, 13.5 정보 밀도, 13. Card hierarchy

### Community 96 - "17. Recording termination UX"
Cohesion: 0.33
Nodes (6): 17.1 확정 정책, 17.2 시간 표시 규칙, 17.3 종료와 제출의 분리 (정책의 핵심), 17.4 인터럽션 처리 (R4), 17.5 STT 조용한 종료 (알려진 한계), 17. Recording termination UX

### Community 97 - "20. Practice screen"
Cohesion: 0.33
Nodes (6): 20.1 레이아웃, 20.2 문항 카드, 20.3 말하기 영역 (고정), 20.4 권한 거부 전용 화면 (신규 · A11 대응), 20.5 배너 광고, 20. Practice screen

### Community 98 - "21. Result screen"
Cohesion: 0.33
Nodes (6): 21.1 A 버킷 결과 구조, 21.2 표시 규칙, 21.3 플랜에 따라 없는 항목 처리, 21.4 B / C 버킷, 21.5 부분 결과 (`resultStatus == "partial"`), 21. Result screen

### Community 99 - "24. Settings"
Cohesion: 0.33
Nodes (6): 24.1 구성 (`List` 기반 · 현재 구조 유지), 24.2 목표 등급 변경 (핵심 수정), 24.3 도움말 다시 보기, 24.4 구독 섹션, 24.5 배너 광고, 24. Settings

### Community 100 - "27. Advertising rules"
Cohesion: 0.33
Nodes (6): 27.1 배너, 27.2 리워드 광고 (5개 트리거 · 변경 없음), 27.3 리워드 광고 UX 규칙, 27.4 동의 · 추적 (ATT), 27.5 금지, 27. Advertising rules

### Community 101 - "28. Motion principles"
Cohesion: 0.33
Nodes (6): 28.1 원칙, 28.2 허용되는 모션 (4종), 28.3 금지, 28.4 Reduce Motion (A9), 28.5 인터럽터블, 28. Motion principles

### Community 102 - "29. VoiceOver behavior"
Cohesion: 0.33
Nodes (6): 29.1 화면별 읽기 순서, 29.2 필수 발표 (Announcement), 29.3 라벨 작성 규칙, 29.4 모달 (A10), 29.5 로딩 중 이름 보존 (A11), 29. VoiceOver behavior

### Community 103 - "31. Anti-patterns"
Cohesion: 0.33
Nodes (6): 31.1 시각, 31.2 데이터 표현 (가장 중요), 31.3 인터랙션, 31.4 SwiftUI에 웹 패턴 이식 금지, 31.5 카피, 31. Anti-patterns

### Community 104 - "P3 — 말하기 상태 머신"
Cohesion: 0.17
Nodes (12): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P3 — 말하기 상태 머신 (+4 more)

### Community 105 - "11. 1차 audit 대비 변경 내역"
Cohesion: 0.40
Nodes (5): 11.1 `[CODE]` → `[SIM]` 승격, 11. 1차 audit 대비 변경 내역, 11.2 신규 발견 (시뮬레이터 없이는 보이지 않던 것), 11.3 **철회 — 1차에서 문제로 적었으나 사실이 아님**, 11.4 심각도 조정

### Community 106 - "3. 주요 사용자 여정 — 실제 조작 기준 `[SIM]`"
Cohesion: 0.40
Nodes (5): 3. 주요 사용자 여정 — 실제 조작 기준 `[SIM]`, A. 데일리 (Practice) `[SIM]`, B. 모의고사 (MockExam) `[SIM]` — **여정 중단됨**, C. 통계 (Progress) `[SIM]`, D. 공통 진입점 `[SIM]`

### Community 107 - "8. 우선순위별 정리"
Cohesion: 0.40
Nodes (5): 8. 우선순위별 정리, P0 — 사용자가 데이터·기회·돈을 잃는다, P1 — 핵심 플로우가 오작동하거나 거짓을 말한다, P2 — 품질·신뢰 저하, P3 — 정리

### Community 108 - "11. Navigation / sheet / modal patterns"
Cohesion: 0.40
Nodes (5): 11.1 모달 계약 (전 모달 공통), 11.2 커스텀 오버레이 → 시스템 컴포넌트 대체, 11.3 시트 크기, 11.4 fullScreenCover 2종 (§4.1), 11. Navigation / sheet / modal patterns

### Community 109 - "15. Loading / empty / error patterns"
Cohesion: 0.40
Nodes (5): 15.1 로딩 3종, 15.2 빈 상태, 15.3 오류 상태, 15.4 절대 만들지 않는 상태, 15. Loading / empty / error patterns

### Community 110 - "26. Subscription / restore / manage"
Cohesion: 0.40
Nodes (5): 26.1 현재 구현 확인 (전부 존재하며 올바름 — 유지), 26.2 플랜 판정 우선순위, 26.3 기술 부채 (Q8 LOCKED 기록), 26.4 UI 규칙, 26. Subscription / restore / manage

### Community 111 - "30. Touch target rules"
Cohesion: 0.40
Nodes (5): 30.1 절대 규칙, 30.2 컴포넌트가 책임진다, 30.3 현재 위반 (수정 대상), 30.4 안전 영역, 30. Touch target rules

### Community 112 - "4. Navigation architecture"
Cohesion: 0.40
Nodes (5): 4.1 루트 계약, 4.2 제시 방식 결정표, 4.3 뒤로가기 계약, 4.4 모의고사 특례, 4. Navigation architecture

### Community 113 - "5. Session preservation rules"
Cohesion: 0.40
Nodes (5): 5.1 상태 소유권 계층 (핵심 아키텍처 결정), 5.2 보존 규칙 (R1–R6), 5.3 데일리 드래프트 (R5 신규), 5.4 세션 파괴가 허용되는 유일한 경우, 5. Session preservation rules

### Community 114 - "7. Dynamic Type strategy"
Cohesion: 0.40
Nodes (5): 7.1 지원 범위, 7.2 3단계 적응 전략, 7.3 절대 축소되면 안 되는 요소 (AX5에서도 화면 안), 7.4 검증 방법, 7. Dynamic Type strategy

### Community 115 - "8. Light / Dark Mode strategy"
Cohesion: 0.40
Nodes (5): 8.1 원칙, 8.2 모드별 차이 규칙, 8.3 하드코딩 금지, 8.4 검증, 8. Light / Dark Mode strategy

### Community 116 - "DailyOPIc — DESIGN DECISION LOCK"
Cohesion: 0.40
Nodes (4): DailyOPIc — DESIGN DECISION LOCK, Decisions — LOCKED (2026-08-08 제품 소유자 승인 완료), 구현 범위로 이월된 항목 (DESIGN.md 범위 밖, 별도 작업), 문서 상태

### Community 117 - "SwiftUI"
Cohesion: 0.12
Nodes (13): AppRootView, .body, DailyTokenBadge, .body, Int, AuthRecoveryView, .body, String (+5 more)

### Community 118 - "10. 이번 단계에서도 확인하지 못한 것"
Cohesion: 0.50
Nodes (4): 10.1 `[CODE]`로만 확인된 영역, 10.2 `[UNVERIFIED]`, 10.3 재현 조건이 확정되지 않은 것, 10. 이번 단계에서도 확인하지 못한 것

### Community 119 - "1. 현재 빌드 / 실행 상태"
Cohesion: 0.50
Nodes (4): 1.1 빌드 `[SIM]`, 1.2 런타임 `[SIM]` — **1차 대비 변경**, 1.3 이 audit이 커버하는 범위, 1. 현재 빌드 / 실행 상태

### Community 120 - "3. Information architecture"
Cohesion: 0.50
Nodes (4): 3.1 전체 구조, 3.2 계층 원칙, 3.3 명명 규칙 (T3 LOCKED 반영), 3. Information architecture

### Community 122 - "P4 — 결과 신뢰도 + 명명 정리"
Cohesion: 0.17
Nodes (12): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Isolated backend validation, Objective, P4 — 결과 신뢰도 + 명명 정리 (+4 more)

### Community 123 - "P7 — 접근성 마감"
Cohesion: 0.18
Nodes (11): Commit boundary, Compatibility requirements, Dependencies, Done criteria, Exact areas likely to change, Objective, P7 — 접근성 마감, Production risk (+3 more)

### Community 124 - "HistoryItem"
Cohesion: 0.22
Nodes (9): HistoryItem, HistoryRow, .body, Kind, mock, practice, .historyRows, Date (+1 more)

### Community 125 - "2.3 DESIGN.md 순서 중 **그대로 구현하면 안 되는 것** (4건)"
Cohesion: 0.22
Nodes (9): 2.1 그래프, 2.2 특별 의존성 심사 (요청 항목 전수), 2.3 DESIGN.md 순서 중 **그대로 구현하면 안 되는 것** (4건), 2.4 신규 선행 단계 — P-1 (DESIGN.md에 없음), 2. Dependency graph, 🔁 정정 1 — 페이월 `Button` 전환을 P6에 두지 않는다, 🔁 정정 2 — 백엔드(P5)를 P4 뒤에 놓지 않는다, ⚠️ 정정 3 — A/B/C를 "P4의 한 항목"으로 다루지 않는다 (+1 more)

### Community 126 - "PracticeHistoryRecord"
Cohesion: 0.25
Nodes (6): PracticeHistoryRecord, .evaluation, .predictedLevel, .question, .targetLevel, SwiftData

### Community 127 - "IMPLEMENTATION_PLAN.md"
Cohesion: 0.25
Nodes (7): 11. Definition of done per phase, 12.1 왜 이것이 첫 슬라이스인가, 12.2 슬라이스 구성 (커밋 4개), 12. Recommended first implementation slice, DailyOPIc — IMPLEMENTATION_PLAN.md, 부록 A. 이 계획이 근거로 삼은 신규 검증 사실, 부록 B. 이 단계에서 하지 않은 것

### Community 128 - "PersistenceService"
Cohesion: 0.43
Nodes (3): PersistenceService, String, ModelContext

### Community 129 - "RecordedAnswer"
Cohesion: 0.40
Nodes (4): RecordedAnswer, .audioURL, .id, URL

### Community 130 - "10. Commit strategy"
Cohesion: 0.33
Nodes (6): 10.1 Conventional Commit 규약, 10.2 커밋 크기 규칙, 10.3 브랜치 · PR, 10. Commit strategy, Scope (이 프로젝트 확정 목록), Type

### Community 131 - "1. Release safety principles"
Cohesion: 0.40
Nodes (5): 1.1 두 개의 게이트, 1.2 불변 규칙 (SP1–SP10), 1.3 "배포"의 정의 (이 저장소 한정 — 검증됨), 1.4 페이월 카피 원칙 (교차검증 결과 반영), 1. Release safety principles

### Community 132 - "5. Backend compatibility strategy"
Cohesion: 0.40
Nodes (5): 5.1 응답 진화 규칙, 5.2 Firestore 진화 규칙, 5.3 클라이언트 하위 호환 실증 방법, 5.4 서버 기능 플래그 관례 (기존 패턴 재사용), 5. Backend compatibility strategy

### Community 133 - "9. Rollback strategy"
Cohesion: 0.40
Nodes (5): 9.1 계층별 롤백 수단, 9.2 여기서 나오는 결론, 9.3 롤백 경계 (커밋 설계 원칙), 9.4 사후 조치, 9. Rollback strategy

### Community 134 - "3. P0–P8 implementation roadmap"
Cohesion: 0.50
Nodes (4): 3. P0–P8 implementation roadmap, P8 — 기술 부채, P8a — 플랜 매핑 정리 (**P6 이전으로 승격**), P8b — 잔여 정리

### Community 135 - "7. Simulator / device verification matrix"
Cohesion: 0.50
Nodes (4): 7.1 시뮬레이터 (기본 검증), 7.2 실기기 (필수 구간), 7.3 검증 계정·데이터 원칙, 7. Simulator / device verification matrix

### Community 136 - "8. Production-safe rollout strategy"
Cohesion: 0.50
Nodes (4): 8.1 iOS 롤아웃, 8.2 백엔드 롤아웃, 8.3 릴리스 묶음 권장, 8. Production-safe rollout strategy

### Community 137 - "4. Frontend / backend boundaries"
Cohesion: 0.67
Nodes (3): 4.1 경계 원칙, 4.2 이 경계에서 나오는 규칙, 4. Frontend / backend boundaries

### Community 138 - "6. Testing matrix"
Cohesion: 0.67
Nodes (3): 6.1 현재 테스트 자산 (검증됨), 6.2 신설이 필요한 테스트, 6. Testing matrix

## Ambiguous Edges - Review These
- `Whisper Video/Audio Transcription` → `Reserved Onboarding Video Assets`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md · relation: conceptually_related_to
- `DailyOPIc iOS App` → `Reserved Onboarding Video Assets`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md · relation: conceptually_related_to

## Knowledge Gaps
- **786 isolated node(s):** `DailyOPIc — IMPLEMENTATION_PLAN.md`, `1.1 두 개의 게이트`, `1.2 불변 규칙 (SP1–SP10)`, `1.3 "배포"의 정의 (이 저장소 한정 — 검증됨)`, `1.4 페이월 카피 원칙 (교차검증 결과 반영)` (+781 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Whisper Video/Audio Transcription` and `Reserved Onboarding Video Assets`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `DailyOPIc iOS App` and `Reserved Onboarding Video Assets`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `View` connect `View` to `StoreService`, `StudyInsightsSection`, `MockExamScreen.swift`, `PracticeViewModel`, `AsyncOperationKind`, `SelfAssessmentLevel`, `GuideTopic`, `PrimaryButton`, `AppPreferences`, `AppLoadingIndicator`, `ProgressScreen`, `AppPalette`, `MockExamScreen`, `.recorder`, `SetupView`, `MockHistoryDetailView`, `DailyOPIcApp`, `FlowTags`, `State`, `DailyRefreshDialog`, `ErrorBanner`, `SwiftUI`, `HistoryItem`?**
  _High betweenness centrality (0.093) - this node is a cross-community bridge._
- **Why does `MockExamViewModel` connect `MockExamViewModel` to `APIClient`, `RecordedAnswer`, `PersistenceService`, `SpeechRecognitionService`, `Sendable`, `String`, `BackgroundSurvey`, `AsyncOperationKind`, `OPIcLevel`, `SelfAssessmentLevel`, `Foundation`, `AppPreferences`, `.resetExam`, `PromptPlaybackService`, `AdService`, `DifficultyAdjustment`, `MockExamScreen`, `AppEnvironment`, `Phase`, `State`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Why does `PracticeViewModel` connect `PracticeViewModel` to `APIClient`, `PersistenceService`, `SpeechRecognitionService`, `.resetExam`, `Sendable`, `PromptPlaybackService`, `AdService`, `String`, `AppEnvironment`, `AsyncOperationKind`, `OPIcLevel`, `SelfAssessmentLevel`, `Foundation`, `State`, `AppPreferences`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `MockExamViewModel` (e.g. with `PromptPlaybackService` and `SpeechRecognitionService`) actually correct?**
  _`MockExamViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `PracticeViewModel` (e.g. with `PromptPlaybackService` and `SpeechRecognitionService`) actually correct?**
  _`PracticeViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._