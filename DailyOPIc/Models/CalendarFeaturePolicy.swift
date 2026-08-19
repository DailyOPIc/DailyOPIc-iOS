import Foundation

/// 플래너의 유료 기능을 쓸 수 있는지 여부. 플래너(캘린더) 자체는 어떤 플랜에서도 잠기지 않는다.
///
/// 플랜 이름 비교(`plan == .plus`)를 planner와 화면 여기저기에 흩지 않기 위해,
/// "이 사용자가 무엇을 할 수 있는가"는 이 타입 한 곳에서만 결정한다.
struct CalendarFeaturePolicy: Equatable, Sendable {
    /// 놓친/추가 학습을 앞으로의 일정에 반영해 하루 배정량을 다시 계산한다.
    let canAutoReplan: Bool
    /// 최근 평가 등급을 권장 총 학습량에 반영한다.
    let canUseRecentEvaluation: Bool
    /// 시험일까지 남은 학습일에 남은 학습량을 다시 나눈다.
    let canBackplanToExam: Bool
    /// 개인 일정 알림(로컬 알림). 유료 기능이라 무료는 잠긴다.
    /// 자동화 깊이와 달리 유료 플랜 사이에는 차이가 없다 — 무료 vs 유료 하나뿐이다.
    ///
    /// **매일 학습 알림은 여기 없다.** P9부터 전 플랜이 쓰므로 게이트 자체가 사라졌다 —
    /// 값을 남겨 두면 언젠가 누군가 그 값으로 다시 잠근다.
    let canUseEventReminder: Bool

    static let free = CalendarFeaturePolicy(
        canAutoReplan: false,
        canUseRecentEvaluation: false,
        canBackplanToExam: false,
        canUseEventReminder: false
    )
    static let everything = CalendarFeaturePolicy(
        canAutoReplan: true,
        canUseRecentEvaluation: true,
        canBackplanToExam: true,
        canUseEventReminder: true
    )

    /// 진실은 서버 capabilities다. 다만 방금 결제한 직후에는 로컬 엔타이틀먼트가 서버
    /// 스냅샷보다 앞서 가므로, 서버가 **같은 플랜**을 말할 때만 서버 값을 쓴다.
    /// 그 외(스냅샷 없음·오래된 서버·플랜 불일치)에는 플랜 폴백 표를 쓴다.
    static func resolve(capabilities: Capabilities?, plan: PlanEntitlement) -> CalendarFeaturePolicy {
        let fallback = fallback(for: plan)
        guard let quota = capabilities?.quotaPolicy,
              PlanEntitlement(from: capabilities?.plan) == plan,
              let autoReplan = quota.calendarAutoReplan
        else { return fallback }
        return CalendarFeaturePolicy(
            canAutoReplan: autoReplan,
            canUseRecentEvaluation: quota.calendarEvaluationAdaptive ?? false,
            canBackplanToExam: quota.calendarExamBackplan ?? false,
            // 일정 알림 필드를 모르는 구 서버일 수 있다. 이때 false로 두면 베이직
            // 사용자가 산 기능을 잃으므로 플랜 폴백 값을 쓴다.
            canUseEventReminder: quota.calendarEventReminder ?? fallback.canUseEventReminder
        )
    }

    /// 서버 값을 못 쓸 때의 **유일한** 폴백 표. 여기 말고 다른 곳에서 플랜을 보고
    /// 기능을 정하지 않는다.
    static func fallback(for plan: PlanEntitlement) -> CalendarFeaturePolicy {
        switch plan {
        case .free: .free
        case .basic: CalendarFeaturePolicy(
            canAutoReplan: true,
            canUseRecentEvaluation: false,
            canBackplanToExam: false,
            canUseEventReminder: true
        )
        case .plus, .pro: .everything
        }
    }
}

/// 잠긴 캘린더 기능. 화면 문구·접근성 라벨·분석 이벤트·필요 플랜이 전부 여기서 나온다.
/// 구현이 있는 기능만 넣는다(취약점 기반 일정은 G8이라 없다).
enum CalendarLockedFeature: String, CaseIterable, Identifiable, Sendable {
    case autoReplan = "auto_replan"
    case evaluationAdaptive = "evaluation_adaptive"
    case examBackplan = "exam_backplan"
    case eventReminder = "event_reminder"

    /// "학습 플랜 기능" 카드에 모아 보여주는 자동화 3종.
    /// 개인 일정 알림은 일정 편집 화면의 자기 자리에서 잠기므로 여기 목록에 넣지 않는다 —
    /// 넣으면 무료 사용자에게 같은 기능이 두 번 보인다.
    static let automationCases: [CalendarLockedFeature] = [
        .autoReplan, .evaluationAdaptive, .examBackplan
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoReplan: "자동 일정 재조정"
        case .evaluationAdaptive: "최근 평가를 반영한 학습 계획"
        case .examBackplan: "시험일까지 역산한 일정"
        case .eventReminder: "일정 알림"
        }
    }

    var detail: String {
        switch self {
        case .autoReplan: "놓친 학습과 추가 학습을 앞으로의 일정에 다시 나눠요."
        case .evaluationAdaptive: "최근 분석 등급으로 권장 학습량을 다시 계산해요."
        case .examBackplan: "시험 전까지 남은 학습일에 학습량을 다시 나눠요."
        case .eventReminder: "개인 일정 시작 전에 한 번 알려드려요."
        }
    }

    var requiredPlan: PlanEntitlement {
        switch self {
        case .autoReplan, .eventReminder: .basic
        case .evaluationAdaptive, .examBackplan: .plus
        }
    }

    /// "베이직부터" / "플러스부터".
    var requirementText: String { "\(requiredPlan.displayName)부터" }

    /// 자물쇠 아이콘과 색에만 기대지 않기 위한 VoiceOver 라벨.
    var accessibilityLabel: String { "\(title), 잠김, \(requirementText) 이용 가능" }

    func isLocked(under policy: CalendarFeaturePolicy) -> Bool {
        switch self {
        case .autoReplan: !policy.canAutoReplan
        case .evaluationAdaptive: !policy.canUseRecentEvaluation
        case .examBackplan: !policy.canBackplanToExam
        case .eventReminder: !policy.canUseEventReminder
        }
    }
}
