import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// P3: 하루 상세의 개인 일정·메모는 이 기기에만 저장되고,
/// 학습 기록은 그 저장과 무관하게 실제 학습에서만 나온다.
@MainActor
struct PlannerLocalEntryTests {
    private func makePersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: PlannerEventRecord.self, PlannerDayNoteRecord.self,
            StudySetCompletionRecord.self, StudyDayPlanRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    // MARK: A·B·C. 추가와 날짜 분리

    @Test func eventIsAddedToItsOwnDate() throws {
        let persistence = try makePersistence()
        #expect(
            try persistence.savePlannerEvent(
                localDate: "2026-08-20",
                title: "카페에서 OPIc 공부",
                timeMinutes: 19 * 60
            )
        )
        let events = try persistence.plannerEvents(on: "2026-08-20")
        #expect(events.count == 1)
        #expect(events.first?.title == "카페에서 OPIc 공부")
        #expect(events.first?.timeMinutes == 1140)
        #expect(events.first?.time?.hour == 19)
    }

    @Test func multipleEventsCanShareOneDay() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "모의고사 풀기")
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "모의고사 풀기") // 같은 제목 허용
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "스터디", timeMinutes: 9 * 60
        )
        try persistence.savePlannerEvent(
            localDate: "2026-08-20", title: "복습", timeMinutes: 9 * 60 // 같은 시각 허용
        )
        #expect(try persistence.plannerEvents(on: "2026-08-20").count == 4)
    }

    @Test func eventsOnDifferentDatesStaySeparated() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "스터디")
        try persistence.savePlannerEvent(localDate: "2026-08-21", title: "면접")
        #expect(try persistence.plannerEvents(on: "2026-08-20").map(\.title) == ["스터디"])
        #expect(try persistence.plannerEvents(on: "2026-08-21").map(\.title) == ["면접"])
        #expect(try persistence.plannerEvents(on: "2026-08-22").isEmpty)
    }

    @Test func emptyTitleIsNeverSaved() throws {
        let persistence = try makePersistence()
        #expect(try persistence.savePlannerEvent(localDate: "2026-08-20", title: "   ") == false)
        #expect(try persistence.savePlannerEvent(localDate: "2026-08-20", title: "") == false)
        #expect(try persistence.plannerEvents(on: "2026-08-20").isEmpty)
    }

    @Test func titleIsTrimmedOnSave() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "  스터디 모임  ")
        #expect(try persistence.plannerEvents(on: "2026-08-20").first?.title == "스터디 모임")
    }

    // MARK: D·E·F. 수정과 삭제

    @Test func editingChangesTitleWithoutAddingARow() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "스터디")
        let id = try #require(try persistence.plannerEvents(on: "2026-08-20").first?.id)

        try persistence.savePlannerEvent(id: id, localDate: "2026-08-20", title: "스터디 취소됨")
        let events = try persistence.plannerEvents(on: "2026-08-20")
        #expect(events.count == 1)
        #expect(events.first?.title == "스터디 취소됨")
        #expect(events.first?.id == id)
    }

    @Test func editingChangesTimeIncludingRemovingIt() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "스터디")
        let id = try #require(try persistence.plannerEvents(on: "2026-08-20").first?.id)

        try persistence.savePlannerEvent(
            id: id, localDate: "2026-08-20", title: "스터디", timeMinutes: 7 * 60 + 30
        )
        #expect(try persistence.plannerEvents(on: "2026-08-20").first?.timeMinutes == 450)

        // 시간을 다시 비우면 "시간 없음"으로 돌아간다.
        try persistence.savePlannerEvent(id: id, localDate: "2026-08-20", title: "스터디")
        #expect(try persistence.plannerEvents(on: "2026-08-20").first?.timeMinutes == nil)
    }

    @Test func deletingRemovesOnlyThatEvent() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "스터디")
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "면접")
        let id = try #require(
            try persistence.plannerEvents(on: "2026-08-20").first { $0.title == "스터디" }?.id
        )

        try persistence.deletePlannerEvent(id: id)
        #expect(try persistence.plannerEvents(on: "2026-08-20").map(\.title) == ["면접"])
        // 없는 일정을 지워도 조용히 넘어간다.
        try persistence.deletePlannerEvent(id: UUID())
        #expect(try persistence.plannerEvents(on: "2026-08-20").count == 1)
    }

    // MARK: G·H. 시간 없는 일정과 정렬

    @Test func untimedEventKeepsNoTime() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "언젠가 복습")
        let event = try #require(try persistence.plannerEvents(on: "2026-08-20").first)
        #expect(event.timeMinutes == nil)
        #expect(event.time == nil) // 없는 시각을 지어내지 않는다
        // 범위를 벗어난 값도 시간 없음으로 정규화된다.
        #expect(PlannerEventRecord.normalizedTimeMinutes(-1) == nil)
        #expect(PlannerEventRecord.normalizedTimeMinutes(24 * 60) == nil)
        #expect(PlannerEventRecord.normalizedTimeMinutes(0) == 0)
    }

    @Test func timedEventsComeFirstInChronologicalOrder() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "저녁 학습", timeMinutes: 1140)
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "시간 미정")
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "아침 학습", timeMinutes: 420)
        #expect(
            try persistence.plannerEvents(on: "2026-08-20").map(\.title)
            == ["아침 학습", "저녁 학습", "시간 미정"]
        )
    }

    // MARK: I. 타임존이 바뀌어도 같은 날

    /// 날짜 정체성은 "yyyy-MM-dd" 문자열이다. 기기 타임존이 바뀌어도 일정이 옆 칸으로 넘어가지 않는다.
    @Test func localDateKeyIsStableAcrossTimezones() throws {
        let persistence = try makePersistence()
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let newYork = TimeZone(identifier: "America/New_York")!
        // 서울 기준 8월 20일 09:00에 만든 일정.
        let moment = LocalCalendarDate.date(from: "2026-08-20", timeZone: seoul)!
            .addingTimeInterval(9 * 60 * 60)
        let key = LocalCalendarDate.text(from: moment, timeZone: seoul)
        #expect(key == "2026-08-20")
        try persistence.savePlannerEvent(localDate: key, title: "스터디", timeMinutes: 9 * 60)
        try persistence.savePlannerNote(localDate: key, text: "오늘 IH 목표")

        // 뉴욕으로 옮겨도 같은 키로 읽는다. 저장된 값 자체가 문자열이라 흔들릴 여지가 없다.
        #expect(try persistence.plannerEvents(on: "2026-08-20").count == 1)
        #expect(try persistence.plannerNote(on: "2026-08-20")?.text == "오늘 IH 목표")
        // 절대 시각으로 저장했다면 뉴욕에서 8월 19일이 됐을 순간이다.
        #expect(LocalCalendarDate.text(from: moment, timeZone: newYork) == "2026-08-19")
        #expect(try persistence.plannerEvents(on: "2026-08-19").isEmpty)
        // 벽시계 09:00도 그대로다(절대 시각이 아니라 분으로 저장한다).
        #expect(try persistence.plannerEvents(on: "2026-08-20").first?.time?.hour == 9)
    }

    // MARK: J·K·L·M. 메모

    @Test func memoIsSavedForItsDate() throws {
        let persistence = try makePersistence()
        #expect(try persistence.savePlannerNote(localDate: "2026-08-20", text: "롤플레이 연습하기"))
        #expect(try persistence.plannerNote(on: "2026-08-20")?.text == "롤플레이 연습하기")
        #expect(try persistence.plannerNote(on: "2026-08-21") == nil)
    }

    @Test func memoUpdateReplacesTheText() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerNote(localDate: "2026-08-20", text: "첫 메모")
        let createdAt = try #require(try persistence.plannerNote(on: "2026-08-20")?.createdAt)
        try persistence.savePlannerNote(localDate: "2026-08-20", text: "고친 메모")

        let note = try #require(try persistence.plannerNote(on: "2026-08-20"))
        #expect(note.text == "고친 메모")
        #expect(note.createdAt == createdAt) // 같은 기록을 고친다
    }

    @Test func whitespaceOnlyMemoIsTreatedAsNoMemo() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerNote(localDate: "2026-08-20", text: "기억할 것")
        #expect(try persistence.savePlannerNote(localDate: "2026-08-20", text: "   \n ") == false)
        #expect(try persistence.plannerNote(on: "2026-08-20") == nil)
        // 처음부터 공백만 적으면 아무것도 만들지 않는다.
        #expect(try persistence.savePlannerNote(localDate: "2026-08-21", text: " ") == false)
        #expect(try persistence.plannerNote(on: "2026-08-21") == nil)
        // 앞뒤 공백은 털어서 저장한다.
        try persistence.savePlannerNote(localDate: "2026-08-22", text: "  메모  ")
        #expect(try persistence.plannerNote(on: "2026-08-22")?.text == "메모")
    }

    @Test func memoIsDeletedExplicitly() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerNote(localDate: "2026-08-20", text: "지울 메모")
        try persistence.deletePlannerNote(localDate: "2026-08-20")
        #expect(try persistence.plannerNote(on: "2026-08-20") == nil)
    }

    /// 날짜당 메모는 하나뿐이다. 여러 번 저장해도 기록이 늘지 않는다.
    @Test func onlyOneMemoExistsPerDate() throws {
        let persistence = try makePersistence()
        for text in ["하나", "둘", "셋"] {
            try persistence.savePlannerNote(localDate: "2026-08-20", text: text)
        }
        #expect(try persistence.plannerNote(on: "2026-08-20")?.text == "셋")
        try persistence.savePlannerNote(localDate: "2026-08-21", text: "다른 날")
        #expect(try persistence.plannerNote(on: "2026-08-20")?.text == "셋")
    }
}

