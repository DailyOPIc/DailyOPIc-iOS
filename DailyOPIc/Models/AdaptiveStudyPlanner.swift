import Foundation

/// 계획의 현재 상태. UI 문구와 위험 표시가 여기서 갈린다.
enum StudyPlannerMode: String, Sendable, Equatable {
    /// 남은 학습량을 기본 학습량 그대로 소화해도 괜찮은 상태(시험일이 없거나 여유 있음).
    case onTrack
    /// 시험일까지 남은 학습일에 남은 학습량을 다시 나눈 상태.
    case compressed
    /// 안전 상한까지 올려도 시험 전에 끝낼 수 없는 상태. 거짓으로 가능하다고 하지 않는다.
    case insufficientTime
    /// 권장 학습량을 모두 마친 상태. 더 이상 의무 학습을 만들지 않는다.
    case completed
}

/// 특정 날짜에 배정된 학습량. 휴식일에는 아예 만들지 않는다(= 계획 없음).
struct StudyDayPlan: Equatable, Sendable {
    let date: Date
    let targetSets: Int
}

/// G3 적응형 계획의 전체 결과. 저장하지 않고 매번 계산한다.
struct AdaptiveStudyPlan: Sendable {
    let mode: StudyPlannerMode
    /// 목표 등급 기준 권장 총 학습량(G2 베이스라인 그대로).
    let totalRecommendedSets: Int
    /// 계획 시작 이후의 실제 완료 세트 수.
    let completedSets: Int
    /// 남은 권장 학습량. 음수가 되지 않는다.
    let remainingSets: Int
    /// 강도와 플랜 한도로 정해지는 평소 하루 학습량.
    let baseDailyTarget: Int
    /// 압축 모드에서도 넘지 않는 하루 상한.
    let adaptiveDailyCeiling: Int
    let dailyCapacity: Int
    let desiredDailySets: Int
    /// 오늘부터의 학습 일정. 날짜순 정렬이며 휴식일과 학습량 0인 날은 들어가지 않는다.
    let upcomingDays: [StudyDayPlan]
    /// 남은 학습량을 모두 끝내는 날. 계획이 이미 끝났으면 nil.
    let estimatedCompletionDate: Date?
    let examDate: Date?
    /// 시험 전 학습일에 상한까지 채웠을 때 가능한 최대 학습량. 시험일이 없으면 nil.
    let maximumSetsPossibleBeforeExam: Int?
    /// 시험 전에 모자라는 학습량. `insufficientTime`이 아니면 nil.
    let shortfallSets: Int?

    var isCappedByPlan: Bool { baseDailyTarget < desiredDailySets }

    /// 남은 학습일 수(오늘 포함). 대시보드의 "약 n일" 표기에 쓴다.
    var estimatedStudyDays: Int { upcomingDays.count }

    func plan(for day: Date) -> StudyDayPlan? {
        upcomingDays.first { $0.date == day }
    }
}

/// 남은 학습량을 앞으로의 학습일에 나누는 결정론적 planner.
/// 같은 입력이면 항상 같은 일정을 만든다. 난수·AI·네트워크를 쓰지 않는다.
enum AdaptiveStudyPlanner {
    static func plan(
        settings: StudyPlanSettings,
        targetLevel: OPIcLevel,
        recentLevel: OPIcLevel?,
        dailyCapacity: Int,
        completions: [Date: Int],
        today: Date = .now
    ) -> AdaptiveStudyPlan {
        let calendar = settings.calendar
        let startOfToday = calendar.startOfDay(for: today)

        let total = StudyPlanEstimator.recommendedTotalSets(target: targetLevel, recent: recentLevel)
        let completed = eligibleCompletedSets(
            settings: settings,
            completions: completions,
            today: startOfToday
        )
        let remaining = max(0, total - completed)
        let base = StudyPlanEstimator.effectiveDailyTarget(
            intensity: settings.intensity,
            dailyCapacity: dailyCapacity
        )
        let ceiling = StudyPlanEstimator.adaptiveDailyCeiling(
            baseDailyTarget: base,
            dailyCapacity: dailyCapacity
        )
        let exam = settings.examDate.map { calendar.startOfDay(for: $0) }

        func result(
            mode: StudyPlannerMode,
            days: [StudyDayPlan],
            maximumBeforeExam: Int? = nil,
            shortfall: Int? = nil
        ) -> AdaptiveStudyPlan {
            AdaptiveStudyPlan(
                mode: mode,
                totalRecommendedSets: total,
                completedSets: completed,
                remainingSets: remaining,
                baseDailyTarget: base,
                adaptiveDailyCeiling: ceiling,
                dailyCapacity: dailyCapacity,
                desiredDailySets: settings.intensity.desiredDailySets,
                upcomingDays: days,
                estimatedCompletionDate: days.last?.date,
                examDate: exam,
                maximumSetsPossibleBeforeExam: maximumBeforeExam,
                shortfallSets: shortfall
            )
        }

        // 권장 학습량을 다 채웠으면 더 이상 숙제를 만들지 않는다. 자율 연습은 그대로 가능하다.
        guard remaining > 0 else { return result(mode: .completed, days: []) }

        // 1) 평소 속도로 짠 일정. 놓친 날의 몫을 다음 날에 몰아주지 않고,
        //    남은 학습량이 그만큼 뒤로 밀릴 뿐이다.
        let normalDays = distribute(
            remaining,
            over: studyDates(from: startOfToday, settings: settings),
            perDay: base
        )

        guard let exam else { return result(mode: .onTrack, days: normalDays) }

        // 2) 시험일이 있으면 마지막 학습일은 시험 전날까지다. 시험 당일에 숙제를 내지 않는다.
        guard let lastAllowed = calendar.date(byAdding: .day, value: -1, to: exam),
              lastAllowed >= startOfToday else {
            // 시험이 오늘이거나 이미 지났다. 남은 학습일이 없으므로 솔직하게 부족 상태로 둔다.
            return result(
                mode: .insufficientTime,
                days: [],
                maximumBeforeExam: 0,
                shortfall: remaining
            )
        }

        if let completion = normalDays.last?.date, completion <= lastAllowed {
            return result(mode: .onTrack, days: normalDays)
        }

        // 3) 평소 속도로는 시험을 넘긴다 → 시험 전 학습일에 다시 나눈다.
        //    휴식일은 압축 모드에서도 휴식일이다.
        let available = studyDates(from: startOfToday, through: lastAllowed, settings: settings)
        let maximumBeforeExam = available.count * ceiling

        if remaining <= maximumBeforeExam {
            return result(
                mode: .compressed,
                days: balanced(remaining, over: available),
                maximumBeforeExam: maximumBeforeExam
            )
        }

        // 4) 상한까지 채워도 모자란다. 상한 이상을 몰래 배정하지 않고 부족분을 드러낸다.
        //    예상 완료일은 시험일이 아니라 "이 속도로 끝나는 실제 날짜"를 쓴다.
        return result(
            mode: .insufficientTime,
            days: distribute(
                remaining,
                over: studyDates(from: startOfToday, settings: settings),
                perDay: ceiling
            ),
            maximumBeforeExam: maximumBeforeExam,
            shortfall: remaining - maximumBeforeExam
        )
    }

