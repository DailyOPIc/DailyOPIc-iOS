import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let onboarding = "native_onboarding_completed"
        static let targetLevel = "native_target_level"
        static let background = "native_background_profile"
        static let mockSurvey = "native_mock_background_survey"
    }

    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
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
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        targetLevel = defaults.string(forKey: Key.targetLevel).flatMap(OPIcLevel.init(rawValue:))
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

    func completeOnboarding(level: OPIcLevel, profile: BackgroundProfile) {
        targetLevel = level
        backgroundProfile = profile
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}