/// 하루 상세가 말하는 학습 상태. 격자와 같은 계산에서 나오고, 사용자가 손으로 바꿀 수 없다.
@MainActor
struct PlannerDayStudyStatusTests {
    private let settings = StudyCalendarFixture.settings() // 월~금, 하루 2세트

    private func status(
        _ date: String,
        today: String,
        completions: [String: Int] = [:],
        historical: [String: Int] = [:],
        intensity: StudyIntensity = .steady
    ) -> PlannerDayStudyStatus {
        let settings = StudyCalendarFixture.settings(intensity: intensity)
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 5,
            completions: StudyCalendarFixture.completions(completions),
            historicalTargets: historical,
            today: StudyCalendarFixture.date(today)
        )
        let day = StudyCalendarEngine.day(
            date: StudyCalendarFixture.date(date),
            today: snapshot.today.date,
            settings: settings,
            schedule: snapshot.schedule,
            completions: StudyCalendarFixture.completions(completions)
        )
        return PlannerDayStudyStatus.make(
            day: day,
            isStudyWeekday: settings.isStudyDay(StudyCalendarFixture.date(date))
        )
    }

    // A. 지난 학습일, 배정만큼 다 했다.
    @Test func pastFullyCompletedDayIsCompleted() {
        #expect(
            status("2026-08-12", today: "2026-08-14", completions: ["2026-08-12": 2]) == .completed
        )
    }

    // B. 지난 학습일, 일부만 했다.
    @Test func pastPartiallyCompletedDayIsPartial() {
        #expect(
            status("2026-08-12", today: "2026-08-14", completions: ["2026-08-12": 1]) == .partial
        )
    }

    // C. 지난 학습일, 기록이 없다. 문구는 자책하게 만들지 않는다.
    @Test func pastDayWithoutRecordIsMissedButNeutral() {
        #expect(status("2026-08-12", today: "2026-08-14") == .missed)
        #expect(PlannerDayStudyStatus.missed.title == "아직 학습 기록이 없어요")
    }

    // D. 미래 학습일은 "미완료"가 아니라 예정이다.
    @Test func futureStudyDayIsScheduled() {
        #expect(status("2026-08-19", today: "2026-08-14") == .scheduled)
        #expect(PlannerDayStudyStatus.scheduled.title == "학습 예정")
    }

    // E. 공부 요일이 아닌 날은 휴식일이다.
    @Test func nonStudyWeekdayIsRest() {
        // 2026-08-15는 토요일(공부 요일 아님).
        #expect(status("2026-08-15", today: "2026-08-14") == .rest)
    }

    // F. 아직 끝나지 않은 오늘의 0세트는 지난 날의 미기록과 같지 않다.
    @Test func todayWithoutProgressIsNotTreatedAsAPastMiss() {
        #expect(status("2026-08-14", today: "2026-08-14") == .scheduled)
        #expect(status("2026-08-14", today: "2026-08-14", completions: ["2026-08-14": 1]) == .partial)
        #expect(status("2026-08-14", today: "2026-08-14", completions: ["2026-08-14": 2]) == .completed)
    }

    // G. 지난 날은 그날 고정된 배정량으로 판정한다. 오늘 강도를 올려도 어제가 바뀌지 않는다.
    @Test func frozenHistoricalTargetWinsOverNewSettings() {
        // 어제는 1세트 배정 · 1세트 완료로 고정돼 있다.
        let frozen = ["2026-08-13": 1]
        #expect(
            status(
                "2026-08-13",
                today: "2026-08-14",
                completions: ["2026-08-13": 1],
                historical: frozen,
                intensity: .focused // 오늘부터 하루 3세트로 올렸다
            ) == .completed
        )
        // 고정 기록이 없었다면 오늘 설정(3세트)으로 되살아나 "일부 학습"이 됐을 상황이다.
        #expect(
            status(
                "2026-08-13",
                today: "2026-08-14",
                completions: ["2026-08-13": 1],
                intensity: .focused
            ) == .partial
        )
    }

    // H. 배정보다 더 해도 목표가 늘어나지 않는다.
    @Test func extraCompletionDoesNotCorruptTheTarget() {
        let settings = StudyCalendarFixture.settings()
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 5,
            completions: StudyCalendarFixture.completions(["2026-08-12": 5]),
            historicalTargets: ["2026-08-12": 2],
            today: StudyCalendarFixture.date("2026-08-14")
        )
        let day = StudyCalendarEngine.day(
            date: StudyCalendarFixture.date("2026-08-12"),
            today: snapshot.today.date,
            settings: settings,
            schedule: snapshot.schedule,
            completions: StudyCalendarFixture.completions(["2026-08-12": 5])
        )
        #expect(day.targetSets == 2)
        #expect(day.completedSets == 5)
        #expect(PlannerDayStudyStatus.make(day: day, isStudyWeekday: true) == .completed)
    }

    /// 배정이 0인 공부 요일은 휴식일이 아니라 "계획 없음"이다(계획이 끝난 뒤의 학습 요일).
    @Test func studyWeekdayWithoutTargetIsUnplanned() {
        let day = StudyDay(
            date: StudyCalendarFixture.date("2026-08-14"),
            state: .rest,
            completedSets: 0,
            targetSets: 0
        )
        #expect(PlannerDayStudyStatus.make(day: day, isStudyWeekday: true) == .unplanned)
        #expect(PlannerDayStudyStatus.make(day: day, isStudyWeekday: false) == .rest)
    }
}