    /// 계획 시작일부터 오늘까지의 학습일 배정량("yyyy-MM-dd" → 세트).
    /// 고정 기록이 없는 지난 날을 되살리는 값이며, 화면 표시와 고정 저장이 **같은 함수**를
    /// 쓴다(보이는 값과 저장되는 값이 갈라지지 않게 하려는 것이 이 함수의 목적이다).
    /// 휴식일은 만들지 않는다.
    static func historicalTargets(
        settings: StudyPlanSettings,
        baseDailyTarget: Int,
        today: Date
    ) -> [String: Int] {
        guard baseDailyTarget > 0 else { return [:] }
        let startOfToday = settings.calendar.startOfDay(for: today)
        let start = planStartDay(settings: settings, today: startOfToday)
        return studyDates(from: start, through: startOfToday, settings: settings)
            .reduce(into: [:]) { targets, date in
                targets[LocalCalendarDate.text(from: date, timeZone: settings.timeZone)] = baseDailyTarget
            }
    }

    /// 계획 시작일 이후의 완료만 남은 학습량을 줄인다. 계획을 세우기 전에 해 둔 연습이
    /// 새 계획을 이미 끝낸 것처럼 만들지 않는다.
    /// `createdAt`이 없으면(아직 서버 왕복 전) 오늘을 시작일로 본다.
    static func eligibleCompletedSets(
        settings: StudyPlanSettings,
        completions: [Date: Int],
        today: Date
    ) -> Int {
        let start = planStartDay(settings: settings, today: today)
        return completions.reduce(0) { sum, entry in
            entry.key >= start ? sum + entry.value : sum
        }
    }

    static func planStartDay(settings: StudyPlanSettings, today: Date) -> Date {
        let calendar = settings.calendar
        guard let createdAt = settings.createdAt else { return calendar.startOfDay(for: today) }
        return min(calendar.startOfDay(for: createdAt), calendar.startOfDay(for: today))
    }

    /// 선택한 공부 요일만 골라 날짜를 만든다. 압축이 필요해도 주말을 몰래 쓰지 않는다.
    static func studyDates(
        from start: Date,
        through end: Date? = nil,
        settings: StudyPlanSettings,
        limit: Int = StudyPlanEstimatorConfig.maximumForecastDays
    ) -> [Date] {
        guard !settings.studyWeekdays.isEmpty else { return [] }
        let calendar = settings.calendar
        var day = calendar.startOfDay(for: start)
        var dates: [Date] = []
        for _ in 0..<limit {
            if let end, day > end { break }
            if settings.isStudyDay(day) { dates.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    /// 하루 `perDay`씩 채우다 남은 학습량이 떨어지면 멈춘다(마지막 날은 남은 만큼만).
    static func distribute(_ sets: Int, over dates: [Date], perDay: Int) -> [StudyDayPlan] {
        guard perDay > 0 else { return [] }
        var remaining = sets
        var plans: [StudyDayPlan] = []
        for date in dates where remaining > 0 {
            let assigned = min(perDay, remaining)
            plans.append(StudyDayPlan(date: date, targetSets: assigned))
            remaining -= assigned
        }
        return plans
    }

    /// 남은 학습량을 학습일에 고르게 나눈다. 나머지는 앞쪽 날짜부터 1세트씩 더 준다.
    /// 예: 11세트 / 5일 → 3, 2, 2, 2, 2. 한 날에 몰아주지 않는다.
    static func balanced(_ sets: Int, over dates: [Date]) -> [StudyDayPlan] {
        guard !dates.isEmpty, sets > 0 else { return [] }
        let perDay = sets / dates.count
        let remainder = sets % dates.count
        return dates.enumerated().compactMap { index, date in
            let target = perDay + (index < remainder ? 1 : 0)
            guard target > 0 else { return nil }
            return StudyDayPlan(date: date, targetSets: target)
        }
    }
}
