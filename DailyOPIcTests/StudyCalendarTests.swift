import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 학습 캘린더의 계산 계약. 예측은 "권장 학습 계획을 끝내는 데 걸리는 기간"이지
/// 등급 취득 보장이 아니다.
struct StudyCalendarTests {
    private static let seoul = "Asia/Seoul"

    private func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        intensity: StudyIntensity = .steady,
        examDate: String? = nil
    ) -> StudyPlanSettings {
        let timeZone = TimeZone(identifier: Self.seoul) ?? .current
        return StudyPlanSettings(
            examDate: examDate.flatMap { LocalCalendarDate.date(from: $0, timeZone: timeZone) },
            studyWeekdays: weekdays,
            intensity: intensity,
            preferredStudyTime: StudyTimeOfDay(hour: 21, minute: 0),
            timezoneIdentifier: Self.seoul
        )
    }

    private func date(_ text: String) -> Date {
        LocalCalendarDate.date(from: text, timeZone: TimeZone(identifier: Self.seoul)!)!
    }

    // MARK: 학습 강도와 플랜 한도

    @Test func intensityMapsToDesiredDailySets() {
        #expect(StudyIntensity.light.desiredDailySets == 1)
        #expect(StudyIntensity.steady.desiredDailySets == 2)
        #expect(StudyIntensity.focused.desiredDailySets == 3)
    }

    /// 무료 플랜은 하루 토큰이 1개다. "집중"을 골라도 오늘 목표는 1세트다.
    @Test func effectiveTargetIsCappedByDailyTokenCapacity() {
        #expect(StudyPlanEstimator.effectiveDailyTarget(intensity: .focused, dailyCapacity: 1) == 1)
        #expect(StudyPlanEstimator.effectiveDailyTarget(intensity: .focused, dailyCapacity: 3) == 3)
        #expect(StudyPlanEstimator.effectiveDailyTarget(intensity: .light, dailyCapacity: 20) == 1)
    }

    /// 프로의 20토큰은 한도지 숙제가 아니다. 권장량은 강도에서만 나온다.
    @Test func planCapacityNeverRaisesTheRecommendedWorkload() {
        let forecast = StudyPlanEstimator.forecast(
            settings: settings(intensity: .steady),
            targetLevel: .IH,
            recentLevel: .IM2,
            dailyCapacity: 20,
            today: date("2026-08-10")
        )
        #expect(forecast.effectiveDailyTarget == 2)
        #expect(forecast.dailyCapacity == 20)
        #expect(forecast.isCappedByPlan == false)
    }

    @Test func dailyCapacityPrefersServerCapabilitiesOverThePlanTable() {
        #expect(StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: .free) == 1)
        #expect(StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: .pro) == 20)
    }

    // MARK: 권장 학습량

    @Test func recommendedSetsGrowWithTheLevelGapAndStayClamped() {
        let config = StudyPlanEstimatorConfig.self
        #expect(StudyPlanEstimator.recommendedTotalSets(target: .IH, recent: .IH) == config.baseTotalSets)
        #expect(
            StudyPlanEstimator.recommendedTotalSets(target: .IH, recent: .IM3)
                == config.baseTotalSets + config.setsPerLevelStep
        )
        // IM2 → IH는 IM3를 거치는 두 단계다(OPIcLevel.rank 순서가 진실).
        #expect(
            StudyPlanEstimator.recommendedTotalSets(target: .IH, recent: .IM2)
                == config.baseTotalSets + config.setsPerLevelStep * 2
        )
        // 이미 목표를 넘어선 경우에도 유지 학습량은 남는다(음수가 되지 않는다).
        #expect(StudyPlanEstimator.recommendedTotalSets(target: .IL, recent: .AL) == config.baseTotalSets)
        #expect(StudyPlanEstimator.recommendedTotalSets(target: .AL, recent: .NL) <= config.maximumTotalSets)
    }

    /// 최근 분석 결과가 없으면 아는 척하지 않고 보수적인 기본값을 쓴다.
    @Test func unknownCurrentLevelFallsBackToAFixedAssumption() {
        #expect(
            StudyPlanEstimator.levelSteps(target: .IH, recent: nil)
                == StudyPlanEstimatorConfig.assumedLevelStepsWhenUnknown
        )
    }

    // MARK: 예상 완료일

    /// 선택한 공부 요일만 센다. 주말만 고른 사용자의 4세트(주 2일 × 2세트)는 2주가 걸린다.
    @Test func completionDateCountsOnlySelectedWeekdays() {
        let weekendOnly = settings(weekdays: [.saturday, .sunday])
        let completion = StudyPlanEstimator.completionDate(
            studyDays: 4,
            settings: weekendOnly,
            today: date("2026-08-14") // 금요일
        )
        #expect(completion == date("2026-08-23")) // 토·일·토·일 → 둘째 주 일요일
    }

    @Test func completionDateStartsFromTodayWhenTodayIsAStudyDay() {
        let completion = StudyPlanEstimator.completionDate(
            studyDays: 1,
            settings: settings(),
            today: date("2026-08-14")
        )
        #expect(completion == date("2026-08-14"))
    }

    @Test func forecastRoundsPartialDaysUp() {
        let forecast = StudyPlanEstimator.forecast(
            settings: settings(intensity: .steady),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            today: date("2026-08-10")
        )
        // 권장 20세트 ÷ 하루 2세트 = 10일
        #expect(forecast.recommendedTotalSets == 20)
        #expect(forecast.estimatedStudyDays == 10)
    }

    // MARK: 시험일

    @Test func examDateIsOptionalAndRendersAsDDay() {
        let withoutExam = StudyCalendarSnapshot.make(
            settings: settings(),
            targetLevel: .IH,
            recentLevel: .IM2,
            dailyCapacity: 2,
            completions: [:],
            today: date("2026-08-14")
        )
        #expect(withoutExam.examDaysRemaining == nil)
        #expect(withoutExam.forecastLandsAfterExam == false)

        let withExam = StudyCalendarSnapshot.make(
            settings: settings(examDate: "2026-09-04"),
            targetLevel: .IH,
            recentLevel: .IM2,
            dailyCapacity: 2,
            completions: [:],
            today: date("2026-08-14")
        )
        #expect(withExam.examDaysRemaining == 21)
    }

    /// 시험일보다 늦게 끝날 것 같으면 알리기만 한다. 학습량을 자동으로 늘리지 않는다.
    @Test func forecastAfterExamIsFlaggedWithoutChangingTheWorkload() {
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings(intensity: .light, examDate: "2026-08-20"),
            targetLevel: .AL,
            recentLevel: .NL,
            dailyCapacity: 1,
            completions: [:],
            today: date("2026-08-14")
        )
        #expect(snapshot.forecastLandsAfterExam)
        #expect(snapshot.forecast.effectiveDailyTarget == 1)
    }

    // MARK: 하루 상태

    @Test func dayStatesCoverRestPlannedPartialCompletedMissed() {
        let plan = settings() // 월~금
        let today = date("2026-08-14")
        func state(_ day: String, completed: Int) -> StudyDayState {
            StudyCalendarEngine.day(
                date: date(day),
                today: today,
                settings: plan,
                targetSets: 2,
                completions: [date(day): completed]
            ).state
        }

        #expect(state("2026-08-15", completed: 0) == .rest)       // 토요일은 미선택 요일
        #expect(state("2026-08-17", completed: 0) == .planned)    // 다음 주 월요일
        #expect(state("2026-08-14", completed: 0) == .planned)    // 오늘은 아직 놓친 게 아니다
        #expect(state("2026-08-14", completed: 1) == .partial)
        #expect(state("2026-08-14", completed: 2) == .completed)
        #expect(state("2026-08-13", completed: 0) == .missed)     // 지난 학습일
        #expect(state("2026-08-13", completed: 3) == .completed)
    }

    /// 휴식일에 공부해도 그날은 휴식일이다(목표가 없던 날이므로 미달로 세지 않는다).
    @Test func restDayNeverBecomesMissed() {
        let day = StudyCalendarEngine.day(
            date: date("2026-08-08"),
            today: date("2026-08-14"),
            settings: settings(),
            targetSets: 2,
            completions: [:]
        )
        #expect(day.state == .rest)
        #expect(day.targetSets == 0)
    }

    // MARK: 스트릭

    @Test func streakCountsConsecutiveCompletedStudyDays() {
        let plan = settings() // 월~금
        let completions = [
            date("2026-08-12"): 2,
            date("2026-08-13"): 2,
            date("2026-08-14"): 2
        ]
        #expect(
            StudyCalendarEngine.streak(
                today: date("2026-08-14"),
                settings: plan,
                targetSets: 2,
                completions: completions
            ) == 3
        )
    }

    /// 계획된 휴식일은 스트릭을 끊지 않는다.
    @Test func plannedRestDaysDoNotBreakTheStreak() {
        let plan = settings(weekdays: [.monday, .thursday, .friday])
        let completions = [date("2026-08-13"): 1, date("2026-08-14"): 1] // 목·금
        #expect(
            StudyCalendarEngine.streak(
                today: date("2026-08-14"),
                settings: plan,
                targetSets: 1,
                completions: completions
            ) == 2
        )
    }

    /// 아직 끝나지 않은 오늘은 스트릭을 끊지 않지만, 놓친 학습일은 끊는다.
    @Test func todayIsNotCountedAsMissedButPastMissesBreakTheStreak() {
        let plan = settings()
        let completions = [date("2026-08-12"): 2, date("2026-08-13"): 2]
        #expect(
            StudyCalendarEngine.streak(
                today: date("2026-08-14"),
                settings: plan,
                targetSets: 2,
                completions: completions
            ) == 2
        )
        #expect(
            StudyCalendarEngine.streak(
                today: date("2026-08-14"),
                settings: plan,
                targetSets: 2,
                completions: [date("2026-08-12"): 2] // 13일(목) 미달 → 끊김
            ) == 0
        )
    }

    /// 미래 날짜의 기록은 스트릭에 영향을 주지 않는다.
    @Test func futureCompletionsDoNotInflateTheStreak() {
        #expect(
            StudyCalendarEngine.streak(
                today: date("2026-08-14"),
                settings: settings(),
                targetSets: 2,
                completions: [date("2026-08-17"): 5]
            ) == 0
        )
    }

    // MARK: 주간 요약

    @Test func weekSummaryCountsScheduledDaysOnly() {
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings(),
            targetLevel: .IH,
            recentLevel: .IM2,
            dailyCapacity: 2,
            completions: [date("2026-08-10"): 2, date("2026-08-11"): 1],
            today: date("2026-08-14")
        )
        #expect(snapshot.weekScheduledDays == 5)
        #expect(snapshot.weekCompletedDays == 1)
        #expect(snapshot.weekDays.count == 7)
        #expect(snapshot.weekDays.first?.date == date("2026-08-10")) // 주는 월요일에 시작
    }

    // MARK: 설정 직렬화

    /// 시험일과 학습 시각은 로컬 값이다. ISO8601 절대 시각으로 실어 보내면 타임존만큼 밀린다.
    @Test func settingsEncodeToTheServerWireFormat() throws {
        let encoded = try JSONCoding.encoder.encode(settings(examDate: "2026-09-04"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(json["examDate"] as? String == "2026-09-04")
        #expect(json["preferredStudyTime"] as? String == "21:00")
        #expect(json["studyWeekdays"] as? [Int] == [1, 2, 3, 4, 5])
        #expect(json["timezoneIdentifier"] as? String == Self.seoul)
        #expect(json["schemaVersion"] as? Int == 1)
        // 목표 등급의 진실은 기존 target-level이다. 계획에 복제하지 않는다.
        #expect(json["targetLevel"] == nil)
    }

    @Test func settingsSurviveARoundTrip() throws {
        let original = settings(weekdays: [.tuesday, .sunday], intensity: .focused, examDate: "2026-12-01")
        let decoded = try JSONCoding.decoder.decode(
            StudyPlanSettings.self,
            from: try JSONCoding.encoder.encode(original)
        )
        #expect(decoded.examDate == original.examDate)
        #expect(decoded.studyWeekdays == original.studyWeekdays)
        #expect(decoded.intensity == .focused)
        #expect(decoded.preferredStudyTime == original.preferredStudyTime)
        #expect(decoded.timezoneIdentifier == Self.seoul)
    }

    /// 설정이 없는 기존 사용자는 오류가 아니라 미설정 상태다.
    @Test func unconfiguredResponseDecodesWithoutASettingsObject() throws {
        let json = Data(#"{"configured":false,"studyPlan":null}"#.utf8)
        let response = try JSONCoding.decoder.decode(StudyPlanResponse.self, from: json)
        #expect(response.configured == false)
        #expect(response.studyPlan == nil)
    }

    @Test func requestOmitsServerOwnedFields() throws {
        let encoded = try JSONCoding.encoder.encode(StudyPlanRequest(settings: settings()))
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["schemaVersion"] == nil)
        #expect(json["createdAt"] == nil)
        #expect(json["examDate"] == nil) // 시험일 미선택은 아예 보내지 않는다
    }

    // MARK: 요일 변환

    @Test func weekdayUsesISONumberingNotCalendarNumbering() {
        let calendar = LocalCalendarDate.calendar(timeZone: TimeZone(identifier: Self.seoul)!)
        #expect(StudyWeekday.from(date: date("2026-08-10"), calendar: calendar) == .monday)
        #expect(StudyWeekday.from(date: date("2026-08-16"), calendar: calendar) == .sunday)
        #expect(StudyWeekday.sunday.rawValue == 7)
    }
}

/// 완료 집계 저장소. "세트를 받았다"가 아니라 "분석이 성공했다"를 센다.
@MainActor
struct StudyCompletionStoreTests {
    private func makePersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: StudySetCompletionRecord.self, PracticeHistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    /// 같은 세트를 몇 번 다시 분석해도 하루 완료 수는 한 번만 늘어난다.
    @Test func sameSetIsCountedOnlyOnce() throws {
        let persistence = try makePersistence()
        #expect(try persistence.recordStudySetCompletion(setId: "set-1") == true)
        #expect(try persistence.recordStudySetCompletion(setId: "set-1") == false)
        #expect(try persistence.recordStudySetCompletion(setId: "set-1") == false)
        #expect(try persistence.recordStudySetCompletion(setId: "set-2") == true)
    }

    @Test func emptySetIdIsNeverRecorded() throws {
        let persistence = try makePersistence()
        #expect(try persistence.recordStudySetCompletion(setId: "") == false)
    }

    @Test func completionsAreGroupedByLocalDay() {
        let calendar = LocalCalendarDate.calendar(timeZone: TimeZone(identifier: "Asia/Seoul")!)
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let counts = StudyCalendarEngine.completionCounts(
            completedAt: [
                day.addingTimeInterval(60 * 60),      // 01:00
                day.addingTimeInterval(60 * 60 * 23), // 23:00 같은 날
                day.addingTimeInterval(60 * 60 * 25)  // 다음 날 01:00
            ],
            calendar: calendar
        )
        #expect(counts[day] == 2)
        #expect(counts[calendar.date(byAdding: .day, value: 1, to: day)!] == 1)
    }
}
