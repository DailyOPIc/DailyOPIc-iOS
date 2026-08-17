import Foundation
import Testing
import UserNotifications
@testable import DailyOPIc

/// P4: 학습 알림은 유료 플래너 기능이다(무료 잠김 · 베이직/플러스/프로 사용 가능).
///
/// 여기서 지키는 것은 두 가지다.
/// 1. 자격 판단은 `CalendarFeaturePolicy` 한 곳에서만 나온다.
/// 2. 자격을 잃으면 예약된 알림이 걷히고 로컬 "켜 둠" 의도도 꺼진다.
@MainActor
struct StudyReminderEntitlementTests {

    // MARK: 자격 해석 (§17 A–G)

    private func capabilities(
        plan: String?,
        studyReminder: Bool? = nil,
        autoReplan: Bool? = true
    ) -> Capabilities {
        Capabilities(
            minimumSupportedAppVersion: "1.0.0",
            questionGenerationV2: true,
            mockSessionV2: true,
            evaluationRubricV2: true,
            practiceRefresh: true,
            guideSchemaVersion: 1,
            plan: plan,
            quotaPolicy: Capabilities.QuotaPolicy(
                dailyAnalysisFree: 1,
                dailyRefreshRewards: 1,
                mockSessionsPerDay: 1,
                mockRewardGates: 3,
                practiceDaily: 1,
                practiceAdBonus: 1,
                historyDays: 7,
                analysisDepth: "summary",
                reviewSet: false,
                adsEnabled: true,
                calendarAutoReplan: autoReplan,
                calendarEvaluationAdaptive: false,
                calendarExamBackplan: false,
                calendarStudyReminder: studyReminder
            )
        )
    }

    /// A~D. 서버를 못 볼 때의 폴백 표가 곧 제품 정책이다: 무료만 잠긴다.
    @Test func fallbackLocksStudyReminderOnlyForFree() {
        #expect(CalendarFeaturePolicy.fallback(for: .free).canUseStudyReminder == false)
        #expect(CalendarFeaturePolicy.fallback(for: .basic).canUseStudyReminder)
        #expect(CalendarFeaturePolicy.fallback(for: .plus).canUseStudyReminder)
        #expect(CalendarFeaturePolicy.fallback(for: .pro).canUseStudyReminder)
    }

    /// 유료끼리는 차이가 없다. 알림에서 프로가 베이직보다 나은 점은 없다.
    @Test func paidPlansGetTheSameReminderCapability() {
        let paid: [PlanEntitlement] = [.basic, .plus, .pro]
        let values = paid.map { CalendarFeaturePolicy.fallback(for: $0).canUseStudyReminder }
        #expect(values == [true, true, true])
    }

