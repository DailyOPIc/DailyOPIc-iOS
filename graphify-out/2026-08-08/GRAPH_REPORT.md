# Graph Report - DailyOPIc  (2026-08-07)

## Corpus Check
- 82 files · ~103,287 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1253 nodes · 2574 edges · 69 communities (68 shown, 1 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 268 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5d96467a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- APIClient
- StoreService
- SpeechRecognitionService
- graphify Pipeline
- String
- ProgressScreen
- MockExamScreen.swift
- QuestionSet
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
- AppTelemetry
- OPIcLevel
- OnboardingView
- GuideTopic
- Foundation
- PrimaryButton
- SelfAssessmentLevel
- AuthenticationService
- FirebaseBootstrap
- DailyOPIcTests
- AppPreferences
- AppLoadingIndicator
- .updateLocalEntitlement
- DailyOPIcUITests
- PaywallView
- .saveDraft
- AppPalette
- .application
- PromptPlaybackService
- PlanEntitlement
- AdService
- AsyncOperationKind
- GoogleBannerView
- DifficultyAdjustment
- .body
- PracticeScreen
- TargetLevelConfirmationDialog
- SetupView
- AppEnvironment
- WeaknessTier
- AsyncOperationState
- AdError
- RewardedAdPresentationDelegate
- SwiftUI
- SpeechRecognitionService.swift
- FlowTags
- State
- PersistenceService
- DailyRefreshDialog
- RewardPurpose
- RubricBand
- RubricDimension
- AuthenticationService.swift
- ErrorBanner
- AdService.swift
- MockExamScreen
- D + Microphone Lockup Brand Mark
- GuideState
- .subscript
- AppTypography.swift
- Step

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
  DailyOPIc/Views/Screens/Main/MockExam/MockExamScreen.swift → DailyOPIc/Views/Components/AppLoadingIndicator.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **graphify Extraction and Build Pipeline** — _claude_skills_graphify_skill_graphify, _claude_skills_graphify_skill_ast_structural_extraction, _claude_skills_graphify_skill_semantic_extraction, _claude_skills_graphify_skill_semantic_extraction_cache, _claude_skills_graphify_skill_community_detection, _claude_skills_graphify_skill_graph_health_check, _claude_skills_graphify_skill_manifest [EXTRACTED 1.00]
- **DailyOPIc Request Authentication Flow** — readme_keychain_uuid_identity, readme_firebase_app_check, dailyopic_resources_firebase_readme_app_attest, dailyopic_resources_firebase_readme_app_check_debug_provider, dailyopic_resources_firebase_readme_google_service_info_plist, readme_dailyopic_be_backend [EXTRACTED 1.00]
- **AdMob Rewarded SSV End-to-End Test Setup** — readme_admob_rewarded_ssv, readme_cloudflare_tunnel_debug_url, readme_api_base_url_resolution, readme_admob_ad_unit_ids, readme_gad_test_device_ids, readme_xcconfig_injection [EXTRACTED 1.00]
- **AppIcon appearance variants (light / dark / tinted) rendering one brand mark** — dailyopic_assets_xcassets_appicon_appiconset_ic_dailyopic_light, dailyopic_assets_xcassets_appicon_appiconset_ic_dailyopic_dark, dailyopic_assets_xcassets_appicon_appiconset_ic_dailyopic_tinted, dailyopic_assets_xcassets_appicon_appiconset_d_microphone_lockup_mark [EXTRACTED 1.00]

## Communities (69 total, 1 thin omitted)

### Community 0 - "APIClient"
Cohesion: 0.07
Nodes (33): async, APIClient, .rewardVerificationTimeoutMessage, APIClientError, .code, .errorDescription, invalidResponse, .isAIUnavailable (+25 more)

### Community 1 - "StoreService"
Cohesion: 0.17
Nodes (10): AppUserIDProvider, StorePackage, StoreService, Bool, Never, PlanEntitlement, String, Task (+2 more)

### Community 2 - "SpeechRecognitionService"
Cohesion: 0.16
Nodes (9): AVAudioFile, SpeechRecognitionService, Bool, URL, Notification, SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask, SFSpeechRecognizer (+1 more)

### Community 3 - "graphify Pipeline"
Cohesion: 0.06
Nodes (45): graphify Skill Trigger Registration, Watch Debounce Window, URL Ingest into Corpus, Watch Mode Auto-Rebuild, FalkorDB Cypher Export, graphify MCP Stdio Server, Neo4j Cypher Export, Token Reduction Benchmark (+37 more)

### Community 4 - "String"
Cohesion: 0.16
Nodes (37): Codable, Answer, AudioMetrics, Capabilities, ConfidenceBand, high, .label, low (+29 more)

### Community 5 - "ProgressScreen"
Cohesion: 0.05
Nodes (50): Content, DimensionAverage, StudyInsights, Date, Int, String, TrendPoint, .ordinal (+42 more)

### Community 6 - "MockExamScreen.swift"
Cohesion: 0.10
Nodes (30): CGPoint, CGRect, CGSize, Arrangement, FlexibleChips, .body, FlowLayout, Item (+22 more)

### Community 7 - "QuestionSet"
Cohesion: 0.08
Nodes (32): ExamSection, advanced, comparison, introduction, .label, practice, roleplay, survey (+24 more)

### Community 8 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKey, CodingKeys, afterAdjust, beforeAdjust, changed, legacyEffectiveLevel, legacyInitialLevel, legacyPreviousInitialLevel (+19 more)

### Community 9 - "PracticeViewModel"
Cohesion: 0.08
Nodes (24): AnalyzedResult, PracticeViewModel, .analyzedNumbers, .canGoNext, .canGoPrevious, .currentQuestion, .currentResult, .dailyTokenCount (+16 more)

### Community 10 - "MockExamViewModel"
Cohesion: 0.09
Nodes (25): EvaluationRetryContext, MockExamViewModel, .canResume, .canRetryEvaluation, .currentQuestion, .expectedQuestionCount, .initialLevel, .mockAvailable (+17 more)

### Community 11 - "RecordingState"
Cohesion: 0.11
Nodes (18): PermissionState, denied, granted, unknown, RecordingState, failed, idle, interrupted (+10 more)

### Community 12 - "BackgroundSurvey"
Cohesion: 0.15
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
Cohesion: 0.11
Nodes (27): Alignment, AppTypography, FeedbackSection, .body, LevelResultCard, .body, LockedFeedbackSection, .body (+19 more)

### Community 18 - "AppTelemetry"
Cohesion: 0.24
Nodes (5): AppTelemetry, Bool, Int, UUID, OSLog

### Community 19 - "OPIcLevel"
Cohesion: 0.07
Nodes (40): MockDraftRecord, .answers, .questionSet, .targetLevel, MockHistoryRecord, .answers, .evaluation, .predictedLevel (+32 more)

### Community 20 - "OnboardingView"
Cohesion: 0.18
Nodes (10): OnboardingView, .body, .guidanceText, .levelSelection, .preferences, ProgressBanner, .body, Error (+2 more)

### Community 21 - "GuideTopic"
Cohesion: 0.15
Nodes (16): GuidePage, GuideReaderView, .body, .pages, GuideTopic, exam, .icon, .id (+8 more)

### Community 22 - "Foundation"
Cohesion: 0.20
Nodes (5): JSONDecoder.DateDecodingStrategy, Foundation, Observation, RevenueCat, SwiftData

### Community 23 - "PrimaryButton"
Cohesion: 0.13
Nodes (13): ButtonStyle, Configuration, PressableButtonStyle, PrimaryButton, .body, String, Void, .body (+5 more)

### Community 24 - "SelfAssessmentLevel"
Cohesion: 0.13
Nodes (14): SelfAssessmentLevel, .estimatedRange, .expectedTargetLevel, .id, level1, level2, level3, level4 (+6 more)

### Community 25 - "AuthenticationService"
Cohesion: 0.26
Nodes (8): AuthenticationService, AuthError, appCheckUnavailable, .errorDescription, firebaseAuthUnavailable, installationIDUnavailable, Bool, String

### Community 26 - "FirebaseBootstrap"
Cohesion: 0.29
Nodes (7): FirebaseBootstrap, .buildConfiguration, .runtimeTarget, .shouldForceRefreshAppCheckToken, Bool, String, ISO8601DateFormatter

### Community 27 - "DailyOPIcTests"
Cohesion: 0.15
Nodes (5): DailyOPIc, DailyOPIcTests, Int, String, Testing

### Community 28 - "AppPreferences"
Cohesion: 0.11
Nodes (14): AppPreferences, .guideState, .hasCompletedOnboarding, .initialLevel, .isInitialLevelSyncPending, .isNewToOPIc, .lastGuidePage, .onboardingSchemaVersion (+6 more)

### Community 29 - "AppLoadingIndicator"
Cohesion: 0.22
Nodes (7): AILoadingOverlay, .body, Bool, AppLoadingIndicator, .body, CGFloat, Color

### Community 30 - ".updateLocalEntitlement"
Cohesion: 0.17
Nodes (8): CustomerInfo, StoreError, .errorDescription, notConfigured, purchaseCancelled, unknown, .body, LocalizedError

### Community 31 - "DailyOPIcUITests"
Cohesion: 0.14
Nodes (6): DailyOPIcUITests, DailyOPIcUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool, XCTest, XCTestCase

### Community 32 - "PaywallView"
Cohesion: 0.14
Nodes (17): .body, PaywallTier, .id, PaywallTierCard, .body, .statusLine, PaywallView, .currentPlan (+9 more)

### Community 33 - ".saveDraft"
Cohesion: 0.21
Nodes (4): AudioFileService, Int, String, URL

### Community 34 - "AppPalette"
Cohesion: 0.14
Nodes (12): AppPalette, Color, Double, AnswerPanel, .body, Bool, String, GuideTopicCard (+4 more)

### Community 35 - ".application"
Cohesion: 0.29
Nodes (6): Any, AppDelegate, Bool, NSObject, UIApplication, UIApplicationDelegate

### Community 36 - "PromptPlaybackService"
Cohesion: 0.17
Nodes (8): AVSpeechSynthesizer, AVSpeechSynthesizerDelegate, AVSpeechUtterance, PromptPlaybackService, Int, Set, String, ObservableObject

### Community 37 - "PlanEntitlement"
Cohesion: 0.06
Nodes (31): CaseIterable, Comparable, PlanEntitlement, basic, .displayName, free, .isPaid, .monthlyPriceKRW (+23 more)

### Community 38 - "AdService"
Cohesion: 0.20
Nodes (7): ConsentStatus, AdService, String, FormStatus, PrivacyOptionsRequirementStatus, RequestParameters, RewardedAd

### Community 39 - "AsyncOperationKind"
Cohesion: 0.22
Nodes (8): AsyncOperationKind, dataLoading, difficultyAdjustment, mockResult, questionGeneration, retry, speechAnalysis, .title

### Community 40 - "GoogleBannerView"
Cohesion: 0.38
Nodes (5): BannerView, Context, .body, GoogleBannerView, UIViewRepresentable

### Community 41 - "DifficultyAdjustment"
Cohesion: 0.22
Nodes (8): DifficultyAdjustment, easier, harder, .id, same, .subtitle, .title, QuestionSetAdjustmentRequest

### Community 43 - "PracticeScreen"
Cohesion: 0.13
Nodes (14): Bool, PromptPlayButton, .title, Bool, String, Void, QuestionCard, RecordingButton (+6 more)

### Community 44 - "TargetLevelConfirmationDialog"
Cohesion: 0.29
Nodes (7): Bool, Void, TargetLevelConfirmationDialog, .adChange, .body, .message, .paidChange

### Community 45 - "SetupView"
Cohesion: 0.24
Nodes (8): GoalLevelRoutingDialog, .body, SetupAlert, SetupView, .appUserID, .body, String, Void

### Community 46 - "AppEnvironment"
Cohesion: 0.07
Nodes (24): App, DailyOPIcApp, .body, StorageRecoveryView, .body, String, AppEnvironment, .currentPlan (+16 more)

### Community 47 - "WeaknessTier"
Cohesion: 0.33
Nodes (6): PlanEntitlement, .weaknessTier, WeaknessTier, advanced, basic, none

### Community 48 - "AsyncOperationState"
Cohesion: 0.08
Nodes (25): AsyncOperationState, completed, idle, .isRunning, recoverableFailure, running, terminalFailure, Bool (+17 more)

### Community 49 - "AdError"
Cohesion: 0.29
Nodes (7): AdError, busy, .errorDescription, notEarned, privacyOptionsNotRequired, privacyOptionsUnavailable, unavailable

### Community 50 - "RewardedAdPresentationDelegate"
Cohesion: 0.33
Nodes (6): RewardedAdPresentationDelegate, Bool, Error, Void, FullScreenContentDelegate, FullScreenPresentingAd

### Community 51 - "SwiftUI"
Cohesion: 0.11
Nodes (14): DailyTokenBadge, .body, Int, MockResultView, .body, Void, PracticeResultView, String (+6 more)

### Community 52 - "SpeechRecognitionService.swift"
Cohesion: 0.50
Nodes (3): AVFoundation, Combine, Speech

### Community 55 - "FlowTags"
Cohesion: 0.38
Nodes (6): .body, FlowTags, .body, String, TagChip, .body

### Community 56 - "State"
Cohesion: 0.25
Nodes (7): State, failed, idle, loading, presenting, ready, verifying

### Community 57 - "PersistenceService"
Cohesion: 0.43
Nodes (3): PersistenceService, String, ModelContext

### Community 59 - "DailyRefreshDialog"
Cohesion: 0.52
Nodes (5): DailyRefreshDialog, .body, Bool, String, Void

### Community 60 - "RewardPurpose"
Cohesion: 0.29
Nodes (7): RewardPurpose, mockAdjustment, mockResult, mockStart, practiceCredits, practiceRefresh, targetLevelChange

### Community 61 - "RubricBand"
Cohesion: 0.29
Nodes (7): RubricBand, advanced, developing, foundation, functional, .label, strong

### Community 62 - "RubricDimension"
Cohesion: 0.29
Nodes (7): RubricDimension, discourse, fluency, grammar, .label, taskFulfillment, vocabulary

### Community 63 - "AuthenticationService.swift"
Cohesion: 0.33
Nodes (5): DeviceCheck, FirebaseAppCheck, FirebaseAuth, FirebaseCore, Security

### Community 64 - "ErrorBanner"
Cohesion: 0.15
Nodes (10): BannerAdView, UIViewController, UIApplication, .topViewController, ErrorBanner, .body, String, Void (+2 more)

### Community 65 - "AdService.swift"
Cohesion: 0.33
Nodes (5): AppTrackingTransparency, UIViewController, UIApplication, .topViewController, UserMessagingPlatform

### Community 67 - "MockExamScreen"
Cohesion: 0.18
Nodes (9): DifficultyAdjustmentDialog, .body, Bool, String, Void, MockExamScreen, .adjustment, .canResetExam (+1 more)

### Community 68 - "D + Microphone Lockup Brand Mark"
Cohesion: 0.60
Nodes (5): D + Microphone Lockup Brand Mark, DailyOPIc App Icon (Dark Appearance), DailyOPIc App Icon (Light Appearance), DailyOPIc App Icon (Tinted / Monochrome Appearance), iOS 18 Appearance-Variant App Icon Set

### Community 69 - "GuideState"
Cohesion: 0.40
Nodes (5): GuideState, completed, inProgress, skipped, unseen

### Community 71 - ".subscript"
Cohesion: 0.50
Nodes (3): Array, Element, Index

### Community 73 - "AppTypography.swift"
Cohesion: 0.67
Nodes (3): AppRadius, AppSpacing, CGFloat

### Community 74 - "Step"
Cohesion: 0.50
Nodes (4): Step, firstQuestion, guide, level

## Ambiguous Edges - Review These
- `Whisper Video/Audio Transcription` → `Reserved Onboarding Video Assets`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md · relation: conceptually_related_to
- `DailyOPIc iOS App` → `Reserved Onboarding Video Assets`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md · relation: conceptually_related_to

## Knowledge Gaps
- **352 isolated node(s):** `1. 브랜드 · 언어 · 출시 상태`, `2. 주 사용자와 사용 맥락 [방향]`, `3. 포지셔닝 / 대체 불가능한 지점 [방향]`, `4. 앱 구조 (현재 구현) [VERIFIED]`, `배경 설문(Survey)` (+347 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Whisper Video/Audio Transcription` and `Reserved Onboarding Video Assets`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `DailyOPIc iOS App` and `Reserved Onboarding Video Assets`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `MockExamViewModel` connect `MockExamViewModel` to `APIClient`, `SpeechRecognitionService`, `String`, `QuestionSet`, `PracticeViewModel`, `BackgroundSurvey`, `OPIcLevel`, `Foundation`, `SelfAssessmentLevel`, `AppPreferences`, `.saveDraft`, `PromptPlaybackService`, `AdService`, `AsyncOperationKind`, `.body`, `AppEnvironment`, `AsyncOperationState`, `PersistenceService`, `ErrorBanner`, `MockExamScreen`?**
  _High betweenness centrality (0.142) - this node is a cross-community bridge._
- **Why does `View` connect `View` to `ErrorBanner`, `PaywallView`, `AppPalette`, `MockExamScreen`, `ProgressScreen`, `MockExamScreen.swift`, `PracticeScreen`, `TargetLevelConfirmationDialog`, `SetupView`, `AppEnvironment`, `SwiftUI`, `OnboardingView`, `FlowTags`, `GuideTopic`, `PrimaryButton`, `DailyRefreshDialog`, `AppPreferences`, `AppLoadingIndicator`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `PracticeViewModel` connect `PracticeViewModel` to `APIClient`, `.saveDraft`, `SpeechRecognitionService`, `String`, `PromptPlaybackService`, `AdService`, `AsyncOperationKind`, `QuestionSet`, `RecordingState`, `PracticeScreen`, `AppEnvironment`, `AsyncOperationState`, `OPIcLevel`, `Foundation`, `SelfAssessmentLevel`, `PersistenceService`, `AppPreferences`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `MockExamViewModel` (e.g. with `PromptPlaybackService` and `SpeechRecognitionService`) actually correct?**
  _`MockExamViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `PracticeViewModel` (e.g. with `PromptPlaybackService` and `SpeechRecognitionService`) actually correct?**
  _`PracticeViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._