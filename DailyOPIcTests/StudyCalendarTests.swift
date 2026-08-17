import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 학습 캘린더 공통 픽스처. 2026-08-10은 월요일이다.
enum StudyCalendarFixture {
    static let seoul = "Asia/Seoul"
    static let seoulTimeZone = TimeZone(identifier: seoul)!

    static func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        intensity: StudyIntensity = .steady,
        examDate: String? = nil,
        createdAt: String? = "2026-08-03",
        preferredStudyTime: StudyTimeOfDay = StudyTimeOfDay(hour: 21, minute: 0),
        timeZone: String = seoul
    ) -> StudyPlanSettings {
        let zone = TimeZone(identifier: timeZone) ?? .current
        return StudyPlanSettings(
            examDate: examDate.flatMap { LocalCalendarDate.date(from: $0, timeZone: zone) },
            studyWeekdays: weekdays,
            intensity: intensity,
            preferredStudyTime: preferredStudyTime,
            timezoneIdentifier: timeZone,
            createdAt: createdAt.flatMap { LocalCalendarDate.date(from: $0, timeZone: zone) }
        )
    }

    static func date(_ text: String, timeZone: String = seoul) -> Date {
        LocalCalendarDate.date(from: text, timeZone: TimeZone(identifier: timeZone)!)!
    }

    static func completions(_ entries: [String: Int]) -> [Date: Int] {
        entries.reduce(into: [:]) { result, entry in result[date(entry.key)] = entry.value }
    }
}

/// 캘린더의 기본 계산 계약. 예측은 "권장 학습 계획을 끝내는 데 걸리는 기간"이지
/// 등급 취득 보장이 아니다.
struct StudyCalendarTests {
    private func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        intensity: StudyIntensity = .steady,
        examDate: String? = nil
    ) -> StudyPlanSettings {
        StudyCalendarFixture.settings(weekdays: weekdays, intensity: intensity, examDate: examDate)
    }

    private func date(_ text: String) -> Date { StudyCalendarFixture.date(text) }

    /// 지난 날의 배정량은 고정 기록에서만 온다. 오늘·미래는 현재 적응형 계획에서 온다.
    private func schedule(
        historical: [String: Int] = [:],
        settings: StudyPlanSettings,
        today: Date,
        dailyCapacity: Int = 2,
        completions: [Date: Int] = [:]
    ) -> StudySchedule {
        StudySchedule(
            historicalTargets: historical,
            plan: AdaptiveStudyPlanner.plan(
                settings: settings,
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: dailyCapacity,
                completions: completions,
                today: today
            ),
            settings: settings,
            today: today
        )
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
        let plan = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .steady),
            targetLevel: .IH,
            recentLevel: .IM2,
            dailyCapacity: 20,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(plan.baseDailyTarget == 2)
        #expect(plan.dailyCapacity == 20)
        #expect(plan.isCappedByPlan == false)
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

    // MARK: 시험일 표기

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
        #expect(withoutExam.plan.mode == .onTrack)

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

    // MARK: 하루 상태

    @Test func dayStatesCoverRestPlannedPartialCompletedMissed() {
        let plan = settings() // 월~금
        let today = date("2026-08-14")
        // 지난 학습일은 그날 2세트로 고정되어 있었다.
        let historical = ["2026-08-13": 2, "2026-08-14": 2]
        func state(_ day: String, completed: Int) -> StudyDayState {
            StudyCalendarEngine.day(
                date: date(day),
                today: today,
                settings: plan,
                schedule: schedule(
                    historical: historical,
                    settings: plan,
                    today: today,
                    completions: [date(day): completed]
                ),
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
        let plan = settings()
        let today = date("2026-08-14")
        let day = StudyCalendarEngine.day(
            date: date("2026-08-08"), // 토요일
            today: today,
            settings: plan,
            schedule: schedule(settings: plan, today: today),
            completions: [:]
        )
        #expect(day.state == .rest)
        #expect(day.targetSets == 0)
    }

    // MARK: 스트릭

    @Test func streakCountsConsecutiveCompletedStudyDays() {
        let plan = settings() // 월~금
        let today = date("2026-08-14")
        let completions = StudyCalendarFixture.completions([
            "2026-08-12": 2, "2026-08-13": 2, "2026-08-14": 2
        ])
        #expect(
            StudyCalendarEngine.streak(
                today: today,
                settings: plan,
                schedule: schedule(
                    historical: ["2026-08-12": 2, "2026-08-13": 2],
                    settings: plan,
                    today: today,
                    completions: completions
                ),
                completions: completions
            ) == 3
        )
    }

    /// 계획된 휴식일은 스트릭을 끊지 않는다.
    @Test func plannedRestDaysDoNotBreakTheStreak() {
        let plan = settings(weekdays: [.monday, .thursday, .friday])
        let today = date("2026-08-14")
        let completions = StudyCalendarFixture.completions(["2026-08-13": 1, "2026-08-14": 1])
        #expect(
            StudyCalendarEngine.streak(
                today: today,
                settings: plan,
                schedule: schedule(
                    historical: ["2026-08-13": 1],
                    settings: plan,
                    today: today,
                    dailyCapacity: 1,
                    completions: completions
                ),
                completions: completions
            ) == 2
        )
    }

    /// 아직 끝나지 않은 오늘은 스트릭을 끊지 않지만, 놓친 학습일은 끊는다.
    @Test func todayIsNotCountedAsMissedButPastMissesBreakTheStreak() {
        let plan = settings()
        let today = date("2026-08-14")
        let historical = ["2026-08-12": 2, "2026-08-13": 2]
        func streak(_ completions: [Date: Int]) -> Int {
            StudyCalendarEngine.streak(
                today: today,
                settings: plan,
                schedule: schedule(
                    historical: historical,
                    settings: plan,
                    today: today,
                    completions: completions
                ),
                completions: completions
            )
        }
        #expect(streak(StudyCalendarFixture.completions(["2026-08-12": 2, "2026-08-13": 2])) == 2)
        // 13일(목) 미달 → 끊김
        #expect(streak(StudyCalendarFixture.completions(["2026-08-12": 2])) == 0)
    }

    /// 미래 날짜의 기록은 스트릭에 영향을 주지 않는다.
    @Test func futureCompletionsDoNotInflateTheStreak() {
        let plan = settings()
        let today = date("2026-08-14")
        let completions = StudyCalendarFixture.completions(["2026-08-17": 5])
        #expect(
            StudyCalendarEngine.streak(
                today: today,
                settings: plan,
                schedule: schedule(settings: plan, today: today, completions: completions),
                completions: completions
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
            completions: StudyCalendarFixture.completions(["2026-08-10": 2, "2026-08-11": 1]),
            historicalTargets: [
                "2026-08-10": 2, "2026-08-11": 2, "2026-08-12": 2, "2026-08-13": 2
            ],
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
        #expect(json["timezoneIdentifier"] as? String == StudyCalendarFixture.seoul)
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
        #expect(decoded.timezoneIdentifier == StudyCalendarFixture.seoul)
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
        let calendar = LocalCalendarDate.calendar(timeZone: StudyCalendarFixture.seoulTimeZone)
        #expect(StudyWeekday.from(date: date("2026-08-10"), calendar: calendar) == .monday)
        #expect(StudyWeekday.from(date: date("2026-08-16"), calendar: calendar) == .sunday)
        #expect(StudyWeekday.sunday.rawValue == 7)
    }
}

