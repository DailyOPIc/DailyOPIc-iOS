import Foundation

/// 예상 학습 기간 계산에 쓰는 모든 상수. 화면·뷰모델에 흩어 두지 않는다.
/// 이 값들은 검증된 학습 곡선이 아니라 보수적인 휴리스틱이고, 여기 한 곳만
/// 고치면 예측 전체가 같이 움직인다. 근거와 의미는 docs/PRODUCT.md에 있다.
enum StudyPlanEstimatorConfig {
    /// 이미 목표 등급에 도달했을 때도 유지·복습으로 권장하는 최소 학습량(세트).
    static let baseTotalSets = 20
    /// 목표까지 등급 한 단계당 더하는 학습량(세트).
    static let setsPerLevelStep = 12
    /// 최근 분석 결과가 없어 현재 등급을 모를 때 가정하는 등급 차이.
    /// 아는 척하지 않되 지나치게 길게 잡지도 않는다.
    static let assumedLevelStepsWhenUnknown = 2
    /// 최근 등급으로 인정하는 분석 기록의 최대 나이(일).
    static let recentLevelMaxAgeDays = 60
    static let minimumTotalSets = 12
    static let maximumTotalSets = 120
    /// 예상 완료일 탐색 상한(일). 계획이 비현실적으로 길면 날짜 대신 nil을 준다.
    static let maximumForecastDays = 365
    /// capabilities를 못 받았을 때 쓰는 플랜별 하루 Daily 토큰 수.
    /// 진실은 언제나 서버 `quotaPolicy.practiceDaily`이고 이건 오프라인 폴백이다.
    static let fallbackDailyCapacity: [PlanEntitlement: Int] = [
        .free: 1, .basic: 3, .plus: 10, .pro: 20
    ]
}

/// 권장 학습 계획의 예측. "이 날짜에 해당 등급을 취득한다"는 뜻이 아니라
/// "권장 학습량을 이 속도로 끝내는 데 걸리는 예상 기간"이다.
struct StudyPlanForecast: Equatable, Sendable {
    let recommendedTotalSets: Int
    let desiredDailySets: Int
    /// 플랜의 하루 Daily 토큰 한도로 깎은 실제 목표. 20토큰은 한도지 숙제가 아니다.
    let effectiveDailyTarget: Int
    let dailyCapacity: Int
    let estimatedStudyDays: Int
    let estimatedCompletionDate: Date?

    var isCappedByPlan: Bool { effectiveDailyTarget < desiredDailySets }

    static let disclaimer = "최근 학습 정보와 설정한 학습량을 바탕으로 계산한 예상치이며, 실제 OPIc 등급 달성을 보장하지 않아요."
}

enum StudyPlanEstimator {
    /// 하루 Daily 토큰 한도. 서버 capabilities가 진실이고, 없을 때만 플랜 표로 폴백한다.
    /// 광고 보너스는 매일 보장되지 않으므로 권장 학습량에 넣지 않는다.
    static func dailyCapacity(capabilities: Capabilities?, plan: PlanEntitlement) -> Int {
        if let practiceDaily = capabilities?.quotaPolicy.practiceDaily, practiceDaily > 0 {
            return practiceDaily
        }
        return StudyPlanEstimatorConfig.fallbackDailyCapacity[plan] ?? 1
    }

    /// 목표까지 남은 등급 단계. 최근 등급을 모르면 보수적으로 가정한다.
    static func levelSteps(target: OPIcLevel, recent: OPIcLevel?) -> Int {
        guard let recent else { return StudyPlanEstimatorConfig.assumedLevelStepsWhenUnknown }
        return max(0, target.rank - recent.rank)
    }

    static func recommendedTotalSets(target: OPIcLevel, recent: OPIcLevel?) -> Int {
        let steps = levelSteps(target: target, recent: recent)
        let raw = StudyPlanEstimatorConfig.baseTotalSets
            + StudyPlanEstimatorConfig.setsPerLevelStep * steps
        return min(
            StudyPlanEstimatorConfig.maximumTotalSets,
            max(StudyPlanEstimatorConfig.minimumTotalSets, raw)
        )
    }

    static func effectiveDailyTarget(intensity: StudyIntensity, dailyCapacity: Int) -> Int {
        max(1, min(intensity.desiredDailySets, dailyCapacity))
    }

