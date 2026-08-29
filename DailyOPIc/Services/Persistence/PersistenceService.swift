import Foundation
import SwiftData

@MainActor
final class PersistenceService {
    private var context: ModelContext?

    func configure(context: ModelContext) {
        self.context = context
    }

    /// 컨텍스트가 붙기 전에는 조회가 전부 빈 값이다. 그 빈 값을 "기록이 없다"로
    /// 읽으면 안 되는 곳(알림 재조정)이 있어서 준비 여부를 밖에서 볼 수 있게 둔다.
    var isReady: Bool { context != nil }

    func savePractice(
        targetLevel: OPIcLevel,
        question: GeneratedQuestion,
        transcript: String,
        evaluation: PracticeEvaluation
    ) throws {
        guard let context else { return }
        let record = try PracticeHistoryRecord(
            targetLevel: targetLevel,
            question: question,
            transcript: transcript,
            evaluation: evaluation
        )
        context.insert(record)
        // 플래너용 가벼운 사본(P11.1)을 **같은 저장**에 함께 넣는다. 분석 성공 말고
        // 사본이 생기는 경로는 없다 — 실패·중도 이탈·모의고사는 여기 오지 못한다.
        if let learned = PlannerLearnedQuestionRecord(record: record) {
            context.insert(learned)
        }
        try trimPracticeHistory(context: context)
        try trimLearnedQuestions(context: context, now: record.createdAt)
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

    /// 그날 학습한 문제(P11 · 저장소 P11.1). 재료는 가벼운 사본
    /// `PlannerLearnedQuestionRecord`다 — 문제 제목을 보여주자고 전사·평가 덩어리를
    /// 읽지 않는다.
    ///
    /// 날짜 경계는 **학습 계획 타임존**이다 — 히트맵이 완료 기록을 세는 변환과 같아서
    /// 칸의 "3회 학습"과 시트의 문제 목록이 서로 다른 날을 가리킬 수 없다.
    /// 하루치만 읽는다. 캘린더 칸마다 부르는 곳은 없고, 시트가 열릴 때 한 번 부른다.
    func learnedQuestions(on localDate: String, timeZone: TimeZone) throws -> [LearnedQuestion] {
        guard let context else { return [] }
        let calendar = LocalCalendarDate.calendar(timeZone: timeZone)
        guard let start = LocalCalendarDate.date(from: localDate, timeZone: timeZone),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return [] }
        let records = try context.fetch(
            FetchDescriptor<PlannerLearnedQuestionRecord>(
                predicate: #Predicate { $0.learnedAt >= start && $0.learnedAt < end },
                sortBy: [SortDescriptor(\.learnedAt)]
            )
        )
        return LearnedQuestion.timeline(
            records.map { LearnedQuestion(record: $0, calendar: calendar) }
        )
    }

    /// 이 빌드를 처음 연 사용자에게도 남아 있는 분석 기록(최대 50개)의 문제 문장을
    /// 사본으로 옮긴다. 로컬 전용 · 네트워크 없음 · 없는 과거를 지어내지 않는다.
    /// 원본 ID가 유니크라 몇 번을 돌려도 결과가 같다.
    /// - Returns: 이번에 새로 만든 사본 수.
    @discardableResult
    func backfillLearnedQuestions(now: Date = .now) throws -> Int {
        guard let context else { return 0 }
        let existing = Set(
            try context.fetch(FetchDescriptor<PlannerLearnedQuestionRecord>())
                .map(\.sourcePracticeHistoryID)
        )
        var inserted = 0
        for record in try context.fetch(FetchDescriptor<PracticeHistoryRecord>())
        where !existing.contains(record.id) {
            guard let learned = PlannerLearnedQuestionRecord(record: record) else { continue }
            context.insert(learned)
            inserted += 1
        }
        try trimLearnedQuestions(context: context, now: now)
        guard inserted > 0 else { return 0 }
        try context.save()
        return inserted
    }

