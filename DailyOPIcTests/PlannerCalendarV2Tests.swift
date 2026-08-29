import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 플래너 캘린더 V2와 날짜별 학습 기록(P14.5.2).
///
/// 이 파일이 지키는 약속은 하나다: **캘린더는 실제로 한 것만 말한다.** 세 숫자의
/// 출처가 서로 다르므로(단어/데일리/모의) 어느 하나도 화면에서 추정하거나 두 번
/// 세지 않는지, 기록이 없던 날을 완료로 부풀리지 않는지를 본다.
@MainActor
struct PlannerCalendarV2Tests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    // MARK: 도우미

    private func moment(_ localDate: String, hour: Int = 9) throws -> Date {
        let day = try #require(LocalCalendarDate.date(from: localDate, timeZone: seoul))
        return try #require(
            LocalCalendarDate.calendar(timeZone: seoul).date(byAdding: .hour, value: hour, to: day)
        )
    }

    private func makeService() throws -> PersistenceService {
        let container = try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func code(_ file: String) -> String {
        file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let plannerPath = "Views/Screens/Main/Calendar/PlannerHomeView.swift"
    private let screenPath = "Views/Screens/Main/Calendar/StudyCalendarScreen.swift"
    private let notificationPath = "Views/Screens/Main/Calendar/PlannerNotificationSettingsView.swift"

    // MARK: 1. 복습 횟수 (§10)

    /// 처음 학습한 것은 복습이 아니다. 하루 만에 "복습 1회"가 되면 숫자가 거짓말이 된다.
    @Test func firstStudyIsNotAReview() throws {
        let service = try makeService()
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: try moment("2026-08-28")
        )
        let record = try #require(try service.vocabularyStates().first)
        #expect(record.reviewCount == 0)
    }

    /// 같은 날 다시 답하는 것(카드 안 재시도)은 복습 회차가 아니다.
    @Test func sameDayRetryDoesNotCount() throws {
        let service = try makeService()
        for hour in [9, 10, 21] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: hour != 10,
                timeZone: seoul, now: try moment("2026-08-28", hour: hour)
            )
        }
        let record = try #require(try service.vocabularyStates().first)
        #expect(record.reviewCount == 0)
    }

    /// 다른 날 다시 학습하면 그때부터 1회씩 쌓인다.
    @Test func laterDaysCountAsReviews() throws {
        let service = try makeService()
        for date in ["2026-08-28", "2026-08-29", "2026-09-01"] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: try moment(date)
            )
        }
        let record = try #require(try service.vocabularyStates().first)
        #expect(record.reviewCount == 2)
    }

    /// 기존 사용자는 0에서 시작한다. 과거 학습을 복습으로 되짚어 만들지 않는다.
    @Test func existingRecordsStartAtZero() {
        let record = VocabularyStateRecord(entryID: "cafe-crowded")
        #expect(record.reviewCount == 0)
    }

    // MARK: 2. 날짜별 단어 학습량 (§28~§30)

    /// 그날 처음 다룬 단어만 센다. 같은 단어를 같은 날 세 번 답해도 1이다.
    @Test func aWordCountsOncePerDay() throws {
        let service = try makeService()
        for hour in [9, 12, 20] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true,
                timeZone: seoul, now: try moment("2026-08-28", hour: hour)
            )
        }
        try service.recordVocabularyAnswer(
            entryID: "airport-delay", knewIt: true, timeZone: seoul, now: try moment("2026-08-28")
        )
        let records = try service.studyActivityRecords()
        #expect(records.count == 1)
        #expect(records.first?.vocabularyStudiedCount == 2)
    }

    /// 날짜가 바뀌면 다른 줄이 된다. 어제의 숫자는 오늘 학습해도 그대로다.
    @Test func eachDayKeepsItsOwnCount() throws {
        let service = try makeService()
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: try moment("2026-08-28")
        )
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: try moment("2026-08-29")
        )
        let byDate = try service.studyActivityRecords()
            .reduce(into: [String: Int]()) { $0[$1.localDate] = $1.vocabularyStudiedCount }
        #expect(byDate == ["2026-08-28": 1, "2026-08-29": 1])
    }

    /// 배정 개수(완료 배지의 분모)는 같은 값으로 다시 적어도 한 줄로 남는다.
    @Test func theDailyGoalIsIdempotent() throws {
        let service = try makeService()
        for _ in 0..<3 {
            try service.setVocabularyDailyGoal(localDate: "2026-08-28", count: 20)
        }
        let records = try service.studyActivityRecords()
        #expect(records.count == 1)
        #expect(records.first?.vocabularyGoalCount == 20)
        // 목표만 적었을 뿐 학습한 것은 아직 없다.
        #expect(records.first?.vocabularyStudiedCount == 0)
    }

    // MARK: 3. 캘린더가 읽는 활동

    @Test func activitiesJoinThreeDifferentSources() throws {
        let record = StudyActivityDailyRecord(
            localDate: "2026-08-28", vocabularyStudiedCount: 20, vocabularyGoalCount: 20
        )
        let activities = PlannerActivityCalendar.activities(
            vocabulary: [record],
            dailyAnsweredAt: [try moment("2026-08-28"), try moment("2026-08-28", hour: 20)],
            mockCompletedAt: [try moment("2026-08-27")],
            timeZone: seoul
        )
        #expect(activities["2026-08-28"]?.vocabularyStudied == 20)
        #expect(activities["2026-08-28"]?.dailyAnswers == 2)
        #expect(activities["2026-08-28"]?.mockExams == 0)
        #expect(activities["2026-08-27"]?.mockExams == 1)
        // 아무것도 하지 않은 날은 아예 없다 — 빈 칸을 만들어 두지 않는다.
        #expect(activities["2026-08-26"] == nil)
    }

    /// 하루 경계는 학습 계획의 타임존을 따른다. 새 날짜 유틸을 만들지 않았다.
    @Test func theDayBoundaryFollowsTheStudyPlanTimeZone() throws {
        let instant = try moment("2026-08-28", hour: 8)
        let newYork = TimeZone(identifier: "America/New_York")!
        let seoulActivities = PlannerActivityCalendar.activities(
            vocabulary: [], dailyAnsweredAt: [instant], mockCompletedAt: [], timeZone: seoul
        )
        let newYorkActivities = PlannerActivityCalendar.activities(
            vocabulary: [], dailyAnsweredAt: [instant], mockCompletedAt: [], timeZone: newYork
        )
        #expect(seoulActivities.keys.first == "2026-08-28")
        #expect(newYorkActivities.keys.first == "2026-08-27")
    }

    /// 배지는 한 것만, 늘 같은 순서로, 최대 세 개.
    @Test func badgesShowOnlyWhatHappened() {
        #expect(PlannerActivityCalendar.badges(.empty).isEmpty)
        let all = PlannerDayActivity(
            vocabularyStudied: 20, vocabularyGoal: 20, dailyAnswers: 1, mockExams: 1
        )
        #expect(PlannerActivityCalendar.badges(all).map(\.label) == ["단어", "데일리", "모의"])
        let onlyDaily = PlannerDayActivity(dailyAnswers: 3)
        #expect(PlannerActivityCalendar.badges(onlyDaily).map(\.label) == ["데일리"])
        #expect(PlannerActivityCalendar.badges(onlyDaily).first?.count == 3)
    }

    /// 분모가 없는 날은 완료가 아니다. 이 기능 이전의 날짜가 갑자기 "완료"로 바뀌면 안 된다.
    @Test func completionNeedsARealDenominator() {
        #expect(!PlannerDayActivity(vocabularyStudied: 20, vocabularyGoal: 0).isVocabularyComplete)
        #expect(!PlannerDayActivity(vocabularyStudied: 12, vocabularyGoal: 20).isVocabularyComplete)
        #expect(PlannerDayActivity(vocabularyStudied: 20, vocabularyGoal: 20).isVocabularyComplete)
    }

    /// 배지는 아이콘이라 소리로 읽히지 않는다. 한 칸의 낭독에 한 일이 함께 들어간다.
    @Test func activityIsSpokenNotJustDrawn() {
        let activity = PlannerDayActivity(vocabularyStudied: 20, vocabularyGoal: 20, dailyAnswers: 1)
        let text = StudyDayCell.accessibilityText(
            date: "8월 28일", weekday: "금요일", isToday: true,
            completedSets: 1, hasEvent: false, activity: activity
        )
        #expect(text.contains("단어 20"))
        #expect(text.contains("데일리 1"))
        #expect(!text.contains("배지"))
        // 활동이 없으면 아무 말도 덧붙이지 않는다.
        #expect(PlannerActivityCalendar.accessibilityText(.empty) == nil)
    }

    /// 데일리·모의 숫자는 기록에서 **끌어내는** 값이라 화면을 다시 그려도 늘지 않는다.
    /// (단어만 별도 기록인데, 그쪽은 위에서 하루 한 번만 오르는 것을 확인했다.)
    @Test func recountingNeverInflates() throws {
        let record = StudyActivityDailyRecord(
            localDate: "2026-08-28", vocabularyStudiedCount: 20, vocabularyGoalCount: 20
        )
        let inputs = (
            daily: [try moment("2026-08-28"), try moment("2026-08-28", hour: 20)],
            mock: [try moment("2026-08-28", hour: 22)]
        )
        let first = PlannerActivityCalendar.activities(
            vocabulary: [record], dailyAnsweredAt: inputs.daily,
            mockCompletedAt: inputs.mock, timeZone: seoul
        )
        let second = PlannerActivityCalendar.activities(
            vocabulary: [record], dailyAnsweredAt: inputs.daily,
            mockCompletedAt: inputs.mock, timeZone: seoul
        )
        #expect(first == second)
        #expect(first["2026-08-28"] == PlannerDayActivity(
            vocabularyStudied: 20, vocabularyGoal: 20, dailyAnswers: 2, mockExams: 1
        ))
    }

    // MARK: 4. 플래너 홈은 캘린더다 (§12~§19)

    /// 내린 것들: 오늘의 학습 카드 · OPIc 팁 · 단어 학습하기 · 전체 캘린더 보기 ·
    /// 주간 스트립. 캘린더 하나만 남는다.
    @Test func theHubCardsAreGone() throws {
        let planner = code(try source(plannerPath))
        for removed in ["오늘의 학습", "OPIc 팁", "단어 학습하기", "전체 캘린더", "PlannerWeekStrip"] {
            #expect(!planner.contains(removed))
        }
        #expect(Set(PlannerRoute.allCases) == [.settings, .notifications])
    }

    /// 캘린더는 미리보기가 아니라 그 자체다. 달 이동이 여기 있고, 격자는 하나다.
    @Test func theMonthGridIsTheScreen() throws {
        let planner = code(try source(plannerPath))
        #expect(planner.contains("monthGrid"))
        #expect(planner.contains("monthOffset -= 1"))
        #expect(planner.contains("monthOffset += 1"))
        #expect(planner.contains("LazyVGrid"))
        // 격자를 두 번 그리지 않는다.
        #expect(planner.components(separatedBy: "LazyVGrid").count == 2)
    }

    /// 선택한 날 요약은 캘린더 아래 짧은 한 덩어리다 — 카드 더미가 아니다.
    @Test func theSelectedDaySummaryStaysSmall() throws {
        let planner = code(try source(plannerPath))
        #expect(planner.contains("selectedDaySummary"))
        #expect(planner.contains("+ 일정 추가"))
        // 요약은 캘린더보다 뒤에 온다.
        let grid = try #require(planner.range(of: "monthGrid\n"))
        let summary = try #require(planner.range(of: "selectedDaySummary\n"))
        #expect(grid.lowerBound < summary.lowerBound)
        // 카드 스타일은 요약 한 곳뿐이다.
        #expect(planner.components(separatedBy: ".cardStyle()").count == 2)
    }

    /// 칸 안의 일정은 최대 두 개 + "+n"이다. 세 번째 제목까지 그리면 숫자가 안 보인다.
    @Test func dayCellsFoldExtraSchedules() throws {
        let planner = code(try source(plannerPath))
        #expect(planner.contains("eventTitles.prefix(2)"))
        #expect(planner.contains("+\\(eventTitles.count - 2)"))
    }

    /// 데일리와 단어를 둘 다 끝낸 날에만 도장이 찍힌다.
    @Test func onlyBothCompleteGetsTheSeal() throws {
        let planner = code(try source(plannerPath))
        #expect(planner.contains("dailyCompleted && activity.isVocabularyComplete"))
        #expect(planner.contains("completionSeal"))
    }

    /// 스트릭은 현재와 최고를 함께 보여준다. 계산 규칙 자체는 그대로다.
    @Test func streakShowsCurrentAndBest() throws {
        let planner = code(try source(plannerPath))
        #expect(planner.contains("현재 연속 학습"))
        #expect(planner.contains("최고 연속 학습"))

        let calendar = LocalCalendarDate.calendar(timeZone: seoul)
        // 3일 연속 → 하루 쉼 → 2일 연속. 최고는 3, 지금은 2다.
        let days = ["2026-08-20", "2026-08-21", "2026-08-22", "2026-08-27", "2026-08-28"]
        let learningDays = Set(try days.map { try #require(LocalCalendarDate.date(from: $0, timeZone: seoul)) })
        #expect(LearningStreak.longest(learningDays: learningDays, calendar: calendar) == 3)
        #expect(LearningStreak.longest(learningDays: [], calendar: calendar) == 0)
    }

    /// 캘린더가 읽는 숫자는 화면이 아니라 기록에서 온다.
    @Test func theScreenReadsRecordsNotGuesses() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("PlannerActivityCalendar.activities("))
        #expect(screen.contains("vocabulary: activityRecords"))
        #expect(screen.contains("dailyAnsweredAt: learnedQuestionRecords.map(\\.learnedAt)"))
        #expect(screen.contains("mockCompletedAt: mockRecords.map(\\.createdAt)"))
        #expect(screen.contains("viewModel.settings?.timeZone ?? .current"))
    }

    // MARK: 5. 학습 알림 (§23~§27)

    /// 톱니가 아니라 종이다. 그리고 그 종은 알림 화면 하나만 연다.
    @Test func theToolbarIconIsABell() throws {
        let planner = code(try source(plannerPath))
        #expect(planner.contains("Image(systemName: \"bell\")"))
        #expect(planner.contains("NavigationLink(value: PlannerRoute.notifications)"))
        #expect(planner.contains("accessibilityLabel(\"학습 알림\")"))
        #expect(!planner.contains("gearshape"))
    }

    /// 화면을 여는 것만으로 권한을 묻지 않는다. 켠 순간에만 묻는다.
    @Test func permissionIsAskedOnlyWhenTurningItOn() throws {
        let view = code(try source(notificationPath))
        #expect(view.contains("await environment.studyReminders.enable()"))
        #expect(view.contains("await environment.studyReminders.disable()"))
        // .task는 상태를 새로 읽기만 한다.
        #expect(view.contains(".task { await environment.studyReminders.refreshAuthorizationStatus() }"))
        #expect(!view.contains(".task { await environment.studyReminders.enable()"))
        #expect(!view.contains("requestAuthorization"))
    }

    /// 꺼 둔 알림의 시각을 고르게 하지 않는다.
    @Test func theTimePickerOnlyExistsWhenOn() throws {
        let view = code(try source(notificationPath))
        #expect(view.contains("if reminderState.isOn {"))
        let toggle = try #require(view.range(of: "if reminderState.isOn {"))
        let picker = try #require(view.range(of: "DatePicker("))
        #expect(toggle.lowerBound < picker.lowerBound)
        #expect(view.contains("오늘 학습 알림"))
        #expect(view.contains("오늘 학습 시간"))
        #expect(view.contains("displayedComponents: .hourAndMinute"))
    }

    /// 스위치는 앱 설정 화면에도 있다. 두 화면이 **같은 값 하나**를 읽고 쓰므로
    /// 한쪽에서 끈 알림이 다른 쪽에서 켜져 보일 수 없다.
    @Test func bothSwitchesReadTheSameTruth() throws {
        let planner = code(try source(notificationPath))
        let settings = code(try source("Views/Screens/Setup/SetupView.swift"))
        for view in [planner, settings] {
            #expect(view.contains("preference: environment.studyReminders.preference"))
            #expect(view.contains("authorization: environment.studyReminders.authorizationStatus"))
        }
        // 두 번째 선호값(로컬 @State 스위치)을 만들지 않았다.
        #expect(!planner.contains("@State private var isOn"))
    }

    /// 새 알림 서비스도 서버도 만들지 않았다. 예약은 언제나 같은 재조정 한 곳을 거친다.
    @Test func noSecondNotificationSystemWasBuilt() throws {
        let view = code(try source(notificationPath))
        #expect(view.contains("viewModel.reconcileReminders()"))
        #expect(!view.contains("UNUserNotificationCenter"))
        #expect(!view.contains("APIClient"))
        #expect(!view.contains("notifications/"))
    }
}
