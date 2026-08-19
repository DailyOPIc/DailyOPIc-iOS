import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import DailyOPIc

/// P9: 개인 일정은 전 플랜이 쓰고, **일정 알림만** 유료다(무료 잠김 · 베이직/플러스/프로 동일).
///
/// 여기서 지키는 것:
/// 1. 알림 설정을 저장해도 일정 CRUD 자체는 어떤 플랜에서도 막히지 않는다.
/// 2. 예약은 일정 id 네임스페이스 안에서만 일어나고 학습 알림을 건드리지 않는다.
@MainActor
struct PlannerEventReminderModelTests {
    private func makePersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: PlannerEventRecord.self, PlannerDayNoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func event(_ persistence: PersistenceService) throws -> PlannerEventRecord {
        try #require(try persistence.plannerEvents(on: "2026-08-20").first)
    }

    /// A. 알림 없이 저장되는 것이 기본이다. 시간을 적었다고 알림이 저절로 붙지 않는다.
    @Test func newEventHasNoReminderByDefault() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "스터디", timeMinutes: 19 * 60
        )
        #expect(try event(persistence).reminderOffsetMinutes == nil)
        #expect(PlannerEventReminderPolicy.optionTitle(nil) == "알림 없음")
    }

    /// B. 시간 없는 일정에는 알림을 걸 수 없다(저장 단계에서 정규화된다).
    @Test func untimedEventCannotHoldAReminder() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "언젠가 복습", reminderOffsetMinutes: 30
        )
        #expect(try event(persistence).reminderOffsetMinutes == nil)
        #expect(PlannerEventReminderPolicy.normalizedOffset(30, hasTime: false) == nil)
    }

    /// C. 허용 간격은 0 · 10 · 30 · 60뿐이다. 그 밖의 값은 저장되지 않는다.
    @Test func onlyTheFourAllowedOffsetsPersist() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "스터디", timeMinutes: 19 * 60
        )
        let id = try event(persistence).id
        for offset in PlannerEventReminderPolicy.allowedOffsets {
            try persistence.savePlannerEvent(
                id: id, localDate: "2026-08-20", title: "스터디",
                timeMinutes: 19 * 60, reminderOffsetMinutes: offset
            )
            #expect(try event(persistence).reminderOffsetMinutes == offset)
        }
        for rejected in [-10, 5, 45, 120] {
            try persistence.savePlannerEvent(
                id: id, localDate: "2026-08-20", title: "스터디",
                timeMinutes: 19 * 60, reminderOffsetMinutes: rejected
            )
            #expect(try event(persistence).reminderOffsetMinutes == nil, "\(rejected)")
        }
        #expect(PlannerEventReminderPolicy.allowedOffsets.map(PlannerEventReminderPolicy.optionTitle)
            == ["일정 시간", "10분 전", "30분 전", "1시간 전"])
    }

    /// D·E. 알림을 바꾸거나 없애는 것이 그대로 남는다. 기록이 늘지 않는다.
    @Test func changingAndClearingTheReminderPersists() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "스터디",
            timeMinutes: 19 * 60, reminderOffsetMinutes: 10
        )
        let id = try event(persistence).id

        try persistence.savePlannerEvent(
            id: id, localDate: "2026-08-20", title: "스터디",
            timeMinutes: 19 * 60, reminderOffsetMinutes: 60
        )
        #expect(try event(persistence).reminderOffsetMinutes == 60)

        try persistence.savePlannerEvent(
            id: id, localDate: "2026-08-20", title: "스터디", timeMinutes: 19 * 60
        )
        #expect(try event(persistence).reminderOffsetMinutes == nil)
        #expect(try persistence.plannerEvents(on: "2026-08-20").count == 1)
    }

    /// F. 제목·시간을 고쳐도 골라 둔 알림 설정은 살아남는다.
    @Test func editingTitleOrTimeKeepsTheReminderChoice() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "스터디",
            timeMinutes: 19 * 60, reminderOffsetMinutes: 30
        )
        let id = try event(persistence).id

        try persistence.savePlannerEvent(
            id: id, localDate: "2026-08-20", title: "스터디 장소 변경",
            timeMinutes: 20 * 60, reminderOffsetMinutes: 30
        )
        let updated = try event(persistence)
        #expect(updated.title == "스터디 장소 변경")
        #expect(updated.timeMinutes == 20 * 60)
        #expect(updated.reminderOffsetMinutes == 30)

        // 시간을 지우면 알림도 함께 사라진다 — 걸 곳이 없어졌기 때문이다.
        try persistence.savePlannerEvent(
            id: id, localDate: "2026-08-20", title: "스터디 장소 변경",
            reminderOffsetMinutes: 30
        )
        #expect(try event(persistence).reminderOffsetMinutes == nil)
    }

    /// G. 예약 입력 목록에는 알림을 켠 일정만 들어간다(제목은 여기서만 쓰인다).
    @Test func reminderInputsContainOnlyEventsWithAReminder() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "메모용 일정")
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "알림 없는 일정", timeMinutes: 9 * 60
        )
        try persistence.savePlannerEvent(
            localDate: "2026-08-21", title: "면접", timeMinutes: 14 * 60, reminderOffsetMinutes: 60
        )

        let inputs = try persistence.plannerEventReminderInputs()
        #expect(inputs.map(\.title) == ["면접"])
        #expect(inputs.first?.reminderOffsetMinutes == 60)
        #expect(inputs.first?.localDate == "2026-08-21")
    }

    /// H. 옵셔널 필드만 더했으므로 알림을 모르는 기존 저장소가 그대로 열린다.
    @Test func schemaAdditionIsNonDestructive() throws {
        let persistence = try makePersistence()
        // 알림 인자를 아예 넘기지 않는 (구버전) 호출 경로.
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "예전 일정", timeMinutes: 600)
        let record = try event(persistence)
        #expect(record.reminderOffsetMinutes == nil)
        #expect(record.title == "예전 일정")
        #expect(try persistence.plannerEventReminderInputs().isEmpty)
    }
}

