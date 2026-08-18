import Foundation
import Observation

#if canImport(RevenueCat)
import RevenueCat
#endif

/// 페이월에 표시할 구매 가능 상품(플랜/패스). RevenueCat Package를 UI에서 분리한다.
struct StorePackage: Identifiable, Sendable {
    let id: String  // RevenueCat package identifier
    let plan: PlanEntitlement
    let title: String
    let localizedPrice: String
    let isSubscription: Bool
}

enum StoreError: LocalizedError {
    case notConfigured
    case purchaseCancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "결제 모듈이 설정되지 않았습니다. 잠시 후 다시 시도해 주세요."
        case .purchaseCancelled:
            "구매가 취소되었습니다."
        case let .unknown(message):
            message
        }
    }
}

/// RevenueCat 래퍼. 서버 `/v1/capabilities` 가 엔타이틀먼트의 진실 소스이며,
/// StoreService는 (1) 구매/복원 트리거, (2) 구매 직후 즉시 UI용 플랜 힌트만 담당.
/// RevenueCat SPM 패키지가 없으면 자동으로 no-op 스텁으로 컴파일된다.
@MainActor
@Observable
final class StoreService {
    typealias AppUserIDProvider = @MainActor () -> String?

    private(set) var packages: [StorePackage] = []
    private(set) var isConfigured = false
    private(set) var isLoading = false
    /// RevenueCat SDK가 현재 사용 중인 실제 App User ID. 별도 ID를 생성하거나 저장하지 않는다.
    private(set) var appUserID: String?
    /// 구매 직후 CustomerInfo 기준 즉시 반영용 힌트(서버 반영 전 UI 잠금 해제).
    private(set) var localEntitlement: PlanEntitlement = .free
    /// CustomerInfo를 **한 번이라도** 실제로 읽었는가.
    /// 읽기 전의 기본값 `.free`를 "무료 사용자"로 단정하면 유료 사용자의 기능이
    /// 앱을 켤 때마다 잠깐 사라진다(학습 알림은 그 순간 예약까지 지워졌다).
    private(set) var hasResolvedEntitlement = false

    /// 엔타이틀먼트가 바뀌었을 수 있을 때 호출(호출부에서 서버 capabilities 재조회).
    var onEntitlementMayHaveChanged: (() async -> Void)?

    private let appUserIDProvider: AppUserIDProvider

    init() {
        appUserIDProvider = Self.currentRevenueCatAppUserID
    }

    init(appUserIDProvider: @escaping AppUserIDProvider) {
        self.appUserIDProvider = appUserIDProvider
    }

    /// 설정 화면 진입 시 SDK의 현재 식별자를 다시 읽는다. 빈 값은 사용 가능한 ID로 취급하지 않는다.
    func refreshAppUserID() {
        guard let current = appUserIDProvider(), !current.isEmpty else {
            appUserID = nil
            return
        }
        appUserID = current
    }

