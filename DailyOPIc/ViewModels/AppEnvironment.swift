import Foundation
import Observation
import UserNotifications
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

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
    /// 학습 알림. 권한은 사용자가 캘린더에서 직접 켤 때만 요청한다(여기서는 아무것도 하지 않는다).
    let studyReminders: StudyReminderService
    /// 앱 스토어 리뷰 요청. 학습 결과가 성공적으로 나온 순간에만 호출된다.
    let appReview: AppReviewCoordinator
    var launchState: LaunchState = .launching
    var capabilities: Capabilities?

    /// 진행 중인 학습 세션은 루트 뷰 계층보다 오래 살아야 한다(DESIGN.md §5.1 R2).
    /// 가이드·목표등급 재선택은 AppRootView의 분기를 바꿔 MainTabView를 통째로
    /// 걷어내므로, ViewModel을 MainTabView의 @State가 아니라 여기서 소유한다.
    ///
    /// lazy인 이유: 두 ViewModel은 SpeechRecognitionService(AVAudioEngine,
    /// 오디오 세션 인터럽션 옵저버)와 PromptPlaybackService를 함께 만든다.
    /// 지금처럼 탭에 처음 도달할 때 만들어야 온보딩만 하고 나가는 사용자에게
    /// 불필요한 오디오 자원을 잡지 않는다. 생성 시점은 그대로 두고 수명만 늘린다.
    @ObservationIgnored private(set) lazy var practiceViewModel = PracticeViewModel(environment: self)
    @ObservationIgnored private(set) lazy var mockViewModel = MockExamViewModel(environment: self)
    /// 캘린더도 탭을 떠나도 살아 있어야 서버 설정을 매번 다시 받지 않는다.
    /// 오디오 자원을 잡지 않으므로 생성 비용은 사실상 없다.
    @ObservationIgnored private(set) lazy var studyCalendarViewModel = StudyCalendarViewModel(environment: self)

    /// 현재 유효 플랜 = App Store 구독(RevenueCat)과 서버 플랜 중 높은 쪽.
    ///
    /// RevenueCat은 구매 · 업그레이드를 서버 웹훅보다 먼저 알고, 서버 플랜은 웹에서 산
    /// 30일 이용권(토스)까지 합친 값이다. 앱 구독만 보면 웹 이용권 구매자가 앱에서 무료로
    /// 보이고, 서버만 보면 방금 결제한 사용자가 웹훅이 올 때까지 무료로 보인다.
    /// 서버 쿼터 강제는 여전히 서버가 권위.
    /// ponytail: 웹 이용권만 있는 프로 사용자에게도 설정의 "구독 관리"(Apple 화면)가 보인다.
    ///           웹 이용권 사용자가 늘면 플랜 출처를 capabilities로 받아 버튼을 나눈다.
    var currentPlan: PlanEntitlement {
        Self.effectivePlan(
            storePlan: store.isConfigured ? store.localEntitlement : nil,
            serverPlan: capabilities?.plan
        )
    }

    nonisolated static func effectivePlan(storePlan: PlanEntitlement?, serverPlan: String?) -> PlanEntitlement {
        let server = PlanEntitlement(from: serverPlan)
        guard let storePlan else { return server }
        return max(storePlan, server)
    }

    /// 플랜을 **실제로 확인했는가**. `currentPlan`은 확인 전에도 기본값 `.free`를 말하므로
    /// "무료다"와 "아직 모른다"를 이 값으로 구분한다.
    ///
    /// 앱이 켜지는 순간 `scenePhase == .active` 재조정은 `initialize()`(인증 → capabilities →
    /// RevenueCat 설정)와 나란히 달린다. 그때 무료로 단정하면 유료 사용자의 학습 알림이
    /// 강등으로 처리돼 예약이 전부 지워졌다(P7 근본 원인).
    var isEntitlementResolved: Bool {
        if store.isConfigured, store.hasResolvedEntitlement { return true }
        return capabilities != nil
    }

    /// 광고 노출 여부. 유료 플랜/무플랜 서버 정책을 따른다(기본 노출).
    var showsAds: Bool {
        capabilities?.quotaPolicy.adsEnabled ?? !currentPlan.isPaid
    }

    init() {
        let authentication = AuthenticationService()
        self.authentication = authentication
        let preferences = AppPreferences()
        self.preferences = preferences
        let persistence = PersistenceService()
        self.persistence = persistence
        studyReminders = StudyReminderService(preferences: preferences)
        // 리뷰 자격의 근거는 캘린더가 쓰는 완료 원장 그대로다(세트당 한 줄, 분석 성공 시에만).
        appReview = AppReviewCoordinator(preferences: preferences) {
            (try? persistence.studySetCompletionDates()) ?? []
        }
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
        do {
            try AppConfiguration.validateForLaunch()
            // 화면(웹앱)에 필요한 건 계정 ID뿐이다. 익명 로그인까지만 기다리고 바로 띄운다.
            // App Check · 플랜 · 결제 준비는 화면이 뜬 뒤 이어서 한다(웹은 요청할 때 토큰을 받아 간다).
            // 익명 로그인이 응답 없이 멈추면(네트워크 · App Check) 흰 화면에 갇힌다. 20초 뒤엔 다시 시도 화면을 띄운다.
            _ = try await Self.withTimeout(seconds: 20) { [authentication] in try await authentication.currentUserID() }
            launchState = .ready
            // 이전 버전(네이티브 플래너)이 최대 30일 치 미리 예약해 둔 학습 알림을 지운다.
            // 새 화면에는 플래너가 없어 알림을 눌러도 갈 곳이 없다.
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        } catch {
            launchState = .failed(error.localizedDescription)
            return
        }
        capabilities = try? await api.capabilities()
        await configureStore()
        // 광고(무료 플랜의 배너 · 보상형 광고). 동의(UMP) · 추적 권한 확인 후 AdMob 시작.
        await ads.prepare()
    }

    struct LaunchTimeout: LocalizedError {
        var errorDescription: String? { "연결이 오래 걸리고 있어요. 네트워크를 확인하고 다시 시도해 주세요." }
    }

    /// 작업이 seconds 안에 끝나지 않으면 LaunchTimeout을 던진다. Firebase 콜백은 취소되지 않아서
    /// TaskGroup으로 묶으면 끝날 때까지 기다리게 된다. 그래서 먼저 끝난 쪽 하나만 이어 준다.
    nonisolated static func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task {
                do { once.resume(.success(try await work())) } catch { once.resume(.failure(error)) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(.failure(LaunchTimeout()))
            }
        }
    }

    private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
        func resume(_ result: Result<T, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
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

    /// 로그인 수단 연결 후 기존 계정으로 옮겼거나 계정을 지웠을 때: 새 uid 기준으로
    /// RevenueCat 사용자와 서버 플랜을 다시 읽는다.
    /// ponytail: 이미 불러온 오늘의 세트·모의고사 ViewModel은 이전 uid 것을 그대로 들고 있다.
    ///           전환이 드문 경로라 다음 앱 실행에서 맞춰진다. 바로 맞춰야 하면 ViewModel 재생성.
    /// `transferPurchases`: 이미 있는 계정으로 전환했을 때 이 기기의 구독을 그 계정으로 옮긴다.
    func accountDidChange(transferPurchases: Bool = false) async {
        guard let userID = try? await authentication.currentUserID() else { return }
        await store.logIn(userId: userID)
        if transferPurchases { await store.syncPurchases() }
        await refreshCapabilities()
    }

    /// 계정 삭제: (Apple 연결 시 토큰 폐기) → 서버 데이터·Firebase 사용자 삭제 → 기기 기록 삭제 → 새 익명 계정.
    /// 구독은 Apple이 관리하므로 여기서 해지되지 않는다(화면에서 안내).
    func deleteAccount(appleAuthorizationCode: String?) async throws {
        #if canImport(FirebaseAuth)
        if let appleAuthorizationCode {
            try await authentication.revokeAppleToken(authorizationCode: appleAuthorizationCode)
        }
        try await api.deleteAccount()
        try? persistence.deleteAllHistory()
        try await authentication.signOutAfterDeletion()
        await accountDidChange()
        #endif
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
