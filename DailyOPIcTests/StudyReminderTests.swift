import Foundation
import Testing
import UserNotifications
@testable import DailyOPIc

/// 테스트용 알림 센터. 실제 권한 창을 절대 띄우지 않는다.
final class FakeNotificationCenter: UserNotificationCenterProtocol, @unchecked Sendable {
    var status: UNAuthorizationStatus = .notDetermined
    /// 권한 요청이 실제로 몇 번 나갔는지. 자동 요청이 없다는 것을 이 값으로 지킨다.
    var authorizationRequestCount = 0
    /// 권한 창에서 사용자가 누를 결과.
    var grantsAuthorization = true
    var pending: [UNNotificationRequest] = []
    /// iOS가 예약을 거절하는 상황(대기 상한 초과 등)을 재현한다.
    var addFailure: NotificationAddFailure?

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        status = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }

    func pendingRequests() async -> [UNNotificationRequest] { pending }

    @discardableResult
    func add(_ request: UNNotificationRequest) async -> NotificationAddFailure? {
        if let addFailure { return addFailure }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
        return nil
    }

    func removePendingRequests(identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    var studyReminderIdentifiers: [String] {
        pending.map(\.identifier).filter(StudyReminderPolicy.isStudyReminder).sorted()
    }

    var eventReminderIdentifiers: [String] {
        pending.map(\.identifier).filter(PlannerEventReminderPolicy.isEventReminder).sorted()
    }

    func body(for localDate: String) -> String? {
        pending.first { $0.identifier == StudyReminderPolicy.identifier(forLocalDate: localDate) }?
            .content.body
    }

    func components(for localDate: String) -> DateComponents? {
        let request = pending.first {
            $0.identifier == StudyReminderPolicy.identifier(forLocalDate: localDate)
        }
        return (request?.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    }
}

/// 격리된 UserDefaults 위의 서비스 한 벌. 테스트끼리 설정이 새지 않는다.
@MainActor
struct ReminderServiceHarness {
    let center: FakeNotificationCenter
    let preferences: AppPreferences
    let service: StudyReminderService
    private let defaults: UserDefaults
    private let suite: String

    init(
        status: UNAuthorizationStatus = .authorized,
        preference: StudyReminderPreference? = nil
    ) {
        center = FakeNotificationCenter()
        center.status = status
        suite = "DailyOPIcTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = AppPreferences(defaults: defaults)
        if let preference { preferences.studyReminderPreference = preference }
        service = StudyReminderService(preferences: preferences, center: center)
    }

    /// 앱을 다시 켠 상황. 저장된 의도가 살아 있는지 보는 데 쓴다.
    func reloadedPreferences() -> AppPreferences { AppPreferences(defaults: defaults) }

    func tearDown() { defaults.removePersistentDomain(forName: suite) }
}

/// P9: 학습 알림은 **전 플랜 공통**이고, 명시적으로 끈 적이 없으면 켜진 것으로 본다.
/// 로컬 알림만 쓰고(FCM 없음), 권한은 사용자가 직접 켤 때만 요청한다.
@MainActor
struct StudyReminderTests {
    /// 2026-08-14(금) 오전 8시. 알림 시각(21:00) 이전이라 오늘 알림이 살아 있다.
    private let now = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(8 * 3600)

    private func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        intensity: StudyIntensity = .steady,
        examDate: String? = nil,
        preferredStudyTime: StudyTimeOfDay = StudyTimeOfDay(hour: 21, minute: 0),
        timeZone: String = StudyCalendarFixture.seoul
    ) -> StudyPlanSettings {
        StudyCalendarFixture.settings(
            weekdays: weekdays,
            intensity: intensity,
            examDate: examDate,
            preferredStudyTime: preferredStudyTime,
            timeZone: timeZone
        )
    }

    private func reminders(
        settings: StudyPlanSettings? = nil,
        completions: [String: Int] = [:],
        now: Date? = nil
    ) -> [LocalNotificationRequest] {
        StudyReminderPlanner.reminders(
            settings: settings ?? self.settings(),
            completions: StudyCalendarFixture.completions(completions),
            now: now ?? self.now
        )
    }

    private func localDates(_ requests: [LocalNotificationRequest]) -> [String] {
        requests.map { $0.identifier.replacingOccurrences(
            of: StudyReminderPolicy.identifierPrefix,
            with: ""
        ) }
    }

    // MARK: A~C. 전 플랜 공통 (P4 유료 잠금 폐기)

    /// A+B. 무료·베이직·플러스·프로 모두 학습 알림을 받는다.
    /// 예약 판단에 플랜이 **입력으로 들어가지 않는다**는 것이 이 테스트의 요지다.
    @Test func everyPlanReceivesStudyReminders() async {
        for plan in PlanEntitlement.allCases {
            let harness = ReminderServiceHarness()
            defer { harness.tearDown() }
            let policy = CalendarFeaturePolicy.fallback(for: plan)

            await harness.service.reconcile(reminders())

            #expect(!harness.center.studyReminderIdentifiers.isEmpty, "\(plan) 잠김")
            // 자동화 권한(플랜별로 다름)은 알림 여부를 바꾸지 않는다.
            #expect(policy.canUseEventReminder == plan.isPaid)
        }
    }

    /// C. 구버전 서버가 무료에게 `calendarStudyReminder=false`를 내려도 잠기지 않는다.
    /// 그 값은 이제 학습 알림 게이트가 아니다.
    @Test func legacyBackendFalseDoesNotLockStudyReminder() async {
        let legacy = StudyCalendarFixture.capabilities(
            plan: "free",
            autoReplan: false,
            studyReminder: false
        )
        // 값은 그대로 읽되(진단용), 이 값으로 잠그는 코드가 어디에도 없다.
        #expect(legacy.quotaPolicy.calendarStudyReminder == false)

        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())

        #expect(!harness.center.studyReminderIdentifiers.isEmpty)
    }

    // MARK: D~F. 기본 ON과 명시적 선택

    /// D. 고른 적 없음 + 권한 있음 → 켜진 것으로 본다.
    @Test func unspecifiedPreferenceDefaultsOnWhenAuthorized() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        #expect(harness.service.preference == .unspecified)
        #expect(harness.service.isEnabled)

        await harness.service.reconcile(reminders())

        #expect(!harness.center.studyReminderIdentifiers.isEmpty)
        #expect(StudyReminderSettingsState.make(
            preference: .unspecified,
            authorization: .authorized
        ) == StudyReminderSettingsState(
            isOn: true,
            statusText: "매일 정한 시간에 알려드려요",
            requestsPermissionOnEnable: false
        ))
    }

    /// E. 직접 끈 선택은 앱을 다시 켜도 유지되고, 어떤 자동 경로도 되켜지 않는다.
    @Test func explicitOffSurvivesReload() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())
        #expect(!harness.center.studyReminderIdentifiers.isEmpty)

        await harness.service.disable()
        #expect(harness.center.studyReminderIdentifiers.isEmpty)

        #expect(harness.reloadedPreferences().studyReminderPreference == .disabled)
        let reopened = StudyReminderService(
            preferences: harness.reloadedPreferences(),
            center: harness.center
        )
        await reopened.reconcile(reminders())

        #expect(!reopened.isEnabled)
        #expect(harness.center.studyReminderIdentifiers.isEmpty)
        #expect(StudyReminderSettingsState.make(
            preference: .disabled,
            authorization: .authorized
        ).statusText == "학습 알림이 꺼져 있어요")
    }

    /// F. 직접 켠 선택도 그대로 남는다.
    @Test func explicitOnSurvivesReload() async {
        let harness = ReminderServiceHarness(status: .notDetermined)
        defer { harness.tearDown() }

        await harness.service.enable()

        #expect(harness.reloadedPreferences().studyReminderPreference == .enabled)
    }

    /// 구버전 Bool 이관: 저장된 true만 명시적 ON이 된다.
    /// (P4의 무료 회수 경로가 동의 없이 써 넣은 false는 "직접 껐다"가 아니다.)
    @Test func legacyBoolPreferenceMigratesConservatively() {
        let suite = "DailyOPIcTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "native_study_reminders_enabled")
        #expect(AppPreferences(defaults: defaults).studyReminderPreference == .enabled)

        defaults.set(false, forKey: "native_study_reminders_enabled")
        #expect(AppPreferences(defaults: defaults).studyReminderPreference == .unspecified)
    }

    // MARK: G~H. 권한

    /// G. 화면을 열거나 일정을 맞추는 것만으로는 권한 창이 뜨지 않는다.
    @Test func reconciliationNeverRequestsPermissionByItself() async {
        let harness = ReminderServiceHarness(status: .notDetermined)
        defer { harness.tearDown() }

        await harness.service.reconcile(reminders())

        #expect(harness.center.authorizationRequestCount == 0)
        #expect(harness.center.studyReminderIdentifiers.isEmpty)
        // 아직 물어본 적이 없으므로 설정 화면은 꺼진 스위치를 보여준다(켜는 행동 = 의도적 허용).
        let state = StudyReminderSettingsState.make(
            preference: .unspecified,
            authorization: .notDetermined
        )
        #expect(!state.isOn)
        #expect(state.requestsPermissionOnEnable)
    }

    /// 사용자가 직접 켤 때만 시스템 권한을 요청한다.
    @Test func explicitEnableRequestsPermissionOnce() async {
        let harness = ReminderServiceHarness(status: .notDetermined)
        defer { harness.tearDown() }

        let status = await harness.service.enable()

        #expect(harness.center.authorizationRequestCount == 1)
        #expect(status == .authorized)
        #expect(harness.service.isEnabled)
    }

    /// H. 거부한 사용자에게 권한 창을 다시 들이밀지 않는다.
    @Test func deniedNeverPromptsAgain() async {
        let harness = ReminderServiceHarness(status: .denied)
        defer { harness.tearDown() }

        await harness.service.enable()
        await harness.service.enable()
        await harness.service.requestAuthorizationIfNeeded()
        await harness.service.reconcile(reminders())

        #expect(harness.center.authorizationRequestCount == 0)
        #expect(harness.center.studyReminderIdentifiers.isEmpty)
        #expect(harness.service.needsSystemPermission)
        #expect(StudyReminderSettingsState.make(
            preference: .enabled,
            authorization: .denied
        ).statusText == "iPhone 설정에서 알림을 허용해 주세요")
    }

    /// 설정에서 권한을 다시 허용하면, 앱에서 다시 켜지 않아도 예약이 살아난다.
    @Test func restoredAuthorizationResumesReminders() async {
        let harness = ReminderServiceHarness(status: .denied)
        defer { harness.tearDown() }

        await harness.service.reconcile(reminders())
        #expect(harness.center.studyReminderIdentifiers.isEmpty)

        harness.center.status = .authorized
        await harness.service.reconcile(reminders())

        #expect(!harness.center.studyReminderIdentifiers.isEmpty)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    // MARK: I~L. 예약 규칙

    /// I. 휴식일에도 알림이 간다. 배정량 0이 "알리지 않을 이유"가 되지 않는다(P9).
    @Test func restDaysAlsoReceiveReminders() {
        let dates = Set(localDates(reminders()))

        #expect(dates.contains("2026-08-14")) // 금 · 학습일
        #expect(dates.contains("2026-08-15")) // 토 · 휴식일
        #expect(dates.contains("2026-08-16")) // 일 · 휴식일
        // 공부 요일을 화·목만 남겨도 나머지 날의 알림이 사라지지 않는다.
        let narrow = Set(localDates(reminders(settings: settings(weekdays: [.tuesday, .thursday]))))
        #expect(narrow.contains("2026-08-15"))
    }

    /// J. 오늘 한 세트라도 실제로 마쳤으면 오늘 알림은 사라진다(내일 것은 남는다).
    @Test func oneRealCompletionCancelsTodayReminder() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())
        #expect(harness.center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-14"))

        await harness.service.reconcile(reminders(completions: ["2026-08-14": 1]))

        #expect(!harness.center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-14"))
        #expect(harness.center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-15"))
    }

    /// K. 배정 3세트 중 1세트만 했어도 오늘 알림은 사라진다.
    /// "다 채워야 취소"(P4)로 되돌아가면 오늘 이미 공부한 사람을 또 부른다.
    @Test func partialCompletionStillCancelsTodayReminder() {
        let today = StudyCalendarFixture.date("2026-08-14")
        let outcome = StudyReminderPlanner.outcome(
            for: today,
            settings: settings(intensity: .focused),
            completions: StudyCalendarFixture.completions(["2026-08-14": 1]),
            now: now
        )

        #expect(outcome == .skipped(.alreadyLearnedToday))
        #expect(outcome.reason.rawValue == "already_learned_today")
    }

    /// L. 시험 당일에는 일반 학습 알림을 보내지 않는다(전용 경험은 P12).
    @Test func examDayIsStillExcluded() {
        let dates = Set(localDates(reminders(settings: settings(examDate: "2026-08-21"))))

        #expect(!dates.contains("2026-08-21"))
        #expect(dates.contains("2026-08-20"))
    }

    /// 오늘의 공부 시간이 지났으면 오늘은 늦은 알림을 만들지 않는다.
    @Test func passedPreferredTimeSkipsToday() {
        let evening = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(22 * 3600)
        let dates = Set(localDates(reminders(now: evening)))

        #expect(!dates.contains("2026-08-14"))
        #expect(dates.contains("2026-08-15"))
    }

    /// 하루 한 개, 식별자는 로컬 날짜로 결정된다. 예약 지평은 30일을 넘지 않는다.
    @Test func oneDeterministicReminderPerDayWithinHorizon() {
        let requests = reminders()
        let dates = localDates(requests)

        #expect(Set(dates).count == dates.count)
        #expect(requests.first?.identifier == "dailyopic.study-reminder.2026-08-14")
        #expect(requests.count <= StudyReminderPolicy.horizonDays)
        #expect(dates.allSatisfy { $0 < "2026-09-13" })
        #expect(localDates(reminders()) == dates)
    }

    /// 알림 시각은 학습 설정의 공부 시간 그대로이고, 날짜·시각은 학습 계획 타임존으로 정해진다.
    @Test func preferredTimeAndPlanTimezoneDecideTheTrigger() {
        let request = reminders(
            settings: settings(preferredStudyTime: StudyTimeOfDay(hour: 7, minute: 30))
        ).first
        #expect(request?.dateComponents.hour == 7)
        #expect(request?.dateComponents.minute == 30)

        let newYork = "America/New_York"
        let abroad = reminders(
            settings: settings(timeZone: newYork),
            now: StudyCalendarFixture.date("2026-08-14", timeZone: newYork)
                .addingTimeInterval(8 * 3600)
        ).first
        #expect(abroad?.dateComponents.timeZone == TimeZone(identifier: newYork))
        #expect(abroad?.dateComponents.hour == 21)
        #expect(abroad?.identifier == "dailyopic.study-reminder.2026-08-14")
    }

    /// 시간을 바꾸면 같은 날짜의 예약이 새 시각으로 교체된다(중복되지 않는다).
    @Test func changingPreferredStudyTimeReplacesExistingRequest() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())
        #expect(harness.center.components(for: "2026-08-14")?.hour == 21)

        await harness.service.reconcile(
            reminders(settings: settings(preferredStudyTime: StudyTimeOfDay(hour: 19, minute: 15)))
        )

        #expect(harness.center.components(for: "2026-08-14")?.hour == 19)
        #expect(harness.center.components(for: "2026-08-14")?.minute == 15)
        #expect(harness.center.studyReminderIdentifiers.filter { $0.hasSuffix("2026-08-14") }.count == 1)
    }

    /// 같은 입력으로 두 번 돌려도 결과가 같다.
    @Test func repeatedReconciliationIsIdempotent() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }

        await harness.service.reconcile(reminders())
        let first = harness.center.studyReminderIdentifiers
        await harness.service.reconcile(reminders())

        #expect(harness.center.studyReminderIdentifiers == first)
        #expect(Set(first).count == first.count)
    }

    /// 우리 네임스페이스만 건드린다. 다른 알림은 그대로 둔다.
    @Test func onlyOwnIdentifierNamespaceIsRemoved() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        harness.center.pending = [
            UNNotificationRequest(
                identifier: "someone.else.reminder",
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        ]

        await harness.service.reconcile(reminders())
        await harness.service.disable()

        #expect(harness.center.pending.map(\.identifier) == ["someone.else.reminder"])
    }

    // MARK: M. 문구

    /// M. 문구는 제품 진실 그대로다. 자책·마감 압박·점수 약속이 없다.
    @Test func copyMatchesProductTruth() {
        let requests = reminders(settings: settings(examDate: "2026-08-21"))

        #expect(requests.allSatisfy { $0.title == "데일리오픽 할 시간!" })
        #expect(requests.allSatisfy { $0.body == "하루 한 문제부터, 오늘도 가볍게 시작해볼까요?" })
        let banned = ["못 채", "남았", "놓", "뒤처", "점수", "등급", "업그레이드", "플랜", "구독", "세트"]
        #expect(requests.allSatisfy { request in
            banned.allSatisfy { !request.body.contains($0) && !request.title.contains($0) }
        })
    }

    // MARK: nil vs [] (P1 회귀)

    /// 앱이 켜지는 순간의 재조정은 계획을 읽기 전에 돌 수 있다.
    /// 이때(일정 모름 = nil) 앞으로의 멀쩡한 예약을 지우면 알림이 영영 오지 않는다.
    @Test func unknownScheduleNeverErasesPendingReminders() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())
        let scheduled = harness.center.studyReminderIdentifiers
        #expect(!scheduled.isEmpty)

        await harness.service.reconcile(nil)

        #expect(harness.center.studyReminderIdentifiers == scheduled)
    }

    /// "모른다"와 "예약할 것이 없다"는 다르다. 계획을 알고 비어 있으면 걷어낸다.
    @Test func knownEmptyScheduleStillClearsReminders() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())
        #expect(!harness.center.studyReminderIdentifiers.isEmpty)

        await harness.service.reconcile([])

        #expect(harness.center.studyReminderIdentifiers.isEmpty)
    }

    /// 일정을 모르는 동안에도 권한 상태는 최신으로 만든다.
    @Test func unknownScheduleStillRefreshesAuthorizationStatus() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        #expect(harness.service.authorizationStatus == .notDetermined)

        await harness.service.reconcile(nil)

        #expect(harness.service.authorizationStatus == .authorized)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    /// 학습 시간에 앱을 보고 있어도 알림이 뜬다.
    /// delegate가 이 옵션을 돌려주지 않으면 iOS가 포그라운드 알림을 조용히 버린다.
    @Test func foregroundStudyReminderIsPresentedWithBannerAndSound() {
        let options = StudyReminderPresentation.options(
            for: StudyReminderPolicy.identifier(forLocalDate: "2026-08-14")
        )

        #expect(options.contains(.banner))
        #expect(options.contains(.sound))
        #expect(options.contains(.list))
        #expect(StudyReminderPresentation.options(for: "someone.else.reminder").isEmpty)
    }
}
