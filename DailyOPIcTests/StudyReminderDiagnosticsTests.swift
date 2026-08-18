import Foundation
import Testing
import UserNotifications
@testable import DailyOPIc

/// P7: "왜 실기기에 알림이 안 오는가"를 코드가 스스로 설명할 수 있어야 한다.
///
/// 근본 원인은 **자격을 아직 모르는 상태를 무료로 단정한 것**이었다. 앱이 켜지는 순간
/// RevenueCat도 서버도 대답하기 전인데 `currentPlan`은 기본값 무료를 말하고, 재조정이
/// 그것을 강등으로 읽어 예약을 전부 지우고 로컬 의도까지 꺼 버렸다.
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

    private func plan(
        settings: StudyPlanSettings,
        completions: [Date: Int] = [:]
    ) -> AdaptiveStudyPlan {
        AdaptiveStudyPlanner.plan(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            completions: completions,
            policy: .everything,
            today: now
        )
    }

    private func reminders(
        settings: StudyPlanSettings? = nil,
        completions: [String: Int] = [:]
    ) -> [StudyReminderRequest] {
        let settings = settings ?? self.settings()
        let counts = StudyCalendarFixture.completions(completions)
        return StudyReminderPlanner.reminders(
            plan: plan(settings: settings, completions: counts),
            settings: settings,
            completions: counts,
            now: now
        )
    }

    /// 오늘(2026-08-14) 판단 결과.
    private func outcome(
        settings: StudyPlanSettings? = nil,
        completions: [String: Int] = [:],
        on day: String = "2026-08-14",
        now: Date? = nil
    ) -> StudyReminderOutcome {
        let settings = settings ?? self.settings()
        let counts = StudyCalendarFixture.completions(completions)
        return StudyReminderPlanner.outcome(
            for: StudyCalendarFixture.date(day),
            plan: plan(settings: settings, completions: counts),
            settings: settings,
            completions: counts,
            now: now ?? self.now
        )
    }

    /// **실제 시계** 기준으로 미래인 알림들. 트리거 검증에는 픽스처 날짜(2026-08-14)를
    /// 쓸 수 없다 — `nextTriggerDate()`는 언제나 지금 시각으로 계산하므로 이미 지난
    /// 날짜의 트리거는 검증하려는 값을 돌려주지 않는다.
    private func futureReminders(now: Date = .now) -> [StudyReminderRequest] {
        let settings = StudyCalendarFixture.settings(weekdays: Set(StudyWeekday.allCases))
        let plan = AdaptiveStudyPlanner.plan(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            completions: [:],
            policy: .everything,
            today: now
        )
        return StudyReminderPlanner.reminders(
            plan: plan,
            settings: settings,
            completions: [:],
            now: now
        )
    }

    private func service(
        center: FakeNotificationCenter,
        enabled: Bool
    ) -> (StudyReminderService, String) {
        let suite = "DailyOPIcTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = AppPreferences(defaults: defaults)
        preferences.studyRemindersEnabled = enabled
        return (StudyReminderService(preferences: preferences, center: center), suite)
    }

    private func cleanUp(_ suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    // MARK: A. 근본 원인 — 자격 미상

    /// **P7 회귀 테스트.** 플랜을 아직 모를 때는 예약을 지우지 않는다.
    /// 이것이 실기기에서 알림이 오지 않던 이유다: 앱을 켤 때마다 30일치가 지워졌다.
    @Test func unknownEligibilityKeepsPendingReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        await service.reconcile(reminders(), eligibility: .eligible)
        let scheduled = center.studyReminderIdentifiers
        #expect(!scheduled.isEmpty)

        // 앱 재실행 직후: 아직 RevenueCat도 서버도 대답하지 않았다.
        await service.reconcile(nil, eligibility: .unknown)

        #expect(center.studyReminderIdentifiers == scheduled)
        #expect(service.lastSkipReason == .eligibilityUnknown)
    }

    /// 자격 미상은 로컬 "알림 받기" 의도도 끄지 않는다.
    /// 의도가 꺼지면 사용자가 직접 다시 켜기 전까지 알림이 영영 오지 않는다.
    @Test func unknownEligibilityKeepsUserIntent() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        await service.reconcile(reminders(), eligibility: .unknown)

        #expect(service.isEnabled)
        #expect(service.lastSkipReason == .eligibilityUnknown)
    }

    /// 자격 미상에서는 예약을 새로 만들지도 않는다(무료 사용자에게 알림이 생기지 않는다).
    @Test func unknownEligibilityDoesNotSchedule() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        await service.reconcile(reminders(), eligibility: .unknown)

        #expect(center.studyReminderIdentifiers.isEmpty)
    }

    /// P4는 그대로다: **확인된** 무료(강등)는 여전히 예약을 걷어내고 의도를 끈다.
    @Test func knownIneligibleStillRevokes() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        await service.reconcile(reminders(), eligibility: .eligible)
        #expect(!center.studyReminderIdentifiers.isEmpty)

        await service.reconcile(reminders(), eligibility: .ineligible)

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(!service.isEnabled)
        #expect(service.lastSkipReason == .featureLocked)
    }

    /// 앱이 켜지는 순간의 실제 조합을 그대로 재현한다.
    /// RevenueCat 미설정 + capabilities 없음 → `currentPlan`은 기본값 무료를 말하지만
    /// 그것은 "무료 사용자"가 아니라 "아직 모른다"이다.
    @Test func launchBeforeEntitlementResolvesIsUnknownNotFree() {
        let store = StoreService()
        // 아직 아무것도 확인하지 못한 상태.
        #expect(!store.isConfigured)
        #expect(!store.hasResolvedEntitlement)
        #expect(store.localEntitlement == .free)
        // 이 상태에서 무료 폴백 표는 알림을 잠근다 — 그래서 미상 처리가 필요하다.
        #expect(!CalendarFeaturePolicy.resolve(capabilities: nil, plan: .free).canUseStudyReminder)

        #expect(
            StudyReminderEligibility.resolve(
                isEntitlementResolved: false,
                canUseStudyReminder: false
            ) == .unknown
        )
    }

    /// 확인된 뒤에는 평소대로 갈린다.
    @Test func resolvedEntitlementDecidesNormally() {
        #expect(
            StudyReminderEligibility.resolve(
                isEntitlementResolved: true,
                canUseStudyReminder: true
            ) == .eligible
        )
        #expect(
            StudyReminderEligibility.resolve(
                isEntitlementResolved: true,
                canUseStudyReminder: false
            ) == .ineligible
        )
    }

    // MARK: B. 원한 목록 ≠ 실제 대기 목록

    /// iOS가 예약을 거절하면 desired와 pending이 갈라진다.
    /// 앱이 "원했다"는 사실은 예약됐다는 증거가 아니다.
    @Test func pendingCanDifferFromDesired() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        center.addFailure = StudyReminderAddFailure(domain: "UNErrorDomain", code: 1)
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        let desired = reminders()
        #expect(!desired.isEmpty)
        await service.reconcile(desired, eligibility: .eligible)

        #expect(center.studyReminderIdentifiers.isEmpty)
        #expect(service.lastAddFailure?.code == 1)
        #expect(await service.pendingSnapshot().count == 0)
    }

    /// 성공하면 실패 기록이 남지 않는다.
    @Test func successfulScheduleClearsAddFailure() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        await service.reconcile(reminders(), eligibility: .eligible)

        #expect(service.lastAddFailure == nil)
        let snapshot = await service.pendingSnapshot()
        #expect(snapshot.count == center.studyReminderIdentifiers.count)
    }

    // MARK: C. 건너뛴 이유 분류

    @Test func classifiesEligibilityUnknown() {
        let diagnosis = StudyReminderDiagnosis.make(
            eligibility: .unknown,
            isEnabled: true,
            authorization: .authorized,
            desired: reminders(),
            todayOutcome: outcome()
        )
        #expect(diagnosis.reason == .eligibilityUnknown)
        #expect(!diagnosis.isScheduledToday)
    }

    @Test func classifiesFeatureLocked() {
        let diagnosis = StudyReminderDiagnosis.make(
            eligibility: .ineligible,
            isEnabled: true,
            authorization: .authorized,
            desired: reminders(),
            todayOutcome: outcome()
        )
        #expect(diagnosis.reason == .featureLocked)
    }

    @Test func classifiesUserDisabled() {
        let diagnosis = StudyReminderDiagnosis.make(
            eligibility: .eligible,
            isEnabled: false,
            authorization: .authorized,
            desired: reminders(),
            todayOutcome: outcome()
        )
        #expect(diagnosis.reason == .userDisabled)
    }

    @Test func classifiesPermissionStates() {
        func reason(_ status: UNAuthorizationStatus) -> StudyReminderSkipReason {
            StudyReminderDiagnosis.make(
                eligibility: .eligible,
                isEnabled: true,
                authorization: status,
                desired: reminders(),
                todayOutcome: outcome()
            ).reason
        }
        #expect(reason(.notDetermined) == .permissionNotDetermined)
        #expect(reason(.denied) == .permissionDenied)
        // provisional/ephemeral은 조용히 전달되므로 예약을 막지 않는다.
        #expect(reason(.provisional) == .requestGenerated)
    }

    @Test func classifiesScheduleUnknown() {
        let diagnosis = StudyReminderDiagnosis.make(
            eligibility: .eligible,
            isEnabled: true,
            authorization: .authorized,
            desired: nil,
            todayOutcome: nil
        )
        #expect(diagnosis.reason == .scheduleUnknown)
        #expect(diagnosis.desiredCount == nil)
    }

    /// 2026-08-15는 토요일 → 휴식일.
    @Test func classifiesRestDay() {
        #expect(outcome(on: "2026-08-15") == .skipped(.restDay))
    }

    /// 오늘 배정 2세트를 다 했다.
    @Test func classifiesTargetComplete() {
        #expect(
            outcome(completions: ["2026-08-14": 2]) == .skipped(.targetComplete)
        )
    }

    /// 공부 시간(21:00)이 지난 뒤에 재조정하면 오늘은 예약하지 않는다.
    @Test func classifiesPreferredTimePassed() {
        let late = StudyCalendarFixture.date("2026-08-14").addingTimeInterval(22 * 3600)
        #expect(outcome(now: late) == .skipped(.preferredTimePassed))
    }

    /// 시험 당일에는 학습 숙제 알림을 보내지 않는다.
    @Test func classifiesExamDay() {
        #expect(
            outcome(settings: settings(examDate: "2026-08-14")) == .skipped(.examDay)
        )
    }

    /// 30일 지평 밖.
    @Test func classifiesOutsideHorizon() {
        #expect(outcome(on: "2026-12-01") == .skipped(.outsideHorizon))
        // 지난 날짜도 예약 대상이 아니다.
        #expect(outcome(on: "2026-08-13") == .skipped(.outsideHorizon))
    }

    /// 권장 학습량을 다 채우면 더 이상 숙제가 없다.
    @Test func classifiesTargetCompleteWhenPlanFinished() {
        // 목표 IH·최근 IH → 권장 20세트. 계획 시작 이후 20세트를 채웠다.
        #expect(
            outcome(completions: ["2026-08-10": 20]) == .skipped(.targetComplete)
        )
    }

    @Test func classifiesRequestGenerated() {
        let diagnosis = StudyReminderDiagnosis.make(
            eligibility: .eligible,
            isEnabled: true,
            authorization: .authorized,
            desired: reminders(),
            todayOutcome: outcome()
        )
        #expect(diagnosis.reason == .requestGenerated)
        #expect(diagnosis.isScheduledToday)
        #expect((diagnosis.desiredCount ?? 0) > 0)
    }

    /// 예약 목록과 진단이 **같은 함수**를 쓴다: 오늘 예약이 있으면 목록에도 오늘이 있다.
    @Test func outcomeAgreesWithReminderList() {
        let today = StudyReminderPolicy.identifier(forLocalDate: "2026-08-14")
        #expect(outcome().request?.identifier == today)
        #expect(reminders().first?.identifier == today)
        // 휴식일은 목록에도 없다.
        let saturday = StudyReminderPolicy.identifier(forLocalDate: "2026-08-15")
        #expect(!reminders().contains { $0.identifier == saturday })
    }

    // MARK: D. 진단 출력에 사용자 콘텐츠가 없다

    /// 로그 한 줄에는 고정 값만 들어간다(문구·UID·메모·답변 없음).
    @Test func diagnosticOutputHasNoPrivateContent() {
        let requests = reminders()
        let diagnosis = StudyReminderDiagnosis.make(
            eligibility: .eligible,
            isEnabled: true,
            authorization: .authorized,
            desired: requests,
            todayOutcome: outcome()
        )
        let line = diagnosis.logLine
        // 알림 문구가 새어 나가지 않는다.
        #expect(!line.contains(StudyReminderPlanner.title))
        for request in requests {
            #expect(!line.contains(request.body))
            #expect(!line.contains(request.identifier))
        }
        // 남는 것은 고정 토큰뿐이다.
        #expect(line.contains("reason=request_generated"))
        #expect(line.contains("eligibility=eligible"))
        #expect(line.contains("status=authorized"))
    }

    /// 이유 값은 전부 고정 문자열이다(자유 텍스트가 섞이지 않는다).
    @Test func skipReasonsAreFixedTokens() {
        for reason in StudyReminderSkipReason.allCases {
            #expect(!reason.rawValue.isEmpty)
            #expect(reason.rawValue == reason.rawValue.lowercased())
            #expect(!reason.rawValue.contains(" "))
        }
    }

    // MARK: E. 트리거가 실제로 울릴 수 있는가

    /// DateComponents를 눈으로 보지 않고 **iOS가 계산한** 다음 발화 시각을 확인한다.
    /// 여기가 통과해야 "앱은 예약했는데 iOS는 울릴 생각이 없다"를 배제할 수 있다.
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
    /// DateComponents에 타임존을 붙였을 때 발화 시각이 밀리지 않는지 확인한다.
    @Test func triggerHonoursPlanTimeZoneNotDeviceTimeZone() throws {
        let request = try #require(futureReminders().first)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: request.dateComponents,
            repeats: false
        )
        let next = try #require(trigger.nextTriggerDate())

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 같은 순간을 뉴욕 벽시계로 보면 21:00이 아니다 — 그래도 발화 순간은 하나다.
        #expect(newYork.dateComponents([.hour], from: next).hour != 21)
        // 서울 벽시계로는 정확히 21:00.
        #expect(StudyCalendarFixture.settings().calendar
            .dateComponents([.hour], from: next).hour == 21)
    }

    /// pending 스냅샷은 트리거가 계산한 실제 발화 시각을 읽는다.
    @Test func pendingSnapshotReadsRealTriggerDate() async throws {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        let desired = futureReminders()
        await service.reconcile(desired, eligibility: .eligible)
        let snapshot = await service.pendingSnapshot()

        #expect(snapshot.count == desired.count)
        #expect(snapshot.nextTriggerTimeZone == "Asia/Seoul")
        let firstLocalDate = try #require(desired.first).identifier
            .replacingOccurrences(of: StudyReminderPolicy.identifierPrefix, with: "")
        #expect(snapshot.nextLocalDate == firstLocalDate)
        #expect(try #require(snapshot.nextTriggerDate) > Date.now)
    }

    // MARK: F. 포그라운드 표시 · DEBUG 자가 테스트

    /// 실제로 만들어지는 식별자가 포그라운드 표시 조건을 만족한다.
    @Test func realIdentifierIsRecognizedForForegroundPresentation() throws {
        let request = try #require(reminders().first)
        #expect(StudyReminderPolicy.isStudyReminder(request.identifier))
        #expect(!StudyReminderPresentation.options(for: request.identifier).isEmpty)
        // 남의 알림은 지금까지처럼 건드리지 않는다.
        #expect(StudyReminderPresentation.options(for: "other.app.notification").isEmpty)
    }

    /// 60초 테스트 알림은 학습 알림과 다른 네임스페이스를 쓴다.
    @Test func selfTestUsesSeparateNamespace() {
        let request = StudyReminderSelfTest.request()
        #expect(request.identifier.hasPrefix("dailyopic.debug.notification-test."))
        #expect(!StudyReminderPolicy.isStudyReminder(request.identifier))
        let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 60)
        #expect(trigger?.repeats == false)
        // 포그라운드에서도 보여야 "전달 자체는 되는가"를 볼 수 있다.
        #expect(!StudyReminderPresentation.options(for: request.identifier).isEmpty)
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

    /// 자가 테스트는 학습 알림 예약과 사용자 설정을 건드리지 않는다.
    @Test func selfTestDoesNotTouchStudyReminders() async {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let (service, suite) = service(center: center, enabled: true)
        defer { cleanUp(suite) }

        await service.reconcile(reminders(), eligibility: .eligible)
        let before = center.studyReminderIdentifiers

        let result = await service.scheduleSelfTestNotification()

        #expect(center.studyReminderIdentifiers == before)
        #expect(service.isEnabled)
        if case .scheduled = result {} else { Issue.record("자가 테스트가 예약되지 않았다") }
        // 학습 알림 정리가 테스트 알림을 지우지 않는다(반대도 마찬가지).
        await service.cancelAll()
        #expect(center.pending.contains { StudyReminderSelfTest.isSelfTest($0.identifier) })
    }
}
