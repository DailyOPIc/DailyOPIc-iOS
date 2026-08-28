import Foundation
import SwiftData

@Model
final class PracticeHistoryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var targetLevelRaw: String
    var predictedLevelRaw: String
    var questionData: Data
    var transcript: String
    var evaluationData: Data

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        targetLevel: OPIcLevel,
        question: GeneratedQuestion,
        transcript: String,
        evaluation: PracticeEvaluation
    ) throws {
        self.id = id
        self.createdAt = createdAt
        self.targetLevelRaw = targetLevel.rawValue
        self.predictedLevelRaw = evaluation.predictedLevel.rawValue
        self.questionData = try JSONCoding.encoder.encode(question)
        self.transcript = transcript
        self.evaluationData = try JSONCoding.encoder.encode(evaluation)
    }

    var targetLevel: OPIcLevel { OPIcLevel(rawValue: targetLevelRaw) ?? .IM2 }
    var predictedLevel: OPIcLevel { OPIcLevel(rawValue: predictedLevelRaw) ?? .NL }
    var question: GeneratedQuestion? { try? JSONCoding.decoder.decode(GeneratedQuestion.self, from: questionData) }
    var evaluation: PracticeEvaluation? { try? JSONCoding.decoder.decode(PracticeEvaluation.self, from: evaluationData) }
}

@Model
final class MockHistoryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var targetLevelRaw: String
    var predictedLevelRaw: String
    var questionSetData: Data
    var answersData: Data
    var evaluationData: Data

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        targetLevel: OPIcLevel,
        questionSet: QuestionSet,
        answers: [RecordedAnswer],
        evaluation: MockEvaluation
    ) throws {
        self.id = id
        self.createdAt = createdAt
        self.targetLevelRaw = targetLevel.rawValue
        self.predictedLevelRaw = evaluation.predictedLevel.rawValue
        self.questionSetData = try JSONCoding.encoder.encode(questionSet)
        self.answersData = try JSONCoding.encoder.encode(answers)
        self.evaluationData = try JSONCoding.encoder.encode(evaluation)
    }

    var targetLevel: OPIcLevel { OPIcLevel(rawValue: targetLevelRaw) ?? .IM2 }
    var predictedLevel: OPIcLevel { OPIcLevel(rawValue: predictedLevelRaw) ?? .NL }
    var questionSet: QuestionSet? { try? JSONCoding.decoder.decode(QuestionSet.self, from: questionSetData) }
    var answers: [RecordedAnswer] { (try? JSONCoding.decoder.decode([RecordedAnswer].self, from: answersData)) ?? [] }
    var evaluation: MockEvaluation? { try? JSONCoding.decoder.decode(MockEvaluation.self, from: evaluationData) }
}

/// 캘린더 완료 집계의 원장. 세트를 받는 것(토큰 소모)만으로는 기록되지 않고,
/// 그 세트에서 AI 분석이 처음 성공했을 때 한 줄만 남는다.
/// setId가 유일 키라 재시도·결과 재진입·같은 세트 재분석이 중복으로 세지 않는다.
/// dailyUsage(서버 토큰 사용량)와 목적이 달라 따로 둔다.
@Model
final class StudySetCompletionRecord {
    @Attribute(.unique) var setId: String
    var completedAt: Date

    init(setId: String, completedAt: Date = .now) {
        self.setId = setId
        self.completedAt = completedAt
    }
}

/// 그날 어떤 문제를 학습했는지만 남기는 **가벼운 사본**(P11.1).
///
/// 왜 따로 두나: 풍부한 분석 기록(`PracticeHistoryRecord`)은 최근 50개만 남는데
/// 플래너의 학습 이력은 366일이다. 50개를 넘긴 순간 "3회 학습"만 남고 무슨 문제를
/// 풀었는지가 사라진다. 그렇다고 답변·전사·평가까지 1년을 들고 있을 이유는 없다 —
/// 그래서 **문제 문장과 시각만** 떼어 플래너 이력과 같은 기간 보관한다.
///
/// 여기 없는 것: 전사 · 답변 · 오디오 · 평가 · 점수 · 예상 등급 · 사용자 식별자 · 토큰/결제 정보.
/// 표시 전용이다 — 히트맵·연속 학습·토큰 집계는 여전히 `StudySetCompletionRecord`만 본다.
@Model
final class PlannerLearnedQuestionRecord {
    /// 원본 분석 기록의 ID. 유니크라 같은 학습이 두 줄이 되지 않고,
    /// 백필을 몇 번 돌려도 결과가 같다.
    @Attribute(.unique) var sourcePracticeHistoryID: UUID
    var learnedAt: Date
    /// 사용자가 실제로 본 문제 문장 그대로. 나중에 다시 만들어 내지 않는다.
    var prompt: String
    var kindLabel: String

    init(sourcePracticeHistoryID: UUID, learnedAt: Date, prompt: String, kindLabel: String) {
        self.sourcePracticeHistoryID = sourcePracticeHistoryID
        self.learnedAt = learnedAt
        self.prompt = prompt
        self.kindLabel = kindLabel
    }
}

extension PlannerLearnedQuestionRecord {
    /// 분석 기록 하나에서 뜨는 사본 하나. 문제 문장을 못 읽으면 만들지 않는다.
    convenience init?(record: PracticeHistoryRecord) {
        guard let question = record.question else { return nil }
        self.init(
            sourcePracticeHistoryID: record.id,
            learnedAt: record.createdAt,
            prompt: question.prompt,
            // 문제 카드가 사용자에게 보여 준 분류와 같은 식이다.
            kindLabel: question.questionStyle?.label ?? question.examSection.label
        )
    }
}

