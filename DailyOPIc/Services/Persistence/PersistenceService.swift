import Foundation
import SwiftData

@MainActor
final class PersistenceService {
    private var context: ModelContext?

    func configure(context: ModelContext) {
        self.context = context
    }

    func savePractice(
        targetLevel: OPIcLevel,
        question: GeneratedQuestion,
        transcript: String,
        evaluation: PracticeEvaluation
    ) throws {
        guard let context else { return }
        context.insert(
            try PracticeHistoryRecord(
                targetLevel: targetLevel,
                question: question,
                transcript: transcript,
                evaluation: evaluation
            )
        )
        try trimPracticeHistory(context: context)
        try context.save()
    }

    func saveMock(
        targetLevel: OPIcLevel,
        questionSet: QuestionSet,
        answers: [RecordedAnswer],
        evaluation: MockEvaluation
    ) throws {
        guard let context else { return }
        context.insert(
            try MockHistoryRecord(
                targetLevel: targetLevel,
                questionSet: questionSet,
                answers: answers,
                evaluation: evaluation
            )
        )
        try clearDraft()
        try context.save()
    }

    func saveDraft(
        targetLevel: OPIcLevel,
        questionSet: QuestionSet,
        answers: [RecordedAnswer]
    ) throws {
        guard let context else { return }
        var descriptor = FetchDescriptor<MockDraftRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let draft = try context.fetch(descriptor).first {
            draft.updatedAt = .now
            draft.targetLevelRaw = targetLevel.rawValue
            draft.questionSetData = try JSONCoding.encoder.encode(questionSet)
            draft.answersData = try JSONCoding.encoder.encode(answers)
        } else {
            context.insert(
                try MockDraftRecord(
                    targetLevel: targetLevel,
                    questionSet: questionSet,
                    answers: answers
                )
            )
        }
        try context.save()
    }

    func latestDraft() throws -> MockDraftRecord? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<MockDraftRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func clearDraft() throws {
        guard let context else { return }
        try context.delete(model: MockDraftRecord.self)
        try context.save()
    }

    private func trimPracticeHistory(context: ModelContext) throws {
        let descriptor = FetchDescriptor<PracticeHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        for item in records.dropFirst(50) {
            context.delete(item)
        }
    }
}
