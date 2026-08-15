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

    /// 캘린더 완료 기록. 같은 세트는 몇 번 분석하든 한 번만 센다.
    /// - Returns: 이번 호출로 새로 기록됐으면 true.
    @discardableResult
    func recordStudySetCompletion(setId: String, at date: Date = .now) throws -> Bool {
        guard let context, !setId.isEmpty else { return false }
        var descriptor = FetchDescriptor<StudySetCompletionRecord>(
            predicate: #Predicate { $0.setId == setId }
        )
        descriptor.fetchLimit = 1
        if try context.fetch(descriptor).first != nil { return false }
        context.insert(StudySetCompletionRecord(setId: setId, completedAt: date))
        try trimStudyCompletions(context: context, now: date)
        try context.save()
        return true
    }

    /// 1년치만 남긴다. 캘린더는 그보다 과거를 보여주지 않는다.
    private func trimStudyCompletions(context: ModelContext, now: Date) throws {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: now) else {
            return
        }
        try context.delete(
            model: StudySetCompletionRecord.self,
            where: #Predicate { $0.completedAt < cutoff }
        )
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
