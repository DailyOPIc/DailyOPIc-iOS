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

    /// 현재 유효 플랜.
    /// RevenueCat(StoreService)가 설정돼 있으면 Apple의 실제 활성 엔타이틀먼트를
    /// 그대로 따른다(업그레이드·다운그레이드·해지·만료가 즉시 반영). 미설정 시에만
    /// 서버 capabilities로 폴백한다. 서버 쿼터 강제는 여전히 서버가 권위.
    var currentPlan: PlanEntitlement {
        if store.isConfigured {
            return store.localEntitlement
        }
        return PlanEntitlement(from: capabilities?.plan)
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

    /// 앱 포그라운드 복귀 등에서 스토어·서버 엔타이틀먼트를 최신화한다.
    func refreshEntitlements() async {
        await store.refreshCustomerInfo()
        await refreshCapabilities()
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