/// 플랜 게이팅(§29). 자격 판단은 `CalendarFeaturePolicy` 한 곳에서만 나온다.
@MainActor
struct PlannerEventReminderPlanTests {
    /// A. 무료도 일정 CRUD는 그대로 쓴다. 잠기는 것은 알림 옵션뿐이다.
    @Test func freeKeepsEventCrudAndOnlyLosesTheReminder() throws {
        let container = try ModelContainer(
            for: PlannerEventRecord.self, PlannerDayNoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = PersistenceService()
        persistence.configure(context: ModelContext(container))

        #expect(try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "스터디", timeMinutes: 19 * 60
        ))
        let id = try #require(try persistence.plannerEvents(on: "2026-08-20").first?.id)
        try persistence.savePlannerEvent(id: id, localDate: "2026-08-20", title: "스터디 2")
        try persistence.deletePlannerEvent(id: id)
        #expect(try persistence.plannerEvents(on: "2026-08-20").isEmpty)

        #expect(!CalendarFeaturePolicy.fallback(for: .free).canUseEventReminder)
        #expect(CalendarLockedFeature.eventReminder.isLocked(under: .free))
        #expect(CalendarLockedFeature.eventReminder.title == "일정 알림")
        #expect(CalendarLockedFeature.eventReminder.requirementText == "베이직부터")
    }

    /// B. 유료 세 플랜은 똑같이 쓴다. 프로가 베이직보다 나은 점은 없다.
    @Test func paidPlansShareTheSameEventReminderCapability() {
        let paid: [PlanEntitlement] = [.basic, .plus, .pro]
        #expect(paid.map { CalendarFeaturePolicy.fallback(for: $0).canUseEventReminder }
            == [true, true, true])
        for plan in paid {
            #expect(!CalendarLockedFeature.eventReminder
                .isLocked(under: .fallback(for: plan)), "\(plan)")
        }
    }

    /// C. 서버가 진실이다 — 같은 플랜을 말할 때에 한해서.
    @Test func matchingServerSnapshotWins() {
        #expect(CalendarFeaturePolicy.resolve(
            capabilities: StudyCalendarFixture.capabilities(
                plan: "basic", autoReplan: true, eventReminder: false
            ),
            plan: .basic
        ).canUseEventReminder == false)
    }

    /// D. 이 필드를 모르는 구 서버. 없다고 베이직이 산 기능을 뺏지 않는다.
    @Test func oldBackendWithoutTheFieldFallsBackToThePlan() {
        let old = StudyCalendarFixture.capabilities(plan: "basic", autoReplan: true)
        #expect(old.quotaPolicy.calendarEventReminder == nil)
        #expect(CalendarFeaturePolicy.resolve(capabilities: old, plan: .basic).canUseEventReminder)
        #expect(!CalendarFeaturePolicy.resolve(
            capabilities: StudyCalendarFixture.capabilities(plan: "free", autoReplan: false),
            plan: .free
        ).canUseEventReminder)
        #expect(!CalendarFeaturePolicy.resolve(capabilities: nil, plan: .free).canUseEventReminder)
        #expect(CalendarFeaturePolicy.resolve(capabilities: nil, plan: .pro).canUseEventReminder)
    }

    /// E. 방금 결제해 로컬 엔타이틀먼트가 앞서 간 상태. 낡은 free 스냅샷으로 잠그지 않는다.
    @Test func staleServerSnapshotDoesNotLockAJustUpgradedUser() {
        #expect(CalendarFeaturePolicy.resolve(
            capabilities: StudyCalendarFixture.capabilities(
                plan: "free", autoReplan: false, eventReminder: false
            ),
            plan: .plus
        ).canUseEventReminder)
    }

    /// F. 플랜을 아직 확인하지 못했으면 "무료"가 아니라 "모름"이다(P7).
    @Test func unresolvedEntitlementIsUnknownNotIneligible() {
        #expect(ReminderEligibility.resolve(isEntitlementResolved: false, isCapable: false)
            == .unknown)
        #expect(ReminderEligibility.resolve(isEntitlementResolved: true, isCapable: false)
            == .ineligible)
        #expect(ReminderEligibility.resolve(isEntitlementResolved: true, isCapable: true)
            == .eligible)
    }
}

