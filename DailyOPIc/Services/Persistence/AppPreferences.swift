import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let onboarding = "native_onboarding_completed"
        static let initialLevel = "native_initial_level"
        static let targetLevel = "native_target_level"
        static let background = "native_background_profile"
        static let mockSurvey = "native_mock_background_survey"
    }

    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }
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
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        initialLevel = storedInitialLevel
        targetLevel = storedTargetLevel ?? storedInitialLevel?.expectedTargetLevel
        if let data = defaults.data(forKey: Key.background),
           let profile = try? JSONCoding.decoder.decode(BackgroundProfile.self, from: data) {
            backgroundProfile = profile
        } else {
            backgroundProfile = BackgroundProfile()
        }
        if let data = defaults.data(forKey: Key.mockSurvey),
           let survey = try? JSONCoding.decoder.decode(BackgroundSurvey.self, from: data) {
            mockSurvey = survey
        } else {
            mockSurvey = nil
        }
    }

    func completeOnboarding(initialLevel: SelfAssessmentLevel, profile: BackgroundProfile) {
        self.initialLevel = initialLevel
        targetLevel = initialLevel.expectedTargetLevel
        backgroundProfile = profile
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}