    /// 기록 탭의 "전체 삭제". 문제 사본도 함께 지운다 — 사용자가 지운 문제 문장이
    /// 플래너에 몰래 남아 있으면 안 된다. 완료 기록(달력의 학습량)은 기존 정책대로
    /// 그대로 두고, 그날 시트는 "문제 내용은 저장돼 있지 않아요"로 돌아간다.
    func deleteAllHistory() throws {
        guard let context else { return }
        try context.delete(model: PracticeHistoryRecord.self)
        try context.delete(model: MockHistoryRecord.self)
        try context.delete(model: MockDraftRecord.self)
        try context.delete(model: PlannerLearnedQuestionRecord.self)
        try context.save()
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
    ///   - targets: "yyyy-MM-dd" → 그날 배정 학습량. **휴식일은 0으로 넣는다**(P8.1) —
    ///     비워 두면 "기록 없음"이 되어 나중에 공부 요일을 바꿨을 때 그날이 현재 설정으로
    ///     되살아난다. 0도 그날의 계획이다.
    ///   - today: 오늘의 "yyyy-MM-dd"(학습 계획 타임존 기준).
    func freezeStudyDayPlans(_ targets: [String: Int], today: String) throws {
        guard let context, !targets.isEmpty else { return }
        let existing = Dictionary(
            try studyDayPlans().map { ($0.localDate, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false
        for (localDate, targetSets) in targets {
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

    // MARK: 플래너 개인 일정 (이 기기에만 저장)

    /// 그날의 개인 일정. 정렬 규칙은 모델 한 곳에만 둔다.
    func plannerEvents(on localDate: String) throws -> [PlannerEventRecord] {
        guard let context else { return [] }
        let events = try context.fetch(
            FetchDescriptor<PlannerEventRecord>(
                predicate: #Predicate { $0.localDate == localDate }
            )
        )
        return PlannerEventRecord.sorted(events)
    }

    /// 일정 추가·수정 한 경로. `id`가 있으면 수정, 없으면 추가다.
    /// 제목은 공백을 털어 저장하고, 빈 제목은 저장하지 않는다.
    /// 시간을 지우면 알림도 같이 지워진다 — 시각 없는 일정에는 걸 곳이 없다.
    /// - Returns: 저장했으면 true.
    @discardableResult
    func savePlannerEvent(
        id: UUID? = nil,
        localDate: String,
        title: String,
        timeMinutes: Int? = nil,
        reminderOffsetMinutes: Int? = nil
    ) throws -> Bool {
        guard let context else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !localDate.isEmpty else { return false }
        let minutes = PlannerEventRecord.normalizedTimeMinutes(timeMinutes)
        let offset = PlannerEventReminderPolicy.normalizedOffset(
            reminderOffsetMinutes,
            hasTime: minutes != nil
        )
        if let id, let existing = try plannerEvent(id: id, context: context) {
            existing.localDate = localDate
            existing.title = trimmed
            existing.timeMinutes = minutes
            existing.reminderOffsetMinutes = offset
            existing.updatedAt = .now
        } else {
            context.insert(
                PlannerEventRecord(
                    id: id ?? UUID(),
                    localDate: localDate,
                    title: trimmed,
                    timeMinutes: minutes,
                    reminderOffsetMinutes: offset
                )
            )
        }
        try context.save()
        return true
    }

    /// 알림을 켜 둔 일정 전부. 플래너 화면이 열려 있지 않아도 재조정이 돌아야 해서
    /// @Query가 아니라 여기서 직접 읽는다(같은 기록이다).
    func plannerEventReminderInputs() throws -> [PlannerEventReminderInput] {
        guard let context else { return [] }
        return try context.fetch(FetchDescriptor<PlannerEventRecord>())
            .filter { $0.reminderOffsetMinutes != nil }
            .map(PlannerEventReminderInput.init(record:))
    }

    func deletePlannerEvent(id: UUID) throws {
        guard let context, let record = try plannerEvent(id: id, context: context) else { return }
        context.delete(record)
        try context.save()
    }

    private func plannerEvent(id: UUID, context: ModelContext) throws -> PlannerEventRecord? {
        var descriptor = FetchDescriptor<PlannerEventRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: 단어장 (P14 · 이 기기에만 저장)

    /// 상태 기록이 있는 항목 전부. 기록이 없는 항목은 `.new`이고 저장 안 함이다.
    func vocabularyStates() throws -> [VocabularyStateRecord] {
        guard let context else { return [] }
        return try context.fetch(FetchDescriptor<VocabularyStateRecord>())
    }

    /// 저장/저장 해제. 아직 학습한 적 없는 항목도 저장할 수 있어야 해서 없으면 만든다.
    func setVocabularySaved(entryID: String, isSaved: Bool, now: Date = .now) throws {
        guard let context, !entryID.isEmpty else { return }
        let record = try vocabularyState(entryID: entryID, context: context)
            ?? insertVocabularyState(entryID: entryID, context: context)
        guard record.isSaved != isSaved else { return }
        record.isSaved = isSaved
        record.updatedAt = now
        try context.save()
    }

    /// 카드에서 "알아요 / 몰라요"를 누른 결과. 다음에 언제 볼지는
    /// `VocabularyReviewPolicy` 한 곳에서만 정한다.
    ///
    /// 오늘 날짜는 학습 계획 타임존으로 계산한다 — 기기 자정이 아니라 플래너와 같은 하루 경계다.
    func recordVocabularyAnswer(
        entryID: String,
        knewIt: Bool,
        timeZone: TimeZone,
        now: Date = .now
    ) throws {
        guard let context, !entryID.isEmpty else { return }
        let record = try vocabularyState(entryID: entryID, context: context)
            ?? insertVocabularyState(entryID: entryID, context: context)
        let today = LocalCalendarDate.text(from: now, timeZone: timeZone)
        if !knewIt { record.failureCount += 1 }
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: knewIt,
            consecutiveSuccessCount: record.consecutiveSuccessCount,
            today: today,
            timeZone: timeZone
        )
        record.statusRaw = outcome.status.rawValue
        record.consecutiveSuccessCount = outcome.consecutiveSuccessCount
        record.nextReviewLocalDate = outcome.nextReviewLocalDate
        // 같은 세션에서 다시 답해도 "오늘 봤다"는 사실은 그대로다 — 진행도가 두 번 오르지 않는다.
        record.lastStudiedLocalDate = today
        record.updatedAt = now
        try context.save()
    }

    // MARK: AI 맞춤 단어장 (P14.2 · 이 기기에만 저장)

    /// 만든 세트 전부, 최신이 먼저. 세트를 다시 여는 것은 공짜다 — 저장된 항목을
    /// 읽을 뿐 서버도 AI도 부르지 않는다.
    func vocabularyGeneratedSets() throws -> [VocabularyGeneratedSetRecord] {
        guard let context else { return [] }
        return try context.fetch(
            FetchDescriptor<VocabularyGeneratedSetRecord>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    /// 받은 세트를 저장한다. 같은 `setId`가 이미 있으면 덮어쓰지 않고 그냥 둔다 —
    /// 같은 조작을 재시도해 서버가 같은 세트를 다시 준 경우이고, 그때 학습 기록이
    /// 붙어 있는 항목을 새 항목으로 바꿔칠 이유가 없다.
    func saveVocabularyGeneratedSet(_ set: VocabularyGeneratedSet) throws {
        guard let context else { return }
        let setID = set.setId
        var descriptor = FetchDescriptor<VocabularyGeneratedSetRecord>(
            predicate: #Predicate { $0.setID == setID }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(try VocabularyGeneratedSetRecord(set: set))
        try context.save()
    }

    // MARK: AI 말하기 코치 (P14.3 · 이 기기에만 저장)

    /// 한 항목의 코칭 결과 전부, 최신이 먼저. 저장된 결과를 다시 여는 것은 공짜다 —
    /// 서버도 AI도 부르지 않는다.
    func vocabularyCoachResults(entryID: String) throws -> [VocabularySpeakingCoachResult] {
        guard let context, !entryID.isEmpty else { return [] }
        let descriptor = FetchDescriptor<VocabularyCoachResultRecord>(
            predicate: #Predicate { $0.entryID == entryID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap(\.result)
    }

    /// 같은 항목 · 같은 답변에 대한 코칭이 이미 있는가.
    ///
    /// 다시 녹음해도 결국 같은 말을 했다면 이미 값을 치른 결과가 있다는 뜻이다.
    /// 화면은 이걸 먼저 보고 새 유료 요청을 건너뛴다 — 실수로 두 번 결제되지 않게.
    func vocabularyCoachResult(
        entryID: String,
        transcript: String
    ) throws -> VocabularySpeakingCoachResult? {
        guard let context, !entryID.isEmpty else { return nil }
        let key = VocabularySpeakingPrompt.transcriptKey(transcript)
        guard !key.isEmpty else { return nil }
        var descriptor = FetchDescriptor<VocabularyCoachResultRecord>(
            predicate: #Predicate { $0.entryID == entryID && $0.transcriptKey == key },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.result
    }

    /// 받은 코칭을 저장한다. 같은 `resultId`가 이미 있으면 덮어쓰지 않는다 —
    /// 같은 조작을 재시도해 서버가 같은 결과를 다시 준 경우다.
    ///
    /// 사용자가 일부러 다시 분석해 만든 결과는 새 줄로 쌓인다. 이미 값을 치른
    /// 결과를 조용히 지우지 않는다.
    func saveVocabularyCoachResult(_ result: VocabularySpeakingCoachResult) throws {
        guard let context else { return }
        let resultID = result.resultId
        var descriptor = FetchDescriptor<VocabularyCoachResultRecord>(
            predicate: #Predicate { $0.resultID == resultID }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(try VocabularyCoachResultRecord(result: result))
        try context.save()
    }

    private func insertVocabularyState(
        entryID: String,
        context: ModelContext
    ) -> VocabularyStateRecord {
        let record = VocabularyStateRecord(entryID: entryID)
        context.insert(record)
        return record
    }

    private func vocabularyState(
        entryID: String,
        context: ModelContext
    ) throws -> VocabularyStateRecord? {
        var descriptor = FetchDescriptor<VocabularyStateRecord>(
            predicate: #Predicate { $0.entryID == entryID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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

    /// 완료 기록과 **같은 366일** 창을 쓴다. 달력이 보여주는 기간과 문제 사본이
    /// 남는 기간이 어긋나면 P11.1이 없앤 그 불일치가 그대로 돌아온다.
    private func trimLearnedQuestions(context: ModelContext, now: Date) throws {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: now) else {
            return
        }
        try context.delete(
            model: PlannerLearnedQuestionRecord.self,
            where: #Predicate { $0.learnedAt < cutoff }
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