    /// E. 서버 값이 있고 플랜이 일치하면 서버가 진실이다.
    @Test func matchingServerSnapshotWins() {
        #expect(CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "basic", studyReminder: true), plan: .basic
        ).canUseStudyReminder)
        // 서버가 잠갔다고 말하면 유료 플랜이라도 잠긴다(정책 변경은 서버가 먼저다).
        #expect(!CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "basic", studyReminder: false), plan: .basic
        ).canUseStudyReminder)
    }

    /// F. 이 필드를 모르는 구 서버. 없다고 유료 사용자의 기능을 뺏지 않는다.
    @Test func oldBackendWithoutTheFieldFallsBackToThePlan() {
        #expect(CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "basic", studyReminder: nil), plan: .basic
        ).canUseStudyReminder)
        #expect(!CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "free", studyReminder: nil, autoReplan: false),
            plan: .free
        ).canUseStudyReminder)
    }

    /// F'. capabilities 자체가 없어도 안전하게 플랜 폴백으로 간다.
    @Test func missingCapabilitiesFallsBackToThePlan() {
        #expect(!CalendarFeaturePolicy.resolve(capabilities: nil, plan: .free).canUseStudyReminder)
        #expect(CalendarFeaturePolicy.resolve(capabilities: nil, plan: .pro).canUseStudyReminder)
    }

    /// G. 방금 결제해 로컬 엔타이틀먼트가 앞서 간 상태. 낡은 free 스냅샷으로 잠그지 않는다.
    @Test func staleServerSnapshotIsIgnored() {
        let policy = CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "free", studyReminder: false, autoReplan: false),
            plan: .plus
        )
        #expect(policy.canUseStudyReminder)
        #expect(policy == .everything)
    }

    /// 구 서버 JSON(필드 없음)이 디코딩을 깨지 않는다.
    @Test func decodingSucceedsWithoutTheNewField() throws {
        let json = """
        {
          "minimumSupportedAppVersion": "1.0.0",
          "questionGenerationV2": true,
          "mockSessionV2": true,
          "evaluationRubricV2": true,
          "practiceRefresh": true,
          "guideSchemaVersion": 1,
          "plan": "basic",
          "quotaPolicy": {
            "dailyAnalysisFree": 3,
            "dailyRefreshRewards": 10,
            "mockSessionsPerDay": 1,
            "mockRewardGates": 0,
            "calendarAutoReplan": true
          }
        }
        """
        let decoded = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        #expect(decoded.quotaPolicy.calendarStudyReminder == nil)
        // 베이직이 산 기능을 구 서버 때문에 잃지 않는다.
        #expect(CalendarFeaturePolicy.resolve(capabilities: decoded, plan: .basic).canUseStudyReminder)
    }

    /// 새 서버 JSON은 그대로 읽는다.
    @Test func decodingReadsTheNewField() throws {
        let json = """
        {
          "minimumSupportedAppVersion": "1.0.0",
          "questionGenerationV2": true,
          "mockSessionV2": true,
          "evaluationRubricV2": true,
          "practiceRefresh": true,
          "guideSchemaVersion": 1,
          "plan": "free",
          "quotaPolicy": {
            "dailyAnalysisFree": 1,
            "dailyRefreshRewards": 1,
            "mockSessionsPerDay": 1,
            "mockRewardGates": 3,
            "calendarAutoReplan": false,
            "calendarStudyReminder": false
          }
        }
        """
        let decoded = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        #expect(decoded.quotaPolicy.calendarStudyReminder == false)
    }

    // MARK: 강등 (§18 A–F)

    private let now = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(8 * 3600)

    /// 유료 시절 예약해 둔 알림 목록.
    private func reminders() -> [StudyReminderRequest] {
        let settings = StudyCalendarFixture.settings(
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            preferredStudyTime: StudyTimeOfDay(hour: 21, minute: 0)
        )
        return StudyReminderPlanner.reminders(
            plan: AdaptiveStudyPlanner.plan(
                settings: settings,
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: 2,
                completions: [:],
                policy: .everything,
                today: now
            ),
            settings: settings,
            completions: [:],
            now: now
        )
    }

    private func service(
        center: FakeNotificationCenter,
        enabled: Bool
    ) -> (StudyReminderService, UserDefaults, String) {
        let suite = "DailyOPIcTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = AppPreferences(defaults: defaults)
        preferences.studyRemindersEnabled = enabled
        return (StudyReminderService(preferences: preferences, center: center), defaults, suite)
    }

    /// A. 유료로 예약해 둔 알림은 무료로 내려가는 순간 걷힌다.
    @Test func downgradeRemovesPendingStudyReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: true)
        #expect(!center.studyReminderIdentifiers.isEmpty)

        await service.reconcile(reminders(), isEligible: false)

        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// B. 로컬 "켜 둠" 의도도 함께 꺼진다. 나중에 다시 올라가도 저절로 켜지지 않는다.
    @Test func downgradeResetsTheLocalEnabledIntent() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: false)

        #expect(!service.isEnabled)
        #expect(!service.isActive)
        #expect(!defaults.bool(forKey: "native_study_reminders_enabled"))
    }

    /// C. OS 권한은 건드리지 않는다. 알림 허용은 사용자가 OS에 준 것이다.
    @Test func downgradeLeavesTheSystemAuthorizationAlone() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: false)

        #expect(center.status == .authorized)
        #expect(center.authorizationRequestCount == 0)
    }

    /// D. 우리 네임스페이스 밖의 알림은 손대지 않는다.
    @Test func downgradeDoesNotTouchForeignNotifications() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let foreign = UNNotificationRequest(
            identifier: "com.other.app.reminder",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        await center.add(foreign)
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: true)
        await service.reconcile(reminders(), isEligible: false)

        #expect(center.pending.map(\.identifier) == ["com.other.app.reminder"])
    }

    /// E. 여러 번 강제해도 결과가 같다(포그라운드 복귀마다 호출된다).
    @Test func repeatedDowngradeEnforcementIsIdempotent() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: true)
        for _ in 0..<3 {
            await service.reconcile(reminders(), isEligible: false)
        }

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(!service.isEnabled)
        #expect(center.authorizationRequestCount == 0)
    }

    /// F. 예전 버전에서 켜 둔 무료 사용자. 앱을 켜는 순간(일정을 모르는 상태여도) 정리된다.
    @Test func staleEnabledFlagIsCleanedUpEvenBeforeTheScheduleIsKnown() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders(), isEligible: true)

        // nil = "아직 일정을 모른다". 자격이 없으면 일정을 몰라도 걷어낸다.
        await service.reconcile(nil, isEligible: false)

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(!service.isEnabled)
    }

    /// 무료 + iOS 권한 허용 상태여도 예약은 생기지 않는다.
    @Test func freeUserNeverSchedulesEvenWithSystemPermission() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: false)

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(center.authorizationRequestCount == 0)
    }

    // MARK: 업그레이드 (§19 A–D)

    /// A. 무료 → 베이직이면 기능이 열린다.
    @Test func upgradeUnlocksTheCapability() {
        #expect(!CalendarFeaturePolicy.fallback(for: .free).canUseStudyReminder)
        #expect(CalendarFeaturePolicy.fallback(for: .basic).canUseStudyReminder)
    }

    /// B·C. 업그레이드는 알림을 켜지도, 권한을 묻지도 않는다.
    @Test func upgradeNeitherEnablesNorAsksForPermission() async {
        let center = FakeNotificationCenter()
        center.status = .notDetermined
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 업그레이드 직후의 재조정 — 이제 자격은 있지만 사용자는 아직 켠 적이 없다.
        await service.reconcile(reminders(), isEligible: true)

        #expect(!service.isEnabled)
        #expect(center.authorizationRequestCount == 0)
        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// D. 업그레이드 후 사용자가 직접 켜면 P1의 켜기 흐름이 그대로 동작한다.
    @Test func explicitEnableAfterUpgradeStillWorks() async {
        let center = FakeNotificationCenter()
        center.status = .notDetermined
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.enable()
        await service.reconcile(reminders(), isEligible: true)

        #expect(center.authorizationRequestCount == 1)
        #expect(service.isEnabled)
        #expect(!center.studyReminderIdentifiers.isEmpty)
    }

    /// 강등으로 꺼진 뒤 다시 올라가도 저절로 켜지지 않는다(명시적 opt-in 유지).
    @Test func reUpgradeDoesNotReactivateAutomatically() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(), isEligible: true)
        await service.reconcile(reminders(), isEligible: false)
        await service.reconcile(reminders(), isEligible: true)

        #expect(!service.isEnabled)
        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    // MARK: 잠금 UI 계약 (§20)

    /// 무료에게도 기능은 보인다 — 잠긴 채로.
    @Test func freePlanShowsTheReminderAsLocked() {
        #expect(CalendarLockedFeature.studyReminder.isLocked(under: .free))
        #expect(CalendarLockedFeature.studyReminder.title == "학습 알림")
        #expect(CalendarLockedFeature.studyReminder.requirementText == "베이직부터")
        #expect(CalendarLockedFeature.studyReminder.accessibilityLabel
            == "학습 알림, 잠김, 베이직부터 이용 가능")
    }

    /// 유료에서는 잠금이 사라진다.
    @Test func paidPlansShowNoReminderLock() {
        for plan in [PlanEntitlement.basic, .plus, .pro] {
            let policy = CalendarFeaturePolicy.fallback(for: plan)
            #expect(!CalendarLockedFeature.studyReminder.isLocked(under: policy), "\(plan)")
        }
    }

    /// 학습 알림은 "학습 플랜 기능" 목록에 끼지 않는다(같은 화면에 두 번 보이면 안 된다).
    @Test func reminderIsNotDuplicatedInTheAutomationList() {
        #expect(!CalendarLockedFeature.automationCases.contains(.studyReminder))
    }

    /// 문구가 원격 푸시를 약속하지 않는다. 우리는 기기 로컬 알림만 쓴다.
    @Test func copyNeverPromisesRemotePush() {
        let copy = CalendarLockedFeature.studyReminder.title
            + CalendarLockedFeature.studyReminder.detail
            + PaywallPlanCopy.copy(for: .basic).benefits.joined()
            + PaywallComparisonRow.all.map { $0.title + $0.values.joined() }.joined()
        for forbidden in ["푸시", "스마트 알림", "AI 알림", "서버"] {
            #expect(!copy.contains(forbidden), "\(forbidden)")
        }
    }

    /// 페이월 비교표가 무료=없음 / 유료=있음을 그대로 말한다.
    @Test func paywallComparisonTellsTheTruthAboutTheReminder() throws {
        let row = try #require(PaywallComparisonRow.all.first { $0.title == "학습 알림" })
        #expect(PaywallComparisonRow.planColumns == [.free, .basic, .plus, .pro])
        #expect(row.values == ["없음", "있음", "있음", "있음"])
    }
}
