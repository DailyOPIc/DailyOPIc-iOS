import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let onboarding = "native_onboarding_completed"
        static let targetLevel = "native_target_level"
        static let background = "native_background_profile"
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