/// 그날 실제로 배정됐던 학습량. 지난 날의 상태(완료/일부 완료/놓침)를 나중 설정으로
/// 다시 계산하지 않기 위해 필요하다. 강도를 꾸준히→집중으로 바꿔도 어제의 "1 / 1 완료"가
/// "1 / 3 일부 완료"로 바뀌면 안 된다.
///
/// 키는 학습 계획 타임존 기준 "yyyy-MM-dd"다. Date로 잡으면 기기 타임존이 바뀔 때
/// 같은 날이 두 칸으로 갈라진다. 문자열이라 정렬·비교도 사전순 그대로 통한다.
/// 휴식일은 아예 기록하지 않는다(레코드 없음 = 그날 배정된 학습 없음).
/// 완료 수는 여기 복제하지 않는다 — 그건 `StudySetCompletionRecord`의 몫이다.
@Model
final class StudyDayPlanRecord {
    @Attribute(.unique) var localDate: String
    var targetSets: Int
    var createdAt: Date

    init(localDate: String, targetSets: Int, createdAt: Date = .now) {
        self.localDate = localDate
        self.targetSets = targetSets
        self.createdAt = createdAt
    }
}

@Model
final class MockDraftRecord {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var targetLevelRaw: String
    var questionSetData: Data
    var answersData: Data

    init(
        id: UUID = UUID(),
        updatedAt: Date = .now,
        targetLevel: OPIcLevel,
        questionSet: QuestionSet,
        answers: [RecordedAnswer]
    ) throws {
        self.id = id
        self.updatedAt = updatedAt
        self.targetLevelRaw = targetLevel.rawValue
        self.questionSetData = try JSONCoding.encoder.encode(questionSet)
        self.answersData = try JSONCoding.encoder.encode(answers)
    }

    var targetLevel: OPIcLevel { OPIcLevel(rawValue: targetLevelRaw) ?? .IM2 }
    var questionSet: QuestionSet? { try? JSONCoding.decoder.decode(QuestionSet.self, from: questionSetData) }
    var answers: [RecordedAnswer] { (try? JSONCoding.decoder.decode([RecordedAnswer].self, from: answersData)) ?? [] }
}

/// 단어장 항목 하나에 대한 **내 상태**(P14). 항목 내용은 번들 시드가 진실이고,
/// 여기에는 그 항목을 내가 어떻게 다뤘는지만 남는다 — 저장했는지, 몇 번 맞히고
/// 틀렸는지, 언제 다시 볼지.
///
/// 여기 없는 것: 단어 뜻·예문(시드에 있다) · 사용자 식별자 · 토큰/결제 정보.
/// 이 기기에만 저장되고 서버로 보내지 않는다.
///
/// 상태 기록이 아예 없는 항목은 `.new`이고 저장하지 않은 항목이다 — 128개 시드에
/// 대해 빈 레코드를 미리 만들어 두지 않는다.
@Model
final class VocabularyStateRecord {
    /// 시드 항목의 id. 유니크라 같은 단어가 두 줄이 되지 않는다.
    @Attribute(.unique) var entryID: String
    var statusRaw: String
    /// 학습 상태와 무관하다. 익혔다고 저장되지 않고, 저장을 풀어도 학습 기록은 남는다.
    var isSaved: Bool
    /// **연속** 성공 횟수. 복습 간격을 정하는 값이라 "몰라요" 한 번에 0으로 돌아간다.
    /// 누적 성공 횟수가 아니다.
    var consecutiveSuccessCount: Int
    /// 누적 오답 횟수. 이쪽은 초기화하지 않는다.
    var failureCount: Int
    /// 마지막으로 답한 날("yyyy-MM-dd", 학습 계획 타임존). 오늘 진행도의 근거다 —
    /// 시각이 아니라 날짜로 들고 있어야 "오늘 봤는가"가 타임존과 무관하게 같은 답을 준다.
    var lastStudiedLocalDate: String?
    /// 다음 복습 날짜("yyyy-MM-dd"). 아직 학습 전이면 없다.
    var nextReviewLocalDate: String?
    var updatedAt: Date

    init(
        entryID: String,
        status: VocabularyStatus = .new,
        isSaved: Bool = false,
        consecutiveSuccessCount: Int = 0,
        failureCount: Int = 0,
        lastStudiedLocalDate: String? = nil,
        nextReviewLocalDate: String? = nil,
        updatedAt: Date = .now
    ) {
        self.entryID = entryID
        self.statusRaw = status.rawValue
        self.isSaved = isSaved
        self.consecutiveSuccessCount = consecutiveSuccessCount
        self.failureCount = failureCount
        self.lastStudiedLocalDate = lastStudiedLocalDate
        self.nextReviewLocalDate = nextReviewLocalDate
        self.updatedAt = updatedAt
    }

    var status: VocabularyStatus { VocabularyStatus(rawValue: statusRaw) ?? .new }

    /// 한 번이라도 학습한 항목인가. 오늘의 **새** 단어 후보에서 빼는 기준이다 —
    /// 저장만 해 둔 항목(`.new`)은 아직 새 단어다.
    var hasBeenStudied: Bool { status != .new }

    /// 오늘 복습할 차례인가. 예정일이 오늘이거나 지났으면 차례다.
    /// 익힘(mastered)도 30일마다 돌아오므로 여기서 빠지지 않는다.
    /// "yyyy-MM-dd"는 사전순 비교가 곧 날짜순 비교다.
    func isDueForReview(on today: String) -> Bool {
        guard let nextReviewLocalDate else { return false }
        return nextReviewLocalDate <= today
    }

    /// 오늘 이미 답했는가. 같은 세션에서 다시 만나도 이 값은 한 번만 오늘로 바뀐다.
    func wasStudied(on today: String) -> Bool { lastStudiedLocalDate == today }
}