/// G3 적응형 계획. 남은 학습량 = 권장 총량 − 실제 완료량이고, 지난 기록은 다시 계산하지 않는다.
struct AdaptiveStudyPlannerTests {
    private func settings(
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        intensity: StudyIntensity = .steady,
        examDate: String? = nil,
        createdAt: String? = "2026-08-03",
        preferredStudyTime: StudyTimeOfDay = StudyTimeOfDay(hour: 21, minute: 0),
        timeZone: String = StudyCalendarFixture.seoul
    ) -> StudyPlanSettings {
        StudyCalendarFixture.settings(
            weekdays: weekdays,
            intensity: intensity,
            examDate: examDate,
            createdAt: createdAt,
            preferredStudyTime: preferredStudyTime,
            timeZone: timeZone
        )
    }

    private func date(_ text: String) -> Date { StudyCalendarFixture.date(text) }

    /// 기본 픽스처: 권장 20세트(IH → IH), 월~금, 꾸준히(하루 2세트).
    private func plan(
        _ settings: StudyPlanSettings,
        completions: [String: Int] = [:],
        targetLevel: OPIcLevel = .IH,
        recentLevel: OPIcLevel? = .IH,
        dailyCapacity: Int = 2,
        today: String = "2026-08-10"
    ) -> AdaptiveStudyPlan {
        AdaptiveStudyPlanner.plan(
            settings: settings,
            targetLevel: targetLevel,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            completions: StudyCalendarFixture.completions(completions),
            today: date(today)
        )
    }

    // MARK: 1~4, 30. 남은 학습량과 예상 완료일의 이동

    /// 1. 완료한 학습은 남은 학습량을 줄인다.
    @Test func completedWorkReducesRemainingWorkload() {
        let result = plan(settings(), completions: ["2026-08-04": 4, "2026-08-05": 2])
        #expect(result.totalRecommendedSets == 20)
        #expect(result.completedSets == 6)
        #expect(result.remainingSets == 14)
    }

