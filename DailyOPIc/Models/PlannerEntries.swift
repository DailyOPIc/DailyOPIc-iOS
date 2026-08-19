import Foundation
import SwiftData

/// 사용자가 직접 적어 넣은 일정. DailyOPIc 학습 기록(`StudySetCompletionRecord`)과 절대 섞지 않는다.
/// 학습 완료는 실제 학습으로만 생기고, 이 기록은 사용자가 손으로 만든다.
///
/// 날짜 정체성은 "yyyy-MM-dd" 문자열이다. Date로 잡으면 기기 타임존이 바뀔 때
/// "8월 20일 일정"이 19일이나 21일 칸으로 넘어간다(`StudyDayPlanRecord`와 같은 이유).
/// 시각도 절대 시각이 아니라 자정 이후 분(0~1439)으로 둔다 — 벽시계 19:00은 어디서 봐도 19:00이다.
///
/// 이 기록은 이 기기에만 남는다. 서버로 보내지 않는다. 알림은 이 기기의 로컬 알림으로만
/// 걸고(P9), 제목은 그 알림 문구에만 들어간다 — 로그·진단·서버 어디에도 남기지 않는다.
@Model
final class PlannerEventRecord {
    @Attribute(.unique) var id: UUID
    var localDate: String
    var title: String
    /// 자정 이후 분. nil이면 "시간 없음" 일정이다.
    var timeMinutes: Int?
    /// 일정 시작 몇 분 전에 알릴지. nil이면 "알림 없음"이고 새 일정의 기본값이다.
    /// 옵셔널로 **추가만** 하므로 기존 저장소가 그대로 열린다(파괴적 마이그레이션 없음).
    /// 무료로 강등돼도 이 값은 지우지 않는다 — 예약만 걷고 설정은 남긴다.
    var reminderOffsetMinutes: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        localDate: String,
        title: String,
        timeMinutes: Int? = nil,
        reminderOffsetMinutes: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.localDate = localDate
        self.title = title
        self.timeMinutes = timeMinutes
        self.reminderOffsetMinutes = PlannerEventReminderPolicy.normalizedOffset(
            reminderOffsetMinutes,
            hasTime: timeMinutes != nil
        )
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 화면에 그릴 벽시계 시각. 시간 없는 일정은 nil이고, 없는 시각을 지어내지 않는다.
    var time: StudyTimeOfDay? {
        timeMinutes.map { StudyTimeOfDay(hour: $0 / 60, minute: $0 % 60) }
    }

    /// 시간이 있는 일정이 시간순으로 먼저, 시간 없는 일정이 뒤에. 같은 시각이면 만든 순서다.
    /// 정렬 규칙이 화면마다 달라지지 않도록 여기 한 곳만 둔다.
    static func sorted(_ records: [PlannerEventRecord]) -> [PlannerEventRecord] {
        records.sorted { lhs, rhs in
            switch (lhs.timeMinutes, rhs.timeMinutes) {
            case let (left?, right?):
                return left == right ? lhs.createdAt < rhs.createdAt : left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    /// 자정 이후 분으로 정규화. 범위를 벗어난 값은 저장하지 않는다(= 시간 없음).
    static func normalizedTimeMinutes(_ minutes: Int?) -> Int? {
        guard let minutes, (0..<(24 * 60)).contains(minutes) else { return nil }
        return minutes
    }
}

/// 날짜당 하나뿐인 개인 메모. 일정과 달리 여러 개를 두지 않는다.
/// 평문만 담고, 서버로 보내지 않으며, AI가 읽지도 않는다.
@Model
final class PlannerDayNoteRecord {
    @Attribute(.unique) var localDate: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(
        localDate: String,
        text: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.localDate = localDate
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 하루 상세가 보여줄 학습 상태. 캘린더 격자와 같은 판정(`StudyCalendarEngine.state`)을
/// 옮겨 적기만 한다 — 두 번째 계산 경로를 만들면 지난 날짜가 화면마다 다른 말을 하게 된다.
enum PlannerDayStudyStatus: String, Sendable, CaseIterable {
    case completed
    case partial
    case missed
    case scheduled
    case rest
    case unplanned

    /// - Parameter isStudyWeekday: 그 요일이 공부 요일로 선택돼 있는지.
    ///   배정이 없는 날을 "휴식일"과 "계획 없음"으로 가르는 유일한 기준이다.
    static func make(day: StudyDay, isStudyWeekday: Bool) -> PlannerDayStudyStatus {
        switch day.state {
        case .completed: .completed
        case .partial: .partial
        case .missed: .missed
        // 미래·오늘의 미완료는 "놓침"이 아니라 예정이다(엔진이 이미 구분한다).
        case .planned: .scheduled
        // 배정이 0인 공부 요일 = 계획이 끝났거나 아직 계획에 들어오지 않은 날.
        case .rest: isStudyWeekday ? .unplanned : .rest
        }
    }

    /// 부족한 날도 사실만 말한다. 자책하게 만드는 표현은 쓰지 않는다.
    var title: String {
        switch self {
        case .completed: "학습 완료"
        case .partial: "일부 학습"
        case .missed: "아직 학습 기록이 없어요"
        case .scheduled: "학습 예정"
        case .rest: "휴식일"
        case .unplanned: "계획 없음"
        }
    }

    /// 색만으로 상태를 구분하지 않도록 기호를 함께 쓴다.
    var symbolName: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missed: "circle"
        case .scheduled: "circle.dotted"
        case .rest: "moon.zzz"
        case .unplanned: "minus.circle"
        }
    }
}
