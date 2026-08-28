import Foundation
import Testing
import UserNotifications
@testable import DailyOPIc

/// P7: "왜 실기기에 알림이 안 오는가"를 코드가 스스로 설명할 수 있어야 한다.
///
/// 근본 원인은 **자격을 아직 모르는 상태를 무료로 단정한 것**이었다. 앱이 켜지는 순간
/// RevenueCat도 서버도 대답하기 전인데 `currentPlan`은 기본값 무료를 말하고, 재조정이
/// 그것을 강등으로 읽어 예약을 전부 지웠다.
///
/// P9에서 학습 알림은 전 플랜 공통이 되어 이 위험 자체가 사라졌고, 같은 보호가
/// **개인 일정 알림**으로 옮겨 갔다. 진단은 두 알림을 **따로** 설명해야 한다.
@MainActor
struct StudyReminderDiagnosticsTests {
    /// 2026-08-14(금) 오전 8시. 알림 시각(21:00) 이전이라 오늘 알림이 살아 있다.
    private let now = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(8 * 3600)

    private func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        examDate: String? = nil,
        preferredStudyTime: StudyTimeOfDay = StudyTimeOfDay(hour: 21, minute: 0)
    ) -> StudyPlanSettings {
        StudyCalendarFixture.settings(
            weekdays: weekdays,
            examDate: examDate,
            preferredStudyTime: preferredStudyTime
        )
    }

    private func reminders(
        settings: StudyPlanSettings? = nil,
        completions: [String: Int] = [:]
    ) -> [LocalNotificationRequest] {
        StudyReminderPlanner.reminders(
            settings: settings ?? self.settings(),
            completions: StudyCalendarFixture.completions(completions),
            now: now
        )
    }

    /// 오늘(2026-08-14) 판단 결과.
    private func outcome(
        settings: StudyPlanSettings? = nil,
        completions: [String: Int] = [:],
        on day: String = "2026-08-14",
        now: Date? = nil
    ) -> ReminderOutcome {
        StudyReminderPlanner.outcome(
            for: StudyCalendarFixture.date(day),
            settings: settings ?? self.settings(),
            completions: StudyCalendarFixture.completions(completions),
            now: now ?? self.now
        )
    }

    /// **실제 시계** 기준으로 미래인 알림들. 트리거 검증에는 픽스처 날짜(2026-08-14)를
    /// 쓸 수 없다 — `nextTriggerDate()`는 언제나 지금 시각으로 계산하므로 이미 지난
    /// 날짜의 트리거는 검증하려는 값을 돌려주지 않는다.
    private func futureReminders(now: Date = .now) -> [LocalNotificationRequest] {
        StudyReminderPlanner.reminders(
            settings: StudyCalendarFixture.settings(weekdays: Set(StudyWeekday.allCases)),
            completions: [:],
            now: now
        )
    }

    // MARK: A. 근본 원인 — 자격 미상

    /// **P7 회귀 테스트.** 자격을 아직 모를 때는 예약을 지우지 않는다.
    /// P9부터 이 보호가 붙는 곳은 개인 일정 알림이다.
    @Test func unknownEligibilityKeepsPendingEventReminders() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        let events = eventReminders()

        await harness.service.reconcileEventReminders(events, eligibility: .eligible)
        let scheduled = harness.center.eventReminderIdentifiers
        #expect(!scheduled.isEmpty)

        // 앱 재실행 직후: 아직 RevenueCat도 서버도 대답하지 않았다.
        await harness.service.reconcileEventReminders(nil, eligibility: .unknown)

        #expect(harness.center.eventReminderIdentifiers == scheduled)
        #expect(harness.service.lastEventSkipReason == .entitlementUnknown)
    }

    /// 학습 알림은 자격 판단을 **거치지 않는다**. 플랜이 무엇이든, 확인 전이든 예약된다.
    @Test func studyRemindersNeverReportAnEntitlementReason() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }

        await harness.service.reconcile(reminders())

        #expect(!harness.center.studyReminderIdentifiers.isEmpty)
        #expect(harness.service.lastSkipReason == nil)
        // 무료라고 잠기는 경로가 남아 있지 않다(P4 정책 폐기).
        #expect(harness.service.lastSkipReason != .featureLocked)
        #expect(harness.service.lastSkipReason != .entitlementUnknown)
    }

    /// 앱이 켜지는 순간의 실제 조합. `currentPlan`의 기본값 무료는 "무료 사용자"가 아니다.
    @Test func launchBeforeEntitlementResolvesIsUnknownNotFree() {
        let store = StoreService()
        #expect(!store.isConfigured)
        #expect(!store.hasResolvedEntitlement)
        #expect(store.localEntitlement == .free)
        // 이 상태에서 무료 폴백 표는 **일정 알림**을 잠근다 — 그래서 미상 처리가 필요하다.
        #expect(!CalendarFeaturePolicy.resolve(capabilities: nil, plan: .free).canUseEventReminder)
        #expect(
            ReminderEligibility.resolve(isEntitlementResolved: false, isCapable: false) == .unknown
        )
    }

    /// 확인된 뒤에는 평소대로 갈린다.
    @Test func resolvedEntitlementDecidesNormally() {
        #expect(
            ReminderEligibility.resolve(isEntitlementResolved: true, isCapable: true) == .eligible
        )
        #expect(
            ReminderEligibility.resolve(isEntitlementResolved: true, isCapable: false) == .ineligible
        )
    }

    // MARK: B. 원한 목록 ≠ 실제 대기 목록

    /// iOS가 예약을 거절하면 desired와 pending이 갈라진다.
    /// 앱이 "원했다"는 사실은 예약됐다는 증거가 아니다.
    @Test func pendingCanDifferFromDesired() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        harness.center.addFailure = NotificationAddFailure(domain: "UNErrorDomain", code: 1)

        let desired = reminders()
        #expect(!desired.isEmpty)
        await harness.service.reconcile(desired)

        #expect(harness.center.studyReminderIdentifiers.isEmpty)
        #expect(harness.service.lastAddFailure?.code == 1)
        #expect(await harness.service.pendingSnapshot().count == 0)
    }

    /// 두 네임스페이스의 실패는 **따로** 남는다. 합치면 어느 쪽이 실패했는지 사라진다.
    @Test func eventAndStudyFailuresAreReportedSeparately() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }

        await harness.service.reconcile(reminders())
        harness.center.addFailure = NotificationAddFailure(domain: "UNErrorDomain", code: 7)
        await harness.service.reconcileEventReminders(eventReminders(), eligibility: .eligible)

        #expect(harness.service.lastAddFailure == nil)
        #expect(harness.service.lastEventAddFailure?.code == 7)
        #expect(await harness.service.pendingSnapshot().count > 0)
        #expect(await harness.service.pendingEventSnapshot().count == 0)
    }

    /// 성공하면 실패 기록이 남지 않는다.
    @Test func successfulScheduleClearsAddFailure() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }

        await harness.service.reconcile(reminders())

        #expect(harness.service.lastAddFailure == nil)
        let snapshot = await harness.service.pendingSnapshot()
        #expect(snapshot.count == harness.center.studyReminderIdentifiers.count)
    }

    // MARK: C. 건너뛴 이유 분류

    private func diagnosis(
        eligibility: ReminderEligibility = .eligible,
        isEnabled: Bool = true,
        authorization: UNAuthorizationStatus = .authorized,
        desired: [LocalNotificationRequest]? = nil,
        todayOutcome: ReminderOutcome? = nil
    ) -> ReminderDiagnosis {
        ReminderDiagnosis.make(
            eligibility: eligibility,
            isEnabled: isEnabled,
            authorization: authorization,
            desired: desired ?? reminders(),
            todayOutcome: todayOutcome ?? outcome()
        )
    }

    @Test func classifiesEntitlementUnknown() {
        let diagnosis = diagnosis(eligibility: .unknown)
        #expect(diagnosis.reason == .entitlementUnknown)
        #expect(diagnosis.reason.rawValue == "entitlement_unknown")
        #expect(!diagnosis.isScheduledToday)
    }

    @Test func classifiesFeatureLocked() {
        #expect(diagnosis(eligibility: .ineligible).reason == .featureLocked)
    }

    @Test func classifiesUserDisabled() {
        #expect(diagnosis(isEnabled: false).reason == .userDisabled)
    }

    @Test func classifiesPermissionStates() {
        #expect(diagnosis(authorization: .notDetermined).reason == .permissionNotDetermined)
        #expect(diagnosis(authorization: .denied).reason == .permissionDenied)
        // provisional/ephemeral은 조용히 전달되므로 예약을 막지 않는다.
        #expect(diagnosis(authorization: .provisional).reason == .requestGenerated)
    }

    @Test func classifiesScheduleUnknown() {
        let diagnosis = ReminderDiagnosis.make(
            eligibility: .eligible,
            isEnabled: true,
            authorization: .authorized,
            desired: nil,
            todayOutcome: nil
        )
        #expect(diagnosis.reason == .scheduleUnknown)
        #expect(diagnosis.desiredCount == nil)
    }

    /// P9: 휴식일이라는 이유로 건너뛰지 않는다. 2026-08-15는 토요일이다.
    @Test func restDayIsNoLongerASkipReason() {
        #expect(outcome(on: "2026-08-15").reason == .requestGenerated)
        #expect(!ReminderSkipReason.allCases.map(\.rawValue).contains("rest_day"))
        #expect(!ReminderSkipReason.allCases.map(\.rawValue).contains("target_complete"))
    }

    /// P9: 오늘 **한 세트라도** 했으면 그것이 이유다. 배정을 다 채웠는지는 보지 않는다.
    @Test func classifiesAlreadyLearnedToday() {
        #expect(outcome(completions: ["2026-08-14": 1]) == .skipped(.alreadyLearnedToday))
        #expect(outcome(completions: ["2026-08-14": 5]) == .skipped(.alreadyLearnedToday))
        #expect(ReminderSkipReason.alreadyLearnedToday.rawValue == "already_learned_today")
    }

    /// 공부 시간(21:00)이 지난 뒤에 재조정하면 오늘은 예약하지 않는다.
    @Test func classifiesPreferredTimePassed() {
        let late = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(22 * 3600)
        #expect(outcome(now: late) == .skipped(.preferredTimePassed))
    }

    /// 시험 당일에는 일반 학습 알림을 보내지 않는다(전용 경험은 P12).
    @Test func classifiesExamDay() {
        #expect(outcome(settings: settings(examDate: "2026-08-14")) == .skipped(.examDay))
    }

    /// 30일 지평 밖.
    @Test func classifiesOutsideHorizon() {
        #expect(outcome(on: "2026-12-01") == .skipped(.outsideHorizon))
        // 지난 날짜도 예약 대상이 아니다.
        #expect(outcome(on: "2026-08-13") == .skipped(.outsideHorizon))
    }

    @Test func classifiesRequestGenerated() {
        let diagnosis = diagnosis()
        #expect(diagnosis.reason == .requestGenerated)
        #expect(diagnosis.isScheduledToday)
        #expect((diagnosis.desiredCount ?? 0) > 0)
    }

    /// 일정 알림 쪽 이유도 같은 고정 토큰 표에서 나온다.
    @Test func eventReminderReasonsAreTheSameFixedTable() {
        let tokens = Set(ReminderSkipReason.allCases.map(\.rawValue))
        for expected in [
            "feature_locked", "user_selected_none", "event_has_no_time",
            "permission_not_determined", "permission_denied", "trigger_time_passed",
            "entitlement_unknown", "request_generated",
        ] {
            #expect(tokens.contains(expected), "\(expected)")
        }
    }

    /// 예약 목록과 진단이 **같은 함수**를 쓴다: 오늘 예약이 있으면 목록에도 오늘이 있다.
    @Test func outcomeAgreesWithReminderList() {
        let today = StudyReminderPolicy.identifier(forLocalDate: "2026-08-14")
        #expect(outcome().request?.identifier == today)
        #expect(reminders().first?.identifier == today)
        // 오늘 이미 학습했다면 목록에서도 오늘이 빠진다.
        let learned = reminders(completions: ["2026-08-14": 1])
        #expect(!learned.contains { $0.identifier == today })
    }

    // MARK: D. 진단 출력에 사용자 콘텐츠가 없다

    /// 로그 한 줄에는 고정 값만 들어간다(문구·UID·메모·일정 제목·답변 없음).
    @Test func diagnosticOutputHasNoPrivateContent() {
        let requests = reminders()
        let line = diagnosis(desired: requests).logLine
        #expect(!line.contains(StudyReminderPlanner.title))
        for request in requests {
            #expect(!line.contains(request.body))
            #expect(!line.contains(request.identifier))
        }
        #expect(line.contains("reason=request_generated"))
        #expect(line.contains("eligibility=eligible"))
        #expect(line.contains("status=authorized"))
    }

    /// 일정 알림 진단도 마찬가지다. 일정 제목은 **알림 본문에만** 있다.
    @Test func eventDiagnosticOutputNeverCarriesTheEventTitle() {
        let events = eventReminders()
        let line = ReminderDiagnosis.make(
            eligibility: .eligible,
            isEnabled: true,
            authorization: .authorized,
            desired: events,
            todayOutcome: .scheduled(events[0])
        ).logLine
        #expect(!line.contains("면접"))
        #expect(events[0].body.contains("면접")) // 본문에는 있다(이 기기 밖으로 나가지 않는다)
        #expect(line.contains("desired=\(events.count)"))
    }

    /// 이유 값은 전부 고정 문자열이다(자유 텍스트가 섞이지 않는다).
    @Test func skipReasonsAreFixedTokens() {
        for reason in ReminderSkipReason.allCases {
            #expect(!reason.rawValue.isEmpty)
            #expect(reason.rawValue == reason.rawValue.lowercased())
            #expect(!reason.rawValue.contains(" "))
        }
    }

    // MARK: E. 트리거가 실제로 울릴 수 있는가

    /// DateComponents를 눈으로 보지 않고 **iOS가 계산한** 다음 발화 시각을 확인한다.
    @Test func triggerFiresAtIntendedLocalTime() throws {
        let request = try #require(futureReminders().first)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: request.dateComponents,
            repeats: false
        )
        let next = try #require(trigger.nextTriggerDate())

        // 1) 반드시 미래다. 과거 시각이면 iOS는 영원히 울리지 않는다.
        #expect(next > Date.now)
        // 2) 컴포넌트가 가리키는 그 순간과 정확히 같다(타임존까지 반영해 해석한 값).
        let calendar = StudyCalendarFixture.settings().calendar
        #expect(next == calendar.date(from: request.dateComponents))
        // 3) 계획 타임존의 21:00이다.
        #expect(request.dateComponents.timeZone == StudyCalendarFixture.seoulTimeZone)
        #expect(calendar.dateComponents([.hour, .minute], from: next).hour == 21)
        #expect(calendar.dateComponents([.hour, .minute], from: next).minute == 0)
    }

    /// 계획 타임존과 기기 타임존이 달라도 알림은 **계획 타임존의** 공부 시간에 울린다.
    @Test func triggerHonoursPlanTimeZoneNotDeviceTimeZone() throws {
        let request = try #require(futureReminders().first)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: request.dateComponents,
            repeats: false
        )
        let next = try #require(trigger.nextTriggerDate())

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(newYork.dateComponents([.hour], from: next).hour != 21)
        #expect(StudyCalendarFixture.settings().calendar
            .dateComponents([.hour], from: next).hour == 21)
    }

    /// pending 스냅샷은 트리거가 계산한 실제 발화 시각을 읽는다.
    @Test func pendingSnapshotReadsRealTriggerDate() async throws {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }

        let desired = futureReminders()
        await harness.service.reconcile(desired)
        let snapshot = await harness.service.pendingSnapshot()

        #expect(snapshot.count == desired.count)
        #expect(snapshot.nextTriggerTimeZone == "Asia/Seoul")
        let firstLocalDate = try #require(desired.first).identifier
            .replacingOccurrences(of: StudyReminderPolicy.identifierPrefix, with: "")
        #expect(snapshot.nextLocalDate == firstLocalDate)
        #expect(try #require(snapshot.nextTriggerDate) > Date.now)
    }

    /// 실제로 저장된 일정 알림도 같은 방식으로 "정말 대기 중인가"를 확인할 수 있다.
    @Test func pendingEventSnapshotInspectsRealSavedReminders() async throws {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        let events = futureEventReminders()

        await harness.service.reconcileEventReminders(events, eligibility: .eligible)
        let snapshot = await harness.service.pendingEventSnapshot()

        #expect(snapshot.count == events.count)
        #expect(snapshot.nextTriggerTimeZone == "Asia/Seoul")
        #expect(try #require(snapshot.nextTriggerDate) > Date.now)
        // 꼬리표는 일정 id다 — 제목이 아니다.
        #expect(snapshot.nextLocalDate?.contains("면접") == false)
    }

    // MARK: F. 포그라운드 표시 · DEBUG 자가 테스트

    /// 실제로 만들어지는 식별자가 포그라운드 표시 조건을 만족한다.
    @Test func realIdentifiersAreRecognizedForForegroundPresentation() throws {
        let study = try #require(reminders().first)
        let event = try #require(eventReminders().first)
        #expect(StudyReminderPolicy.isStudyReminder(study.identifier))
        #expect(PlannerEventReminderPolicy.isEventReminder(event.identifier))
        #expect(!StudyReminderPresentation.options(for: study.identifier).isEmpty)
        #expect(!StudyReminderPresentation.options(for: event.identifier).isEmpty)
        // 남의 알림은 지금까지처럼 건드리지 않는다.
        #expect(StudyReminderPresentation.options(for: "other.app.notification").isEmpty)
    }

    /// 60초 테스트 알림들은 제품 알림과 **각각 다른** 네임스페이스를 쓴다.
    @Test func selfTestsUseSeparateNamespaces() {
        let study = StudyReminderSelfTest.request()
        let event = PlannerEventSelfTest.request()
        #expect(study.identifier.hasPrefix("dailyopic.debug.notification-test."))
        #expect(event.identifier.hasPrefix("dailyopic.debug.event-notification-test."))
        #expect(!StudyReminderPolicy.isStudyReminder(study.identifier))
        #expect(!PlannerEventReminderPolicy.isEventReminder(event.identifier))
        #expect(!StudyReminderSelfTest.isSelfTest(event.identifier))
        for request in [study, event] {
            let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
            #expect(trigger?.timeInterval == 60)
            #expect(trigger?.repeats == false)
            #expect(!StudyReminderPresentation.options(for: request.identifier).isEmpty)
        }
        #expect(event.content.title == "개인 일정 알림")
    }

    /// 권한이 없으면 예약하지 않는다(여기서 권한 창을 띄우지도 않는다).
    @Test func selfTestRequiresAuthorization() async {
        let center = FakeNotificationCenter()
        center.status = .denied

        let result = await StudyReminderSelfTest.schedule(center: center)

        #expect(result == .unauthorized("denied"))
        #expect(center.pending.isEmpty)
        #expect(center.authorizationRequestCount == 0)
    }

    /// 자가 테스트는 두 제품 알림과 사용자 설정을 건드리지 않는다.
    @Test func selfTestsDoNotTouchProductReminders() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcile(reminders())
        await harness.service.reconcileEventReminders(eventReminders(), eligibility: .eligible)
        let study = harness.center.studyReminderIdentifiers
        let events = harness.center.eventReminderIdentifiers

        let studyResult = await harness.service.scheduleSelfTestNotification()
        let eventResult = await harness.service.scheduleEventSelfTestNotification()

        #expect(harness.center.studyReminderIdentifiers == study)
        #expect(harness.center.eventReminderIdentifiers == events)
        #expect(harness.service.preference == .unspecified)
        for result in [studyResult, eventResult] {
            if case .scheduled = result {} else { Issue.record("자가 테스트가 예약되지 않았다") }
        }
        // 제품 알림 정리가 테스트 알림을 지우지 않는다(반대도 마찬가지).
        await harness.service.cancelAll()
        await harness.service.reconcileEventReminders([], eligibility: .eligible)
        #expect(harness.center.pending.contains { StudyReminderSelfTest.isSelfTest($0.identifier) })
        #expect(harness.center.pending.contains { PlannerEventSelfTest.isSelfTest($0.identifier) })
    }

    // MARK: 픽스처

    private func eventReminders() -> [LocalNotificationRequest] {
        PlannerEventReminderPlanner.reminders(
            events: [
                PlannerEventReminderInput(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
                    localDate: "2026-08-20",
                    title: "면접",
                    timeMinutes: 14 * 60,
                    reminderOffsetMinutes: 30
                )
            ],
            timeZone: StudyCalendarFixture.seoulTimeZone,
            now: now
        )
    }

    /// 실제 시계 기준으로 미래인 일정 알림(트리거 검증용).
    private func futureEventReminders() -> [LocalNotificationRequest] {
        let calendar = LocalCalendarDate.calendar(timeZone: StudyCalendarFixture.seoulTimeZone)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        return PlannerEventReminderPlanner.reminders(
            events: [
                PlannerEventReminderInput(
                    id: UUID(),
                    localDate: LocalCalendarDate.text(
                        from: tomorrow,
                        timeZone: StudyCalendarFixture.seoulTimeZone
                    ),
                    title: "면접",
                    timeMinutes: 14 * 60,
                    reminderOffsetMinutes: 30
                )
            ],
            timeZone: StudyCalendarFixture.seoulTimeZone
        )
    }
}
