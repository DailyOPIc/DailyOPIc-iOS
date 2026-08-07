# Graph Report - .  (2026-08-05)

## Corpus Check
- 85 files · ~101,641 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1236 nodes · 2558 edges · 75 communities
- Extraction: 89% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 268 edges (avg confidence: 0.8)
- Token cost: 125,129 input · 0 output

## Community Hubs (Navigation)
- API Client & Networking
- RevenueCat Store & Subscriptions
- Audio File & Speech Recognition
- graphify Skill Pipeline
- Evaluation Data Models
- Study Insights & Plan Gating
- Mock Exam Screen Layout
- Question & Mock Session Models
- Evaluation Coding Keys
- Practice ViewModel State
- Mock Exam ViewModel State
- Progress History Screen
- Background Survey Profile
- App Root & Launch Wiring
- JSON Value Encoding
- Firebase App Check Setup
- App Configuration & Secrets
- Evaluation Result Cards
- Async Operation Kinds
- Local Record Persistence
- Onboarding Flow View
- OPIc Guide Reader
- Shared Framework Imports
- Primary Button Style
- Self-Assessment Levels
- Authentication Service
- Firebase Bootstrap & AppDelegate
- Unit Test Suite
- App Preferences Storage
- Loading Overlay Components
- Local Record Initializers
- UI Test Suite
- Rubric Score Bars
- OPIc Level Enum
- App Color Palette
- App Entry Point
- Prompt Playback Synthesis
- Plan Entitlement Tiers
- AdMob Consent Flow
- Mock Session Stages
- Banner Ad View
- Difficulty Adjustment
- Mock Session Restore
- Prompt Playback Control
- Onboarding Screens
- Setup Screens
- App Environment State
- Practice Data Loading
- Async Operation State
- Ad Service Rewards
- Ad Service Loading
- Mock Result & History Detail
- Exam Sections
- Question Styles
- Mock Exam Phases
- Tag Chip Component
- Ad Service Internals
- Persistence Service
- Mock Exam Actions
- Daily Refresh Dialog
- Reward Purpose
- Rubric Bands
- Rubric Dimensions
- Firebase Auth & App Check
- Error Banner Component
- Ad Tracking Consent
- Progress Period Filter
- Mock Exam Adjustment UI
- App Icon Variants
- Guide State Tracking
- Launch State
- Array Safe Subscript
- Practice Phases
- App Typography & Spacing
- Onboarding Steps

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

## Communities (75 total, 0 thin omitted)

### Community 0 - "API Client & Networking"
Cohesion: 0.07
Nodes (33): async, APIClient, .rewardVerificationTimeoutMessage, APIClientError, .code, .errorDescription, invalidResponse, .isAIUnavailable (+25 more)

### Community 1 - "RevenueCat Store & Subscriptions"
Cohesion: 0.06
Nodes (34): AppUserIDProvider, CustomerInfo, StoreError, .errorDescription, notConfigured, purchaseCancelled, unknown, StorePackage (+26 more)

### Community 2 - "Audio File & Speech Recognition"
Cohesion: 0.06
Nodes (31): AVAudioFile, AudioFileService, Int, String, URL, PermissionState, denied, granted (+23 more)

### Community 3 - "graphify Skill Pipeline"
Cohesion: 0.06
Nodes (45): graphify Skill Trigger Registration, Watch Debounce Window, URL Ingest into Corpus, Watch Mode Auto-Rebuild, FalkorDB Cypher Export, graphify MCP Stdio Server, Neo4j Cypher Export, Token Reduction Benchmark (+37 more)

### Community 4 - "Evaluation Data Models"
Cohesion: 0.15
Nodes (35): Codable, Answer, AudioMetrics, Capabilities, ConfidenceBand, high, .label, low (+27 more)

### Community 5 - "Study Insights & Plan Gating"
Cohesion: 0.09
Nodes (32): Content, DimensionAverage, PlanEntitlement, .weaknessTier, StudyInsights, Date, Int, String (+24 more)

### Community 6 - "Mock Exam Screen Layout"
Cohesion: 0.10
Nodes (28): CGPoint, CGRect, CGSize, Arrangement, FlexibleChips, .body, FlowLayout, Item (+20 more)

