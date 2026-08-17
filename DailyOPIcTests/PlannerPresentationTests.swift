import Foundation
import Testing
@testable import DailyOPIc

/// P2: 화면은 일요일부터 그리고, 저장·전송 값은 ISO(월=1 … 일=7) 그대로다.
/// 이 파일의 목적은 "표시 순서를 바꿨을 뿐 데이터는 그대로"를 증명하는 것이다.
@MainActor
struct PlannerPresentationTests {
    private let calendar = LocalCalendarDate.calendar(timeZone: StudyCalendarFixture.seoulTimeZone)

    private func date(_ text: String) -> Date { StudyCalendarFixture.date(text) }

    // MARK: A. 표시 순서

    @Test func weekdayDisplayOrderStartsOnSunday() {
        #expect(
            StudyWeekday.displayOrder == [
                .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday
            ]
        )
        #expect(StudyWeekday.displayOrder.map(\.shortLabel) == ["일", "월", "화", "수", "목", "금", "토"])
        // 일곱 요일이 하나도 빠지거나 겹치지 않는다.
        #expect(Set(StudyWeekday.displayOrder) == Set(StudyWeekday.allCases))
    }

    @Test func displayColumnsRunSundayToSaturday() {
        #expect(StudyWeekday.displayOrder.map(\.displayColumn) == [0, 1, 2, 3, 4, 5, 6])
    }

    /// 주간 스트립도 같은 기준으로 시작한다(월요일에 열어도 그 주 일요일부터).
    @Test func weekStripStartsOnSunday() {
        // 2026-08-10은 월요일이다.
        #expect(
            StudyCalendarEngine.startOfWeek(for: date("2026-08-10"), calendar: calendar)
            == date("2026-08-09")
        )
        // 일요일에 열면 그날이 곧 주의 시작이다.
        #expect(
            StudyCalendarEngine.startOfWeek(for: date("2026-08-09"), calendar: calendar)
            == date("2026-08-09")
        )
        // 토요일은 주의 마지막 칸이다.
        #expect(
            StudyCalendarEngine.startOfWeek(for: date("2026-08-15"), calendar: calendar)
            == date("2026-08-09")
        )
    }

    // MARK: B. ISO 저장값

    @Test func isoWeekdayValuesAreUnchanged() {
        #expect(StudyWeekday.monday.rawValue == 1)
        #expect(StudyWeekday.tuesday.rawValue == 2)
        #expect(StudyWeekday.wednesday.rawValue == 3)
        #expect(StudyWeekday.thursday.rawValue == 4)
        #expect(StudyWeekday.friday.rawValue == 5)
        #expect(StudyWeekday.saturday.rawValue == 6)
        #expect(StudyWeekday.sunday.rawValue == 7)
        // 날짜 → 요일 변환도 ISO 그대로다.
        #expect(StudyWeekday.from(date: date("2026-08-10"), calendar: calendar) == .monday)
        #expect(StudyWeekday.from(date: date("2026-08-09"), calendar: calendar) == .sunday)
    }

    /// 서버로 나가는 배열은 여전히 ISO 오름차순이다. 일요일이 앞으로 오지 않는다.
    @Test func wireWeekdaysStayISOSorted() throws {
        let settings = StudyCalendarFixture.settings(
            weekdays: [.sunday, .monday, .wednesday]
        )
        #expect(StudyPlanRequest(settings: settings).studyWeekdays == [1, 3, 7])

        let json = try #require(
            try JSONSerialization.jsonObject(
                with: try JSONCoding.encoder.encode(settings)
            ) as? [String: Any]
        )
        #expect(json["studyWeekdays"] as? [Int] == [1, 3, 7])
    }

    // MARK: C·D·E. 월간 격자 정렬

    /// 1일이 일요일이면 첫 칸(0열)에 놓인다.
    @Test func monthStartingOnSundayPlacesDayOneInFirstColumn() {
        // 2026-02-01, 2026-03-01, 2026-11-01은 모두 일요일이다.
        for text in ["2026-02-01", "2026-03-01", "2026-11-01"] {
            let first = date(text)
            #expect(StudyWeekday.from(date: first, calendar: calendar) == .sunday)
            #expect(StudyWeekday.from(date: first, calendar: calendar).displayColumn == 0)
        }
    }

    /// 1일이 월요일이면 두 번째 칸(1열)에 놓인다.
    @Test func monthStartingOnMondayPlacesDayOneInSecondColumn() {
        let first = date("2026-06-01")
        #expect(StudyWeekday.from(date: first, calendar: calendar) == .monday)
        #expect(StudyWeekday.from(date: first, calendar: calendar).displayColumn == 1)
    }

    /// 앞뒤 달에 걸친 달도 오프셋이 어긋나지 않는다.
    /// 빈 칸 수 + 날짜 순번으로 계산한 열이 그 날짜의 실제 요일 열과 언제나 같아야 한다.
    @Test func monthGridOffsetsMatchEveryDayInTheMonth() {
        // 1일이 토요일(2026-08)·화요일(2026-09)인 달까지 확인한다.
        for text in ["2026-02-01", "2026-06-01", "2026-08-01", "2026-09-01"] {
            let monthStart = date(text)
            let leadingBlanks = StudyWeekday.from(date: monthStart, calendar: calendar).displayColumn
            let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
            #expect(dayCount > 0)
            for offset in 0..<dayCount {
                let day = calendar.date(byAdding: .day, value: offset, to: monthStart)!
                let gridColumn = (leadingBlanks + offset) % 7
                #expect(
                    gridColumn == StudyWeekday.from(date: day, calendar: calendar).displayColumn,
                    "\(text) +\(offset)일의 격자 열이 요일과 어긋난다"
                )
            }
        }
    }

    // MARK: F. 설정 왕복

    @Test func studyWeekdaysSurviveEncodeDecodeUnchanged() throws {
        let original = StudyCalendarFixture.settings(
            weekdays: [.monday, .thursday, .saturday, .sunday],
            examDate: "2026-09-04"
        )
        let decoded = try JSONCoding.decoder.decode(
            StudyPlanSettings.self,
            from: try JSONCoding.encoder.encode(original)
        )
        #expect(decoded.studyWeekdays == original.studyWeekdays)
        #expect(decoded.sortedWeekdays.map(\.rawValue) == [1, 4, 6, 7])
        // 요일 판정도 그대로다: 일요일은 학습일, 화요일은 아니다.
        #expect(decoded.isStudyDay(date("2026-08-09")))
        #expect(!decoded.isStudyDay(date("2026-08-11")))
    }

    // MARK: G. 과거 기록 불변

    /// 표시 순서를 바꿔도 지난 날짜의 배정 학습량은 그대로다(G3).
    @Test func historicalTargetsAreUnaffectedByPresentationOrder() {
        let settings = StudyCalendarFixture.settings()
        let frozen = ["2026-08-10": 5, "2026-08-11": 4]
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IM2,
            dailyCapacity: 2,
            completions: StudyCalendarFixture.completions(["2026-08-10": 5]),
            historicalTargets: frozen,
            today: date("2026-08-14")
        )
        // 고정된 지난 날은 현재 설정(하루 2세트)으로 다시 계산되지 않는다.
        #expect(snapshot.schedule.targetSets(for: date("2026-08-10")) == 5)
        #expect(snapshot.schedule.targetSets(for: date("2026-08-11")) == 4)
        // 다시 고정해도 지난 값이 그대로 나온다("yyyy-MM-dd" 키 형식도 그대로).
        let refrozen = snapshot.targetsToFreeze(settings: settings, today: date("2026-08-14"))
        #expect(refrozen["2026-08-10"] != nil)
        #expect(refrozen["2026-08-09"] == nil) // 일요일은 휴식일이라 고정하지 않는다
    }
}