    /// 계획을 세우기 전의 학습은 새 계획을 미리 끝낸 것으로 쳐주지 않는다.
    @Test func completionsBeforeThePlanStartDoNotCount() {
        let result = plan(
            settings(createdAt: "2026-08-10"),
            completions: ["2026-08-04": 4, "2026-08-10": 2]
        )
        #expect(result.completedSets == 2)
        #expect(result.remainingSets == 18)
    }

    /// 2. 더 한 학습은 예상 완료일을 앞당긴다.
    @Test func extraWorkMovesTheNormalForecastEarlier() {
        let base = plan(settings())
        let ahead = plan(settings(), completions: ["2026-08-10": 4])
        #expect(base.estimatedCompletionDate == date("2026-08-21"))
        #expect(ahead.estimatedCompletionDate == date("2026-08-19"))
    }

    /// 3. 놓친 학습은 (시험일이 없을 때) 예상 완료일을 뒤로 민다.
    @Test func missedStudyMovesTheNoExamForecastLater() {
        let onSchedule = plan(settings(), completions: ["2026-08-10": 2], today: "2026-08-11")
        let missed = plan(settings(), today: "2026-08-11") // 월요일을 통째로 놓쳤다
        #expect(onSchedule.estimatedCompletionDate == date("2026-08-21"))
        #expect(missed.estimatedCompletionDate == date("2026-08-24"))
        #expect(missed.remainingSets > onSchedule.remainingSets)
    }

    /// 4. 놓친 몫을 다음 날에 몰아주지 않는다. 화요일 목표는 여전히 2세트다.
    @Test func missedWorkIsNotDumpedOnTheNextDay() {
        let missed = plan(settings(), today: "2026-08-11")
        #expect(missed.upcomingDays.first?.date == date("2026-08-11"))
        #expect(missed.upcomingDays.first?.targetSets == 2)
        #expect(missed.upcomingDays.allSatisfy { $0.targetSets <= 2 })
    }

    /// 30. 예측은 남은 학습량으로 계산한다. 매일 전체 학습량을 처음부터 다시 세지 않는다.
    @Test func forecastUsesRemainingWorkloadNotTheOriginalTotal() {
        let result = plan(settings(), completions: ["2026-08-10": 4])
        #expect(result.remainingSets == 16)
        #expect(result.estimatedStudyDays == 8)  // 20세트 기준이면 10일이었다
    }

    // MARK: 5~8, 31. 지난 기록 불변

    /// 5. 일부 완료한 날은 그날의 배정량을 그대로 유지한다(1 / 3).
    @Test func partialDayKeepsItsHistoricalTarget() {
        let plan = settings()
        let today = date("2026-08-14")
        let completions = StudyCalendarFixture.completions(["2026-08-13": 1])
        let day = StudyCalendarEngine.day(
            date: date("2026-08-13"),
            today: today,
            settings: plan,
            schedule: StudySchedule(
                historicalTargets: ["2026-08-13": 3],
                plan: nil,
                settings: plan,
                today: today
            ),
            completions: completions
        )
        #expect(day.state == .partial)
        #expect(day.targetSets == 3)  // 현재 기본 학습량(2)이 아니라 그날의 3
        #expect(day.completedSets == 1)
    }

    /// 6·31. 강도를 바꿔도 지난 완료일은 완료로 남는다(1 / 1이 1 / 3이 되지 않는다).
    @Test func pastCompletedDayStaysCompletedAfterIntensityChange() {
        let today = date("2026-08-14")
        let completions = StudyCalendarFixture.completions(["2026-08-13": 1])
        func yesterday(_ settings: StudyPlanSettings, capacity: Int) -> StudyDay {
            StudyCalendarSnapshot.make(
                settings: settings,
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: capacity,
                completions: completions,
                historicalTargets: ["2026-08-13": 1],
                today: today
            ).weekDays.first { $0.date == date("2026-08-13") }!
        }

        let before = yesterday(settings(intensity: .light), capacity: 1)
        let after = yesterday(settings(intensity: .focused), capacity: 3)
        #expect(before.state == .completed)
        #expect(before.targetSets == 1)
        #expect(after.state == .completed)   // 계획 수정이 과거를 일부 완료로 바꾸지 못한다
        #expect(after.targetSets == 1)
    }

    /// 7. 공부 요일을 바꿔도 지난 날의 학습일/휴식일 진실은 바뀌지 않는다.
    @Test func pastDayStateIsStableAfterAWeekdayEdit() {
        let today = date("2026-08-14")
        let completions = StudyCalendarFixture.completions(["2026-08-08": 2])  // 토요일에 학습
        func saturday(_ weekdays: Set<StudyWeekday>) -> StudyDay {
            let plan = settings(weekdays: weekdays)
            return StudyCalendarEngine.day(
                date: date("2026-08-08"),
                today: today,
                settings: plan,
                schedule: StudySchedule(
                    historicalTargets: ["2026-08-08": 2],
                    plan: nil,
                    settings: plan,
                    today: today
                ),
                completions: completions
            )
        }
        // 토요일을 계획에서 뺀 뒤에도 그날은 완료한 학습일로 남는다.
        #expect(saturday([.saturday, .sunday]).state == .completed)
        #expect(saturday([.monday, .tuesday]).state == .completed)
        #expect(saturday([.monday, .tuesday]).targetSets == 2)
    }

