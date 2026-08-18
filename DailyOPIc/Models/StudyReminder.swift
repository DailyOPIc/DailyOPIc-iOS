import Foundation

/// 학습 알림 정책 상수. 예약 규칙을 화면·서비스에 흩어 두지 않는다.
enum StudyReminderPolicy {
    /// 우리 알림만 건드리기 위한 식별자 네임스페이스.
    /// 앞으로 다른 종류의 알림이 생겨도 이 접두사로만 정리한다.
    static let identifierPrefix = "dailyopic.study-reminder."
    /// 앞으로 예약해 두는 로컬 날짜 수. 하루 한 개이므로 대기 알림은 이 값을 넘지 않는다.
    static let horizonDays = 30
    /// 시험이 이만큼 남았을 때만 알림에 D-day를 덧붙인다.
    static let examContextDays = 7

    static func identifier(forLocalDate date: String) -> String { identifierPrefix + date }
    static func isStudyReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }
}

/// 예약하려는 알림 하나. UNNotificationRequest로 바꾸기 전의 순수한 값이라
/// 권한 창을 띄우지 않고 그대로 테스트할 수 있다.
struct StudyReminderRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    /// 학습 계획 타임존이 들어간 연·월·일·시·분. 절대 시각으로 굳히지 않는다.
    let dateComponents: DateComponents
}

/// 캘린더 일정 → 알림 목록. 알림 전용 플래너를 따로 만들지 않고
/// G3/G4가 만든 `AdaptiveStudyPlan.upcomingDays`를 그대로 읽는다.
enum StudyReminderPlanner {
    static let title = "오늘의 Daily 학습"

    static func reminders(
        plan: AdaptiveStudyPlan,
        settings: StudyPlanSettings,
        completions: [Date: Int],
        now: Date = .now
    ) -> [StudyReminderRequest] {
        // upcomingDays에는 휴식일도, 계획을 다 끝낸 뒤의 날도 들어 있지 않다.
        plan.upcomingDays.compactMap { day in
            outcome(
                for: day.date,
                plan: plan,
                settings: settings,
                completions: completions,
                now: now
            ).request
        }
    }

    /// 하루치 판단. 예약 목록과 진단이 **같은 함수**를 쓰게 하려고 분리했다 —
    /// 두 벌로 나뉘면 "화면은 된다는데 알림은 안 온다"를 영영 설명할 수 없다.
    ///
    /// 조건은 전부 AND라서 실패 이유의 순서만 다를 뿐 예약 결과는 이전과 같다.
    static func outcome(
        for date: Date,
        plan: AdaptiveStudyPlan,
        settings: StudyPlanSettings,
        completions: [Date: Int],
        now: Date = .now
    ) -> StudyReminderOutcome {
        let calendar = settings.calendar
        let day = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: now)
        guard let horizonEnd = calendar.date(
            byAdding: .day,
            value: StudyReminderPolicy.horizonDays,
            to: startOfToday
        ), day >= startOfToday, day < horizonEnd else { return .skipped(.outsideHorizon) }

        let examDay = settings.examDate.map { calendar.startOfDay(for: $0) }
        // 시험 당일에는 학습 숙제 알림을 보내지 않는다.
        guard day != examDay else { return .skipped(.examDay) }
        guard settings.isStudyDay(day) else { return .skipped(.restDay) }
        guard let dayPlan = plan.plan(for: day), dayPlan.targetSets > 0 else {
            // 계획에 없는 학습일: 권장 학습량을 다 채웠거나(완료) 계획이 그 전에 끝난다.
            return .skipped(plan.remainingSets > 0 ? .noTarget : .targetComplete)
        }
        let remaining = dayPlan.targetSets - (completions[day] ?? 0)
        guard remaining > 0 else { return .skipped(.targetComplete) }
        // 이미 지난 시각은 예약하지 않는다(오늘의 알림 시간이 지난 경우).
        guard settings.preferredStudyTime.date(on: day, calendar: calendar) > now else {
            return .skipped(.preferredTimePassed)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = settings.preferredStudyTime.hour
        components.minute = settings.preferredStudyTime.minute
        components.timeZone = settings.timeZone
        return .scheduled(
            StudyReminderRequest(
                identifier: StudyReminderPolicy.identifier(
                    forLocalDate: LocalCalendarDate.text(from: day, timeZone: settings.timeZone)
                ),
                title: title,
                body: body(
                    remaining: remaining,
                    isPartiallyDone: remaining < dayPlan.targetSets,
                    daysToExam: examDay.flatMap {
                        calendar.dateComponents([.day], from: day, to: $0).day
                    }
                ),
                dateComponents: components
            )
        )
    }

    /// 고정 템플릿. 답변·전사·UID 같은 사용자 콘텐츠는 절대 넣지 않는다.
    /// 뒤처졌다·놓쳤다처럼 자책하게 만드는 표현도 쓰지 않는다.
    private static func body(remaining: Int, isPartiallyDone: Bool, daysToExam: Int?) -> String {
        let base = isPartiallyDone
            ? "오늘 계획까지 \(remaining)세트 남았어요."
            : "오늘 Daily 연습 \(remaining)세트가 예정되어 있어요."
        guard let daysToExam,
              (1...StudyReminderPolicy.examContextDays).contains(daysToExam) else { return base }
        return "시험까지 \(daysToExam)일 · " + base
    }
}