### Community 7 - "Question & Mock Session Models"
Cohesion: 0.12
Nodes (22): GeneratedQuestion, .id, MockSession, MockSessionAdjustmentRequest, MockSessionRewardRequest, QuestionSet, .debugTopicIDs, QuestionSetStatus (+14 more)

### Community 8 - "Evaluation Coding Keys"
Cohesion: 0.07
Nodes (27): CodingKey, CodingKeys, afterAdjust, beforeAdjust, changed, legacyEffectiveLevel, legacyInitialLevel, legacyPreviousInitialLevel (+19 more)

### Community 9 - "Practice ViewModel State"
Cohesion: 0.11
Nodes (21): AnalyzedResult, PracticeViewModel, .analyzedNumbers, .canGoNext, .canGoPrevious, .currentQuestion, .currentResult, .dailyTokenCount (+13 more)

### Community 10 - "Mock Exam ViewModel State"
Cohesion: 0.09
Nodes (21): MockExamViewModel, .canResume, .canRetryEvaluation, .currentQuestion, .expectedQuestionCount, .initialLevel, .mockAvailable, .mockDailyLimit (+13 more)

### Community 11 - "Progress History Screen"
Cohesion: 0.10
Nodes (22): HistoryItem, HistoryRow, .body, Kind, mock, practice, ProgressScreen, .corruptRecordCount (+14 more)

### Community 12 - "Background Survey Profile"
Cohesion: 0.14
Nodes (14): BackgroundProfile, BackgroundSurvey, .isValid, .selectedTopicCount, SurveyOption, .id, Bool, Int (+6 more)

### Community 13 - "App Root & Launch Wiring"
Cohesion: 0.09
Nodes (16): AppRootView, .body, DailyTokenBadge, .body, Int, AuthRecoveryView, .body, String (+8 more)

### Community 14 - "JSON Value Encoding"
Cohesion: 0.10
Nodes (17): CustomStringConvertible, JSONValue, array, bool, null, number, string, RewardStatus (+9 more)

### Community 15 - "Firebase App Check Setup"
Cohesion: 0.11
Nodes (23): App Attest Attestation Provider, App Check Debug Provider for Simulator, Firestore Server-Only Access Boundary, GoogleService-Info.plist Placement, App Attest production Environment Entitlement, Reserved Onboarding Video Assets, AdMob Banner and Rewarded Unit IDs, AdMob Rewarded SSV Callback (+15 more)

### Community 16 - "App Configuration & Secrets"
Cohesion: 0.17
Nodes (18): AppConfiguration, .apiBaseURL, .apiBaseURLSource, .bannerAdUnitID, .gadTestDeviceIdentifiers, .privacyPolicyURL, .resolvedAPIBaseURL, .revenueCatAPIKey (+10 more)

### Community 17 - "Evaluation Result Cards"
Cohesion: 0.13
Nodes (21): AppTypography, FeedbackSection, .body, LevelResultCard, .body, LockedFeedbackSection, .body, ResultUnlock (+13 more)

### Community 18 - "Async Operation Kinds"
Cohesion: 0.14
Nodes (13): AsyncOperationKind, dataLoading, difficultyAdjustment, mockResult, questionGeneration, retry, speechAnalysis, .title (+5 more)

### Community 19 - "Local Record Persistence"
Cohesion: 0.12
Nodes (13): .answers, .questionSet, MockHistoryRecord, .answers, .evaluation, .predictedLevel, .questionSet, .targetLevel (+5 more)

### Community 20 - "Onboarding Flow View"
Cohesion: 0.20
Nodes (9): OnboardingView, .guidanceText, .levelSelection, .preferences, ProgressBanner, .body, Error, String (+1 more)

### Community 21 - "OPIc Guide Reader"
Cohesion: 0.15
Nodes (16): GuidePage, GuideReaderView, .body, .pages, GuideTopic, exam, .icon, .id (+8 more)

### Community 22 - "Shared Framework Imports"
Cohesion: 0.15
Nodes (7): AVFoundation, Combine, JSONDecoder.DateDecodingStrategy, Foundation, Observation, RevenueCat, Speech

### Community 23 - "Primary Button Style"
Cohesion: 0.12
Nodes (14): ButtonStyle, Configuration, PressableButtonStyle, PrimaryButton, .body, String, Void, PromptPlayButton (+6 more)