    /// 8. 알림 시각만 바꾸는 것은 학습량과 일정에 아무 영향이 없다.
    @Test func preferredStudyTimeChangeDoesNotChangeTheWorkload() {
        let morning = plan(settings(preferredStudyTime: StudyTimeOfDay(hour: 7, minute: 0)))
        let evening = plan(settings(preferredStudyTime: StudyTimeOfDay(hour: 22, minute: 30)))
        #expect(morning.remainingSets == evening.remainingSets)
        #expect(morning.upcomingDays == evening.upcomingDays)
        #expect(morning.estimatedCompletionDate == evening.estimatedCompletionDate)
    }

    // MARK: 9~13. 분배와 휴식일

    /// 9. 평소 모드에서 미선택 요일은 학습일이 되지 않는다.
    @Test func restDaysStayRestInNormalMode() {
        let plan = settings()
        let result = AdaptiveStudyPlanner.plan(
            settings: plan,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(result.upcomingDays.allSatisfy { plan.isStudyDay($0.date) })
        let weekdays = Set(
            result.upcomingDays.map { StudyWeekday.from(date: $0.date, calendar: plan.calendar) }
        )
        #expect(weekdays.isDisjoint(with: [.saturday, .sunday]))
    }

    /// 10·12. 압축 모드도 휴식일을 몰래 쓰지 않는다.
    @Test func restDaysStayRestInCompressedMode() {
        let plan = settings(examDate: "2026-08-19")
        let result = AdaptiveStudyPlanner.plan(
            settings: plan,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 3,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(result.mode == .compressed)
        #expect(result.upcomingDays.allSatisfy { plan.isStudyDay($0.date) })
    }

    /// 11. 압축 배분은 균등하다. 한 날에 몰아주지 않는다.
    @Test func compressedDistributionIsBalanced() {
        let result = AdaptiveStudyPlanner.plan(
            settings: settings(examDate: "2026-08-19"),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 3,
            completions: [:],
            today: date("2026-08-10")
        )
        // 남은 20세트를 8/10~8/18의 학습일 7일에 나눈다: 3,3,3,3,3,3,2
        #expect(result.upcomingDays.map(\.targetSets) == [3, 3, 3, 3, 3, 3, 2])
        #expect(result.upcomingDays.map(\.targetSets).reduce(0, +) == result.remainingSets)
        #expect(result.upcomingDays.first?.date == date("2026-08-10"))
        #expect(result.upcomingDays.last?.date == date("2026-08-18"))
    }

    /// 13. 나머지는 앞쪽 날짜부터 1세트씩. 같은 입력이면 항상 같은 결과다.
    @Test func remainderDistributionIsDeterministic() {
        let dates = ["2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"]
            .map { date($0) }
        let first = AdaptiveStudyPlanner.balanced(11, over: dates)
        let second = AdaptiveStudyPlanner.balanced(11, over: dates)
        #expect(first.map(\.targetSets) == [3, 2, 2, 2, 2])  // 11 = 5×2 + 1
        #expect(first == second)
        #expect(AdaptiveStudyPlanner.balanced(10, over: dates).map(\.targetSets) == [2, 2, 2, 2, 2])
        #expect(AdaptiveStudyPlanner.balanced(3, over: dates).map(\.targetSets) == [1, 1, 1])
        #expect(AdaptiveStudyPlanner.balanced(0, over: dates).isEmpty)
    }

    // MARK: 14~19. 하루 상한

    /// 14. 무료 플랜은 시험이 촉박해도 하루 1세트를 넘기지 않는다.
    @Test func freePlanNeverRequiresMoreThanOneSetPerDay() {
        let result = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .focused, examDate: "2026-08-21"),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 1,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(result.baseDailyTarget == 1)
        #expect(result.adaptiveDailyCeiling == 1)
        #expect(result.upcomingDays.allSatisfy { $0.targetSets <= 1 })
    }

    /// 15~19. 상한 = min(플랜 한도, 기본 학습량 + 2, 5).
    @Test func adaptiveCeilingObeysCapacityBufferAndProductMaximum() {
        let ceiling = StudyPlanEstimator.adaptiveDailyCeiling
        #expect(ceiling(1, 1) == 1)   // 무료 + 가볍게
        #expect(ceiling(2, 3) == 3)   // 베이직 + 꾸준히 → 플랜 한도가 먼저 걸린다
        #expect(ceiling(2, 10) == 4)  // 플러스의 10토큰을 숙제로 쓰지 않는다(기본 2 + 2)
        #expect(ceiling(3, 20) == 5)  // 프로의 20토큰도 마찬가지(제품 상한 5)
        #expect(ceiling(5, 20) == 5)  // 어떤 경우에도 5를 넘지 않는다
        #expect(StudyPlanEstimatorConfig.adaptiveBuffer == 2)
        #expect(StudyPlanEstimatorConfig.productMaximumAdaptiveDailySets == 5)
    }

    /// 16·17. 상위 플랜에서도 압축 배정이 상한을 넘지 않는다.
    @Test func higherPlansDoNotTurnTokenLimitsIntoHomework() {
        func compressed(intensity: StudyIntensity, capacity: Int) -> AdaptiveStudyPlan {
            AdaptiveStudyPlanner.plan(
                settings: settings(intensity: intensity, examDate: "2026-08-21"),
                targetLevel: .IH,
                recentLevel: .IM2,  // 44세트
                dailyCapacity: capacity,
                completions: [:],
                today: date("2026-08-10")
            )
        }
        let plus = compressed(intensity: .steady, capacity: 10)
        let pro = compressed(intensity: .focused, capacity: 20)
        #expect(plus.adaptiveDailyCeiling == 4)
        #expect(plus.upcomingDays.allSatisfy { $0.targetSets <= 4 })
        #expect(pro.adaptiveDailyCeiling == 5)
        #expect(pro.upcomingDays.allSatisfy { $0.targetSets <= 5 })
    }

    // MARK: 20~23, 32. 시험일

    /// 20·21·22. 상한까지 올려도 못 끝내면 솔직하게 부족 상태를 알린다.
    @Test func insufficientExamTimeIsReportedExplicitly() {
        let result = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .light, examDate: "2026-08-14"),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 1,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(result.mode == .insufficientTime)
        #expect(result.remainingSets == 20)
        // 8/10~8/13의 학습일 4일 × 하루 상한 1세트
        #expect(result.maximumSetsPossibleBeforeExam == 4)
        #expect(result.shortfallSets == 16)
        // 시험일을 완료일이라고 거짓말하지 않는다.
        #expect(result.estimatedCompletionDate != result.examDate)
        #expect((result.estimatedCompletionDate ?? .distantPast) > date("2026-08-14"))
    }

