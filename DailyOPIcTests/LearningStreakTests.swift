import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 연속 학습(스트릭)의 계약. **계획 달성률이 아니라 실제 학습 활동**을 센다.
/// 하루에 1세트라도 실제로 학습했으면 그날은 학습한 날이고, 휴식일에 스스로 학습해도
/// 학습한 날이다. 대신 계획은 그대로 휴식일로 남는다(배정량을 만들지 않는다).
struct LearningStreakTests {
    private func date(_ text: String) -> Date { StudyCalendarFixture.date(text) }

    private func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        intensity: StudyIntensity = .steady,
        examDate: String? = nil
    ) -> StudyPlanSettings {
        StudyCalendarFixture.settings(weekdays: weekdays, intensity: intensity, examDate: examDate)
    }

    private func streak(
        _ completions: [String: Int],
        today: String,
        settings: StudyPlanSettings? = nil
    ) -> Int {
        let settings = settings ?? self.settings()
        return LearningStreak.current(
            learningDays: LearningStreak.learningDays(from: StudyCalendarFixture.completions(completions)),
            today: date(today),
            calendar: settings.calendar
        )
    }

    private func snapshot(
        today: String,
        completions: [String: Int] = [:],
        settings: StudyPlanSettings? = nil,
        historical: [String: Int] = [:]
    ) -> StudyCalendarSnapshot {
        StudyCalendarSnapshot.make(
            settings: settings ?? self.settings(),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 5,
            completions: StudyCalendarFixture.completions(completions),
            historicalTargets: historical,
            today: date(today)
        )
    }

    // MARK: 스트릭 코어

    /// A. 오늘 1세트만 해도 오늘은 학습한 날이다.
    @Test func oneCompletionTodayCountsAsALearningDay() {
        #expect(streak(["2026-08-14": 1], today: "2026-08-14") == 1)
    }

    /// B. 배정 3 · 완료 1 — 계획은 일부만 달성이지만 학습한 날이다.
    @Test func partialPlanCompletionStillCountsForTheStreak() {
        let focused = settings(intensity: .focused)
        let snapshot = snapshot(today: "2026-08-14", completions: ["2026-08-14": 1], settings: focused)
        #expect(snapshot.today.targetSets == 3)
        #expect(snapshot.today.completedSets == 1)
        #expect(snapshot.today.state == .partial)
        #expect(snapshot.today.hasLearning)
        #expect(snapshot.streak == 1)
    }

    /// C. 배정 3 · 완료 3도 당연히 학습한 날이다(달성 여부로 갈리지 않는다).
    @Test func fullPlanCompletionCountsForTheStreak() {
        let focused = settings(intensity: .focused)
        let snapshot = snapshot(today: "2026-08-14", completions: ["2026-08-14": 3], settings: focused)
        #expect(snapshot.today.state == .completed)
        #expect(snapshot.streak == 1)
    }

    /// D·E. 이어진 날만큼 늘어난다.
    @Test func consecutiveLearningDaysAccumulate() {
        #expect(streak(["2026-08-13": 1, "2026-08-14": 1], today: "2026-08-14") == 2)
        #expect(streak(["2026-08-12": 1, "2026-08-13": 1, "2026-08-14": 1], today: "2026-08-14") == 3)
    }

    /// F. 중간에 학습 없이 지나간 날이 있으면 거기서 끊긴다.
    @Test func aGapDayResetsTheStreak() {
        #expect(streak(["2026-08-11": 1, "2026-08-13": 1], today: "2026-08-14") == 1)
    }

    /// G. 오늘은 아직 안 끝났다. 오늘 기록이 없다고 어제까지의 연속이 사라지지 않는다.
    @Test func todayWithoutLearningKeepsTheActiveStreakVisible() {
        #expect(streak(["2026-08-12": 1, "2026-08-13": 1], today: "2026-08-14") == 2)
    }

    /// H. 그 하루를 통째로 넘기고 다음 날이 되면 끊긴다.
    @Test func theStreakBreaksOnceTheMissedDayIsPast() {
        #expect(streak(["2026-08-12": 1, "2026-08-13": 1], today: "2026-08-15") == 0)
    }

    /// I. 같은 날 여러 세트를 해도 하루는 하루다.
    @Test func multipleCompletionsOnOneDateCountAsOneDay() {
        #expect(streak(["2026-08-13": 4, "2026-08-14": 7], today: "2026-08-14") == 2)
    }

    /// J. 일정·메모는 학습이 아니다. 스트릭의 재료는 세트 완료 기록뿐이다.
    @Test @MainActor func eventsAndNotesDoNotCountAsLearning() throws {
        let container = try ModelContainer(
            for: PlannerEventRecord.self, PlannerDayNoteRecord.self, StudySetCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = PersistenceService()
        persistence.configure(context: ModelContext(container))
        #expect(try persistence.savePlannerEvent(localDate: "2026-08-14", title: "스터디 모임"))
        #expect(try persistence.savePlannerNote(localDate: "2026-08-14", text: "내일 3세트"))

        let counts = StudyCalendarEngine.completionCounts(
            completedAt: try persistence.studySetCompletionDates(),
            calendar: settings().calendar
        )
        #expect(counts.isEmpty)
        #expect(LearningStreak.current(
            learningDays: LearningStreak.learningDays(from: counts),
            today: date("2026-08-14"),
            calendar: settings().calendar
        ) == 0)
    }

    /// 세트 완료 기록이 그대로 스트릭의 재료가 된다(저장 → 집계 → 스트릭 한 줄기).
    @Test @MainActor func persistedSetCompletionsFeedTheStreak() throws {
        let container = try ModelContainer(
            for: StudySetCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = PersistenceService()
        persistence.configure(context: ModelContext(container))
        #expect(try persistence.recordStudySetCompletion(setId: "a", at: date("2026-08-13")))
        #expect(try persistence.recordStudySetCompletion(setId: "b", at: date("2026-08-14")))

        let counts = StudyCalendarEngine.completionCounts(
            completedAt: try persistence.studySetCompletionDates(),
            calendar: settings().calendar
        )
        #expect(LearningStreak.current(
            learningDays: LearningStreak.learningDays(from: counts),
            today: date("2026-08-14"),
            calendar: settings().calendar
        ) == 2)
    }

    // MARK: 휴식일 학습

    /// A. 아무것도 안 한 휴식일은 학습한 날이 아니다(전날까지의 연속은 그대로 보인다).
    @Test func restDayWithoutLearningEarnsNoCredit() {
        #expect(streak(["2026-08-15": 0], today: "2026-08-15") == 0)
        #expect(streak(["2026-08-14": 2], today: "2026-08-15") == 1)
    }

    /// B. 휴식일(토요일)에 스스로 한 학습도 학습한 날이다.
    @Test func restDayLearningCountsForTheStreak() {
        let snapshot = snapshot(today: "2026-08-15", completions: ["2026-08-14": 2, "2026-08-15": 1])
        #expect(snapshot.today.state == .rest)
        #expect(snapshot.today.hasUnscheduledLearning)
        #expect(snapshot.streak == 2)
    }

    /// C. 휴식일에 3세트를 해도 하루는 하루다.
    @Test func repeatedRestDayLearningIsStillOneDay() {
        #expect(streak(["2026-08-15": 3], today: "2026-08-15") == 1)
    }

    /// D. 휴식일에 학습해도 그날의 배정량은 0으로 남는다 — 가짜 목표를 만들지 않는다.
    @Test func restDayLearningDoesNotCreateATarget() {
        let snapshot = snapshot(today: "2026-08-15", completions: ["2026-08-15": 1])
        #expect(snapshot.today.targetSets == 0)
        #expect(snapshot.schedule.targetSets(for: date("2026-08-15")) == 0)
        #expect(snapshot.remainingToday == 0)
    }

    /// E. 계획 자체(공부 요일)도 그대로다. 토요일은 여전히 학습일이 아니다.
    @Test func restDayLearningDoesNotChangeTheSchedule() {
        let settings = settings()
        let snapshot = snapshot(today: "2026-08-15", completions: ["2026-08-15": 1], settings: settings)
        #expect(settings.studyWeekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(!settings.isStudyDay(date("2026-08-15")))
        #expect(!snapshot.plan.upcomingDays.contains { !settings.isStudyDay($0.date) })
    }

    /// F. 휴식일 자율 학습은 "이번 주 N / M일 완료"를 부풀리지 않는다. 계획 이행률은 계획만 센다.
    @Test func restDayLearningDoesNotInflateWeeklyPlanProgress() {
        let planned = ["2026-08-10": 2, "2026-08-11": 2, "2026-08-12": 2, "2026-08-13": 2, "2026-08-14": 2]
        let withoutRest = snapshot(today: "2026-08-15", completions: planned)
        let withRest = snapshot(today: "2026-08-15", completions: planned.merging(["2026-08-15": 2]) { _, new in new })
        #expect(withoutRest.weekScheduledDays == withRest.weekScheduledDays)
        #expect(withoutRest.weekCompletedDays == withRest.weekCompletedDays)
        #expect(withRest.weekScheduledDays == 5)
        #expect(withRest.weekCompletedDays == 5)
        // 계획 이행률은 그대로인데 실제 학습 연속은 6일이다 — 두 지표는 따로 움직인다.
        #expect(withRest.streak == 6)
    }

    /// G. 배정이 없던 날에 "1 / 0세트"도 "1 / 1세트 완료"도 쓰지 않는다.
    @Test func restDayLearningNeverRendersAFakeTarget() {
        let restLearned = snapshot(today: "2026-08-15", completions: ["2026-08-15": 1]).today
        #expect(restLearned.setsSummaryText == "1세트 학습")
        #expect(restLearned.state == .rest)

        let restIdle = snapshot(today: "2026-08-15").today
        #expect(restIdle.setsSummaryText == nil)

        let partial = snapshot(today: "2026-08-14", completions: ["2026-08-14": 1]).today
        #expect(partial.setsSummaryText == "1 / 2세트")
        #expect(partial.state == .partial)
    }

    /// H. 주간 스트립·월간 격자가 읽어 주는 문장에 휴식일 학습이 드러난다.
    @Test func restDayLearningIsAudibleInTheCalendar() {
        #expect(snapshot(today: "2026-08-15", completions: ["2026-08-15": 1]).today.studyAccessibilityText == "휴식, 1세트 학습")
        #expect(snapshot(today: "2026-08-15").today.studyAccessibilityText == "휴식")
        #expect(snapshot(today: "2026-08-14", completions: ["2026-08-14": 1]).today.studyAccessibilityText == "일부 완료, 1 / 2세트")
    }

    // MARK: 과거 기록과 시간대

    /// A. 나중에 강도·시험일을 바꿔도 지난 휴식일의 배정량은 0으로 남는다.
    @Test func pastRestDayTargetSurvivesLaterPlanEdits() {
        let edited = settings(intensity: .focused, examDate: "2026-09-30")
        let snapshot = snapshot(today: "2026-08-17", completions: ["2026-08-15": 1], settings: edited)
        let saturday = StudyCalendarEngine.day(
            date: date("2026-08-15"),
            today: snapshot.today.date,
            settings: edited,
            schedule: snapshot.schedule,
            completions: StudyCalendarFixture.completions(["2026-08-15": 1])
        )
        #expect(saturday.targetSets == 0)
        #expect(saturday.state == .rest)
        #expect(saturday.hasUnscheduledLearning)
    }

    /// 고정된 지난 배정량은 계획을 바꿔도 그대로다(과거는 다시 쓰이지 않는다).
    @Test func frozenPastTargetsIgnoreLaterIntensityChanges() {
        let edited = settings(intensity: .focused)
        let snapshot = snapshot(
            today: "2026-08-14",
            completions: ["2026-08-12": 2],
            settings: edited,
            historical: ["2026-08-12": 2]
        )
        #expect(snapshot.schedule.targetSets(for: date("2026-08-12")) == 2)
    }

    /// B. 완료 기록은 계획 시간대의 그 날짜에 그대로 남는다(늦은 밤 학습이 다음 날로 새지 않는다).
    @Test func lateNightCompletionStaysOnItsLocalDate() {
        let lateNight = date("2026-08-15").addingTimeInterval(23 * 3600 + 30 * 60)
        let counts = StudyCalendarEngine.completionCounts(
            completedAt: [lateNight],
            calendar: settings().calendar
        )
        #expect(counts[date("2026-08-15")] == 1)
    }

    /// C. UTC 기준으로 자르면 하루 앞으로 밀리는 시각도 계획 시간대에서는 제자리다.
    @Test func planTimeZoneDecidesTheDayNotUTC() {
        let morningInSeoul = date("2026-08-16").addingTimeInterval(8 * 3600)  // = 08-15 23:00 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let seoulCounts = StudyCalendarEngine.completionCounts(completedAt: [morningInSeoul], calendar: settings().calendar)
        let utcCounts = StudyCalendarEngine.completionCounts(completedAt: [morningInSeoul], calendar: utc)
        #expect(seoulCounts[date("2026-08-16")] == 1)
        #expect(utcCounts[date("2026-08-16")] == nil)
        #expect(LearningStreak.current(
            learningDays: LearningStreak.learningDays(from: seoulCounts),
            today: date("2026-08-16"),
            calendar: settings().calendar
        ) == 1)
    }

    /// 기기 시간대가 바뀌어도 지난 학습일은 움직이지 않는다 — 계획 시간대가 기준이다.
    @Test func travelingDoesNotMoveHistoricalLearningDays() {
        let mornings = ["2026-08-12", "2026-08-13", "2026-08-14"]
            .map { date($0).addingTimeInterval(9 * 3600) }
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        let planDays = StudyCalendarEngine.completionCounts(completedAt: mornings, calendar: settings().calendar)
        let deviceDays = StudyCalendarEngine.completionCounts(completedAt: mornings, calendar: newYork)
        #expect(Set(planDays.keys) == Set(["2026-08-12", "2026-08-13", "2026-08-14"].map { date($0) }))
        #expect(Set(deviceDays.keys).isDisjoint(with: planDays.keys))
        #expect(LearningStreak.current(
            learningDays: LearningStreak.learningDays(from: planDays),
            today: date("2026-08-14"),
            calendar: settings().calendar
        ) == 3)
    }

    /// D. 자정을 넘기면 오늘의 자리가 한 칸 옮겨간다.
    @Test func localMidnightMovesTheActiveStreakWindow() {
        let completions = ["2026-08-13": 1, "2026-08-14": 1]
        #expect(streak(completions, today: "2026-08-14") == 2)
        #expect(streak(completions, today: "2026-08-15") == 2)
        #expect(streak(completions, today: "2026-08-16") == 0)
    }

    /// E. 주간 스트립은 여전히 일요일에서 시작한다.
    @Test func weekStripStillStartsOnSunday() {
        let snapshot = snapshot(today: "2026-08-15", completions: ["2026-08-15": 1])
        #expect(snapshot.weekDays.first?.date == date("2026-08-09"))
        #expect(snapshot.weekDays.count == 7)
        #expect(snapshot.weekDays.last?.hasUnscheduledLearning == true)
    }
}

