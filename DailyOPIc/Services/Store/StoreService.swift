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
    private(set) var packages: [StorePackage] = []
    private(set) var isConfigured = false
    private(set) var isLoading = false
    /// 구매 직후 CustomerInfo 기준 즉시 반영용 힌트(서버 반영 전 UI 잠금 해제).
    private(set) var localEntitlement: PlanEntitlement = .free

    /// 엔타이틀먼트가 바뀌었을 수 있을 때 호출(호출부에서 서버 capabilities 재조회).
    var onEntitlementMayHaveChanged: (() async -> Void)?

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
    }

    private static func plan(for package: Package) -> PlanEntitlement {
        highestPlan(from: [package.identifier, package.storeProduct.productIdentifier])
    }

    private static func highestPlan(from identifiers: [String]) -> PlanEntitlement {
        var best: PlanEntitlement = .free
        for raw in identifiers {
            let lower = raw.lowercased()
            for candidate in PlanEntitlement.allCases where candidate != .free {
                if lower.contains(candidate.rawValue), candidate > best {
                    best = candidate
                }
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