    static func forecast(
        settings: StudyPlanSettings,
        targetLevel: OPIcLevel,
        recentLevel: OPIcLevel?,
        dailyCapacity: Int,
        today: Date = .now
    ) -> StudyPlanForecast {
        let totalSets = recommendedTotalSets(target: targetLevel, recent: recentLevel)
        let target = effectiveDailyTarget(
            intensity: settings.intensity,
            dailyCapacity: dailyCapacity
        )
        let studyDays = Int((Double(totalSets) / Double(target)).rounded(.up))
        return StudyPlanForecast(
            recommendedTotalSets: totalSets,
            desiredDailySets: settings.intensity.desiredDailySets,
            effectiveDailyTarget: target,
            dailyCapacity: dailyCapacity,
            estimatedStudyDays: studyDays,
            estimatedCompletionDate: completionDate(
                studyDays: studyDays,
                settings: settings,
                today: today
            )
        )
    }

    /// 선택한 공부 요일만 세어 `studyDays`번째 학습일을 찾는다. 오늘이 공부 요일이면
    /// 오늘부터 센다.
    static func completionDate(
        studyDays: Int,
        settings: StudyPlanSettings,
        today: Date = .now
    ) -> Date? {
        guard studyDays > 0, !settings.studyWeekdays.isEmpty else { return nil }
        let calendar = settings.calendar
        var day = calendar.startOfDay(for: today)
        var remaining = studyDays
        for _ in 0..<StudyPlanEstimatorConfig.maximumForecastDays {
            if settings.isStudyDay(day) {
                remaining -= 1
                if remaining == 0 { return day }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}

/// 하루의 학습 상태. 색만으로 구분하지 않도록 기호와 문구를 함께 가진다.
enum StudyDayState: String, Sendable, CaseIterable {
    case rest
    case planned
    case partial
    case completed
    case missed

    var title: String {
        switch self {
        case .rest: "휴식"
        case .planned: "예정"
        case .partial: "일부 완료"
        case .completed: "완료"
        case .missed: "놓침"
        }
    }

    var symbolName: String {
        switch self {
        case .rest: "moon.zzz"
        case .planned: "circle.dotted"
        case .partial: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .missed: "exclamationmark.circle"
        }
    }
}

struct StudyDay: Identifiable, Sendable {
    let date: Date
    let state: StudyDayState
    let completedSets: Int
    let targetSets: Int

    var id: Date { date }
    var isScheduled: Bool { state != .rest }
}

enum StudyCalendarEngine {
    static func state(
        date: Date,
        today: Date,
        isStudyDay: Bool,
        completedSets: Int,
        targetSets: Int,
        calendar: Calendar = .current
    ) -> StudyDayState {
        guard isStudyDay else { return .rest }
        if targetSets > 0, completedSets >= targetSets { return .completed }
        if completedSets > 0 { return .partial }
        // 오늘과 미래는 아직 놓친 게 아니다. 자동 재배치(G3)는 하지 않고 표시만 한다.
        let day = calendar.startOfDay(for: date)
        return day < calendar.startOfDay(for: today) ? .missed : .planned
    }

    static func day(
        date: Date,
        today: Date,
        settings: StudyPlanSettings,
        targetSets: Int,
        completions: [Date: Int]
    ) -> StudyDay {
        let calendar = settings.calendar
        let key = calendar.startOfDay(for: date)
        let completed = completions[key] ?? 0
        return StudyDay(
            date: key,
            state: state(
                date: key,
                today: today,
                isStudyDay: settings.isStudyDay(key),
                completedSets: completed,
                targetSets: targetSets,
                calendar: calendar
            ),
            completedSets: completed,
            targetSets: settings.isStudyDay(key) ? targetSets : 0
        )
    }

    static func days(
        from start: Date,
        count: Int,
        today: Date,
        settings: StudyPlanSettings,
        targetSets: Int,
        completions: [Date: Int]
    ) -> [StudyDay] {
        let calendar = settings.calendar
        let first = calendar.startOfDay(for: start)
        return (0..<max(0, count)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else {
                return nil
            }
            return day(
                date: date,
                today: today,
                settings: settings,
                targetSets: targetSets,
                completions: completions
            )
        }
    }

    /// 연속 학습일. 계획된 휴식일은 끊지 않고, 목표에 못 미친 지난 학습일은 끊는다.
    /// 아직 끝나지 않은 오늘은 끊지 않는다(미완료여도 어제까지의 기록을 유지).
    static func streak(
        today: Date,
        settings: StudyPlanSettings,
        targetSets: Int,
        completions: [Date: Int]
    ) -> Int {
        guard !settings.studyWeekdays.isEmpty else { return 0 }
        let calendar = settings.calendar
        var day = calendar.startOfDay(for: today)
        var streak = 0
        for offset in 0..<StudyPlanEstimatorConfig.maximumForecastDays {
            if settings.isStudyDay(day) {
                let completed = completions[day] ?? 0
                if targetSets > 0, completed >= targetSets {
                    streak += 1
                } else if offset > 0 {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// 이번 주 요약. "이번 주 3 / 5일 완료"의 두 숫자.
    static func weekSummary(
        days: [StudyDay]
    ) -> (completed: Int, scheduled: Int) {
        let scheduled = days.filter(\.isScheduled)
        return (scheduled.filter { $0.state == .completed }.count, scheduled.count)
    }

    /// 완료 기록(세트 단위) → 로컬 날짜별 완료 수.
    static func completionCounts(
        completedAt dates: [Date],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        dates.reduce(into: [:]) { counts, date in
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
    }

    /// 그 주의 월요일. 주간 스트립은 사용자 지역 설정과 무관하게 월~일로 고정한다
    /// (공부 요일 선택 화면과 순서를 맞추기 위해).
    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = StudyWeekday.from(date: day, calendar: calendar).rawValue - 1
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }
}

/// 대시보드가 한 번에 필요로 하는 파생값 묶음. 저장하지 않고 매번 계산한다.
struct StudyCalendarSnapshot: Sendable {
    let forecast: StudyPlanForecast
    let today: StudyDay
    let weekDays: [StudyDay]
    let streak: Int
    let weekCompletedDays: Int
    let weekScheduledDays: Int
    /// 시험일까지 남은 일수(오늘=0). 시험일이 없으면 nil.
    let examDaysRemaining: Int?
    /// 예상 완료일이 시험일 이후인가. 경고 문구에만 쓰고 학습량을 자동으로 늘리지 않는다.
    let forecastLandsAfterExam: Bool

    static func make(
        settings: StudyPlanSettings,
        targetLevel: OPIcLevel,
        recentLevel: OPIcLevel?,
        dailyCapacity: Int,
        completions: [Date: Int],
        today: Date = .now
    ) -> StudyCalendarSnapshot {
        let calendar = settings.calendar
        let startOfToday = calendar.startOfDay(for: today)
        let forecast = StudyPlanEstimator.forecast(
            settings: settings,
            targetLevel: targetLevel,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            today: startOfToday
        )
        let weekDays = StudyCalendarEngine.days(
            from: StudyCalendarEngine.startOfWeek(for: startOfToday, calendar: calendar),
            count: 7,
            today: startOfToday,
            settings: settings,
            targetSets: forecast.effectiveDailyTarget,
            completions: completions
        )
        let summary = StudyCalendarEngine.weekSummary(days: weekDays)
        let examDaysRemaining = settings.examDate.map {
            calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: $0)).day ?? 0
        }
        return StudyCalendarSnapshot(
            forecast: forecast,
            today: StudyCalendarEngine.day(
                date: startOfToday,
                today: startOfToday,
                settings: settings,
                targetSets: forecast.effectiveDailyTarget,
                completions: completions
            ),
            weekDays: weekDays,
            streak: StudyCalendarEngine.streak(
                today: startOfToday,
                settings: settings,
                targetSets: forecast.effectiveDailyTarget,
                completions: completions
            ),
            weekCompletedDays: summary.completed,
            weekScheduledDays: summary.scheduled,
            examDaysRemaining: examDaysRemaining,
            forecastLandsAfterExam: {
                guard let exam = settings.examDate else { return false }
                guard let completion = forecast.estimatedCompletionDate else { return true }
                return calendar.startOfDay(for: completion) > calendar.startOfDay(for: exam)
            }()
        )
    }
}
