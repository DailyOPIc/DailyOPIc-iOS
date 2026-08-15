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
    /// 시험일이 촉박할 때 하루 목표를 기본값 위로 얼마나 더 올릴 수 있는지(세트).
    /// 토큰이 많다고 그만큼 숙제를 낼 수 있는 것은 아니다.
    static let adaptiveBuffer = 2
    /// 어떤 플랜에서도 하루 의무 학습량이 이 값을 넘지 않는다.
    static let productMaximumAdaptiveDailySets = 5
}

enum StudyPlanEstimator {
    /// "이 날짜에 해당 등급을 취득한다"는 뜻이 아니라 "권장 학습량을 이 속도로 끝내는 데
    /// 걸리는 예상 기간"이라는 사실을 화면에서 항상 함께 밝힌다.
    static let disclaimer = "최근 학습 정보와 설정한 학습량을 바탕으로 계산한 예상치이며, 실제 OPIc 등급 달성을 보장하지 않아요."

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

    /// 시험이 촉박할 때 planner가 하루에 낼 수 있는 최대 학습량.
    /// 플랜 토큰이 20개여도 20세트를 숙제로 내지 않는다는 뜻이다.
    static func adaptiveDailyCeiling(baseDailyTarget: Int, dailyCapacity: Int) -> Int {
        max(
            1,
            min(
                dailyCapacity,
                baseDailyTarget + StudyPlanEstimatorConfig.adaptiveBuffer,
                StudyPlanEstimatorConfig.productMaximumAdaptiveDailySets
            )
        )
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

/// 날짜별 배정 학습량. 지난 날은 그날 고정된 값을, 오늘·미래는 지금 계산한 적응형 값을 준다.
/// 지난 날을 현재 설정으로 다시 계산하지 않는 것이 이 타입의 유일한 목적이다.
struct StudySchedule: Sendable {
    private let historical: [Date: Int]
    private let upcoming: [Date: Int]
    private let startOfToday: Date

    init(
        historicalTargets: [String: Int],
        plan: AdaptiveStudyPlan?,
        settings: StudyPlanSettings,
        today: Date
    ) {
        let calendar = settings.calendar
        let timeZone = settings.timeZone
        startOfToday = calendar.startOfDay(for: today)
        // 고정 기록이 없는 지난 학습일은 그날 적용되던 계획으로 되살린다.
        // 캘린더를 며칠 안 열어 기록이 비어 있어도 지난 학습일이 휴식으로 바뀌지 않는다.
        // 고정 기록이 있으면 언제나 그쪽이 이긴다(= 과거는 불변).
        let materialized = AdaptiveStudyPlanner.historicalTargets(
            settings: settings,
            baseDailyTarget: plan?.baseDailyTarget ?? 0,
            today: startOfToday
        )
        historical = materialized.merging(historicalTargets) { _, frozen in frozen }
            .reduce(into: [:]) { result, entry in
                guard let date = LocalCalendarDate.date(from: entry.key, timeZone: timeZone) else {
                    return
                }
                result[calendar.startOfDay(for: date)] = entry.value
            }
        upcoming = (plan?.upcomingDays ?? []).reduce(into: [:]) { result, day in
            result[calendar.startOfDay(for: day.date)] = day.targetSets
        }
    }

    /// 배정 학습량. 0이면 그날은 휴식(또는 계획이 이미 끝난 날)이다.
    func targetSets(for day: Date) -> Int {
        (day < startOfToday ? historical[day] : upcoming[day]) ?? 0
    }
}

enum StudyCalendarEngine {
    static func state(
        date: Date,
        today: Date,
        completedSets: Int,
        targetSets: Int,
        calendar: Calendar = .current
    ) -> StudyDayState {
        // 배정된 학습이 없는 날은 휴식이다. 계획을 다 끝낸 뒤의 학습일도 여기 들어온다.
        guard targetSets > 0 else { return .rest }
        if completedSets >= targetSets { return .completed }
        if completedSets > 0 { return .partial }
        let day = calendar.startOfDay(for: date)
        return day < calendar.startOfDay(for: today) ? .missed : .planned
    }

    static func day(
        date: Date,
        today: Date,
        settings: StudyPlanSettings,
        schedule: StudySchedule,
        completions: [Date: Int]
    ) -> StudyDay {
        let calendar = settings.calendar
        let key = calendar.startOfDay(for: date)
        let completed = completions[key] ?? 0
        let target = schedule.targetSets(for: key)
        return StudyDay(
            date: key,
            state: state(
                date: key,
                today: today,
                completedSets: completed,
                targetSets: target,
                calendar: calendar
            ),
            completedSets: completed,
            targetSets: target
        )
    }

    static func days(
        from start: Date,
        count: Int,
        today: Date,
        settings: StudyPlanSettings,
        schedule: StudySchedule,
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
                schedule: schedule,
                completions: completions
            )
        }
    }

