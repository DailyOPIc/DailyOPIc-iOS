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

    init() {
        let authentication = AuthenticationService()
        self.authentication = authentication
        preferences = AppPreferences()
        persistence = PersistenceService()
        let apiBaseURL = AppConfiguration.apiBaseURL
        api = APIClient(baseURL: apiBaseURL, authentication: authentication)
        ads = AdService()
        print("[DailyOPIc][API] baseURL=\(apiBaseURL.absoluteString) source=\(AppConfiguration.apiBaseURLSource)")
    }

    func initialize() async {
        launchState = .launching
        Task { await ads.prepare() }
        do {
            try await authentication.prepareForLaunch()
            try await Task.sleep(for: .milliseconds(450))
            launchState = .ready
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }
}
