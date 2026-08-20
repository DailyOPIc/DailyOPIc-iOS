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

/// 하루 시트의 "학습한 문제" 한 줄(P11 · 저장소 P11.1).
///
/// 재료는 가벼운 사본 `PlannerLearnedQuestionRecord` 하나다 —
/// 답변·전사·오디오·점수·피드백은 담지 않는다.
/// 문제 문구는 사용자가 문제 카드에서 본 그 문장(`GeneratedQuestion.prompt`)을 그대로 쓴다.
/// 나중에 주제나 ID로 다시 만들어 내지 않는다 — 서버의 문제 내용은 바뀔 수 있고,
/// 지난 학습을 보려고 네트워크를 켜야 할 이유도 없다.
struct LearnedQuestion: Identifiable, Hashable, Sendable {
    /// 원본 분석 기록의 ID. 줄의 정체성이자 중복 방지 키이고,
    /// 화면에도 접근성에도 노출하지 않는다.
    let id: UUID
    /// 정렬용 실제 시각. 화면에는 분까지만 쓴다.
    let learnedAt: Date
    /// 학습 계획 타임존 기준 자정 이후 분(0~1439).
    let minuteOfDay: Int
    let prompt: String
    /// 문제 카드에서 봤던 것과 같은 분류("롤플레이" · "돌발 주제"…).
    let kindLabel: String

    /// "19:12". 로케일 포매터를 쓰지 않는 이유는 하루 시트의 날짜·요일과 같다 —
    /// 기기 설정이 아니라 학습 계획 타임존이 진실이다.
    var timeText: String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    /// "19시 12분, 집에서 보내는 휴일에 대해 말해주세요." 내부 ID는 읽지 않는다.
    var accessibilityText: String {
        "\(minuteOfDay / 60)시 \(minuteOfDay % 60)분, \(prompt)"
    }

    /// 그날의 학습 흐름을 재구성한다 — **오래된 것이 먼저**다.
    ///
    /// 중복은 여기서 걸러내지 않는다. 원본 기록 ID가 저장소에서 유니크라 같은 학습이
    /// 두 줄이 될 수 없고, 반대로 **같은 분에 같은 문제를 두 번 성공한 것은 진짜 두 번**이라
    /// 접으면 사실을 지우게 된다(P11.1에서 (분+문장) 추정을 걷어냈다).
    /// 시각이 같으면 ID로 순서를 고정해 다시 그릴 때마다 줄이 뒤바뀌지 않게 한다.
    static func timeline(_ items: [LearnedQuestion]) -> [LearnedQuestion] {
        items.sorted {
            $0.learnedAt == $1.learnedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.learnedAt < $1.learnedAt
        }
    }
}

extension LearnedQuestion {
    /// 사본 한 줄을 화면 값으로. 시각만 학습 계획 타임존의 벽시계로 바꾼다.
    init(record: PlannerLearnedQuestionRecord, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: record.learnedAt)
        id = record.sourcePracticeHistoryID
        learnedAt = record.learnedAt
        minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        prompt = record.prompt
        kindLabel = record.kindLabel
    }
}

/// "학습한 문제" 칸이 지금 무엇을 말해야 하는지(P11).
///
/// 세 갈래뿐이라 뷰가 조건을 다시 조립하지 않는다. 특히 "학습은 있었는데 문제가 없다"와
/// "그날 학습 자체가 없다"를 섞지 않는 것이 요점이다 — 전자만 설명이 필요하다.
enum LearnedQuestionSection: Equatable, Sendable {
    /// 아직 읽는 중이거나, 그날 학습 자체가 없었다. 칸을 아예 그리지 않는다.
    case hidden
    case questions([LearnedQuestion])
    /// 학습한 것은 분명한데 문제 내용이 남아 있지 않다. 문제를 지어내지 않고 그대로 말한다.
    case unavailable

    static let title = "학습한 문제"
    static let unavailableTitle = "이전 학습 기록"
    /// 원인을 특정하지 않는다 — 구버전 학습일 수도, 보관 한도를 넘겼을 수도,
    /// 사용자가 기록을 지웠을 수도 있다. 셋 다 사실은 하나다: 남아 있지 않다.
    static let unavailableDetail = "이 날의 학습 기록은 남아 있지만, 문제 내용은 저장돼 있지 않아요."

    /// - Parameters:
    ///   - questions: nil이면 아직 읽기 전이다. 빈 배열("없다")과 구분해야
    ///     시트가 열리는 순간 설명 문구가 깜빡이지 않는다.
    ///   - completedSets: 그날의 실제 완료 세트 수. 히트맵·연속 학습과 **같은** 값이다.
    static func make(questions: [LearnedQuestion]?, completedSets: Int) -> LearnedQuestionSection {
        guard let questions else { return .hidden }
        if !questions.isEmpty { return .questions(LearnedQuestion.timeline(questions)) }
        return completedSets > 0 ? .unavailable : .hidden
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

    /// 하루 시트가 읽어 줄 학습 한 줄. 배정이 있던 날은 분모를 그대로 쓰고,
    /// 배정이 없던 날에 가짜 분모("1 / 0세트")를 만들지 않는다.
    /// 재료는 격자와 같은 `StudyDay` 하나뿐이다 — 두 번째 계산 경로를 만들지 않는다.
    func summaryText(day: StudyDay, isToday: Bool) -> String {
        let prefix = isToday ? "오늘 " : ""
        switch self {
        case .completed, .partial:
            return "\(prefix)\(day.completedSets) / \(day.targetSets)세트 학습"
        case .scheduled:
            return "학습 예정 · \(day.targetSets)세트"
        case .missed:
            return "학습 기록 없음 · 계획 \(day.targetSets)세트"
        case .rest:
            return day.completedSets > 0
                ? "휴식일 · \(day.completedSets)회 학습"
                : "휴식일 / 학습 기록 없음"
        case .unplanned:
            return day.completedSets > 0 ? "\(prefix)\(day.completedSets)회 학습" : "학습 기록 없음"
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
