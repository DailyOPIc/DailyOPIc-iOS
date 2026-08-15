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
    var studyRemindersEnabled: Bool {
        didSet { defaults.set(studyRemindersEnabled, forKey: Key.studyReminders) }
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
        studyRemindersEnabled = defaults.bool(forKey: Key.studyReminders)
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