/// P8.1 — 지난 휴식일도 배정 0으로 고정한다.
/// 0을 저장하지 않으면 "기록 없음"이 되어, 나중에 공부 요일을 바꿨을 때 지난 휴식일이
/// 현재 설정으로 되살아나 학습일이 된다. 계획의 과거는 불변이어야 한다.
@MainActor
struct FrozenRestDayTests {
    private func date(_ text: String) -> Date { StudyCalendarFixture.date(text) }

    private func makePersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: StudyDayPlanRecord.self, StudySetCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func snapshot(
        settings: StudyPlanSettings,
        today: String,
        completions: [String: Int] = [:],
        historical: [String: Int] = [:]
    ) -> StudyCalendarSnapshot {
        StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 5,
            completions: StudyCalendarFixture.completions(completions),
            historicalTargets: historical,
            today: date(today)
        )
    }

    private func day(
        _ target: String,
        settings: StudyPlanSettings,
        snapshot: StudyCalendarSnapshot,
        completions: [String: Int]
    ) -> StudyDay {
        StudyCalendarEngine.day(
            date: date(target),
            today: snapshot.today.date,
            settings: settings,
            schedule: snapshot.schedule,
            completions: StudyCalendarFixture.completions(completions)
        )
    }

    private func frozen(_ persistence: PersistenceService) throws -> [String: Int] {
        try persistence.studyDayPlans().reduce(into: [:]) { $0[$1.localDate] = $1.targetSets }
    }

    /// A. 휴식일도 기록된다 — 배정 0으로.
    @Test func restDaysAreFrozenAsZero() throws {
        let persistence = try makePersistence()
        try persistence.freezeStudyDayPlans(["2026-08-15": 0, "2026-08-14": 2], today: "2026-08-14")
        let records = try frozen(persistence)
        #expect(records.count == 2)
        #expect(records["2026-08-15"] == 0)
        #expect(records["2026-08-14"] == 2)
    }

    /// B. 공부 요일을 바꿔도 지난 휴식일은 휴식일로 남는다(P8.1의 핵심).
    @Test func pastRestDaySurvivesAWeekdayEdit() throws {
        let persistence = try makePersistence()
        let before = StudyCalendarFixture.settings(createdAt: "2026-08-10")
        let completions = ["2026-08-15": 1]

        // 토요일에 자율 학습한 뒤 캘린더를 열어 지난 날들을 고정한다.
        let sealed = snapshot(settings: before, today: "2026-08-15", completions: completions)
        try persistence.freezeStudyDayPlans(
            sealed.targetsToFreeze(settings: before, today: date("2026-08-15")),
            today: "2026-08-15"
        )
        #expect(try frozen(persistence)["2026-08-15"] == 0)

        // 그 뒤 토요일을 공부 요일로 추가한다.
        let after = StudyCalendarFixture.settings(
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
            createdAt: "2026-08-10"
        )
        let updated = snapshot(
            settings: after,
            today: "2026-08-17",
            completions: completions,
            historical: try frozen(persistence)
        )
        let saturday = day("2026-08-15", settings: after, snapshot: updated, completions: completions)
        #expect(saturday.targetSets == 0)
        #expect(saturday.state == .rest)
        #expect(saturday.hasUnscheduledLearning)
        #expect(!saturday.isScheduled)  // 주간 계획 이행률의 분모에 들어가지 않는다
        #expect(saturday.setsSummaryText == "1세트 학습")
        #expect(saturday.studyAccessibilityText == "휴식, 1세트 학습")
    }

    /// C. 강도를 바꿔도 지난 휴식일은 0이다(지난 학습일의 고정 배정량도 그대로).
    @Test func pastRestDaySurvivesAnIntensityEdit() throws {
        let persistence = try makePersistence()
        let before = StudyCalendarFixture.settings(intensity: .light, createdAt: "2026-08-10")
        let sealed = snapshot(settings: before, today: "2026-08-15")
        try persistence.freezeStudyDayPlans(
            sealed.targetsToFreeze(settings: before, today: date("2026-08-15")),
            today: "2026-08-15"
        )

        let after = StudyCalendarFixture.settings(intensity: .focused, createdAt: "2026-08-10")
        let updated = snapshot(settings: after, today: "2026-08-17", historical: try frozen(persistence))
        #expect(updated.schedule.targetSets(for: date("2026-08-15")) == 0)  // 토요일 휴식
        #expect(updated.schedule.targetSets(for: date("2026-08-14")) == 1)  // 그때의 light 그대로
    }

    /// D. 시험일을 나중에 넣어도 지난 휴식일은 0이다.
    @Test func pastRestDaySurvivesAnExamDateEdit() throws {
        let persistence = try makePersistence()
        let before = StudyCalendarFixture.settings(createdAt: "2026-08-10")
        let sealed = snapshot(settings: before, today: "2026-08-15")
        try persistence.freezeStudyDayPlans(
            sealed.targetsToFreeze(settings: before, today: date("2026-08-15")),
            today: "2026-08-15"
        )

        let after = StudyCalendarFixture.settings(examDate: "2026-08-31", createdAt: "2026-08-10")
        let updated = snapshot(settings: after, today: "2026-08-17", historical: try frozen(persistence))
        #expect(updated.schedule.targetSets(for: date("2026-08-15")) == 0)
    }

    /// E·F. 고정된 0은 계획의 과거일 뿐, 스트릭 입력이 아니다 — 자율 학습은 계속 연속으로 센다.
    @Test func frozenZeroDoesNotTouchTheStreak() throws {
        let persistence = try makePersistence()
        let settings = StudyCalendarFixture.settings(createdAt: "2026-08-10")
        let completions = ["2026-08-14": 1, "2026-08-15": 1]
        let sealed = snapshot(settings: settings, today: "2026-08-15", completions: completions)
        try persistence.freezeStudyDayPlans(
            sealed.targetsToFreeze(settings: settings, today: date("2026-08-15")),
            today: "2026-08-15"
        )
        let reopened = snapshot(
            settings: settings,
            today: "2026-08-15",
            completions: completions,
            historical: try frozen(persistence)
        )
        #expect(reopened.streak == 2)
        #expect(reopened.today.targetSets == 0)
        #expect(reopened.weekScheduledDays == 5)  // 월~금 그대로. 토요일이 끼지 않는다.
        #expect(reopened.weekCompletedDays == 0)
    }

    /// G·I. 하루 상세와 캘린더 칸이 같은 값을 읽는다(문구 출처가 하나다).
    @Test func dayDetailAndCalendarShareTheFrozenZero() throws {
        let persistence = try makePersistence()
        let settings = StudyCalendarFixture.settings(createdAt: "2026-08-10")
        let completions = ["2026-08-15": 2]
        let sealed = snapshot(settings: settings, today: "2026-08-15", completions: completions)
        try persistence.freezeStudyDayPlans(
            sealed.targetsToFreeze(settings: settings, today: date("2026-08-15")),
            today: "2026-08-15"
        )
        let reopened = snapshot(
            settings: settings,
            today: "2026-08-16",
            completions: completions,
            historical: try frozen(persistence)
        )
        let saturday = day("2026-08-15", settings: settings, snapshot: reopened, completions: completions)
        // 주간 스트립·월간 격자가 만드는 칸(같은 엔진, 같은 일정)도 같은 값을 읽는다.
        let cell = StudyCalendarEngine.days(
            from: date("2026-08-09"),
            count: 7,
            today: reopened.today.date,
            settings: settings,
            schedule: reopened.schedule,
            completions: StudyCalendarFixture.completions(completions)
        ).first { $0.date == date("2026-08-15") }
        #expect(saturday.setsSummaryText == "2세트 학습")
        #expect(cell?.setsSummaryText == saturday.setsSummaryText)
        #expect(cell?.state == .rest)
    }

    /// J. 이미 고정된 양수 배정량은 다시 고정해도 바뀌지 않는다.
    @Test func existingPositiveRecordsAreNotRewritten() throws {
        let persistence = try makePersistence()
        try persistence.freezeStudyDayPlans(["2026-08-13": 3], today: "2026-08-14")
        let settings = StudyCalendarFixture.settings(
            weekdays: [.monday, .tuesday, .wednesday],  // 목·금이 휴식일로 바뀐 설정
            intensity: .focused,
            createdAt: "2026-08-10"
        )
        let sealed = snapshot(settings: settings, today: "2026-08-14")
        try persistence.freezeStudyDayPlans(
            sealed.targetsToFreeze(settings: settings, today: date("2026-08-14")),
            today: "2026-08-14"
        )
        let records = try frozen(persistence)
        #expect(records["2026-08-13"] == 3)  // 지난 기록은 덮이지 않는다
        #expect(records["2026-08-11"] == 3)  // 기록 없던 지난 학습일은 지금 값으로 한 번 채운다
        #expect(records["2026-08-12"] == 3)
    }

    /// K. 0을 채워도 저장량은 보관 기간(1년) 안에서 끝난다.
    @Test func zeroTargetsStayInsideTheRetentionWindow() {
        let settings = StudyCalendarFixture.settings(createdAt: "2020-01-01")
        let targets = AdaptiveStudyPlanner.targetsToFreeze(
            settings: settings,
            baseDailyTarget: 2,
            today: date("2026-08-17")
        )
        #expect(targets.count == 366)  // 오늘 포함 1년치
        #expect(targets.keys.min() == "2025-08-17")
        #expect(targets["2026-08-16"] == 0)  // 일요일은 0으로 남는다
        #expect(targets["2026-08-17"] == 2)
    }

    /// 보관 기간(1년)을 넘긴 기록은 예전처럼 지워진다 — 0짜리도 같은 규칙이다.
    @Test func oldRecordsAreStillTrimmed() throws {
        let persistence = try makePersistence()
        try persistence.freezeStudyDayPlans(["2025-01-03": 0, "2025-01-05": 2], today: "2025-01-05")
        #expect(try frozen(persistence).count == 2)

        // 1년 넘게 지난 뒤 다시 고정하면 옛 기록은 정리된다.
        try persistence.freezeStudyDayPlans(["2026-08-14": 2], today: "2026-08-14")
        let records = try frozen(persistence)
        #expect(records["2025-01-03"] == nil)
        #expect(records["2025-01-05"] == nil)
        #expect(records["2026-08-14"] == 2)
    }
}