### Community 24 - "Self-Assessment Levels"
Cohesion: 0.12
Nodes (14): SelfAssessmentLevel, .estimatedRange, .expectedTargetLevel, .id, level1, level2, level3, level4 (+6 more)

### Community 25 - "Authentication Service"
Cohesion: 0.26
Nodes (8): AuthenticationService, AuthError, appCheckUnavailable, .errorDescription, firebaseAuthUnavailable, installationIDUnavailable, Bool, String

### Community 26 - "Firebase Bootstrap & AppDelegate"
Cohesion: 0.19
Nodes (10): Any, Bool, FirebaseBootstrap, .buildConfiguration, .runtimeTarget, .shouldForceRefreshAppCheckToken, Bool, String (+2 more)

### Community 27 - "Unit Test Suite"
Cohesion: 0.17
Nodes (5): DailyOPIc, DailyOPIcTests, Int, String, Testing

### Community 28 - "App Preferences Storage"
Cohesion: 0.14
Nodes (13): AppPreferences, .guideState, .hasCompletedOnboarding, .initialLevel, .isInitialLevelSyncPending, .isNewToOPIc, .lastGuidePage, .onboardingSchemaVersion (+5 more)

### Community 29 - "Loading Overlay Components"
Cohesion: 0.13
Nodes (12): AILoadingOverlay, .body, Bool, AppLoadingIndicator, .body, CGFloat, Color, DifficultyAdjustmentDialog (+4 more)

### Community 30 - "Local Record Initializers"
Cohesion: 0.22
Nodes (10): MockDraftRecord, PracticeHistoryRecord, .evaluation, .predictedLevel, .question, .targetLevel, Date, String (+2 more)

### Community 31 - "UI Test Suite"
Cohesion: 0.14
Nodes (6): DailyOPIcUITests, DailyOPIcUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool, XCTest, XCTestCase

### Community 32 - "Rubric Score Bars"
Cohesion: 0.20
Nodes (10): Alignment, RubricBandsView, .body, ScoreBars, .body, View, PracticeResultView, .body (+2 more)

### Community 33 - "OPIc Level Enum"
Cohesion: 0.14
Nodes (14): .targetLevel, OPIcLevel, AL, .description, .id, IH, IL, IM1 (+6 more)

### Community 34 - "App Color Palette"
Cohesion: 0.16
Nodes (11): AppPalette, Color, Double, AnswerPanel, .body, Bool, String, GuideTopicCard (+3 more)

### Community 35 - "App Entry Point"
Cohesion: 0.19
Nodes (11): App, AppDelegate, DailyOPIcApp, .body, StorageRecoveryView, .body, String, ModelContainer (+3 more)

### Community 36 - "Prompt Playback Synthesis"
Cohesion: 0.21
Nodes (8): AVSpeechSynthesizer, AVSpeechSynthesizerDelegate, AVSpeechUtterance, PromptPlaybackService, Int, Set, String, ObservableObject

### Community 37 - "Plan Entitlement Tiers"
Cohesion: 0.15
Nodes (12): Comparable, PlanEntitlement, basic, .displayName, free, .isPaid, .monthlyPriceKRW, plus (+4 more)

### Community 38 - "AdMob Consent Flow"
Cohesion: 0.24
Nodes (6): ConsentStatus, AdService, FormStatus, PrivacyOptionsRequirementStatus, RequestParameters, RewardedAd

### Community 39 - "Mock Session Stages"
Cohesion: 0.15
Nodes (12): MockSessionStage, answeringFront, answeringTail, awaitingAdjustmentAd, awaitingResultAd, awaitingStartAd, completed, evaluating (+4 more)

### Community 40 - "Banner Ad View"
Cohesion: 0.20
Nodes (9): BannerView, Context, .body, GoogleBannerView, UIViewController, UIApplication, .topViewController, GoogleMobileAds (+1 more)

### Community 41 - "Difficulty Adjustment"
Cohesion: 0.23
Nodes (8): DifficultyAdjustment, easier, harder, .id, same, .subtitle, .title, UUID

### Community 42 - "Mock Session Restore"
Cohesion: 0.24
Nodes (4): .body, .introduction, SavedSurveyDialog, .body

### Community 43 - "Prompt Playback Control"
Cohesion: 0.20
Nodes (6): Bool, RecordingButton, .body, Bool, Void, .answering

