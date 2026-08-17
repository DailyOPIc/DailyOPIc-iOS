import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// G6: 앱 스토어 리뷰는 **학습이 성공한 순간**에만, 네이티브 요청으로만, 아주 가끔 묻는다.
/// 점수는 조건이 아니고(조작이 된다), TestFlight에서는 절대 묻지 않는다.
/// 여기서 실제 네이티브 창은 한 번도 뜨지 않는다 — 요청은 주입된 클로저다.
@MainActor
struct AppReviewTests {
    private let seoul = Calendar.seoulCalendar
    /// 2026-08-14 09:00(KST).
    private let now = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(9 * 3600)

    /// 서로 다른 날짜에 하나씩 성공한 분석 기록.
    private func dates(_ localDates: String...) -> [Date] {
        localDates.map { StudyCalendarFixture.date($0).addingTimeInterval(9 * 3600) }
    }

    private func shouldRequest(
        context: AppReviewContext = .successfulPracticeResult,
        distribution: AppDistribution = .appStore,
        evaluations: [Date],
        lastAttemptAt: Date? = nil,
        now: Date? = nil
    ) -> Bool {
        AppReviewEligibility.shouldRequest(
            context: context,
            distribution: distribution,
            successfulEvaluationDates: evaluations,
            calendar: seoul,
            lastAttemptAt: lastAttemptAt,
            now: now ?? self.now
        )
    }

    /// 자격을 이미 채운 기록. 3번 · 2일.
    private var qualifying: [Date] {
        dates("2026-08-12", "2026-08-13", "2026-08-13")
    }

