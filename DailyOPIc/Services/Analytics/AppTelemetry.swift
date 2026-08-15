import Foundation
import OSLog

enum AppTelemetry {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DailyOPIc",
        category: "operations"
    )

    static func operationStarted(kind: AsyncOperationKind, id: UUID) {
        logger.info("operation_started kind=\(kind.rawValue, privacy: .public) id=\(id.uuidString, privacy: .private(mask: .hash))")
    }

    static func operationCompleted(kind: AsyncOperationKind, id: UUID) {
        logger.info("operation_completed kind=\(kind.rawValue, privacy: .public) id=\(id.uuidString, privacy: .private(mask: .hash))")
    }

    static func operationFailed(kind: AsyncOperationKind, id: UUID, retryable: Bool) {
        logger.error("operation_failed kind=\(kind.rawValue, privacy: .public) id=\(id.uuidString, privacy: .private(mask: .hash)) retryable=\(retryable)")
    }

    static func onboarding(page: Int, state: AppPreferences.GuideState) {
        logger.info("onboarding page=\(page) state=\(state.rawValue, privacy: .public)")
    }

    // MARK: - 구매 퍼널
    //
    // 별도 분석 SDK를 붙이지 않는다. 이 앱에 연결된 Firebase 제품은 Core·Auth·
    // AppCheck 뿐이고 Analytics는 없다. 퍼널은 이미 쓰고 있는 OSLog 구조화 로그로
    // 남기고, 실제 매출 지표는 RevenueCat 대시보드가 이미 갖고 있다.
    //
    // 파라미터는 플랜·진입점·실패 분류(전부 고정 enum)뿐이다. 답변·전사·오디오·
    // UID는 어떤 형태로도 넣지 않는다.

    static func paywallViewed(source: PaywallSource) {
        logger.info("paywall_view source=\(source.rawValue, privacy: .public)")
    }

    static func paywallPlanSelected(plan: PlanEntitlement, source: PaywallSource) {
        logger.info("plan_selected plan=\(plan.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public)")
    }

    static func purchaseStarted(plan: PlanEntitlement, source: PaywallSource) {
        logger.info("purchase_started plan=\(plan.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public)")
    }

    static func purchaseSucceeded(plan: PlanEntitlement, source: PaywallSource) {
        logger.info("purchase_success plan=\(plan.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public)")
    }

    static func purchaseFailed(plan: PlanEntitlement, source: PaywallSource, error: Error) {
        let category = PurchaseErrorCategory(error)
        logger.info("purchase_failed plan=\(plan.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public) error_category=\(category.rawValue, privacy: .public)")
    }

    /// 잠긴 캘린더 기능을 **직접 누른** 순간만 남긴다. 화면이 그려질 때마다 남기지 않는다.
    static func calendarFeatureLockedTap(feature: CalendarLockedFeature, plan: PlanEntitlement) {
        logger.info("calendar_feature_locked_tap feature=\(feature.rawValue, privacy: .public) current_plan=\(plan.rawValue, privacy: .public)")
    }

    static func restoreStarted() {
        logger.info("restore_started")
    }

    static func restoreSucceeded(plan: PlanEntitlement) {
        logger.info("restore_success plan=\(plan.rawValue, privacy: .public)")
    }

    static func restoreFailed(error: Error?) {
        let category = error.map(PurchaseErrorCategory.init) ?? .noActiveSubscription
        logger.info("restore_failed error_category=\(category.rawValue, privacy: .public)")
    }
}

/// 구매/복원 실패의 로그용 분류. 원본 오류 메시지는 스토어·네트워크 문자열이라
/// 자유 텍스트로 남기면 스키마가 되지 않는다. 고정 집합으로만 센다.
enum PurchaseErrorCategory: String, Sendable {
    case cancelled
    case notConfigured = "not_configured"
    case noActiveSubscription = "no_active_subscription"
    case unknown

    init(_ error: Error) {
        switch error as? StoreError {
        case .purchaseCancelled: self = .cancelled
        case .notConfigured: self = .notConfigured
        default: self = .unknown
        }
    }
}
