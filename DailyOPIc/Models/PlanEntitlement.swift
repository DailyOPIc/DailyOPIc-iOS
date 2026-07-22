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

    /// 월 구독가(원). 무료는 0.
    var monthlyPriceKRW: Int {
        switch self {
        case .free: 0
        case .basic: 2_900
        case .plus: 4_900
        case .pro: 7_900
        }
    }

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