    /// 시험이 오늘이거나 이미 지났으면 남은 학습일이 없다.
    @Test func examTodayLeavesNoStudyDays() {
        let result = AdaptiveStudyPlanner.plan(
            settings: settings(examDate: "2026-08-10"),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(result.mode == .insufficientTime)
        #expect(result.upcomingDays.isEmpty)
        #expect(result.maximumSetsPossibleBeforeExam == 0)
        #expect(result.shortfallSets == 20)
    }

    /// 시험일까지 여유가 있으면 압축하지 않는다.
    @Test func comfortableExamDateStaysInNormalMode() {
        let result = plan(settings(examDate: "2026-09-04"))
        #expect(result.mode == .onTrack)
        #expect(result.upcomingDays.allSatisfy { $0.targetSets == 2 })
    }

    /// 23. 압축 중에 더 한 학습도 남은 학습량을 줄인다.
    @Test func extraCompletionReducesCompressedWorkload() {
        func compressed(_ completions: [String: Int]) -> AdaptiveStudyPlan {
            AdaptiveStudyPlanner.plan(
                settings: settings(examDate: "2026-08-19"),
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: 3,
                completions: StudyCalendarFixture.completions(completions),
                today: date("2026-08-10")
            )
        }
        let base = compressed([:])
        let ahead = compressed(["2026-08-04": 4])
        #expect(ahead.mode == .compressed)
        #expect(ahead.remainingSets == 16)
        #expect(ahead.upcomingDays.map(\.targetSets) == [3, 3, 2, 2, 2, 2, 2])
        #expect(
            ahead.upcomingDays.map(\.targetSets).reduce(0, +)
                < base.upcomingDays.map(\.targetSets).reduce(0, +)
        )
    }

    /// 32. 시험 당일에는 의무 학습을 배정하지 않는다.
    @Test func examDayIsNeverAssignedAStudyTask() {
        let exam = date("2026-08-19")
        let result = AdaptiveStudyPlanner.plan(
            settings: settings(examDate: "2026-08-19"),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 3,
            completions: [:],
            today: date("2026-08-10")
        )
        #expect(result.upcomingDays.allSatisfy { $0.date < exam })
        #expect(result.plan(for: exam) == nil)
    }

    // MARK: 24~27. 목표 변경과 계획 완료

