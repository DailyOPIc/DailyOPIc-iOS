import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    enum LaunchState {
        case launching
        case ready
        case failed(String)
    }

    let preferences: AppPreferences
    let persistence: PersistenceService
    let authentication: AuthenticationService
    let api: APIClient
    let ads: AdService
    var launchState: LaunchState = .launching
    var capabilities: Capabilities?

    init() {
        let authentication = AuthenticationService()
        self.authentication = authentication
        preferences = AppPreferences()
        persistence = PersistenceService()
        let apiBaseURL = AppConfiguration.apiBaseURL
        api = APIClient(baseURL: apiBaseURL, authentication: authentication)
        ads = AdService()
        print("[DailyOPIc][API] baseURL=\(apiBaseURL.absoluteString) source=\(AppConfiguration.apiBaseURLSource)")
        print("[DailyOPIc][Privacy] privacyPolicyURL=\(AppConfiguration.privacyPolicyURL?.absoluteString ?? "missing")")
        print(
            "[DailyOPIc][Ads] bannerAdUnitID=\(AppConfiguration.bannerAdUnitID ?? "missing") "
            + "rewardedAdUnitID=\(AppConfiguration.rewardedAdUnitID ?? "missing")"
        )
    }

    func initialize() async {
        launchState = .launching
        if ProcessInfo.processInfo.arguments.contains("-uiTestingNewUser") {
            launchState = .ready
            return
        }
        Task { await ads.prepare() }
        do {
            try AppConfiguration.validateForLaunch()
            try await authentication.prepareForLaunch()
            capabilities = try await api.capabilities()
            try await Task.sleep(for: .milliseconds(450))
            launchState = .ready
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }
}