    private static func currentRevenueCatAppUserID() -> String? {
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return nil }
        return Purchases.shared.appUserID
        #else
        return nil
        #endif
    }

    #if canImport(RevenueCat)
    private var rcPackages: [String: Package] = [:]
    private var infoObserverTask: Task<Void, Never>?

    func configure(userId: String) {
        guard !isConfigured else { return }
        guard let apiKey = AppConfiguration.revenueCatAPIKey, !apiKey.isEmpty else {
            print("[DailyOPIc][Store] RevenueCat API key missing")
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey, appUserID: userId)
        isConfigured = true
        refreshAppUserID()
        startCustomerInfoObserver()
    }

    /// RevenueCat CustomerInfo 변경(구매·갱신·해지·만료)을 실시간으로 반영.
    private func startCustomerInfoObserver() {
        infoObserverTask?.cancel()
        infoObserverTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                let previous = self.localEntitlement
                self.updateLocalEntitlement(from: info)
                if self.localEntitlement != previous {
                    await self.onEntitlementMayHaveChanged?()
                }
            }
        }
    }

    /// 서버 캐시가 아닌 최신 상태를 강제로 다시 읽어 즉시 반영(포그라운드 복귀·페이월 진입 시).
    func refreshCustomerInfo() async {
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            updateLocalEntitlement(from: info)
        } catch {
            print("[DailyOPIc][Store] refreshCustomerInfo failed: \(error)")
        }
    }

    func refresh() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let available = offerings.current?.availablePackages ?? []
            var mapped: [StorePackage] = []
            rcPackages.removeAll()
            for package in available {
                let plan = Self.plan(for: package)
                rcPackages[package.identifier] = package
                mapped.append(
                    StorePackage(
                        id: package.identifier,
                        plan: plan,
                        title: package.storeProduct.localizedTitle,
                        localizedPrice: package.storeProduct.localizedPriceString,
                        isSubscription: package.packageType != .custom
                    )
                )
            }
            packages = mapped.sorted { $0.plan < $1.plan }
            await syncLocalEntitlement()
        } catch {
            print("[DailyOPIc][Store] offerings load failed: \(error)")
        }
    }

    func purchase(_ package: StorePackage) async throws {
        guard isConfigured, let rcPackage = rcPackages[package.id] else {
            throw StoreError.notConfigured
        }
        do {
            let result = try await Purchases.shared.purchase(package: rcPackage)
            if result.userCancelled { throw StoreError.purchaseCancelled }
            updateLocalEntitlement(from: result.customerInfo)
            await onEntitlementMayHaveChanged?()
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.unknown(error.localizedDescription)
        }
    }

    func restore() async throws {
        guard isConfigured else { throw StoreError.notConfigured }
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateLocalEntitlement(from: info)
            await onEntitlementMayHaveChanged?()
        } catch {
            throw StoreError.unknown(error.localizedDescription)
        }
    }

    /// App Store 구독 관리 시트(해지/변경)를 표시한다.
    func manageSubscriptions() async throws {
        guard isConfigured else { throw StoreError.notConfigured }
        do {
            try await Purchases.shared.showManageSubscriptions()
        } catch {
            throw StoreError.unknown(error.localizedDescription)
        }
    }

    private func syncLocalEntitlement() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateLocalEntitlement(from: info)
        } catch {
            print("[DailyOPIc][Store] customerInfo failed: \(error)")
        }
    }

    private func updateLocalEntitlement(from info: CustomerInfo) {
        localEntitlement = Self.highestPlan(from: Array(info.entitlements.active.keys))
        hasResolvedEntitlement = true
    }

    private static func plan(for package: Package) -> PlanEntitlement {
        highestPlan(from: [package.identifier, package.storeProduct.productIdentifier])
    }

    /// 식별자 토큰 → 플랜. 백엔드 `app/services/plans.py`의 엔타이틀먼트 매핑과
    /// 같은 값을 유지한다. 한쪽만 바뀌면 앱과 서버가 다른 플랜을 말하게 된다.
    private static let planByToken: [String: PlanEntitlement] = [
        "basic": .basic,
        "plus": .plus,
        "pro": .pro,
        // 과거 명칭. 지금은 발급하지 않지만 만료 전 구독자가 남아 있을 수 있어
        // 지우지 않는다(지우면 그 순간 무료로 강등된다). 새 상품에 쓰지 않는다.
        "premium": .pro,
        "exam_pass": .pro,
    ]

    /// 부분 문자열이 아니라 토큰으로 맞춘다. `contains`는 "promo_offer"를 프로로
    /// 읽는 등 한 상품이 두 플랜으로 갈릴 수 있었다.
    private static func highestPlan(from identifiers: [String]) -> PlanEntitlement {
        var best: PlanEntitlement = .free
        for raw in identifiers {
            let lower = raw.lowercased()
            // 엔타이틀먼트는 식별자 전체가 이름("exam_pass"), 상품 ID는 구분자로
            // 이어 붙인 형태("com.dailyopic.pro.monthly")라 둘 다 본다.
            let tokens = [lower] + lower
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            for token in tokens {
                if let plan = planByToken[token], plan > best { best = plan }
            }
        }
        return best
    }
    #else
    // RevenueCat 미설치: 컴파일 가능한 no-op 스텁.
    func configure(userId: String) {}
    func refresh() async {}
    func refreshCustomerInfo() async {}
    func purchase(_ package: StorePackage) async throws { throw StoreError.notConfigured }
    func restore() async throws { throw StoreError.notConfigured }
    func manageSubscriptions() async throws { throw StoreError.notConfigured }
    #endif
}
