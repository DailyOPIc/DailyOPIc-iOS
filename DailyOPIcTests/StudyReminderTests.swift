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

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        status = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }

    func pendingRequests() async -> [UNNotificationRequest] { pending }

    func add(_ request: UNNotificationRequest) async {
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePendingRequests(identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    var studyReminderIdentifiers: [String] {
        pending.map(\.identifier).filter(StudyReminderPolicy.isStudyReminder).sorted()
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

/// G5: 학습 알림은 "공부하기로 한 날, 정한 시간에 한 번"만 울린다.
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

    /// 목표 IH · 최근 IH → 권장 20세트. 강도 꾸준히 · 토큰 2 → 하루 2세트.
    private func plan(
        settings: StudyPlanSettings,
        recentLevel: OPIcLevel? = .IH,
        dailyCapacity: Int = 2,
        completions: [Date: Int] = [:],
        policy: CalendarFeaturePolicy = .everything
    ) -> AdaptiveStudyPlan {
        AdaptiveStudyPlanner.plan(
            settings: settings,
            targetLevel: .IH,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            completions: completions,
            policy: policy,
            today: now
        )
    }

    private func reminders(
        settings: StudyPlanSettings? = nil,
        recentLevel: OPIcLevel? = .IH,
        dailyCapacity: Int = 2,
        completions: [String: Int] = [:],
        policy: CalendarFeaturePolicy = .everything,
        now: Date? = nil
    ) -> [StudyReminderRequest] {
        let settings = settings ?? self.settings()
        let counts = StudyCalendarFixture.completions(completions)
        return StudyReminderPlanner.reminders(
            plan: plan(
                settings: settings,
                recentLevel: recentLevel,
                dailyCapacity: dailyCapacity,
                completions: counts,
                policy: policy
            ),
            settings: settings,
            completions: counts,
            now: now ?? self.now
        )
    }

    private func localDates(_ requests: [StudyReminderRequest]) -> [String] {
        requests.map { $0.identifier.replacingOccurrences(
            of: StudyReminderPolicy.identifierPrefix,
            with: ""
        ) }
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

    // MARK: 권한

    /// 1. 화면을 열거나 일정을 맞추는 것만으로는 권한 창이 뜨지 않는다.
    @Test func reconciliationNeverRequestsPermissionByItself() async {
        let center = FakeNotificationCenter()
        center.status = .notDetermined
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())

        #expect(center.authorizationRequestCount == 0)
        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// 2. 사용자가 직접 켤 때만 시스템 권한을 요청한다.
    @Test func explicitEnableRequestsPermissionOnce() async {
        let center = FakeNotificationCenter()
        center.status = .notDetermined
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        let status = await service.enable()

        #expect(center.authorizationRequestCount == 1)
        #expect(status == .authorized)
        #expect(service.isEnabled)
    }

    /// 3. 권한 + 앱 설정이 모두 켜져야 예약된다.
    @Test func authorizedAndEnabledSchedulesReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())

        #expect(service.isActive)
        #expect(!center.studyReminderIdentifiers.isEmpty)
    }

    /// 4. 거부 상태에서는 아무것도 예약하지 않는다.
    @Test func deniedSchedulesNothing() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(service.needsSystemPermission)
    }

    /// 5. 거부한 사용자에게 권한 창을 다시 들이밀지 않는다.
    @Test func deniedNeverPromptsAgain() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.enable()
        await service.enable()
        await service.reconcile(reminders())

        #expect(center.authorizationRequestCount == 0)
    }

    /// 25. 설정에서 권한을 다시 허용하면, 앱에서 다시 켜지 않아도 예약이 살아난다.
    @Test func restoredAuthorizationResumesLocallyEnabledReminders() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())
        #expect(center.studyReminderIdentifiers.isEmpty)

        center.status = .authorized
        await service.reconcile(reminders())

        #expect(!center.studyReminderIdentifiers.isEmpty)
        #expect(center.authorizationRequestCount == 0)
    }

    /// 24. 앱에서 꺼 뒀으면 캘린더 상태와 무관하게 예약하지 않는다.
    @Test func locallyDisabledSchedulesNothingEvenWhenAuthorized() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())

        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// 6. 끄면 우리 알림을 걷어낸다.
    @Test func disablingRemovesScheduledReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        #expect(!center.studyReminderIdentifiers.isEmpty)

        await service.disable()

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(!service.isEnabled)
    }

    /// 22. 우리 네임스페이스만 건드린다. 다른 알림은 그대로 둔다.
    @Test func onlyOwnIdentifierNamespaceIsRemoved() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let foreign = UNNotificationRequest(
            identifier: "someone.else.reminder",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        center.pending = [foreign]
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())
        await service.disable()

        #expect(center.pending.map(\.identifier) == ["someone.else.reminder"])
    }

    // MARK: 예약 일정

    /// 7 + 13(부분 완료 복사본까지). 같은 입력으로 두 번 돌려도 결과가 같다.
    @Test func repeatedReconciliationIsIdempotent() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders())
        let first = center.studyReminderIdentifiers
        await service.reconcile(reminders())

        #expect(center.studyReminderIdentifiers == first)
        #expect(Set(first).count == first.count)
    }

    /// 8 + 21. 하루 한 개, 식별자는 로컬 날짜로 결정된다.
    @Test func atMostOneDeterministicReminderPerLocalDate() {
        let requests = reminders()
        let dates = localDates(requests)

        #expect(Set(dates).count == dates.count)
        #expect(requests.first?.identifier == "dailyopic.study-reminder.2026-08-14")
        #expect(localDates(reminders()) == dates)
    }

    /// 9 + 10. 학습일에만 알린다. 휴식일에는 알리지 않는다.
    @Test func onlyScheduledStudyDaysGetReminders() {
        let dates = Set(localDates(reminders()))

        #expect(dates.contains("2026-08-14"))  // 금
        #expect(dates.contains("2026-08-17"))  // 월
        #expect(!dates.contains("2026-08-15")) // 토
        #expect(!dates.contains("2026-08-16")) // 일
    }

    /// 11. 권장 학습을 다 끝냈으면 앞으로의 알림이 사라진다.
    @Test func completedPlanRemovesAllReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        #expect(!center.studyReminderIdentifiers.isEmpty)

        // 권장 20세트를 모두 채운 상태.
        let finished = reminders(completions: ["2026-08-13": 20])
        await service.reconcile(finished)

        #expect(finished.isEmpty)
        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// 12 + 14. 오늘 계획을 알림 시각 전에 다 끝내면 오늘 알림만 사라진다.
    @Test func completingTodayBeforeReminderTimeCancelsTodayOnly() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        #expect(center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-14"))

        await service.reconcile(reminders(completions: ["2026-08-14": 2]))

        #expect(!center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-14"))
        #expect(center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-17"))
    }

    /// 13. 일부만 했으면 남은 만큼만 말한다. 자책하게 만드는 표현을 쓰지 않는다.
    @Test func partialCompletionUsesRemainingSetCopy() {
        let today = reminders(completions: ["2026-08-14": 1]).first

        #expect(today?.body == "오늘 계획까지 1세트 남았어요.")
        #expect(reminders().first?.body == "오늘 Daily 연습 2세트가 예정되어 있어요.")
        #expect(reminders().first?.title == "오늘의 Daily 학습")
    }

    /// 15. 알림 시각은 학습 설정의 공부 시간 그대로다.
    @Test func preferredStudyTimeIsUsedExactly() {
        let request = reminders(
            settings: settings(preferredStudyTime: StudyTimeOfDay(hour: 7, minute: 30))
        ).first

        #expect(request?.dateComponents.hour == 7)
        #expect(request?.dateComponents.minute == 30)
    }

    /// 16. 시간을 바꾸면 같은 날짜의 예약이 새 시각으로 교체된다(중복되지 않는다).
    @Test func changingPreferredStudyTimeReplacesExistingRequest() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        #expect(center.components(for: "2026-08-14")?.hour == 21)

        await service.reconcile(
            reminders(settings: settings(preferredStudyTime: StudyTimeOfDay(hour: 19, minute: 15)))
        )

        #expect(center.components(for: "2026-08-14")?.hour == 19)
        #expect(center.components(for: "2026-08-14")?.minute == 15)
        let today = center.studyReminderIdentifiers.filter { $0.hasSuffix("2026-08-14") }
        #expect(today.count == 1)
    }

    /// 17. 학습 요일을 바꾸면 더 이상 학습일이 아닌 날의 예약이 사라진다.
    @Test func changingWeekdaysRemovesStaleReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        #expect(center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-17"))

        // 화·목만 학습일로 바꾼다.
        await service.reconcile(reminders(settings: settings(weekdays: [.tuesday, .thursday])))

        #expect(!center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-17"))
        #expect(center.studyReminderIdentifiers.contains("dailyopic.study-reminder.2026-08-18"))
    }

    /// 18. 강도를 바꾸면 그날 배정량이 달라지고 문구도 따라간다.
    @Test func changingIntensityReconcilesTargets() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        await service.reconcile(reminders(dailyCapacity: 3))
        #expect(center.body(for: "2026-08-14") == "오늘 Daily 연습 2세트가 예정되어 있어요.")

        await service.reconcile(
            reminders(settings: settings(intensity: .light), dailyCapacity: 3)
        )

        #expect(center.body(for: "2026-08-14") == "오늘 Daily 연습 1세트가 예정되어 있어요.")
    }

    /// 19 + 시험 맥락. 시험 당일에는 학습 숙제 알림을 보내지 않고,
    /// 남은 날짜는 절제된 한 줄로만 덧붙인다(합격 확률·불안 문구 없음).
    @Test func examDayGetsNoStudyReminderAndContextStaysRestrained() {
        let requests = reminders(settings: settings(examDate: "2026-08-21"))
        let dates = Set(localDates(requests))

        #expect(!dates.contains("2026-08-21"))
        #expect(dates.contains("2026-08-20"))
        #expect(requests.first?.body.hasPrefix("시험까지 7일 · ") == true)
        // 시험이 멀면 D-day를 붙이지 않는다.
        let farExam = reminders(settings: settings(examDate: "2026-10-01"))
        #expect(farExam.first?.body.contains("시험까지") == false)
    }

    /// 20. 날짜·시각은 기기 타임존이 아니라 학습 계획 타임존으로 정해진다.
    @Test func studyPlanTimezoneControlsScheduling() {
        let newYork = "America/New_York"
        let settings = settings(timeZone: newYork)
        let requests = StudyReminderPlanner.reminders(
            plan: plan(settings: settings),
            settings: settings,
            completions: [:],
            // 뉴욕 기준으로는 아직 8/13 저녁이다.
            now: StudyCalendarFixture.date("2026-08-14", timeZone: newYork)
                .addingTimeInterval(8 * 3600)
        )

        #expect(requests.first?.dateComponents.timeZone == TimeZone(identifier: newYork))
        #expect(requests.first?.dateComponents.hour == 21)
        #expect(requests.first?.identifier == "dailyopic.study-reminder.2026-08-14")
    }

    /// 23. 앞으로 예약해 두는 기간은 정해진 창을 넘지 않는다.
    @Test func rollingHorizonIsBounded() {
        // 하루 1세트로 44세트 → 계획은 30일보다 훨씬 길다.
        let requests = reminders(recentLevel: nil, dailyCapacity: 1)

        #expect(requests.count > 10)
        #expect(requests.count <= StudyReminderPolicy.horizonDays)
        #expect(localDates(requests).allSatisfy { $0 < "2026-09-13" })
    }

    // MARK: 플랜 변경

    /// 27. 무료도 쓸모 있는 알림을 받는다. 알림은 유료 잠금이 아니다.
    @Test func freeReceivesUsefulReminders() {
        let requests = reminders(recentLevel: nil, policy: .free)

        #expect(!requests.isEmpty)
        #expect(localDates(requests).contains("2026-08-14"))
        #expect(requests.first?.body.contains("세트") == true)
        #expect(requests.allSatisfy { !$0.body.contains("잠") && !$0.body.contains("플랜") })
    }

    /// 28. 자동 재조정(베이직+)이 켜지면 앞으로의 배정량이 달라지고 알림도 따라간다.
    @Test func autoReplanChangesReminderTargets() {
        // 44세트 · 하루 3세트 → 마지막 날에 2세트만 남는다. 자동 재조정이 없으면 늘 3세트다.
        func lastBody(_ policy: CalendarFeaturePolicy) -> String? {
            reminders(
                settings: settings(intensity: .focused),
                recentLevel: nil,
                dailyCapacity: 3,
                policy: policy
            ).last?.body
        }

        #expect(lastBody(.free) == "오늘 Daily 연습 3세트가 예정되어 있어요.")
        #expect(lastBody(.fallback(for: .basic)) == "오늘 Daily 연습 2세트가 예정되어 있어요.")
    }

    /// 29. 시험일 역산(플러스·프로)이 켜지면 시험 전 배정량이 달라지고 알림도 따라간다.
    @Test func examBackplanChangesReminderTargets() {
        func requests(_ policy: CalendarFeaturePolicy) -> [StudyReminderRequest] {
            reminders(
                // 평소 속도(하루 1세트)로는 시험 전에 못 끝낸다 → 역산이 켜지면 배정량이 올라간다.
                settings: settings(intensity: .light, examDate: "2026-09-04"),
                recentLevel: nil,
                dailyCapacity: 3,
                policy: policy
            )
        }

        let backplanned = requests(.fallback(for: .plus))
        #expect(backplanned.map(\.body) != requests(.fallback(for: .basic)).map(\.body))
        #expect(requests(.fallback(for: .pro)).map(\.body) == backplanned.map(\.body))
        // 어느 플랜에서도 시험 당일에는 숙제 알림을 만들지 않는다.
        #expect(!localDates(backplanned).contains("2026-09-04"))
        #expect(!localDates(requests(.fallback(for: .basic))).contains("2026-09-04"))
    }

    /// 30. 플랜이 바뀌어도 지난 기록은 그대로다. 알림은 오늘 이후만 만든다.
    @Test func planChangeDoesNotAlterHistoricalRecords() {
        let settings = settings()
        // 지난 날의 배정량은 자동화 권한을 보지 않는다(§18.6).
        let historical = AdaptiveStudyPlanner.historicalTargets(
            settings: settings,
            baseDailyTarget: 2,
            today: now
        )

        #expect(!historical.isEmpty)
        #expect(historical["2026-08-13"] == 2)
        for policy in [CalendarFeaturePolicy.free, .fallback(for: .basic), .everything] {
            let dates = localDates(reminders(settings: settings, policy: policy))
            #expect(dates.allSatisfy { $0 >= "2026-08-14" })
        }
    }

    /// 플랜이 바뀌어도 알림은 그대로 온다(유료 잠금이 아니다).
    /// 자동화 권한만큼 앞으로의 일정이 달라지고, 지난 기록은 건드리지 않는다.
    @Test func planChangeReconcilesFutureOnlyAndNeverLocksReminders() {
        let free = reminders(policy: .free)
        let plus = reminders(policy: .everything)

        #expect(!free.isEmpty)
        #expect(!plus.isEmpty)
        #expect(free.allSatisfy { !$0.body.contains("업그레이드") })
        // 예약은 오늘 이후만 만든다. 지난 날짜는 어느 플랜에서도 나오지 않는다.
        #expect((free + plus).allSatisfy { localDates([$0])[0] >= "2026-08-14" })
    }

    // MARK: 전달 (P1 회귀)

    /// P1-1. 앱이 켜지는 순간의 재조정은 계획을 읽기 전에 돌 수 있다.
    /// 이때(일정 모름 = nil) 앞으로의 멀쩡한 예약을 지우면 알림이 영영 오지 않는다.
    @Test func unknownScheduleNeverErasesPendingReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        let scheduled = center.studyReminderIdentifiers
        #expect(!scheduled.isEmpty)

        await service.reconcile(nil)

        #expect(center.studyReminderIdentifiers == scheduled)
    }

    /// P1-2. "모른다"와 "예약할 것이 없다"는 다르다. 계획을 알고 비어 있으면 걷어낸다.
    @Test func knownEmptyScheduleStillClearsReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        await service.reconcile(reminders())
        #expect(!center.studyReminderIdentifiers.isEmpty)

        await service.reconcile([])

        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// P1-3. 일정을 모르는 동안에도 권한 상태는 최신으로 만든다.
    /// (설정에서 권한을 켜고 돌아왔을 때 카드가 꺼진 상태로 남지 않는다.)
    @Test func unknownScheduleStillRefreshesAuthorizationStatus() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, defaults, suite) = service(center: center, enabled: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(service.authorizationStatus == .notDetermined)

        await service.reconcile(nil)

        #expect(service.authorizationStatus == .authorized)
        #expect(center.authorizationRequestCount == 0)
    }

    /// P1-4. 학습 시간에 앱을 보고 있어도 알림이 뜬다.
    /// delegate가 이 옵션을 돌려주지 않으면 iOS가 포그라운드 알림을 조용히 버린다.
    @Test func foregroundStudyReminderIsPresentedWithBannerAndSound() {
        let options = StudyReminderPresentation.options(
            for: StudyReminderPolicy.identifier(forLocalDate: "2026-08-14")
        )

        #expect(options.contains(.banner))
        #expect(options.contains(.sound))
        #expect(options.contains(.list))
        // 우리 알림이 아니면 표시 방식을 바꾸지 않는다.
        #expect(StudyReminderPresentation.options(for: "someone.else.reminder").isEmpty)
    }

    /// 26. 알림 문구에는 답변·전사·UID·점수가 들어가지 않는다. 고정 템플릿뿐이다.
    @Test func notificationCopyCarriesNoUserContent() {
        let requests = reminders(settings: settings(examDate: "2026-08-21"))
        let allowed = ["오늘의 Daily 학습"]

        #expect(requests.allSatisfy { allowed.contains($0.title) })
        #expect(requests.allSatisfy { $0.body.contains("세트") })
        #expect(requests.allSatisfy { !$0.body.contains("점") && !$0.body.contains("등급") })
        #expect(requests.allSatisfy { !$0.body.contains("놓") && !$0.body.contains("뒤처") })
    }
}