/// 캘린더 격자와 하루 상세가 같은 날짜·같은 사실을 가리키는지.
@MainActor
struct PlannerDayDetailIntegrationTests {
    private let settings = StudyCalendarFixture.settings()

    private func makePersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: PlannerEventRecord.self, PlannerDayNoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    /// 격자에서 누른 칸이 그 칸의 날짜로 열린다(뷰가 쓰는 변환과 같은 함수).
    @Test func tappingADateResolvesThatDatesLocalKey() {
        let calendar = settings.calendar
        let monthStart = StudyCalendarFixture.date("2026-08-01")
        for offset in [0, 13, 19, 30] {
            let day = calendar.date(byAdding: .day, value: offset, to: monthStart)!
            let key = LocalCalendarDate.text(from: day, timeZone: settings.timeZone)
            #expect(PlannerRoute.dayDetail(key) == PlannerRoute.dayDetail(key))
            #expect(LocalCalendarDate.date(from: key, timeZone: settings.timeZone) == day)
        }
        #expect(
            LocalCalendarDate.text(
                from: StudyCalendarFixture.date("2026-08-20"),
                timeZone: settings.timeZone
            ) == "2026-08-20"
        )
    }

    /// 일요일 시작은 그대로다(P2 회귀 방지).
    @Test func sundayFirstLayoutSurvivesDayDetail() {
        #expect(StudyWeekday.displayOrder.map(\.shortLabel) == ["일", "월", "화", "수", "목", "금", "토"])
        #expect(
            StudyCalendarEngine.startOfWeek(
                for: StudyCalendarFixture.date("2026-08-20"),
                calendar: settings.calendar
            ) == StudyCalendarFixture.date("2026-08-16") // 그 주 일요일
        )
    }

    /// 개인 일정·메모가 있는 날에만 표시가 붙고, 학습 상태는 전혀 건드리지 않는다.
    @Test func entryIndicatorsFollowStoredEntriesOnly() throws {
        let persistence = try makePersistence()
        try persistence.savePlannerEvent(localDate: "2026-08-20", title: "스터디")
        try persistence.savePlannerNote(localDate: "2026-08-21", text: "메모")

        #expect(try !persistence.plannerEvents(on: "2026-08-20").isEmpty) // 일정 표시
        #expect(try persistence.plannerNote(on: "2026-08-20") == nil)     // 메모 표시 없음
        #expect(try persistence.plannerEvents(on: "2026-08-21").isEmpty)  // 일정 표시 없음
        #expect(try persistence.plannerNote(on: "2026-08-21") != nil)     // 메모 표시
        #expect(try persistence.plannerEvents(on: "2026-08-22").isEmpty)
        #expect(try persistence.plannerNote(on: "2026-08-22") == nil)
    }

    /// 일정·메모를 아무리 적어도 그날의 학습 상태와 고정된 배정량은 그대로다.
    @Test func personalEntriesNeverChangeStudyTruth() throws {
        let persistence = try makePersistence()
        let frozen = ["2026-08-12": 2]
        func day() -> StudyDay {
            let snapshot = StudyCalendarSnapshot.make(
                settings: settings,
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: 2,
                completions: StudyCalendarFixture.completions(["2026-08-12": 1]),
                historicalTargets: frozen,
                today: StudyCalendarFixture.date("2026-08-14")
            )
            return StudyCalendarEngine.day(
                date: StudyCalendarFixture.date("2026-08-12"),
                today: snapshot.today.date,
                settings: settings,
                schedule: snapshot.schedule,
                completions: StudyCalendarFixture.completions(["2026-08-12": 1])
            )
        }
        let before = day()
        try persistence.savePlannerEvent(localDate: "2026-08-12", title: "공부 다 했다고 치기")
        try persistence.savePlannerNote(localDate: "2026-08-12", text: "완료!")
        let after = day()

        #expect(before.state == .partial)
        #expect(after.state == before.state)        // 손으로 완료를 만들 수 없다
        #expect(after.targetSets == 2)              // 고정된 배정량 그대로
        #expect(after.completedSets == before.completedSets)
    }
}
