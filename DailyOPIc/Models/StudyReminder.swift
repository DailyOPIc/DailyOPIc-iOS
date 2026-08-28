import Foundation
import UserNotifications

/// 매일 학습 알림 정책 상수. 예약 규칙을 화면·서비스에 흩어 두지 않는다.
enum StudyReminderPolicy {
    /// 학습 알림만 건드리기 위한 식별자 네임스페이스.
    /// 개인 일정 알림(`PlannerEventReminderPolicy`)과 절대 섞이지 않는다.
    static let identifierPrefix = "dailyopic.study-reminder."
    /// 앞으로 예약해 두는 로컬 날짜 수. 하루 한 개이므로 대기 알림은 이 값을 넘지 않는다.
    static let horizonDays = 30

    static func identifier(forLocalDate date: String) -> String { identifierPrefix + date }
    static func isStudyReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }
}

/// 예약하려는 로컬 알림 하나. UNNotificationRequest로 바꾸기 전의 순수한 값이라
/// 권한 창을 띄우지 않고 그대로 테스트할 수 있다.
/// 학습 알림과 개인 일정 알림이 같은 값을 쓴다(만드는 규칙만 다르다).
struct LocalNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    /// 학습 계획 타임존이 들어간 연·월·일·시·분. 절대 시각으로 굳히지 않는다.
    let dateComponents: DateComponents
}

/// 이 기기에서 학습 알림을 받겠다는 **사용자 의도**. 세 가지 상태다(P9).
///
/// `unspecified`("아직 고른 적 없음")를 따로 두는 것이 P9의 핵심이다. 알림 권한이
/// 이미 있는데도 앱 안에서 한 번 더 켜라고 요구하면, 대부분은 학습 알림이 있다는
/// 사실조차 모른 채 떠난다. 그래서 고른 적이 없으면 켜진 것으로 본다.
/// 반대로 **직접 끈 것은 영구적**이다 — 다음 실행에서 슬그머니 되살리지 않는다.
enum StudyReminderPreference: String, Sendable, Equatable, CaseIterable {
    case unspecified
    case enabled
    case disabled

    /// 지금 켜진 것으로 볼 것인가. 시스템 권한과는 별개의 판단이다.
    var isEffectivelyOn: Bool { self != .disabled }
}

/// 학습 알림 목록을 만드는 곳.
///
/// P9부터 이 알림은 **플랜도 배정 학습량도 보지 않는다.** 매일 정한 시각에 한 번,
/// "오늘도 시작해 보자"고 말할 뿐이다. 휴식일에도 보낸다 — 쉬는 날 그냥 한 문제 푸는
/// 것도 훌륭한 학습이고(P8), 그날 알림을 끄면 우리가 그 길을 막는 셈이다.
/// 대신 **오늘 이미 학습했다면** 오늘 알림은 걷는다.
enum StudyReminderPlanner {
    static let title = "데일리오픽 할 시간!"
    /// 고정 문구. 남은 세트·목표 미달·시험 D-day처럼 재촉하는 말을 넣지 않는다.
    /// 답변·전사·점수·UID 같은 사용자 콘텐츠도 물론 넣지 않는다.
    static let body = "하루 한 문제부터, 오늘도 가볍게 시작해볼까요?"

    /// 오늘부터 예약 지평(30일)까지 하루 한 개.
    ///
    /// - Parameter completions: 학습 계획 타임존의 날짜별 **실제** 학습 완료 수(P8의 원장).
    ///   계획·목표가 아니라 정말로 한 학습만 여기 들어온다.
    static func reminders(
        settings: StudyPlanSettings,
        completions: [Date: Int],
        now: Date = .now
    ) -> [LocalNotificationRequest] {
        let calendar = settings.calendar
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<StudyReminderPolicy.horizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                return nil
            }
            return outcome(for: day, settings: settings, completions: completions, now: now).request
        }
    }

    /// 하루치 판단. 예약 목록과 진단이 **같은 함수**를 쓰게 하려고 분리했다 —
    /// 두 벌로 나뉘면 "화면은 된다는데 알림은 안 온다"를 영영 설명할 수 없다.
    static func outcome(
        for date: Date,
        settings: StudyPlanSettings,
        completions: [Date: Int],
        now: Date = .now
    ) -> ReminderOutcome {
        let calendar = settings.calendar
        let day = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: now)
        guard let horizonEnd = calendar.date(
            byAdding: .day,
            value: StudyReminderPolicy.horizonDays,
            to: startOfToday
        ), day >= startOfToday, day < horizonEnd else { return .skipped(.outsideHorizon) }

        // 시험 당일은 그대로 비워 둔다. 시험날 전용 경험은 P12가 맡는다.
        let examDay = settings.examDate.map { calendar.startOfDay(for: $0) }
        guard day != examDay else { return .skipped(.examDay) }
        // 배정량을 다 채웠는지는 묻지 않는다. **한 세트라도 실제로 했으면** 오늘 알림은 없다.
        guard (completions[day] ?? 0) == 0 else { return .skipped(.alreadyLearnedToday) }
        // 이미 지난 시각은 예약하지 않는다(오늘의 알림 시간이 지난 경우).
        guard settings.preferredStudyTime.date(on: day, calendar: calendar) > now else {
            return .skipped(.preferredTimePassed)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = settings.preferredStudyTime.hour
        components.minute = settings.preferredStudyTime.minute
        components.timeZone = settings.timeZone
        return .scheduled(
            LocalNotificationRequest(
                identifier: StudyReminderPolicy.identifier(
                    forLocalDate: LocalCalendarDate.text(from: day, timeZone: settings.timeZone)
                ),
                title: title,
                body: body,
                dateComponents: components
            )
        )
    }
}

/// 설정 화면의 "학습 알림" 행이 보여줄 것. 화면이 상태 조합을 직접 따지지 않도록
/// 순수 값으로 뽑아 둔다(그래야 시뮬레이터 없이 검증된다).
struct StudyReminderSettingsState: Equatable, Sendable {
    let isOn: Bool
    let statusText: String
    /// 토글을 켜는 순간 시스템 권한 창이 뜰 수 있는가. 자동으로 뜨는 경로는 없다.
    let requestsPermissionOnEnable: Bool

    static func make(
        preference: StudyReminderPreference,
        authorization: UNAuthorizationStatus
    ) -> StudyReminderSettingsState {
        guard preference.isEffectivelyOn else {
            return StudyReminderSettingsState(
                isOn: false,
                statusText: "학습 알림이 꺼져 있어요",
                requestsPermissionOnEnable: authorization == .notDetermined
            )
        }
        switch authorization {
        case .denied:
            // 앱에서는 켜 뒀지만 OS가 막았다. 여기서 다시 물어봐야 창이 뜨지 않는다.
            return StudyReminderSettingsState(
                isOn: true,
                statusText: "iPhone 설정에서 알림을 허용해 주세요",
                requestsPermissionOnEnable: false
            )
        case .authorized, .provisional, .ephemeral:
            return StudyReminderSettingsState(
                isOn: true,
                statusText: "매일 정한 시간에 알려드려요",
                requestsPermissionOnEnable: false
            )
        default:
            // 아직 물어본 적이 없다. 꺼진 모습으로 두어야 켜는 행동이 "의도적 허용"이 된다.
            return StudyReminderSettingsState(
                isOn: false,
                statusText: "알림을 허용하면 매일 정한 시간에 알려드려요",
                requestsPermissionOnEnable: true
            )
        }
    }
}