/// 예약(§30). 트리거가 **정확히** 그 벽시계 순간을 가리키는지까지 본다.
@MainActor
struct PlannerEventReminderSchedulingTests {
    private let zone = StudyCalendarFixture.seoulTimeZone
    /// 2026-08-14(금) 08:00 KST.
    private let now = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(8 * 3600)

    private func event(
        id: UUID = UUID(),
        localDate: String = "2026-08-20",
        title: String = "스터디",
        timeMinutes: Int? = 19 * 60,
        offset: Int? = 0
    ) -> PlannerEventReminderInput {
        PlannerEventReminderInput(
            id: id,
            localDate: localDate,
            title: title,
            timeMinutes: timeMinutes,
            reminderOffsetMinutes: offset
        )
    }

    private func requests(_ events: [PlannerEventReminderInput]) -> [LocalNotificationRequest] {
        PlannerEventReminderPlanner.reminders(events: events, timeZone: zone, now: now)
    }

    private func wallClock(_ text: String, _ hour: Int, _ minute: Int) -> Date {
        StudyCalendarFixture.date(text).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    /// A~D. 일정 시각 / 10 · 30 · 60분 전이 실제 발화 시각으로 이어진다.
    @Test func everyAllowedOffsetFiresAtTheIntendedInstant() {
        let expected: [Int: Date] = [
            0: wallClock("2026-08-20", 19, 0),
            10: wallClock("2026-08-20", 18, 50),
            30: wallClock("2026-08-20", 18, 30),
            60: wallClock("2026-08-20", 18, 0),
        ]
        for (offset, fire) in expected {
            let request = try? #require(requests([event(offset: offset)]).first)
            #expect(PlannerEventReminderPlanner.fireDate(
                for: event(offset: offset), timeZone: zone
            ) == fire, "\(offset)")
            // 우리가 만든 DateComponents를 iOS가 같은 순간으로 읽는지 확인한다.
            let trigger = request?.notificationRequest.trigger as? UNCalendarNotificationTrigger
            #expect(trigger?.nextTriggerDate() == fire, "\(offset)")
        }
    }

    /// 자정 근처에서도 하루를 넘겨 계산한다(`hour = -1` 같은 값을 만들지 않는다).
    @Test func offsetCrossesMidnightCorrectly() {
        let midnightEvent = event(localDate: "2026-08-21", timeMinutes: 30, offset: 60)
        let request = requests([midnightEvent]).first
        let trigger = request?.notificationRequest.trigger as? UNCalendarNotificationTrigger

        #expect(request?.dateComponents.day == 20)
        #expect(request?.dateComponents.hour == 23)
        #expect(request?.dateComponents.minute == 30)
        #expect(trigger?.nextTriggerDate() == wallClock("2026-08-20", 23, 30))
    }

    /// E. 알림은 학습 계획 타임존의 벽시계 시각이다.
    @Test func triggerCarriesThePlannerTimezone() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let request = PlannerEventReminderPlanner.reminders(
            events: [event(offset: 30)],
            timeZone: newYork,
            now: now
        ).first
        #expect(request?.dateComponents.timeZone == newYork)
        #expect(request?.dateComponents.hour == 18)
        #expect(request?.dateComponents.minute == 30)
        // 같은 벽시계 18:30이지만 서울과는 다른 절대 시각이다.
        #expect((request?.notificationRequest.trigger as? UNCalendarNotificationTrigger)?
            .nextTriggerDate() != wallClock("2026-08-20", 18, 30))
    }

    /// F. 이미 지난 알림은 예약하지 않는다. 알림 없음·시간 없음과 이유를 구분한다.
    @Test func skipReasonsAreDistinctAndLowCardinality() {
        let past = event(localDate: "2026-08-10")
        #expect(PlannerEventReminderPlanner
            .outcome(for: past, timeZone: zone, now: now) == .skipped(.triggerTimePassed))
        #expect(PlannerEventReminderPlanner
            .outcome(for: event(offset: nil), timeZone: zone, now: now)
            == .skipped(.userSelectedNone))
        #expect(PlannerEventReminderPlanner
            .outcome(for: event(timeMinutes: nil, offset: 30), timeZone: zone, now: now)
            == .skipped(.eventHasNoTime))
        #expect(PlannerEventReminderPlanner
            .outcome(for: event(), timeZone: zone, now: now).reason == .requestGenerated)
        #expect(requests([past]).isEmpty)
    }

    /// 문구는 정해진 두 가지뿐이고, 제목은 **이 기기의 알림 본문에만** 들어간다.
    @Test func copyMatchesProductTruth() {
        let atTime = try? #require(requests([event(offset: 0)]).first)
        let before = try? #require(requests([event(offset: 30)]).first)

        #expect(atTime?.title == "개인 일정 알림")
        #expect(atTime?.body == "스터디 시작할 시간이에요.")
        #expect(before?.body == "스터디 일정이 곧 시작돼요.")
        // 식별자·진단 값에는 제목이 없다.
        #expect(atTime?.identifier.contains("스터디") == false)
        #expect(ReminderSkipReason.allCases.allSatisfy { !$0.rawValue.contains("스터디") })
    }

    // MARK: 서비스 재조정

    private func harness() -> ReminderServiceHarness { ReminderServiceHarness() }

    /// G. 알림 시각을 바꾸면 그 일정의 예약이 교체된다(같은 식별자, 새 시각).
    @Test func editingAnEventReplacesItsPendingRequest() async {
        let harness = harness()
        defer { harness.tearDown() }
        let id = UUID()

        await harness.service.reconcileEventReminders(requests([event(id: id, offset: 0)]), eligibility: .eligible)
        #expect(harness.center.eventReminderIdentifiers.count == 1)

        await harness.service.reconcileEventReminders(requests([event(id: id, offset: 60)]), eligibility: .eligible)

        let pending = await harness.service.pendingEventSnapshot()
        #expect(pending.count == 1)
        #expect(pending.nextTriggerDate == wallClock("2026-08-20", 18, 0))
        #expect(pending.nextLocalDate == id.uuidString)
    }

    /// H. 일정을 지우면 그 일정의 예약만 사라진다.
    @Test func deletingAnEventCancelsOnlyItsReminder() async {
        let harness = harness()
        defer { harness.tearDown() }
        let kept = UUID()
        let removed = UUID()
        let events = [event(id: kept, offset: 30), event(id: removed, title: "면접", offset: 10)]

        await harness.service.reconcileEventReminders(requests(events), eligibility: .eligible)
        #expect(harness.center.eventReminderIdentifiers.count == 2)

        await harness.service.reconcileEventReminders(
            requests([event(id: kept, offset: 30)]), eligibility: .eligible
        )

        #expect(harness.center.eventReminderIdentifiers
            == [PlannerEventReminderPolicy.identifier(eventID: kept)])
    }

    /// I. 두 네임스페이스는 서로를 지우지 않는다. 남의 알림도 건드리지 않는다.
    @Test func namespacesNeverCrossDelete() async {
        let harness = harness()
        defer { harness.tearDown() }
        harness.center.pending = [
            UNNotificationRequest(
                identifier: "com.other.app.reminder",
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        ]
        let study = StudyReminderPlanner.reminders(
            settings: StudyCalendarFixture.settings(), completions: [:], now: now
        )

        await harness.service.reconcile(study)
        await harness.service.reconcileEventReminders(requests([event()]), eligibility: .eligible)
        let studyCount = harness.center.studyReminderIdentifiers.count
        #expect(studyCount > 0)
        #expect(harness.center.eventReminderIdentifiers.count == 1)

        // 일정 알림을 전부 걷어도 학습 알림은 그대로다.
        await harness.service.reconcileEventReminders([], eligibility: .eligible)
        #expect(harness.center.eventReminderIdentifiers.isEmpty)
        #expect(harness.center.studyReminderIdentifiers.count == studyCount)

        // 학습 알림을 꺼도 일정 알림은 그대로다.
        await harness.service.reconcileEventReminders(requests([event()]), eligibility: .eligible)
        await harness.service.disable()
        #expect(harness.center.studyReminderIdentifiers.isEmpty)
        #expect(harness.center.eventReminderIdentifiers.count == 1)
        #expect(harness.center.pending.contains { $0.identifier == "com.other.app.reminder" })
    }

    /// J. 같은 입력으로 여러 번 돌려도 결과가 같다(포그라운드 복귀마다 호출된다).
    @Test func reconciliationIsIdempotent() async {
        let harness = harness()
        defer { harness.tearDown() }
        let events = [event(id: UUID(), offset: 10), event(id: UUID(), offset: 60)]

        for _ in 0..<3 {
            await harness.service.reconcileEventReminders(requests(events), eligibility: .eligible)
        }

        #expect(harness.center.eventReminderIdentifiers.count == 2)
    }

    /// K. 권한이 없으면 예약하지 않는다. 여기서도 권한 창을 띄우지 않는다.
    @Test func schedulingRequiresExistingAuthorization() async {
        for status in [UNAuthorizationStatus.notDetermined, .denied] {
            let harness = ReminderServiceHarness(status: status)
            defer { harness.tearDown() }

            await harness.service.reconcileEventReminders(
                requests([event()]), eligibility: .eligible
            )

            #expect(harness.center.eventReminderIdentifiers.isEmpty)
            #expect(harness.center.authorizationRequestCount == 0)
        }
    }

    /// L. 앱을 보고 있는 동안 도착해도 배너로 뜬다(실제 제품 식별자로 확인한다).
    @Test func foregroundDeliveryRecognizesBothProductNamespaces() {
        let event = StudyReminderPresentation.options(
            for: PlannerEventReminderPolicy.identifier(eventID: UUID())
        )
        let study = StudyReminderPresentation.options(
            for: StudyReminderPolicy.identifier(forLocalDate: "2026-08-20")
        )
        #expect(event == [.banner, .list, .sound])
        #expect(study == [.banner, .list, .sound])
        #expect(StudyReminderPresentation.options(for: "com.other.app.reminder").isEmpty)
    }
}