    private func coordinator(
        evaluations: [Date],
        distribution: AppDistribution = .appStore,
        lastAttemptAt: Date? = nil
    ) -> (AppReviewCoordinator, AppPreferences) {
        let defaults = UserDefaults(suiteName: "app-review-\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        preferences.lastReviewRequestAttemptAt = lastAttemptAt
        let coordinator = AppReviewCoordinator(
            preferences: preferences,
            distribution: distribution,
            calendar: seoul,
            successfulEvaluationDates: { evaluations }
        )
        return (coordinator, preferences)
    }

    // MARK: - 성공한 분석 횟수

    /// 1~3. 처음 쓰는 사용자에게는 묻지 않는다.
    @Test func fewerThanThreeSuccessfulEvaluationsNeverQualify() {
        #expect(shouldRequest(evaluations: []) == false)
        #expect(shouldRequest(evaluations: dates("2026-08-13")) == false)
        #expect(shouldRequest(evaluations: dates("2026-08-12", "2026-08-13")) == false)
    }

    /// 4. 딱 3번이면 (다른 조건이 맞을 때) 자격이 생긴다.
    @Test func exactlyThreeSuccessfulEvaluationsMayQualify() {
        #expect(AppReviewEligibility.minimumSuccessfulEvaluations == 3)
        #expect(shouldRequest(evaluations: qualifying))
    }

    /// 5. 하루에 몰아서 세 번 해도 아직 아니다. 하루 써 본 사람은 아직 모른다.
    @Test func threeEvaluationsOnASingleDayDoNotQualify() {
        #expect(shouldRequest(evaluations: dates("2026-08-13", "2026-08-13", "2026-08-13")) == false)
    }

    /// 6. 3번 이상 · 서로 다른 2일 이상이면 자격이 있다.
    @Test func threeEvaluationsAcrossTwoDaysQualify() {
        #expect(AppReviewEligibility.minimumDistinctLearningDays == 2)
        #expect(shouldRequest(evaluations: dates("2026-08-11", "2026-08-13", "2026-08-14")))
    }

    /// 7. 실패한 분석은 세지 않는다. 완료 원장은 분석이 성공했을 때만 한 줄 남는다.
    @Test func failedEvaluationDoesNotCount() throws {
        let persistence = try inMemoryPersistence()
        // 실패는 recordStudySetCompletion 자체가 호출되지 않는다(성공 경로에만 있다).
        #expect(try persistence.recordStudySetCompletion(setId: "set-1"))
        #expect(try persistence.studySetCompletionDates().count == 1)
        #expect(shouldRequest(evaluations: try persistence.studySetCompletionDates()) == false)
    }

    /// 8. 같은 세트를 다시 분석해도 두 번 세지 않는다(setId가 유일 키다).
    @Test func sameSetNeverCountsTwice() throws {
        let persistence = try inMemoryPersistence()
        for _ in 0..<3 { _ = try persistence.recordStudySetCompletion(setId: "set-1") }
        #expect(try persistence.studySetCompletionDates().count == 1)
    }

    /// 9 · 26. 같은 결과가 여러 번 그려져도 요청은 한 번뿐이다.
    /// (첫 시도에서 남긴 쿨다운이 곧바로 다음 시도를 막는다.)
    @Test func repeatedResultAppearanceRequestsOnlyOnce() {
        let (coordinator, _) = coordinator(evaluations: qualifying)
        var requestCount = 0
        for _ in 0..<5 {
            coordinator.requestReviewIfEligible(
                context: .successfulPracticeResult,
                now: now
            ) { requestCount += 1 }
        }
        #expect(requestCount == 1)
    }

    // MARK: - 허용된 순간

    /// 10. 성공한 연습 결과에서만 요청한다.
    @Test func successfulPracticeResultContextIsEligible() {
        #expect(shouldRequest(context: .successfulPracticeResult, evaluations: qualifying))
    }

    /// 11~16. 앱 시작·캘린더·페이월·구매·복원·광고에서는 절대 요청하지 않는다.
    @Test func everyOtherContextIsIneligible() {
        for context in AppReviewContext.allCases where context != .successfulPracticeResult {
            #expect(shouldRequest(context: context, evaluations: qualifying) == false)
        }
        #expect(AppReviewContext.allCases.filter(\.allowsReviewRequest).count == 1)
    }

    // MARK: - 점수 중립

    /// 17 · 18. 예상 등급은 자격에 들어오지 않는다. 조건은 등급을 입력으로 받지 않는다.
    /// 낮은 등급이라고 막지 않고, 높은 등급이라고 조건을 건너뛰지도 않는다.
    @Test func predictedLevelNeverAffectsEligibility() {
        // 낮은 결과만 낸 사용자도 자격 조건을 채우면 자격이 있다.
        #expect(shouldRequest(evaluations: qualifying))
        // 반대로 아무리 좋은 결과라도 하루치 두 번이면 자격이 없다.
        #expect(shouldRequest(evaluations: dates("2026-08-13", "2026-08-13")) == false)
    }

    // MARK: - 배포 경로

    /// 19. TestFlight에서는 항상 막는다.
    @Test func testFlightIsAlwaysSuppressed() {
        #expect(shouldRequest(distribution: .testFlight, evaluations: qualifying) == false)
        #expect(AppDistribution.testFlight.allowsReviewRequest == false)
        // 영수증을 확인할 수 없으면 묻지 않는다(과하게 묻느니 덜 묻는다).
        #expect(AppDistribution.unknown.allowsReviewRequest == false)
    }

    /// 20. App Store 배포에서는 자격이 되면 요청한다.
    @Test func appStoreDistributionCanRequest() {
        #expect(shouldRequest(distribution: .appStore, evaluations: qualifying))
    }

    // MARK: - 30일 쿨다운

    /// 21 · 22. 30일이 지나기 전에는 막힌다.
    @Test func cooldownBlocksBeforeThirtyDays() {
        #expect(AppReviewEligibility.cooldownDays == 30)
        let attempt = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(9 * 3600)
        #expect(shouldRequest(evaluations: qualifying, lastAttemptAt: attempt, now: attempt) == false)
        let justBefore = attempt.addingTimeInterval(30 * 86_400 - 1)
        #expect(shouldRequest(evaluations: qualifying, lastAttemptAt: attempt, now: justBefore) == false)
    }

    /// 23. 30일이 되면 다시 자격이 생긴다.
    @Test func cooldownExpiresAtThirtyDays() {
        let attempt = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(9 * 3600)
        let atThirtyDays = seoul.date(byAdding: .day, value: 30, to: attempt)!
        #expect(shouldRequest(evaluations: qualifying, lastAttemptAt: attempt, now: atThirtyDays))
    }

    /// 24. 시도하면 쿨다운 시각이 남는다.
    @Test func attemptPersistsCooldownTimestamp() {
        let (coordinator, preferences) = coordinator(evaluations: qualifying)
        #expect(preferences.lastReviewRequestAttemptAt == nil)
        #expect(coordinator.requestReviewIfEligible(context: .successfulPracticeResult, now: now) {})
        #expect(preferences.lastReviewRequestAttemptAt == now)
    }

    /// 25. Apple이 창을 띄우지 않아도 쿨다운은 그대로 남는다.
    /// 앱은 창이 떴는지 알 수 없으므로 "시도"를 기준으로 삼는다.
    @Test func silentNativeRequestStillKeepsCooldown() {
        // 아무것도 하지 않는 요청(= 창이 뜨지 않은 경우)을 그대로 흉내 낸다.
        let (coordinator, preferences) = coordinator(evaluations: qualifying)
        #expect(coordinator.requestReviewIfEligible(context: .successfulPracticeResult, now: now) {})
        #expect(preferences.lastReviewRequestAttemptAt == now)
        let sameDay = now.addingTimeInterval(3600)
        #expect(coordinator.requestReviewIfEligible(
            context: .successfulPracticeResult,
            now: sameDay
        ) {} == false)
        #expect(preferences.lastReviewRequestAttemptAt == now)
    }

    // MARK: - 기존 사용자 · 상태 보관

    /// 27. 기록이 부족한 기존 사용자에게는 묻지 않는다. 추측해서 자격을 주지 않는다.
    @Test func existingUserWithoutEnoughEvidenceStaysConservative() {
        // 오래 써 왔지만 남아 있는 완료 기록이 하루치 두 건뿐인 경우.
        #expect(shouldRequest(evaluations: dates("2026-05-02", "2026-05-02")) == false)
        // 새 학습으로 조건을 채우면 자연스럽게 자격이 생긴다.
        #expect(shouldRequest(evaluations: dates("2026-05-02", "2026-05-02", "2026-08-13")))
    }

    /// 28. 리뷰 상태는 이 기기에만 남는다. 새 기기(빈 UserDefaults)는 쿨다운이 없다.
    @Test func reviewStateIsDeviceLocal() {
        let (_, preferences) = coordinator(evaluations: qualifying, lastAttemptAt: now)
        #expect(preferences.lastReviewRequestAttemptAt == now)
        let fresh = AppPreferences(defaults: UserDefaults(suiteName: "app-review-\(UUID().uuidString)")!)
        #expect(fresh.lastReviewRequestAttemptAt == nil)
    }

    /// 29 · 30 · 31. 만족도 게이트도, 리뷰 보상도, 결과를 안다고 주장하는 로그도 없다.
    /// 자격 계산의 입력은 순간·배포 경로·성공 기록·쿨다운뿐이다(별점·보상·표시 여부 없음).
    @Test func noSatisfactionGateNoRewardNoOutcomeClaim() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
        let sources = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        let forbidden = [
            "review_shown", "review_submitted", "review_success",
            "리뷰 남겨", "별점", "5점", "마음에 드시"
        ]
        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(source.lastPathComponent)에 '\(word)'가 있다")
            }
        }
    }

    private func inMemoryPersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: StudySetCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }
}

private extension Calendar {
    /// 테스트는 기기 시간대에 흔들리면 안 된다. 날짜 경계를 서울로 고정한다.
    static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = StudyCalendarFixture.seoulTimeZone
        return calendar
    }
}
