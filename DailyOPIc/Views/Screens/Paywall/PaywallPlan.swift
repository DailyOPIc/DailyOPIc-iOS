import Foundation

/// 페이월을 연 지점. 분석 이벤트의 `source` 파라미터로만 쓰이며 UI 분기는 없다.
/// rawValue는 로그 스키마라 표시 문구와 달리 바뀌지 않는다.
enum PaywallSource: String, Sendable {
    case settings
    case tokenExhausted = "token_exhausted"
    case resultLocked = "result_locked"
    case mockLimit = "mock_limit"
    /// 캘린더의 잠긴 자동화 기능을 직접 눌러서 들어온 경우.
    case calendarLocked = "calendar_locked"
}

/// 페이월 한 플랜의 표시 문구.
///
/// 여기 적는 모든 항목은 `DailyOPIc-BE/app/services/plans.py`가 실제로 강제하고
/// 앱에서 실제로 도달 가능한 것만이다. 서버가 값을 내려보내도 앱에 그 기능이
/// 없으면 혜택으로 쓰지 않는다. 지키지 못할 약속은 문구가 아니라 결함이다.
///
/// 일부러 뺀 것:
/// - **학습 기록 보관 기간**: `historyDays`가 capabilities에 있지만 서버에 기록
///   조회 API 자체가 없다. 기록은 기기 로컬(SwiftData)에 전 플랜 동일하게 최근
///   50건만 남는다. 7일/30일/전체는 강제되지 않는다.
/// - **취약점 복습 세트**: 서버 `/v1/question-sets/review`는 프로 전용으로 막혀
///   있지만 앱이 이 엔드포인트를 호출하는 화면이 아직 없다.
/// - **취약점 기반 학습 일정**: 구현이 없다(G8). 캘린더 문구는 실제로 동작하는
///   자동 재조정 · 평가 반영 · 시험일 역산 세 가지만 말한다.
///
/// 알림은 둘 다 **기기가 예약하는 로컬 알림**이다. 서버 푸시가 아니므로 "푸시 알림"·
/// "스마트 알림"이라고 쓰지 않는다. 매일 학습 알림은 P9부터 **전 플랜 공통**이라 파는
/// 물건이 아니고, 유료 경계는 **개인 일정 알림**뿐이다(베이직·플러스·프로 동일).
struct PaywallPlanCopy: Identifiable, Sendable {
    let plan: PlanEntitlement
    /// 이 플랜이 누구에게 맞는지 한 줄. 상시 포지셔닝이며 기간 한정 문구가 아니다.
    let tagline: String
    let benefits: [String]

    var id: String { plan.rawValue }

    static let free = PaywallPlanCopy(
        plan: .free,
        tagline: "가볍게 시작해 보기",
        benefits: [
            "매일 데일리 토큰 1개 (광고 시청으로 1개 더)",
            "예상 등급 · 강점 · 개선점 · 5영역 피드백",
            "모의고사 1회 체험 (광고 시청)",
            "학습 캘린더 · 진행률 · 연속 학습",
            "정한 공부 시간에 매일 학습 알림",
            "광고 포함",
        ]
    )

    /// 선택 가능한 유료 플랜. 순서가 곧 셀렉터 순서다.
    static let paid: [PaywallPlanCopy] = [
        PaywallPlanCopy(
            plan: .basic,
            tagline: "매일 꾸준히 준비",
            benefits: [
                "매일 데일리 토큰 3개",
                "결과 전체 해제 — 교정 답안 · 모범 답안 · 목표 등급까지",
                "모의고사 매일 1회",
                "놓친 학습을 반영한 자동 일정 재조정",
                "개인 일정 시작 전 알림",
                "광고 없음",
            ]
        ),
        PaywallPlanCopy(
            plan: .plus,
            tagline: "시험 전 집중 준비",
            benefits: [
                "매일 데일리 토큰 10개",
                "베이직의 결과 분석 그대로",
                "모의고사 하루 3회",
                "최근 평가를 반영한 학습 계획",
                "시험일까지 역산한 일정 조정",
                "광고 없음",
            ]
        ),
        PaywallPlanCopy(
            plan: .pro,
            tagline: "가장 많이 연습하기",
            benefits: [
                "매일 데일리 토큰 20개",
                "플러스의 결과 분석 그대로",
                "모의고사 하루 5회",
                "플러스의 학습 일정 기능 그대로",
                "광고 없음",
            ]
        ),
    ]

    static func copy(for plan: PlanEntitlement) -> PaywallPlanCopy {
        paid.first { $0.plan == plan } ?? free
    }
}

/// "모든 플랜 비교" 한 줄. 열 순서는 무료 · 베이직 · 플러스 · 프로.
struct PaywallComparisonRow: Identifiable, Sendable {
    let title: String
    let values: [String]

    var id: String { title }

    /// 플랜별로 **실제로 다른** 항목만 넣는다. 차이가 없는 줄은 비교표를 길게 할 뿐
    /// 결정에 도움이 되지 않는다.
    static let all: [PaywallComparisonRow] = [
        PaywallComparisonRow(title: "데일리 토큰", values: ["1 (+광고 1)", "3", "10", "20"]),
        PaywallComparisonRow(title: "AI 결과 분석", values: ["요약", "전체", "전체", "전체"]),
        PaywallComparisonRow(title: "모의고사", values: ["1회 체험", "매일 1회", "하루 3회", "하루 5회"]),
        // 캘린더 자체는 전 플랜이 쓴다. 다른 것은 자동화 깊이뿐이다.
        PaywallComparisonRow(
            title: "학습 일정 자동화",
            values: ["기본 캘린더", "자동 재조정", "평가 반영 · 시험일 역산", "평가 반영 · 시험일 역산"]
        ),
        // 매일 학습 알림은 전 플랜 공통이라 비교할 것이 없어 줄 자체를 두지 않는다.
        // 기기에서 보내는 로컬 알림이고, 유료 플랜 사이에는 차이가 없다.
        PaywallComparisonRow(title: "개인 일정 알림", values: ["없음", "있음", "있음", "있음"]),
        PaywallComparisonRow(title: "광고", values: ["있음", "없음", "없음", "없음"]),
    ]

    static let planColumns: [PlanEntitlement] = [.free, .basic, .plus, .pro]
}