/// 강등·재업그레이드(§31). 예약은 걷되 사용자의 선택은 남긴다.
@MainActor
struct PlannerEventReminderEntitlementChangeTests {
    private let zone = StudyCalendarFixture.seoulTimeZone
    private let now = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(8 * 3600)

    private func requests() -> [LocalNotificationRequest] {
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
            timeZone: zone,
            now: now
        )
    }

    /// A·B. 무료로 내려가면 예약은 걷힌다. 학습 알림은 **그대로 남는다**(P4 정책 폐기).
    @Test func downgradeCancelsEventRemindersButKeepsStudyReminders() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        let study = StudyReminderPlanner.reminders(
            settings: StudyCalendarFixture.settings(), completions: [:], now: now
        )
        await harness.service.reconcile(study)
        await harness.service.reconcileEventReminders(requests(), eligibility: .eligible)
        #expect(harness.center.eventReminderIdentifiers.count == 1)

        await harness.service.reconcileEventReminders(requests(), eligibility: .ineligible)

        #expect(harness.center.eventReminderIdentifiers.isEmpty)
        #expect(!harness.center.studyReminderIdentifiers.isEmpty)
        #expect(harness.service.isEnabled)
        #expect(harness.service.preference == .unspecified)
    }

    /// C. 일정과 골라 둔 알림 설정은 지우지 않는다. 다시 결제하면 그대로 살아난다.
    @Test func downgradeKeepsEventDataAndReminderChoice() throws {
        let container = try ModelContainer(
            for: PlannerEventRecord.self, PlannerDayNoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = PersistenceService()
        persistence.configure(context: ModelContext(container))
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "면접",
            timeMinutes: 14 * 60, reminderOffsetMinutes: 30
        )

        // 강등은 저장소를 건드리지 않는다 — 예약만 걷는 일이다.
        let event = try #require(try persistence.plannerEvents(on: "2026-08-20").first)
        #expect(event.reminderOffsetMinutes == 30)
        #expect(try persistence.plannerEventReminderInputs().count == 1)
    }

    /// D. OS 권한은 손대지 않는다. 알림 허용은 사용자가 OS에 준 것이다.
    @Test func downgradeLeavesSystemAuthorizationAlone() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }

        await harness.service.reconcileEventReminders(requests(), eligibility: .ineligible)

        #expect(harness.center.status == .authorized)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    /// E. 자격을 아직 모를 때는 예약도 삭제도 하지 않는다(P7 회귀 방지).
    @Test func unknownEntitlementTouchesNothing() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcileEventReminders(requests(), eligibility: .eligible)
        let scheduled = harness.center.eventReminderIdentifiers
        #expect(!scheduled.isEmpty)

        await harness.service.reconcileEventReminders(nil, eligibility: .unknown)
        await harness.service.reconcileEventReminders(requests(), eligibility: .unknown)

        #expect(harness.center.eventReminderIdentifiers == scheduled)
        #expect(harness.service.lastEventSkipReason == .entitlementUnknown)
    }

    /// 일정을 아직 읽지 못했을 때도 기존 예약을 지우지 않는다(nil ≠ []).
    @Test func unknownScheduleKeepsPendingEventReminders() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcileEventReminders(requests(), eligibility: .eligible)
        let scheduled = harness.center.eventReminderIdentifiers

        await harness.service.reconcileEventReminders(nil, eligibility: .eligible)

        #expect(harness.center.eventReminderIdentifiers == scheduled)
        #expect(harness.service.lastEventSkipReason == .scheduleUnknown)
    }

    /// F. 다시 결제하면 권한을 새로 묻지 않고, 이미 허용돼 있으면 예약이 되살아난다.
    @Test func reUpgradeRestoresRemindersWithoutAskingAgain() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        await harness.service.reconcileEventReminders(requests(), eligibility: .eligible)
        await harness.service.reconcileEventReminders(requests(), eligibility: .ineligible)

        await harness.service.reconcileEventReminders(requests(), eligibility: .eligible)

        #expect(harness.center.eventReminderIdentifiers.count == 1)
        #expect(harness.center.authorizationRequestCount == 0)
    }

    /// 권한을 아직 물어본 적이 없다면 재업그레이드가 예약을 만들지도, 창을 띄우지도 않는다.
    @Test func reUpgradeWithoutPermissionStaysUnscheduled() async {
        let harness = ReminderServiceHarness(status: .notDetermined)
        defer { harness.tearDown() }

        await harness.service.reconcileEventReminders(requests(), eligibility: .eligible)

        #expect(harness.center.eventReminderIdentifiers.isEmpty)
        #expect(harness.center.authorizationRequestCount == 0)
        #expect(harness.service.lastEventSkipReason == .permissionNotDetermined)
    }
}
