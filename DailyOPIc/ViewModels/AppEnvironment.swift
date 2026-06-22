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
        api = APIClient(authentication: authentication)
        ads = AdService()
    }

    func initialize() async {
        launchState = .launching
        Task { await ads.prepare() }
        do {
            _ = try await authentication.headers()
            try await Task.sleep(for: .milliseconds(450))
            launchState = .ready
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }
}
