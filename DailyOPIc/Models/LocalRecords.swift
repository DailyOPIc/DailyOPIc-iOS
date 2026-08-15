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
