import Foundation

/// 리뷰 요청을 허용하는 순간의 화이트리스트.
/// 성공한 학습 결과 하나만 허용한다. 나머지 값은 "여기서는 요청하지 않는다"를
/// 코드로 못 박아 두기 위한 것이고, 실제로 호출되는 곳은 successfulPracticeResult 뿐이다.
enum AppReviewContext: String, Sendable, CaseIterable {
    case successfulPracticeResult = "successful_practice_result"
    case appLaunch = "app_launch"
    case calendar
    case paywall
    case purchase
    case restore
    case rewardedAd = "rewarded_ad"

    /// 리뷰는 학습 성공에 대한 것이지 결제·광고·앱 실행에 대한 것이 아니다.
    var allowsReviewRequest: Bool { self == .successfulPracticeResult }
}

/// 배포 경로. TestFlight에서는 절대 요청하지 않는다 — 베타 빌드의 평가는 스토어에
/// 남지 않고, 사용자에게는 의미 없는 창만 뜬다.
enum AppDistribution: String, Sendable {
    case debug
    case testFlight = "test_flight"
    case appStore = "app_store"
    case unknown

    /// DEBUG 빌드는 debug. 그 밖에는 영수증 파일 이름으로 구분한다
    /// (TestFlight·샌드박스는 `sandboxReceipt`). 영수증 URL이 없으면 unknown이고,
    /// unknown은 요청하지 않는다 — 과하게 묻느니 덜 묻는다.
    ///
    /// 한계: 이 방법은 App Store 배포와 TestFlight를 파일명 하나로 구분한다.
    /// StoreKit 2의 AppTransaction으로도 알 수 있지만 async·네트워크가 얽히고,
    /// 리뷰 요청 하나 때문에 결과 화면을 기다리게 만들 이유가 없다.
    static var current: AppDistribution {
        #if DEBUG
        return .debug
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return .unknown }
        return receiptURL.lastPathComponent == "sandboxReceipt" ? .testFlight : .appStore
        #endif
    }

    var allowsReviewRequest: Bool {
        switch self {
        case .appStore, .debug: true
        case .testFlight, .unknown: false
        }
    }
}

/// 리뷰 요청 자격. 순수 계산이라 네이티브 호출 없이 그대로 테스트한다.
///
/// "긍정적인 순간"은 **높은 점수**가 아니라 **결과 경험이 성공적으로 전달된 것**이다.
/// 예상 등급은 어떤 형태로도 조건에 들어가지 않는다(높은 평가만 골라 받는 것은 조작이다).
enum AppReviewEligibility {
    static let minimumSuccessfulEvaluations = 3
    static let minimumDistinctLearningDays = 2
    static let cooldownDays = 30

    /// - Parameters:
    ///   - successfulEvaluationDates: 분석이 성공한 세트의 완료 시각들(`StudySetCompletionRecord`).
    ///     세트당 한 줄뿐이라 재시도·결과 재진입·재렌더링은 애초에 두 번 세지 않는다.
    ///   - calendar: 서로 다른 날을 세는 기준. 기기 현재 달력을 쓴다(학습 계획 설정과
    ///     묶지 않는다 — 계획을 만들지 않은 사용자도 같은 규칙이어야 한다).
    ///   - lastAttemptAt: 마지막으로 **시도한** 시각. 창이 떴는지는 알 수 없다.
    static func shouldRequest(
        context: AppReviewContext,
        distribution: AppDistribution,
        successfulEvaluationDates: [Date],
        calendar: Calendar = .current,
        lastAttemptAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard context.allowsReviewRequest, distribution.allowsReviewRequest else { return false }
        guard successfulEvaluationDates.count >= minimumSuccessfulEvaluations else { return false }
        let distinctDays = Set(successfulEvaluationDates.map { calendar.startOfDay(for: $0) })
        guard distinctDays.count >= minimumDistinctLearningDays else { return false }
        guard let lastAttemptAt else { return true }
        guard let cooldownEnd = calendar.date(
            byAdding: .day,
            value: cooldownDays,
            to: lastAttemptAt
        ) else { return true }
        return now >= cooldownEnd
    }
}

/// 자격 판단과 네이티브 호출 사이의 얇은 층. 상태는 이 기기에만 남고 서버로 가지 않는다.
@MainActor
final class AppReviewCoordinator {
    private let preferences: AppPreferences
    private let successfulEvaluationDates: () -> [Date]
    private let distribution: AppDistribution
    private let calendar: Calendar

    init(
        preferences: AppPreferences,
        distribution: AppDistribution = .current,
        calendar: Calendar = .current,
        successfulEvaluationDates: @escaping () -> [Date]
    ) {
        self.preferences = preferences
        self.distribution = distribution
        self.calendar = calendar
        self.successfulEvaluationDates = successfulEvaluationDates
    }

    /// 자격이 되면 네이티브 리뷰 요청을 한 번 시도한다.
    ///
    /// - Parameter request: 실제 네이티브 호출(SwiftUI `RequestReviewAction`).
    ///   창을 띄울지는 Apple이 정하고, 앱은 그 결과를 알 수 없다.
    /// - Returns: **시도했는지**. "창이 떴다"·"리뷰가 등록됐다"는 뜻이 아니다.
    @discardableResult
    func requestReviewIfEligible(
        context: AppReviewContext,
        now: Date = .now,
        request: () -> Void
    ) -> Bool {
        guard AppReviewEligibility.shouldRequest(
            context: context,
            distribution: distribution,
            successfulEvaluationDates: successfulEvaluationDates(),
            calendar: calendar,
            lastAttemptAt: preferences.lastReviewRequestAttemptAt,
            now: now
        ) else { return false }
        AppTelemetry.appReviewEligible(context: context)
        // 창 표시 여부를 확인할 방법이 없으므로 **시도한 시각**을 쿨다운 기준으로 남긴다.
        // 요청 호출보다 먼저 적어야 같은 결과가 다시 그려져도 두 번 시도하지 않는다.
        preferences.lastReviewRequestAttemptAt = now
        AppTelemetry.appReviewRequestAttempted(context: context)
        request()
        return true
    }
}
