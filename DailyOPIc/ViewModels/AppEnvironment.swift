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
    let store: StoreService
    var launchState: LaunchState = .launching
    var capabilities: Capabilities?

    /// 현재 유효 플랜. 서버 capabilities가 진실 소스이며, 구매 직후에는
    /// StoreService의 즉시 힌트(더 높은 등급일 때)로 UX 지연을 보완한다.
    var currentPlan: PlanEntitlement {
        let serverPlan = PlanEntitlement(from: capabilities?.plan)
        return max(serverPlan, store.localEntitlement)
    }

    /// 광고 노출 여부. 유료 플랜/무플랜 서버 정책을 따른다(기본 노출).
    var showsAds: Bool {
        capabilities?.quotaPolicy.adsEnabled ?? !currentPlan.isPaid
    }

    init() {
        let authentication = AuthenticationService()
        self.authentication = authentication
        preferences = AppPreferences()
        persistence = PersistenceService()
        let apiBaseURL = AppConfiguration.apiBaseURL
        api = APIClient(baseURL: apiBaseURL, authentication: authentication)
        ads = AdService()
        store = StoreService()
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
            await configureStore()
            try await Task.sleep(for: .milliseconds(450))
            launchState = .ready
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }

    /// 구매/복원 후 서버 엔타이틀먼트가 반영됐을 수 있으므로 capabilities를 재조회.
    func refreshCapabilities() async {
        capabilities = try? await api.capabilities()
    }

    private func configureStore() async {
        store.onEntitlementMayHaveChanged = { [weak self] in
            await self?.refreshCapabilities()
        }
        guard let userID = try? await authentication.currentUserID() else { return }
        store.configure(userId: userID)
        await store.refresh()
    }
}
