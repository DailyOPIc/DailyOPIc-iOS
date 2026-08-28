import Foundation
import Testing
@testable import DailyOPIc

/// P6 · P10: 주간 스트립에서도 전체 캘린더에서도 하루를 열 수 있다.
/// 이 파일이 지키는 것은 "같은 날짜면 어디서 눌러도 같은 하루가 열린다"는 한 가지다.
/// P10부터 그 "열림"은 화면 밀어내기가 아니라 시트 하나이고, 두 진입점이 넘기는 값은
/// 같은 `LocalCalendarDate.text(from:timeZone:)` 결과다.
@MainActor
struct PlannerNavigationTests {
    private let seoul = StudyCalendarFixture.seoulTimeZone
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func date(_ text: String) -> Date { StudyCalendarFixture.date(text) }

    private func snapshot(
        today: String,
        completions: [String: Int] = [:],
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    ) -> StudyCalendarSnapshot {
        StudyCalendarSnapshot.make(
            settings: StudyCalendarFixture.settings(weekdays: weekdays),
            targetLevel: .IH,
            recentLevel: nil,
            dailyCapacity: 3,
            completions: StudyCalendarFixture.completions(completions),
            today: date(today)
        )
    }

    // MARK: A. 일요일 시작 칸 → 로컬 날짜

    /// 목요일에 열어도 첫 칸은 그 주 일요일이고, 각 칸이 자기 날짜 키를 만든다.
    @Test func weekCellsMapToTheirOwnLocalDates() {
        let week = snapshot(today: "2026-08-20").weekDays   // 2026-08-20은 목요일
        #expect(
            week.map { LocalCalendarDate.text(from: $0.date, timeZone: seoul) }
            == [
                "2026-08-16", "2026-08-17", "2026-08-18",
                "2026-08-19", "2026-08-20", "2026-08-21", "2026-08-22",
            ]
        )
        #expect(LocalCalendarDate.text(from: week[4].date, timeZone: seoul) == "2026-08-20")
    }

    /// 시트에 실리는 값은 Date가 아니라 로컬 날짜 문자열이다. 타임존이 다르면 다른 날이다.
    @Test func selectionCarriesTheLocalDateNotTheInstant() {
        let noon = date("2026-08-20").addingTimeInterval(12 * 3600)
        #expect(
            PlannerSelectedDate(LocalCalendarDate.text(from: noon, timeZone: seoul)).id
            == "2026-08-20"
        )
        // 같은 순간이라도 뉴욕에서는 8월 19일 밤이다 — 계획 타임존을 넘겨야 하는 이유.
        #expect(
            PlannerSelectedDate(LocalCalendarDate.text(from: noon, timeZone: newYork)).id
            == "2026-08-19"
        )
    }

    /// 하루로 **밀고 들어가는** 경로는 더 이상 없다. 남은 경로는 전체 캘린더와 설정뿐이다.
    /// (숨은 두 번째 경로가 생기면 여기서 걸린다.)
    @Test func plannerHasNoDayDetailRoute() {
        #expect(Set(PlannerRoute.allCases) == [.fullCalendar, .settings])
        #expect(PlannerRoute.allCases.count == 2)
    }

    // MARK: B. 두 진입점이 같은 경로를 만든다

    /// 주간 스트립과 전체 캘린더는 같은 날짜에서 **같은** 선택 값을 만든다.
    /// (둘 다 `LocalCalendarDate.text(from:timeZone:)` 하나를 쓴다.)
    @Test func weekStripAndFullCalendarProduceTheSameSelection() {
        let settings = StudyCalendarFixture.settings()
        let snapshot = snapshot(today: "2026-08-20")
        let monthDays = StudyCalendarEngine.days(
            from: date("2026-08-01"),
            count: 31,
            today: snapshot.today.date,
            settings: settings,
            schedule: snapshot.schedule,
            completions: [:]
        )
        for day in snapshot.weekDays {
            let fromWeek = LocalCalendarDate.text(from: day.date, timeZone: seoul)
            let sameDayInMonth = monthDays.first { $0.date == day.date }
            let fromMonth = sameDayInMonth.map {
                LocalCalendarDate.text(from: $0.date, timeZone: seoul)
            }
            #expect(fromWeek == fromMonth)
            // 시트를 여는 값도 하나뿐이다 — 어느 쪽에서 눌러도 같은 시트가 뜬다.
            #expect(PlannerSelectedDate(fromWeek) == fromMonth.map(PlannerSelectedDate.init))
        }
    }

    /// 하루 시트가 그 키로 되짚어 여는 날짜도 같은 날이다(문자열 → Date 왕복).
    @Test func selectionRoundTripsBackToTheSameDay() throws {
        let week = snapshot(today: "2026-08-20").weekDays
        for day in week {
            let key = PlannerSelectedDate(LocalCalendarDate.text(from: day.date, timeZone: seoul)).id
            #expect(LocalCalendarDate.date(from: key, timeZone: seoul) == day.date)
        }
    }

    // MARK: C. 일곱 칸

    @Test func weekStripAlwaysHasSevenCellsStartingSunday() {
        for today in ["2026-08-16", "2026-08-20", "2026-08-22", "2026-02-28"] {
            let week = snapshot(today: today).weekDays
            #expect(week.count == 7)
            let calendar = LocalCalendarDate.calendar(timeZone: seoul)
            #expect(StudyWeekday.from(date: week[0].date, calendar: calendar) == .sunday)
            #expect(StudyWeekday.from(date: week[6].date, calendar: calendar) == .saturday)
            // 선택 키도 일곱 개가 모두 다르다.
            #expect(Set(week.map { LocalCalendarDate.text(from: $0.date, timeZone: seoul) }).count == 7)
        }
    }

    // MARK: D. 이동해도 학습 상태는 그대로

    /// 하루 시트를 열어 보는 것으로 학습 판정이 달라지지 않는다.
    /// (선택 키 생성은 순수 함수이고, 상태는 완료 기록에서만 나온다.)
    @Test func openingDaySheetDoesNotChangeStudyState() {
        let completions = ["2026-08-17": 3, "2026-08-18": 1]
        let before = snapshot(today: "2026-08-20", completions: completions)
        let states = before.weekDays.map(\.state)
        for day in before.weekDays {
            _ = PlannerSelectedDate(LocalCalendarDate.text(from: day.date, timeZone: seoul))
        }
        let after = snapshot(today: "2026-08-20", completions: completions)
        #expect(after.weekDays.map(\.state) == states)
        #expect(after.weekDays.map(\.completedSets) == before.weekDays.map(\.completedSets))
        #expect(after.weekDays.map(\.targetSets) == before.weekDays.map(\.targetSets))
        // 하루 시트가 읽는 값도 격자와 같은 계산에서 나온다.
        let detailDay = StudyCalendarEngine.day(
            date: date("2026-08-17"),
            today: after.today.date,
            settings: StudyCalendarFixture.settings(),
            schedule: after.schedule,
            completions: StudyCalendarFixture.completions(completions)
        )
        let stripDay = after.weekDays.first { $0.date == date("2026-08-17") }
        #expect(detailDay.state == stripDay?.state)
        #expect(detailDay.completedSets == stripDay?.completedSets)
    }

    /// 휴식일 칸도 시트를 열 수 있다. 열 수 없는 날을 만들지 않는다.
    @Test func restDaysAreReachableToo() {
        let week = snapshot(today: "2026-08-20").weekDays
        let sunday = week[0]
        #expect(sunday.state == .rest)
        #expect(LocalCalendarDate.text(from: sunday.date, timeZone: seoul) == "2026-08-16")
    }
}