    /// 연속 학습일. 휴식일은 끊지 않고, 그날 배정량에 못 미친 지난 학습일은 끊는다.
    /// 아직 끝나지 않은 오늘은 끊지 않는다(미완료여도 어제까지의 기록을 유지).
    static func streak(
        today: Date,
        settings: StudyPlanSettings,
        schedule: StudySchedule,
        completions: [Date: Int]
    ) -> Int {
        let calendar = settings.calendar
        var day = calendar.startOfDay(for: today)
        var streak = 0
        for offset in 0..<StudyPlanEstimatorConfig.maximumForecastDays {
            let target = schedule.targetSets(for: day)
            if target > 0 {
                if (completions[day] ?? 0) >= target {
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
    let plan: AdaptiveStudyPlan
    let schedule: StudySchedule
    let today: StudyDay
    let weekDays: [StudyDay]
    let streak: Int
    let weekCompletedDays: Int
    let weekScheduledDays: Int
    /// 시험일까지 남은 일수(오늘=0). 시험일이 없으면 nil.
    let examDaysRemaining: Int?

    /// 오늘 아직 남은 학습량. 초과 학습해도 음수가 되지 않는다.
    var remainingToday: Int { max(0, today.targetSets - today.completedSets) }
    /// 오늘 배정량을 넘겨 더 한 학습량.
    var extraToday: Int { max(0, today.completedSets - today.targetSets) }

    static func make(
        settings: StudyPlanSettings,
        targetLevel: OPIcLevel,
        recentLevel: OPIcLevel?,
        dailyCapacity: Int,
        completions: [Date: Int],
        historicalTargets: [String: Int] = [:],
        policy: CalendarFeaturePolicy = .everything,
        today: Date = .now
    ) -> StudyCalendarSnapshot {
        let calendar = settings.calendar
        let startOfToday = calendar.startOfDay(for: today)
        let plan = AdaptiveStudyPlanner.plan(
            settings: settings,
            targetLevel: targetLevel,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            completions: completions,
            policy: policy,
            today: startOfToday
        )
        let schedule = StudySchedule(
            historicalTargets: historicalTargets,
            plan: plan,
            settings: settings,
            today: startOfToday
        )
        let weekDays = StudyCalendarEngine.days(
            from: StudyCalendarEngine.startOfWeek(for: startOfToday, calendar: calendar),
            count: 7,
            today: startOfToday,
            settings: settings,
            schedule: schedule,
            completions: completions
        )
        let summary = StudyCalendarEngine.weekSummary(days: weekDays)
        return StudyCalendarSnapshot(
            plan: plan,
            schedule: schedule,
            today: StudyCalendarEngine.day(
                date: startOfToday,
                today: startOfToday,
                settings: settings,
                schedule: schedule,
                completions: completions
            ),
            weekDays: weekDays,
            streak: StudyCalendarEngine.streak(
                today: startOfToday,
                settings: settings,
                schedule: schedule,
                completions: completions
            ),
            weekCompletedDays: summary.completed,
            weekScheduledDays: summary.scheduled,
            examDaysRemaining: settings.examDate.map {
                calendar.dateComponents(
                    [.day],
                    from: startOfToday,
                    to: calendar.startOfDay(for: $0)
                ).day ?? 0
            }
        )
    }

    /// 지난 날짜까지 포함해 고정해 둘 배정 학습량("yyyy-MM-dd" → 세트).
    /// 기록이 없는 지난 학습일은 지금 아는 정보(기본 학습량)로 한 번 채우고, 그 뒤로는
    /// 이 값이 바뀌지 않는다. 오늘은 현재 적응형 배정량으로 갱신된다.
    func targetsToFreeze(settings: StudyPlanSettings, today: Date) -> [String: Int] {
        let startOfToday = settings.calendar.startOfDay(for: today)
        let timeZone = settings.timeZone
        // 화면에 되살려 보여준 값을 그대로 고정한다(같은 함수를 쓴다).
        var targets = AdaptiveStudyPlanner.historicalTargets(
            settings: settings,
            baseDailyTarget: plan.baseDailyTarget,
            today: startOfToday
        )
        // 오늘은 계획이 끝났으면 0, 압축 중이면 압축된 값이다.
        targets[LocalCalendarDate.text(from: startOfToday, timeZone: timeZone)] =
            plan.plan(for: startOfToday)?.targetSets ?? 0
        return targets
    }
}