### Community 44 - "Onboarding Screens"
Cohesion: 0.20
Nodes (9): Bool, .body, Bool, Void, TargetLevelConfirmationDialog, .adChange, .body, .message (+1 more)

### Community 45 - "Setup Screens"
Cohesion: 0.31
Nodes (5): SetupAlert, SetupView, .appUserID, .body, String

### Community 46 - "App Environment State"
Cohesion: 0.22
Nodes (7): AppEnvironment, .currentPlan, .showsAds, Bool, PlanEntitlement, MainTabView, .body

### Community 47 - "Practice Data Loading"
Cohesion: 0.25
Nodes (4): Task, PracticeScreen, .body, .practiceBody

### Community 48 - "Async Operation State"
Cohesion: 0.20
Nodes (10): AsyncOperationState, completed, idle, .isRunning, recoverableFailure, running, terminalFailure, Bool (+2 more)

### Community 49 - "Ad Service Rewards"
Cohesion: 0.20
Nodes (8): AdError, busy, .errorDescription, notEarned, privacyOptionsNotRequired, privacyOptionsUnavailable, unavailable, String

### Community 50 - "Ad Service Loading"
Cohesion: 0.33
Nodes (6): RewardedAdPresentationDelegate, Bool, Error, Void, FullScreenContentDelegate, FullScreenPresentingAd

### Community 51 - "Mock Result & History Detail"
Cohesion: 0.22
Nodes (8): MockResultView, .body, Void, MockHistoryDetailView, .body, PracticeHistoryDetailView, .body, .records

### Community 52 - "Exam Sections"
Cohesion: 0.22
Nodes (9): ExamSection, advanced, comparison, introduction, .label, practice, roleplay, survey (+1 more)

### Community 53 - "Question Styles"
Cohesion: 0.22
Nodes (9): QuestionStyle, comparison, description, .label, opinion, pastExperience, problemSolving, roleplay (+1 more)

### Community 54 - "Mock Exam Phases"
Cohesion: 0.22
Nodes (9): Phase, adjustment, analyzing, answering, completed, introduction, loading, readyForReward (+1 more)

### Community 55 - "Tag Chip Component"
Cohesion: 0.28
Nodes (7): QuestionCard, .body, FlowTags, .body, String, TagChip, .body

### Community 56 - "Ad Service Internals"
Cohesion: 0.25
Nodes (7): State, failed, idle, loading, presenting, ready, verifying

### Community 57 - "Persistence Service"
Cohesion: 0.36
Nodes (3): PersistenceService, String, ModelContext

### Community 58 - "Mock Exam Actions"
Cohesion: 0.36
Nodes (4): EvaluationRetryContext, String, UUID, .rewardGate

### Community 59 - "Daily Refresh Dialog"
Cohesion: 0.43
Nodes (5): DailyRefreshDialog, .body, Bool, String, Void

### Community 60 - "Reward Purpose"
Cohesion: 0.29
Nodes (7): RewardPurpose, mockAdjustment, mockResult, mockStart, practiceCredits, practiceRefresh, targetLevelChange

### Community 61 - "Rubric Bands"
Cohesion: 0.29
Nodes (7): RubricBand, advanced, developing, foundation, functional, .label, strong

### Community 62 - "Rubric Dimensions"
Cohesion: 0.29
Nodes (7): RubricDimension, discourse, fluency, grammar, .label, taskFulfillment, vocabulary

### Community 63 - "Firebase Auth & App Check"
Cohesion: 0.33
Nodes (5): DeviceCheck, FirebaseAppCheck, FirebaseAuth, FirebaseCore, Security

### Community 64 - "Error Banner Component"
Cohesion: 0.29
Nodes (6): BannerAdView, ErrorBanner, .body, String, Void, .body

### Community 65 - "Ad Tracking Consent"
Cohesion: 0.33
Nodes (5): AppTrackingTransparency, UIViewController, UIApplication, .topViewController, UserMessagingPlatform

### Community 66 - "Progress Period Filter"
Cohesion: 0.33
Nodes (6): CaseIterable, Period, all, .id, seven, thirty

### Community 67 - "Mock Exam Adjustment UI"
Cohesion: 0.33
Nodes (4): MockExamScreen, .adjustment, .canResetExam, .mockUpsell

