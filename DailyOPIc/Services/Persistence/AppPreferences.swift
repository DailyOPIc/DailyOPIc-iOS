import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    enum GuideState: String, Codable, Sendable {
        case unseen
        case inProgress
        case skipped
        case completed
    }

    private enum Key {
        static let onboarding = "native_onboarding_completed"
        static let initialLevel = "native_initial_level"
        static let targetLevel = "native_target_level"
        static let background = "native_background_profile"
        static let mockSurvey = "native_mock_background_survey"
        static let onboardingSchemaVersion = "native_onboarding_schema_version"
        static let firstOPIcAnswer = "native_first_opic_answer"
        static let guideState = "native_guide_state"
        static let guidePage = "native_guide_page"
        static let initialLevelSyncPending = "native_initial_level_sync_pending"
        static let studyPlan = "native_study_plan"
        static let studyReminders = "native_study_reminders_enabled"
        static let studyReminderPreference = "native_study_reminder_preference"
        static let reviewRequestAttempt = "native_review_request_attempted_at"
        static let vocabularyDailySet = "native_vocabulary_daily_set"
        static let pendingVocabularyCoach = "native_vocabulary_coach_pending"
        static let pendingVocabularyExtra = "native_vocabulary_extra_pending"
    }

    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }
    var onboardingSchemaVersion: Int {
        didSet { defaults.set(onboardingSchemaVersion, forKey: Key.onboardingSchemaVersion) }
    }
    var isNewToOPIc: Bool? {
        didSet {
            if let isNewToOPIc { defaults.set(isNewToOPIc, forKey: Key.firstOPIcAnswer) }
            else { defaults.removeObject(forKey: Key.firstOPIcAnswer) }
        }
    }
    var guideState: GuideState {
        didSet { defaults.set(guideState.rawValue, forKey: Key.guideState) }
    }
    var lastGuidePage: Int {
        didSet { defaults.set(lastGuidePage, forKey: Key.guidePage) }
    }
    var isInitialLevelSyncPending: Bool {
        didSet { defaults.set(isInitialLevelSyncPending, forKey: Key.initialLevelSyncPending) }
    }
    /// 아래 두 값만 저장되지 않는 화면 표시 상태다. 각각 MainTabView 위에 덮이는
    /// 난이도 재선택/도움말을 가리킨다(루트 교체가 아니다). 두 값이 동시에 켜지는
    /// 경로는 없다.
    var isPresentingLevelSelection = false
    var isPresentingGuide = false
    var initialLevel: SelfAssessmentLevel? {
        didSet { defaults.set(initialLevel?.rawValue, forKey: Key.initialLevel) }
    }
    var targetLevel: OPIcLevel? {
        didSet { defaults.set(targetLevel?.rawValue, forKey: Key.targetLevel) }
    }
    var backgroundProfile: BackgroundProfile {
        didSet {
            if let data = try? JSONCoding.encoder.encode(backgroundProfile) {
                defaults.set(data, forKey: Key.background)
            }
        }
    }
    /// 서버에 저장된 학습 계획의 로컬 사본. 진실은 서버지만, 캘린더가 네트워크
    /// 실패 하나로 빈 화면이 되지 않도록 마지막으로 성공한 설정을 들고 있는다.
    var studyPlanSettings: StudyPlanSettings? {
        didSet {
            if let studyPlanSettings,
               let data = try? JSONCoding.encoder.encode(studyPlanSettings) {
                defaults.set(data, forKey: Key.studyPlan)
            } else {
                defaults.removeObject(forKey: Key.studyPlan)
            }
        }
    }
    /// 이 기기에서 학습 알림을 받고 싶은지에 대한 **사용자 의도**.
    /// 실제 발송 권한은 언제나 OS이고, 서버로 보내지 않는다(기기별 설정이다).
    /// 학습 알림 의도. `unspecified`는 "사용자가 아직 고른 적 없음"이고, 이때는 켜진 것으로 본다(P9).
    /// Bool 하나로는 "끈 적 없음"과 "직접 껐음"을 구분할 수 없어 기본 ON이 사용자의
    /// 명시적 OFF를 덮어쓰게 된다.
    var studyReminderPreference: StudyReminderPreference {
        didSet { defaults.set(studyReminderPreference.rawValue, forKey: Key.studyReminderPreference) }
    }
    /// 앱 스토어 리뷰를 마지막으로 **요청한** 시각. 창이 실제로 떴는지는 알 수 없으므로
    /// 시도 시각만 남긴다. 기기별 쿨다운이라 서버로 보내지 않는다.
    var lastReviewRequestAttemptAt: Date? {
        didSet {
            if let lastReviewRequestAttemptAt {
                defaults.set(lastReviewRequestAttemptAt, forKey: Key.reviewRequestAttempt)
            } else {
                defaults.removeObject(forKey: Key.reviewRequestAttempt)
            }
        }
    }
    /// 오늘 배정된 단어장 새 단어(P14). 하루에 한 번만 정해지고, 같은 로컬 날짜
    /// 안에서는 앱을 다시 열어도 바뀌지 않는다.
    ///
    /// SwiftData가 아니라 여기 두는 이유: 하루에 값 **하나**뿐이고 조회 조건이 없다.
    /// 항목별 상태(저장·성공/실패·복습 시각)는 개수가 늘고 목록으로 훑어야 해서
    /// `VocabularyStateRecord`(SwiftData)에 남긴다.
    var vocabularyDailySet: VocabularyDailySet? {
        didSet {
            if let vocabularyDailySet,
               let data = try? JSONCoding.encoder.encode(vocabularyDailySet) {
                defaults.set(data, forKey: Key.vocabularyDailySet)
            } else {
                defaults.removeObject(forKey: Key.vocabularyDailySet)
            }
        }
    }

    /// 시작했지만 아직 결과를 저장하지 못한 AI 말하기 코칭 조작(P14.3.1).
    /// 요청을 보내기 **전에** 여기 남겨야 앱이 도중에 죽어도 같은 키로 재시도해
    /// 이미 값을 치른 결과를 되찾을 수 있다. 한 번에 하나뿐이라 목록이 아니다.
    var pendingVocabularyCoach: PendingVocabularyCoachOperation? {
        didSet {
            if let pendingVocabularyCoach,
               let data = try? JSONCoding.encoder.encode(pendingVocabularyCoach) {
                defaults.set(data, forKey: Key.pendingVocabularyCoach)
            } else {
                defaults.removeObject(forKey: Key.pendingVocabularyCoach)
            }
        }
    }

    /// 시작했지만 아직 저장하지 못한 추가 20개 생성 조작(P14.6). 코칭과 같은 이유로
    /// 요청을 보내기 **전에** 남긴다 — 앱이 도중에 죽어도 같은 키로 재시도해서
    /// 이미 값을 치른 세트를 되찾는다.
    var pendingVocabularyExtra: PendingVocabularyExtraOperation? {
        didSet {
            if let pendingVocabularyExtra,
               let data = try? JSONCoding.encoder.encode(pendingVocabularyExtra) {
                defaults.set(data, forKey: Key.pendingVocabularyExtra)
            } else {
                defaults.removeObject(forKey: Key.pendingVocabularyExtra)
            }
        }
    }

    var mockSurvey: BackgroundSurvey? {
        didSet {
            if let mockSurvey,
               let data = try? JSONCoding.encoder.encode(mockSurvey) {
                defaults.set(data, forKey: Key.mockSurvey)
            } else {
                defaults.removeObject(forKey: Key.mockSurvey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTargetLevel = defaults.string(forKey: Key.targetLevel).flatMap(OPIcLevel.init(rawValue:))
        let storedInitialLevel: SelfAssessmentLevel?
        if let rawInitial = defaults.object(forKey: Key.initialLevel) as? Int {
            storedInitialLevel = SelfAssessmentLevel(rawValue: rawInitial)
        } else {
            storedInitialLevel = SelfAssessmentLevel.from(targetLevel: storedTargetLevel)
        }
        let wasCompleted = defaults.bool(forKey: Key.onboarding)
        hasCompletedOnboarding = wasCompleted
        let storedSchema = defaults.integer(forKey: Key.onboardingSchemaVersion)
        onboardingSchemaVersion = wasCompleted ? max(2, storedSchema) : storedSchema
        isNewToOPIc = defaults.object(forKey: Key.firstOPIcAnswer) as? Bool
        if let raw = defaults.string(forKey: Key.guideState),
           let value = GuideState(rawValue: raw) {
            guideState = value
        } else {
            guideState = wasCompleted ? .skipped : .unseen
        }
        lastGuidePage = min(6, max(0, defaults.integer(forKey: Key.guidePage)))
        isInitialLevelSyncPending = defaults.bool(forKey: Key.initialLevelSyncPending)
        // 구버전 Bool → 3상태 이관. 저장된 `false`는 "직접 껐다"의 증거가 아니다:
        // P4의 무료 강등 회수 경로가 사용자 동의 없이 false를 써 넣었다. 그래서
        // true만 명시적 ON으로 올리고 나머지는 "고른 적 없음"으로 둔다.
        if let raw = defaults.string(forKey: Key.studyReminderPreference),
           let stored = StudyReminderPreference(rawValue: raw) {
            studyReminderPreference = stored
        } else {
            studyReminderPreference = defaults.bool(forKey: Key.studyReminders) ? .enabled : .unspecified
        }
        lastReviewRequestAttemptAt = defaults.object(forKey: Key.reviewRequestAttempt) as? Date
        initialLevel = storedInitialLevel
        targetLevel = storedTargetLevel ?? storedInitialLevel?.expectedTargetLevel
        if let data = defaults.data(forKey: Key.background),
           let profile = try? JSONCoding.decoder.decode(BackgroundProfile.self, from: data) {
            backgroundProfile = profile
        } else {
            backgroundProfile = BackgroundProfile()
        }
        if let data = defaults.data(forKey: Key.studyPlan) {
            studyPlanSettings = try? JSONCoding.decoder.decode(StudyPlanSettings.self, from: data)
        } else {
            studyPlanSettings = nil
        }
        if let data = defaults.data(forKey: Key.mockSurvey),
           let survey = try? JSONCoding.decoder.decode(BackgroundSurvey.self, from: data) {
            mockSurvey = survey
        } else {
            mockSurvey = nil
        }
        if let data = defaults.data(forKey: Key.vocabularyDailySet) {
            vocabularyDailySet = try? JSONCoding.decoder.decode(VocabularyDailySet.self, from: data)
        } else {
            vocabularyDailySet = nil
        }
        if let data = defaults.data(forKey: Key.pendingVocabularyCoach) {
            pendingVocabularyCoach = try? JSONCoding.decoder.decode(
                PendingVocabularyCoachOperation.self,
                from: data
            )
        } else {
            pendingVocabularyCoach = nil
        }
        if let data = defaults.data(forKey: Key.pendingVocabularyExtra) {
            pendingVocabularyExtra = try? JSONCoding.decoder.decode(
                PendingVocabularyExtraOperation.self,
                from: data
            )
        } else {
            pendingVocabularyExtra = nil
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestingNewUser") {
            hasCompletedOnboarding = false
            onboardingSchemaVersion = 0
            isNewToOPIc = nil
            guideState = .unseen
            lastGuidePage = 0
            isPresentingGuide = false
            isPresentingLevelSelection = false
        }
    }

    func completeOnboarding(initialLevel: SelfAssessmentLevel, profile: BackgroundProfile) {
        self.initialLevel = initialLevel
        targetLevel = initialLevel.expectedTargetLevel
        backgroundProfile = profile
        hasCompletedOnboarding = true
        onboardingSchemaVersion = 2
        isInitialLevelSyncPending = false
    }

    func resetOnboarding() {
        isPresentingLevelSelection = true
    }

    func beginGuide() {
        isPresentingGuide = true
        if guideState == .unseen { guideState = .inProgress }
    }

    func finishGuide(skipped: Bool) {
        guideState = skipped ? .skipped : .completed
        isPresentingGuide = false
    }
}
