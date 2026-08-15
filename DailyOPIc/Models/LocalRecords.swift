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