### Community 68 - "App Icon Variants"
Cohesion: 0.60
Nodes (5): D + Microphone Lockup Brand Mark, DailyOPIc App Icon (Dark Appearance), DailyOPIc App Icon (Light Appearance), DailyOPIc App Icon (Tinted / Monochrome Appearance), iOS 18 Appearance-Variant App Icon Set

### Community 69 - "Guide State Tracking"
Cohesion: 0.40
Nodes (5): GuideState, completed, inProgress, skipped, unseen

### Community 70 - "Launch State"
Cohesion: 0.40
Nodes (5): LaunchState, failed, launching, ready, String

### Community 71 - "Array Safe Subscript"
Cohesion: 0.40
Nodes (3): Array, Element, Index

### Community 72 - "Practice Phases"
Cohesion: 0.40
Nodes (5): Phase, analyzing, completed, idle, loading

### Community 73 - "App Typography & Spacing"
Cohesion: 0.67
Nodes (3): AppRadius, AppSpacing, CGFloat

### Community 74 - "Onboarding Steps"
Cohesion: 0.50
Nodes (4): Step, firstQuestion, guide, level

## Ambiguous Edges - Review These
- `Whisper Video/Audio Transcription` → `Reserved Onboarding Video Assets`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md · relation: conceptually_related_to
- `DailyOPIc iOS App` → `Reserved Onboarding Video Assets`  [AMBIGUOUS]
  DailyOPIc/Resources/Videos/README.md · relation: conceptually_related_to

## Knowledge Gaps
- **338 isolated node(s):** `.body`, `JSONDecoder.DateDecodingStrategy`, `questionGeneration`, `speechAnalysis`, `mockResult` (+333 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Whisper Video/Audio Transcription` and `Reserved Onboarding Video Assets`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `DailyOPIc iOS App` and `Reserved Onboarding Video Assets`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `View` connect `Rubric Score Bars` to `RevenueCat Store & Subscriptions`, `Study Insights & Plan Gating`, `Mock Exam Screen Layout`, `Progress History Screen`, `App Root & Launch Wiring`, `Evaluation Result Cards`, `Onboarding Flow View`, `OPIc Guide Reader`, `Primary Button Style`, `App Preferences Storage`, `Loading Overlay Components`, `App Color Palette`, `App Entry Point`, `Mock Session Restore`, `Prompt Playback Control`, `Onboarding Screens`, `Setup Screens`, `App Environment State`, `Practice Data Loading`, `Mock Result & History Detail`, `Tag Chip Component`, `Daily Refresh Dialog`, `Error Banner Component`, `Mock Exam Adjustment UI`?**
  _High betweenness centrality (0.167) - this node is a cross-community bridge._
- **Why does `PracticeViewModel` connect `Practice ViewModel State` to `API Client & Networking`, `Audio File & Speech Recognition`, `Evaluation Data Models`, `Question & Mock Session Models`, `Async Operation Kinds`, `Shared Framework Imports`, `Self-Assessment Levels`, `App Preferences Storage`, `Rubric Score Bars`, `OPIc Level Enum`, `Prompt Playback Synthesis`, `AdMob Consent Flow`, `Difficulty Adjustment`, `Prompt Playback Control`, `App Environment State`, `Practice Data Loading`, `Async Operation State`, `Persistence Service`, `Practice Phases`?**
  _High betweenness centrality (0.130) - this node is a cross-community bridge._
- **Why does `MockExamViewModel` connect `Mock Exam ViewModel State` to `API Client & Networking`, `Audio File & Speech Recognition`, `Evaluation Data Models`, `Question & Mock Session Models`, `Background Survey Profile`, `Async Operation Kinds`, `Self-Assessment Levels`, `App Preferences Storage`, `OPIc Level Enum`, `Prompt Playback Synthesis`, `AdMob Consent Flow`, `Mock Session Restore`, `Prompt Playback Control`, `App Environment State`, `Async Operation State`, `Mock Exam Phases`, `Persistence Service`, `Mock Exam Actions`, `Mock Exam Adjustment UI`, `Array Safe Subscript`?**
  _High betweenness centrality (0.126) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `MockExamViewModel` (e.g. with `PromptPlaybackService` and `SpeechRecognitionService`) actually correct?**
  _`MockExamViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `PracticeViewModel` (e.g. with `PromptPlaybackService` and `SpeechRecognitionService`) actually correct?**
  _`PracticeViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._