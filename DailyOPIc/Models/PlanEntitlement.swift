import Foundation

/// 구독 플랜(엔타이틀먼트). 서버 `/v1/capabilities` 의 `plan` 문자열과 1:1.
/// 게이팅의 최종 판단은 항상 서버(capabilities)이며, 클라이언트는 표시/UX용.
enum PlanEntitlement: String, Codable, Sendable, CaseIterable, Comparable {
    case free
    case basic
    case plus
    case pro

    init(from raw: String?) {
        self = PlanEntitlement(rawValue: (raw ?? "free").lowercased()) ?? .free
    }

    var isPaid: Bool { self != .free }

    /// 마케팅 표기명.
    var displayName: String {
        switch self {
        case .free: "무료"
        case .basic: "베이직"
        case .plus: "플러스"
        case .pro: "프로"
        }
    }

    // 가격 상수는 두지 않는다. 표시 가격은 언제나
    // `package.storeProduct.localizedPriceString`(StoreService)에서만 온다.
    // 앱에 원화 상수를 함께 두면 스토어 가격이 바뀌는 순간 둘 중 하나가 거짓말이 된다.

    private var rank: Int {
        switch self {
        case .free: 0
        case .basic: 1
        case .plus: 2
        case .pro: 3
        }
    }

    static func < (lhs: PlanEntitlement, rhs: PlanEntitlement) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// 설정 화면의 "구독" 칸이 보여줄 것. 화면이 플랜별 분기를 직접 쓰지 않도록 값으로 뽑는다.
///
/// 가격은 담지 않는다 — 표시 가격은 언제나 스토어에서 온다.
/// 아직 확인되지 않은 엔타이틀먼트를 "무료"로 적지 않는 것이 이 타입의 존재 이유다(P7).
struct SubscriptionSettingsState: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        /// 아직 확인 중이라 누를 것이 없다.
        case none
        /// 기존 Paywall을 연다(무료 업그레이드 / 상위 플랜 보기 동일 경로).
        case paywall
        /// 시스템 구독 관리 화면.
        case manage
    }

    let planText: String
    let actionTitle: String?
    let action: Action

    var isResolved: Bool { action != .none }

    static func make(
        plan: PlanEntitlement,
        isEntitlementResolved: Bool
    ) -> SubscriptionSettingsState {
        guard isEntitlementResolved else {
            // 앱이 막 켜졌을 때 currentPlan은 기본값 무료를 말한다. 그것을 적으면
            // 결제한 사용자가 설정에서 "무료"를 본다.
            return SubscriptionSettingsState(
                planText: "구독 정보를 확인하는 중이에요",
                actionTitle: nil,
                action: .none
            )
        }
        let planText = "현재 플랜 \(plan.displayName)"
        return switch plan {
        case .free:
            SubscriptionSettingsState(
                planText: planText,
                actionTitle: "프리미엄으로 업그레이드",
                action: .paywall
            )
        case .basic, .plus:
            SubscriptionSettingsState(
                planText: planText,
                actionTitle: "더 높은 플랜 보기",
                action: .paywall
            )
        case .pro:
            // 최상위 플랜에게 업그레이드를 권하지 않는다. 팔 것이 없다.
            SubscriptionSettingsState(
                planText: planText,
                actionTitle: "구독 관리",
                action: .manage
            )
        }
    }
}
