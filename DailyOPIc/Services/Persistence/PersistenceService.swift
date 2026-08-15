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

    /// 캘린더 화면 밖(알림 예약 등)에서도 완료 기록을 읽어야 한다. 화면의 @Query와 같은 기록이다.
    func studySetCompletionDates() throws -> [Date] {
        guard let context else { return [] }
        return try context.fetch(FetchDescriptor<StudySetCompletionRecord>()).map(\.completedAt)
    }

    /// 가장 최근 분석 기록 하나. 최근 등급을 "언제 기록됐는지"와 함께 판단해야 해서 날짜도 준다.
    func latestPracticeRecord() throws -> PracticeHistoryRecord? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<PracticeHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func studyDayPlans() throws -> [StudyDayPlanRecord] {
        guard let context else { return [] }
        return try context.fetch(FetchDescriptor<StudyDayPlanRecord>())
    }

    /// 배정된 학습량을 날짜별로 고정한다.
    /// 지난 날짜는 이미 기록이 있으면 절대 덮어쓰지 않는다 — 그게 이 저장소의 존재 이유다.
    /// 오늘만 아직 확정 전이라 현재 설정에 맞춰 갱신한다.
    ///
    /// - Parameters:
    ///   - targets: "yyyy-MM-dd" → 그날 배정 학습량. 휴식일은 넣지 않는다.
    ///   - today: 오늘의 "yyyy-MM-dd"(학습 계획 타임존 기준).
    func freezeStudyDayPlans(_ targets: [String: Int], today: String) throws {
        guard let context, !targets.isEmpty else { return }
        let existing = Dictionary(
            try studyDayPlans().map { ($0.localDate, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false
        for (localDate, targetSets) in targets where targetSets > 0 {
            if let record = existing[localDate] {
                // 지난 날은 그대로 둔다. 오늘은 설정이 바뀌었으면 따라간다.
                guard localDate == today, record.targetSets != targetSets else { continue }
                record.targetSets = targetSets
            } else {
                context.insert(StudyDayPlanRecord(localDate: localDate, targetSets: targetSets))
            }
            changed = true
        }
        guard changed else { return }
        try trimStudyDayPlans(context: context, today: today)
        try context.save()
    }

    /// "yyyy-MM-dd"는 사전순 비교가 곧 날짜순 비교라 문자열 하나로 잘라낼 수 있다.
    private func trimStudyDayPlans(context: ModelContext, today: String) throws {
        let parts = today.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        let cutoff = String(format: "%04d-%02d-%02d", parts[0] - 1, parts[1], parts[2])
        try context.delete(
            model: StudyDayPlanRecord.self,
            where: #Predicate { $0.localDate < cutoff }
        )
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
