import Foundation
import SwiftData

/// 하루치 단어 학습량(P14.5.2). **추가만 하는 모델**이라 기존 데이터를 건드리지 않는다.
///
/// 왜 따로 필요한가: 항목별 상태(`VocabularyStateRecord`)는 **마지막으로** 답한 날짜
/// 하나만 들고 있다. 그래서 "어제 몇 개 했는가"는 기존 데이터로 되살릴 수 없다 —
/// 어제 학습한 단어를 오늘 복습하면 그 항목의 날짜는 오늘로 덮인다.
/// 캘린더에 날짜별 단어 수를 그리려면 그날 그날의 숫자를 남기는 수밖에 없다.
///
/// 여기 없는 것: 단어 내용 · 정답 여부 · 사용자 식별자. 날짜와 숫자 둘뿐이고
/// 이 기기에만 저장된다. 하루 한 줄이라 1년에 365줄을 넘지 않는다.
@Model
final class StudyActivityDailyRecord {
    /// 학습 계획 타임존 기준 "yyyy-MM-dd". 유니크라 같은 날이 두 줄이 되지 않는다.
    @Attribute(.unique) var localDate: String
    /// 그날 **처음 다룬** 단어 수. 같은 단어를 같은 날 여러 번 답해도 한 번만 센다.
    var vocabularyStudiedCount: Int
    /// 그날 오늘의 단어로 배정됐던 개수. 완료 배지("둘 다 완료")의 분모다.
    /// 배정 기록이 없던 날(이 기능 이전)은 0이고, 그런 날은 완료로 치지 않는다.
    var vocabularyGoalCount: Int
    var updatedAt: Date

    init(
        localDate: String,
        vocabularyStudiedCount: Int = 0,
        vocabularyGoalCount: Int = 0,
        updatedAt: Date = .now
    ) {
        self.localDate = localDate
        self.vocabularyStudiedCount = vocabularyStudiedCount
        self.vocabularyGoalCount = vocabularyGoalCount
        self.updatedAt = updatedAt
    }
}

/// 캘린더 한 칸이 말할 **실제로 한 학습**. 계획도 목표도 아니다.
///
/// 세 숫자의 출처가 서로 다르다는 점이 중요하다 — 어느 것도 화면에서 추정하지 않는다.
/// - 단어: `StudyActivityDailyRecord`(그날 처음 다룬 항목 수)
/// - 데일리: `PlannerLearnedQuestionRecord`(분석이 성공한 문제 하나당 한 줄)
/// - 모의고사: `MockHistoryRecord`(채점까지 끝난 응시 하나당 한 줄)
struct PlannerDayActivity: Equatable, Sendable {
    var vocabularyStudied = 0
    var vocabularyGoal = 0
    var dailyAnswers = 0
    var mockExams = 0

    static let empty = PlannerDayActivity()

    var isEmpty: Bool { self == .empty }

    /// 그날 배정된 오늘의 단어를 다 했는가. 배정 기록이 없으면 판단하지 않는다 —
    /// 숫자만 있고 분모가 없는 날을 "완료"로 부풀리지 않는다.
    var isVocabularyComplete: Bool {
        vocabularyGoal > 0 && vocabularyStudied >= vocabularyGoal
    }
}

/// 날짜별 활동을 모으는 곳. 뷰가 세 종류의 기록을 각각 세지 않도록 한 번에 만든다.
/// 순수 함수라 화면 없이 그대로 검증된다.
enum PlannerActivityCalendar {
    /// - Parameters:
    ///   - vocabulary: 하루 한 줄인 단어 학습량 기록.
    ///   - dailyAnsweredAt: 분석이 성공한 데일리 문제의 시각(문제 하나당 하나).
    ///   - mockCompletedAt: 채점까지 끝난 모의고사의 시각(응시 하나당 하나).
    static func activities(
        vocabulary: [StudyActivityDailyRecord],
        dailyAnsweredAt: [Date],
        mockCompletedAt: [Date],
        timeZone: TimeZone
    ) -> [String: PlannerDayActivity] {
        var result: [String: PlannerDayActivity] = [:]
        for record in vocabulary {
            result[record.localDate, default: .empty].vocabularyStudied = record.vocabularyStudiedCount
            result[record.localDate, default: .empty].vocabularyGoal = record.vocabularyGoalCount
        }
        for date in dailyAnsweredAt {
            result[LocalCalendarDate.text(from: date, timeZone: timeZone), default: .empty]
                .dailyAnswers += 1
        }
        for date in mockCompletedAt {
            result[LocalCalendarDate.text(from: date, timeZone: timeZone), default: .empty]
                .mockExams += 1
        }
        return result
    }

    /// 캘린더 칸에 찍을 배지. 칸이 작으므로 실제로 한 것만, 최대 세 개다.
    /// 순서는 늘 같다(단어 → 데일리 → 모의) — 날마다 순서가 바뀌면 눈이 다시 읽어야 한다.
    static func badges(_ activity: PlannerDayActivity) -> [(symbol: String, count: Int, label: String)] {
        var badges: [(String, Int, String)] = []
        if activity.vocabularyStudied > 0 {
            badges.append(("book.closed.fill", activity.vocabularyStudied, "단어"))
        }
        if activity.dailyAnswers > 0 {
            badges.append(("mic.fill", activity.dailyAnswers, "데일리"))
        }
        if activity.mockExams > 0 {
            badges.append(("list.number", activity.mockExams, "모의"))
        }
        return badges
    }

    /// 한 문장으로 읽어 주는 활동. 배지 색·아이콘이 아니라 한 일을 그대로 말한다.
    static func accessibilityText(_ activity: PlannerDayActivity) -> String? {
        let parts = badges(activity).map { "\($0.label) \($0.count)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