    /// 24. 목표 등급을 올려도 이미 한 학습은 그대로 인정된다.
    @Test func targetLevelChangePreservesCompletedWork() {
        let completions = ["2026-08-04": 6]
        let before = plan(settings(), completions: completions, targetLevel: .IH)
        let after = plan(settings(), completions: completions, targetLevel: .AL)
        #expect(before.completedSets == 6)
        #expect(after.completedSets == 6)  // 진행 상황을 초기화하지 않는다
        #expect(after.totalRecommendedSets == 32)
        #expect(after.remainingSets == 26)
        #expect(after.remainingSets > before.remainingSets)
    }

    /// 25·26. 권장 학습량을 넘겨도 남은 학습량은 음수가 되지 않고, 계획은 완료 상태가 된다.
    @Test func remainingNeverGoesNegativeAndPlanCompletes() {
        let result = plan(settings(), completions: ["2026-08-04": 30])
        #expect(result.remainingSets == 0)
        #expect(result.mode == .completed)
        #expect(result.upcomingDays.isEmpty)          // 더 이상 의무 학습을 만들지 않는다
        #expect(result.estimatedCompletionDate == nil)
    }

    /// 27. 오늘의 목표는 화면이 따로 계산하지 않고 생성된 일정에서 온다.
    @Test func todayTargetComesFromTheGeneratedSchedule() {
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings(examDate: "2026-08-19"),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 3,
            completions: StudyCalendarFixture.completions(["2026-08-10": 1]),
            today: date("2026-08-10")
        )
        #expect(snapshot.plan.mode == .compressed)
        #expect(snapshot.today.targetSets == snapshot.plan.plan(for: date("2026-08-10"))?.targetSets)
        #expect(snapshot.today.targetSets == 3)   // 압축된 3세트지 기본 2세트가 아니다
        #expect(snapshot.remainingToday == 2)
        #expect(snapshot.extraToday == 0)
    }

    /// 오늘 배정량을 넘겨 학습하면 초과분이 드러난다(문구용).
    @Test func extraTodayIsExposedWithoutGoingNegative() {
        let snapshot = StudyCalendarSnapshot.make(
            settings: settings(),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            completions: StudyCalendarFixture.completions(["2026-08-10": 4]),
            today: date("2026-08-10")
        )
        #expect(snapshot.extraToday == 2)
        #expect(snapshot.remainingToday == 0)
    }

    // MARK: 29. 타임존

    /// 29. 로컬 하루의 경계는 기기 타임존이 아니라 계획에 저장된 타임존이 정한다.
    @Test func localDayBoundaryFollowsThePlanTimezone() {
        let seoulMidnight = StudyCalendarFixture.date("2026-08-11")   // 8/11 00:00 KST
        let justBefore = seoulMidnight.addingTimeInterval(-60 * 60)   // 8/10 23:00 KST
        func firstDay(timeZone: String, at instant: Date) -> Date? {
            AdaptiveStudyPlanner.plan(
                settings: settings(createdAt: nil, timeZone: timeZone),
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: 2,
                completions: [:],
                today: instant
            ).upcomingDays.first?.date
        }

        #expect(
            firstDay(timeZone: StudyCalendarFixture.seoul, at: justBefore)
                == StudyCalendarFixture.date("2026-08-10")
        )
        #expect(
            firstDay(timeZone: StudyCalendarFixture.seoul, at: seoulMidnight)
                == StudyCalendarFixture.date("2026-08-11")
        )
        // 같은 순간이라도 뉴욕 계획에서는 아직 8/10이다.
        #expect(
            firstDay(timeZone: "America/New_York", at: seoulMidnight)
                == StudyCalendarFixture.date("2026-08-10", timeZone: "America/New_York")
        )
    }

    /// 공부 요일을 하나도 고르지 않으면 일정을 만들지 않는다(무한 루프 방지).
    @Test func emptyWeekdaysProduceNoSchedule() {
        let result = plan(settings(weekdays: []))
        #expect(result.upcomingDays.isEmpty)
        #expect(result.estimatedCompletionDate == nil)
        #expect(result.remainingSets == 20)
    }
}

