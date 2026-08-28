import Foundation

/// 개인 일정 알림 정책. 학습 알림과 **다른 네임스페이스**를 쓴다 —
/// 한쪽 정리가 다른 쪽을 지우면 "일정을 지웠더니 학습 알림이 사라졌다"가 된다.
///
/// 일정 자체(추가·수정·삭제)는 전 플랜이 쓰고, **알림 옵션만** 유료다(P9).
enum PlannerEventReminderPolicy {
    static let identifierPrefix = "dailyopic.planner-event-reminder."
    static let title = "개인 일정 알림"
    /// V1이 허용하는 미리 알림 간격(분). 사용자 지정 간격은 없다.
    /// nil은 "알림 없음"이고, 이것이 새 일정의 기본값이다.
    static let allowedOffsets = [0, 10, 30, 60]

    /// 일정 하나당 알림 하나. 식별자가 일정 id로 결정돼야 수정·삭제가 정확히 그 알림만 건드린다.
    static func identifier(eventID: UUID) -> String { identifierPrefix + eventID.uuidString }
    static func isEventReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    /// 시간 없는 일정에는 알림을 붙일 수 없고, 목록에 없는 간격은 저장하지 않는다.
    static func normalizedOffset(_ minutes: Int?, hasTime: Bool) -> Int? {
        guard hasTime, let minutes, allowedOffsets.contains(minutes) else { return nil }
        return minutes
    }

    /// 편집 화면과 목록이 같은 말을 쓰도록 한 곳에만 둔다.
    static func optionTitle(_ minutes: Int?) -> String {
        switch minutes {
        case nil: "알림 없음"
        case 0: "일정 시간"
        case 60: "1시간 전"
        case let minutes?: "\(minutes)분 전"
        }
    }

    /// 알림 본문. 일정 제목은 **이 기기의 알림에만** 들어간다 —
    /// 로그·진단·서버 어디에도 남기지 않는다.
    static func body(eventTitle: String, offsetMinutes: Int) -> String {
        offsetMinutes == 0
            ? "\(eventTitle) 시작할 시간이에요."
            : "\(eventTitle) 일정이 곧 시작돼요."
    }
}

/// 알림 예약에 필요한 일정 값만 복사한 것. SwiftData 모델을 순수 함수에 넘기지 않으려고 둔다.
struct PlannerEventReminderInput: Equatable, Sendable, Identifiable {
    let id: UUID
    /// "yyyy-MM-dd". 일정의 날짜 정체성은 Date가 아니라 이 문자열이다.
    let localDate: String
    let title: String
    /// 자정 이후 분. nil이면 시간 없는 일정이라 알림을 걸 수 없다.
    let timeMinutes: Int?
    let reminderOffsetMinutes: Int?

    init(id: UUID, localDate: String, title: String, timeMinutes: Int?, reminderOffsetMinutes: Int?) {
        self.id = id
        self.localDate = localDate
        self.title = title
        self.timeMinutes = timeMinutes
        self.reminderOffsetMinutes = reminderOffsetMinutes
    }

    init(record: PlannerEventRecord) {
        self.init(
            id: record.id,
            localDate: record.localDate,
            title: record.title,
            timeMinutes: record.timeMinutes,
            reminderOffsetMinutes: record.reminderOffsetMinutes
        )
    }
}

/// 일정 → 알림. 학습 알림과 같은 모양의 순수 함수라 권한 창 없이 그대로 테스트한다.
enum PlannerEventReminderPlanner {
    static func reminders(
        events: [PlannerEventReminderInput],
        timeZone: TimeZone,
        now: Date = .now
    ) -> [LocalNotificationRequest] {
        events.compactMap { outcome(for: $0, timeZone: timeZone, now: now).request }
    }

    /// 알림이 울려야 할 절대 시각. 자정 넘김·서머타임을 직접 계산하지 않고 달력에 맡긴다.
    ///
    /// 자정에서 분을 더하는 이유가 있다. "일정 시각의 DateComponents에서 분만 빼는" 방식은
    /// 00:30 일정의 1시간 전을 `hour = -1`로 만들어 iOS가 엉뚱한 날에 울리게 한다(P7에서
    /// 같은 종류의 트리거 버그를 겪었다). 절대 시각을 먼저 구하고 거기서 성분을 뽑는다.
    static func fireDate(
        for event: PlannerEventReminderInput,
        timeZone: TimeZone
    ) -> Date? {
        guard let timeMinutes = event.timeMinutes,
              let offset = PlannerEventReminderPolicy.normalizedOffset(
                  event.reminderOffsetMinutes,
                  hasTime: true
              ),
              let midnight = LocalCalendarDate.date(from: event.localDate, timeZone: timeZone)
        else { return nil }
        return LocalCalendarDate.calendar(timeZone: timeZone).date(
            byAdding: .minute,
            value: timeMinutes - offset,
            to: midnight
        )
    }

    static func outcome(
        for event: PlannerEventReminderInput,
        timeZone: TimeZone,
        now: Date = .now
    ) -> ReminderOutcome {
        guard let offset = PlannerEventReminderPolicy.normalizedOffset(
            event.reminderOffsetMinutes,
            hasTime: event.timeMinutes != nil
        ) else {
            return .skipped(event.timeMinutes == nil ? .eventHasNoTime : .userSelectedNone)
        }
        guard let fireDate = fireDate(for: event, timeZone: timeZone) else {
            return .skipped(.eventHasNoTime)
        }
        // 이미 지난 알림은 예약하지 않는다. 지난 일정을 고쳐도 울리지 않는다.
        guard fireDate > now else { return .skipped(.triggerTimePassed) }

        var components = LocalCalendarDate.calendar(timeZone: timeZone)
            .dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.timeZone = timeZone
        return .scheduled(
            LocalNotificationRequest(
                identifier: PlannerEventReminderPolicy.identifier(eventID: event.id),
                title: PlannerEventReminderPolicy.title,
                body: PlannerEventReminderPolicy.body(
                    eventTitle: event.title,
                    offsetMinutes: offset
                ),
                dateComponents: components
            )
        )
    }
}