/// 완료 집계 저장소. "세트를 받았다"가 아니라 "분석이 성공했다"를 센다.
@MainActor
struct StudyCompletionStoreTests {
    private func makePersistence() throws -> PersistenceService {
        let container = try ModelContainer(
            for: StudySetCompletionRecord.self, PracticeHistoryRecord.self, StudyDayPlanRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    /// 28. 같은 세트를 몇 번 다시 분석해도 하루 완료 수는 한 번만 늘어난다.
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
        let calendar = LocalCalendarDate.calendar(timeZone: StudyCalendarFixture.seoulTimeZone)
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

    /// 고정된 배정량은 날짜당 하나이고, 하루가 지나면 바뀌지 않는다.
    @Test func frozenDayPlansAreUniqueAndImmutableOnceThePastArrives() throws {
        let persistence = try makePersistence()
        try persistence.freezeStudyDayPlans(["2026-08-13": 3, "2026-08-14": 2], today: "2026-08-14")
        // 계획을 수정해 오늘·과거 배정량이 모두 달라진 상태로 다시 고정한다.
        try persistence.freezeStudyDayPlans(["2026-08-13": 1, "2026-08-14": 5], today: "2026-08-14")

        let records = try persistence.studyDayPlans()
        #expect(records.count == 2)  // 날짜당 한 개
        #expect(records.first { $0.localDate == "2026-08-13" }?.targetSets == 3)  // 과거 불변
        #expect(records.first { $0.localDate == "2026-08-14" }?.targetSets == 5)  // 오늘은 갱신

        // 하루가 지나면 어제 값도 그대로 굳는다.
        try persistence.freezeStudyDayPlans(["2026-08-14": 1, "2026-08-15": 2], today: "2026-08-15")
        let next = try persistence.studyDayPlans()
        #expect(next.first { $0.localDate == "2026-08-14" }?.targetSets == 5)
        #expect(next.count == 3)
    }

    /// 휴식일(배정 0)은 기록하지 않는다. 지난 휴식일이 학습일로 바뀌지 않게 하는 값이다.
    @Test func restDaysAreNotFrozen() throws {
        let persistence = try makePersistence()
        try persistence.freezeStudyDayPlans(["2026-08-15": 0, "2026-08-14": 2], today: "2026-08-14")
        let records = try persistence.studyDayPlans()
        #expect(records.count == 1)
        #expect(records.first?.localDate == "2026-08-14")
    }

    /// 같은 backfill을 몇 번 돌려도 날짜당 기록은 하나다.
    @Test func repeatedBackfillDoesNotDuplicateRecords() throws {
        let persistence = try makePersistence()
        let settings = StudyCalendarFixture.settings(createdAt: "2026-08-10")
        let targets = AdaptiveStudyPlanner.historicalTargets(
            settings: settings,
            baseDailyTarget: 2,
            today: StudyCalendarFixture.date("2026-08-14")
        )
        for _ in 0..<3 {
            try persistence.freezeStudyDayPlans(targets, today: "2026-08-14")
        }
        let records = try persistence.studyDayPlans()
        #expect(records.count == 5)  // 월~금, 중복 없음
        #expect(Set(records.map(\.localDate)).count == 5)
        #expect(records.allSatisfy { $0.targetSets == 2 })
    }
}

/// 캘린더를 매일 열지 않아도 지난 학습일이 살아남아야 한다.
/// 기준 시나리오: 월요일(08-10)에 캘린더를 보고, 화·수·목은 열지 않고, 금요일(08-14)에 다시 들어온다.
struct HistoricalBackfillTests {
    private func snapshot(
        historical: [String: Int] = [:],
        settings: StudyPlanSettings,
        completions: [String: Int] = [:],
        today: String,
        dailyCapacity: Int = 2
    ) -> StudyCalendarSnapshot {
        StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: dailyCapacity,
            completions: StudyCalendarFixture.completions(completions),
            historicalTargets: historical,
            today: StudyCalendarFixture.date(today)
        )
    }

    private func state(
        _ snapshot: StudyCalendarSnapshot,
        _ date: String,
        settings: StudyPlanSettings,
        completions: [String: Int] = [:]
    ) -> StudyDayState {
        StudyCalendarEngine.day(
            date: StudyCalendarFixture.date(date),
            today: snapshot.today.date,
            settings: settings,
            schedule: snapshot.schedule,
            completions: StudyCalendarFixture.completions(completions)
        ).state
    }

    /// 화·수·목 기록이 없어도 휴식이 되지 않고, 완료량에 따라 missed/partial/completed가 된다.
    @Test func skippedDaysAreRestoredAsMissedPartialOrCompleted() {
        let settings = StudyCalendarFixture.settings()
        let completions = ["2026-08-10": 2, "2026-08-12": 1, "2026-08-13": 2]
        // 월요일에 캘린더를 열어 고정된 기록은 08-10 하나뿐이다.
        let snapshot = snapshot(
            historical: ["2026-08-10": 2],
            settings: settings,
            completions: completions,
            today: "2026-08-14"
        )

        #expect(state(snapshot, "2026-08-11", settings: settings, completions: completions) == .missed)
        #expect(state(snapshot, "2026-08-12", settings: settings, completions: completions) == .partial)
        #expect(state(snapshot, "2026-08-13", settings: settings, completions: completions) == .completed)
        #expect(snapshot.schedule.targetSets(for: StudyCalendarFixture.date("2026-08-11")) == 2)
    }

    /// 되살린 날짜는 다시 들어왔을 때 그대로 고정된다(= 화면에 보인 값이 그대로 저장된다).
    @Test func materializedDaysAreExactlyWhatGetsFrozen() {
        let settings = StudyCalendarFixture.settings()
        let snapshot = snapshot(historical: ["2026-08-10": 2], settings: settings, today: "2026-08-14")
        let frozen = snapshot.targetsToFreeze(
            settings: settings,
            today: StudyCalendarFixture.date("2026-08-14")
        )
        #expect(frozen["2026-08-11"] == 2)
        #expect(frozen["2026-08-12"] == 2)
        #expect(frozen["2026-08-13"] == 2)
        #expect(frozen["2026-08-09"] == nil)  // 일요일은 휴식
    }

    /// 이미 고정된 지난 기록은 현재 설정으로 덮이지 않는다.
    @Test func frozenPastTargetsSurviveAnIntensityChange() {
        // 예전에는 light(하루 1세트)였고 지금은 focused로 바꿨다.
        let settings = StudyCalendarFixture.settings(intensity: .focused)
        let snapshot = snapshot(
            historical: ["2026-08-10": 1, "2026-08-11": 1],
            settings: settings,
            completions: ["2026-08-10": 1],
            today: "2026-08-14",
            dailyCapacity: 3
        )
        #expect(snapshot.schedule.targetSets(for: StudyCalendarFixture.date("2026-08-10")) == 1)
        #expect(state(snapshot, "2026-08-10", settings: settings, completions: ["2026-08-10": 1]) == .completed)
        #expect(snapshot.schedule.targetSets(for: StudyCalendarFixture.date("2026-08-14")) == 3)
    }

    /// 공부 요일을 바꿔도 지난 학습일은 휴식이 되지 않는다.
    @Test func pastStudyDaysDoNotBecomeRestAfterAWeekdayChange() {
        // 화요일을 공부 요일에서 뺐지만, 화요일에 이미 배정돼 있던 기록은 남는다.
        let settings = StudyCalendarFixture.settings(weekdays: [.monday, .wednesday, .friday])
        let snapshot = snapshot(
            historical: ["2026-08-11": 2],
            settings: settings,
            today: "2026-08-14"
        )
        #expect(state(snapshot, "2026-08-11", settings: settings) == .missed)
        #expect(snapshot.schedule.targetSets(for: StudyCalendarFixture.date("2026-08-11")) == 2)
    }

    /// 되살리기는 학습일에만 적용된다. 진짜 휴식일은 휴식으로 남는다.
    @Test func genuineRestDaysStayRest() {
        let settings = StudyCalendarFixture.settings()
        let snapshot = snapshot(settings: settings, today: "2026-08-14")
        #expect(state(snapshot, "2026-08-08", settings: settings) == .rest)  // 토요일
        #expect(state(snapshot, "2026-08-09", settings: settings) == .rest)  // 일요일
        // 계획 시작(08-03) 이전은 배정 자체가 없었다.
        #expect(state(snapshot, "2026-07-31", settings: settings) == .rest)
    }

    /// 되살린 날짜는 계획의 타임존을 따른다. 기기 타임존이 달라도 경계가 흔들리지 않는다.
    @Test func materializedDatesFollowThePlanTimezone() {
        let newYork = "America/New_York"
        let settings = StudyCalendarFixture.settings(createdAt: "2026-08-10", timeZone: newYork)
        let today = StudyCalendarFixture.date("2026-08-14", timeZone: newYork)
        let targets = AdaptiveStudyPlanner.historicalTargets(
            settings: settings,
            baseDailyTarget: 2,
            today: today
        )
        #expect(Set(targets.keys) == [
            "2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"
        ])
        // 뉴욕 13일 23:00은 서울 기준으로는 14일이지만 계획상 여전히 13일이다.
        let lateNight = StudyCalendarFixture.date("2026-08-13", timeZone: newYork)
            .addingTimeInterval(60 * 60 * 23)
        let schedule = StudySchedule(
            historicalTargets: [:],
            plan: AdaptiveStudyPlanner.plan(
                settings: settings,
                targetLevel: .IH,
                recentLevel: .IH,
                dailyCapacity: 2,
                completions: [:],
                today: today
            ),
            settings: settings,
            today: today
        )
        #expect(schedule.targetSets(for: settings.calendar.startOfDay(for: lateNight)) == 2)
    }

    /// 계획을 세우기 전(계획 시작일 이전)은 되살리지 않는다.
    @Test func backfillNeverReachesBeforeThePlanStart() {
        let settings = StudyCalendarFixture.settings(createdAt: "2026-08-12")
        let targets = AdaptiveStudyPlanner.historicalTargets(
            settings: settings,
            baseDailyTarget: 2,
            today: StudyCalendarFixture.date("2026-08-14")
        )
        #expect(Set(targets.keys) == ["2026-08-12", "2026-08-13", "2026-08-14"])
    }
}
