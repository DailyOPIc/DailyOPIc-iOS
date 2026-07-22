import Foundation
import Observation

@MainActor
@Observable
final class MockExamViewModel {
    private struct EvaluationRetryContext {
        let rewardNonce: String
        let requestID: UUID
    }

    enum Phase: Equatable {
        case introduction
        case survey
        case loading
        case answering
        case adjustment
        case readyForReward
        case analyzing
        case completed
    }

    let speech = SpeechRecognitionService()
    let promptPlayback = PromptPlaybackService()
    private let api: APIClient
    private let ads: AdService
    private let preferences: AppPreferences
    private let persistence: PersistenceService
    private let environment: AppEnvironment

    var phase: Phase = .introduction
    var session: MockSession?
    var questionSet: QuestionSet?
    var answers: [RecordedAnswer] = []
    var currentIndex = 0
    var evaluation: MockEvaluation?
    var errorMessage: String?
    var surveyDraft: BackgroundSurvey
    var isApplyingAdjustment = false
    var remainingSeconds = 180
    var operationState: AsyncOperationState = .idle
    var operationKind: AsyncOperationKind = .dataLoading
    private var evaluationRetryContext: EvaluationRetryContext?
    private var startOperationID: UUID?
    private var adjustmentOperationID: UUID?
    private var startTask: Task<Void, Never>?
    private var adjustmentTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        api = environment.api
        ads = environment.ads
        preferences = environment.preferences
        persistence = environment.persistence
        surveyDraft = environment.preferences.mockSurvey ?? .defaultSurvey
    }

    var plan: PlanEntitlement { environment.currentPlan }

    /// 모의고사 광고 게이트용 리워드 논스 획득.
    /// 무료 플랜은 리워드 광고를 시청하고, 유료 플랜은 서버 auto-verify로 광고 없이 통과.
    private func acquireRewardNonce(
        purpose: RewardPurpose,
        sessionHash: String?
    ) async throws -> String {
        let intent = try await api.createRewardIntent(
            purpose: purpose,
            sessionHash: sessionHash,
            requestID: UUID()
        )
        if environment.currentPlan.isPaid {
            return intent.nonce
        }
        try await ads.showRewardedAd(
            userIdentifier: intent.userIdentifier,
            customData: intent.customData
        )
        _ = try await api.waitForReward(nonce: intent.nonce)
        return intent.nonce
    }

    var initialLevel: SelfAssessmentLevel { preferences.initialLevel ?? .level5 }
    var targetLevel: OPIcLevel { questionSet?.expectedTargetLevel ?? preferences.targetLevel ?? .IM2 }
    var currentQuestion: GeneratedQuestion? { questionSet?.questions[safe: currentIndex] }
    var expectedQuestionCount: Int { questionSet?.questions.count ?? 15 }
    var progress: Double { Double(answers.count) / Double(max(1, expectedQuestionCount)) }
    var savedSurvey: BackgroundSurvey? { preferences.mockSurvey }
    var canRetryEvaluation: Bool { evaluationRetryContext != nil }

    /// True when we're sitting on the intro but the server has an in-progress
    /// session — used to show an explicit "이어서 하기" button.
    var canResume: Bool {
        phase == .introduction && session != nil && session?.stage != .completed
    }

    func restoreDraftIfAvailable() async {
        guard questionSet == nil else { return }
        if let current = try? await api.currentMockSession() {
            session = current
            if current.stage == .completed {
                errorMessage = "오늘 모의고사를 이미 완료했어요. 내일 새 모의고사가 열려요."
                return
            }
            await enterResume(current)
            return
        }
        // Offline fallback: resume purely from a valid local draft.
        guard let draft = try? persistence.latestDraft() else { return }
        guard draft.updatedAt >= Date.now.addingTimeInterval(-86_400),
              let draftSet = draft.questionSet else {
            AudioFileService.removeAll(draft.answers)
            try? persistence.clearDraft()
            return
        }
        restore(set: draftSet, from: draft.answers)
    }

    /// Continue an in-progress server session. Recovers locally-saved answers when
    /// a matching draft exists; otherwise resumes from the server's question set
    /// (previously recorded audio can't be recovered, e.g. after reinstall).
    func resume() async {
        var current = session
        if current == nil { current = try? await api.currentMockSession() }
        guard let session = current else {
            errorMessage = "이어서 진행할 모의고사를 찾지 못했어요."
            return
        }
        self.session = session
        guard session.stage != .completed else {
            errorMessage = "오늘 모의고사를 이미 완료했어요. 내일 새 모의고사가 열려요."
            return
        }
        await enterResume(session)
    }

    private func enterResume(_ session: MockSession) async {
        var set = session.questionSet
        if set == nil { set = (try? await api.currentMockSession())?.questionSet }
        guard let set else {
            phase = .introduction
            errorMessage = "이어서 진행할 문제를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
            return
        }
        var recovered: [RecordedAnswer] = []
        if let draft = try? persistence.latestDraft(),
           draft.updatedAt >= Date.now.addingTimeInterval(-86_400),
           let ds = draft.questionSet,
           ds.setId == set.setId, ds.setHash == set.setHash {
            recovered = draft.answers
        }
        restore(set: set, from: recovered)
    }

    /// Shared restore: install the set, keep only valid recovered answers, and pick
    /// the resume phase from how far along the answers are.
    private func restore(set: QuestionSet, from rawAnswers: [RecordedAnswer]) {
        let validAnswers = rawAnswers
            .filter { FileManager.default.fileExists(atPath: $0.audioPath) }
            .filter { (1...15).contains($0.number) }
            .filter { number in set.questions.contains { $0.number == number.number } }
        questionSet = set
        answers = Dictionary(grouping: validAnswers, by: \.number)
            .compactMap { $0.value.first }
            .sorted { $0.number < $1.number }
        currentIndex = min(answers.count, max(0, set.questions.count - 1))
        errorMessage = nil
        if !set.isComplete, answers.count >= (set.requiresAdjustmentAfter ?? 7) {
            phase = .adjustment
        } else {
            phase = answers.count == 15 ? .readyForReward : .answering
        }
        try? persistence.saveDraft(targetLevel: targetLevel, questionSet: set, answers: answers)
    }

    func showSurvey() {
        surveyDraft = preferences.mockSurvey ?? .defaultSurvey
        errorMessage = nil
        phase = .survey
    }

    func startWithSavedSurvey() async {
        await startNewExam(survey: preferences.mockSurvey ?? .defaultSurvey)
    }

    func startNewExam(survey: BackgroundSurvey) async {
        guard survey.isValid else {
            errorMessage = "상태와 거주 형태를 선택하고 관심 주제를 3개 이상 선택해 주세요."
            phase = .survey
            return
        }
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart(survey: survey)
        }
        startTask = task
        await task.value
        startTask = nil
    }

    private func performStart(survey: BackgroundSurvey) async {
        phase = .loading
        operationKind = .questionGeneration
        let operationID = startOperationID ?? UUID()
        startOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        errorMessage = nil
        evaluationRetryContext = nil
        do {
            preferences.mockSurvey = survey
            let session = try await api.createMockSession(
                request: QuestionSetRequest(
                    initialLevel: initialLevel,
                    background: preferences.backgroundProfile,
                    survey: survey
                ),
                requestID: UUID()
            )
            // An in-progress session already exists today → resume it instead of
            // dead-ending with a 409 error banner.
            guard session.stage == .awaitingStartAd else {
                self.session = session
                await enterResume(session)
                operationState = .completed
                startOperationID = nil
                return
            }
            let rewardNonce = try await acquireRewardNonce(
                purpose: .mockStart,
                sessionHash: session.sessionHash
            )
            let started = try await api.startMockSession(
                sessionId: session.sessionId,
                rewardNonce: rewardNonce,
                requestID: operationID
            )
            guard let set = started.questionSet else {
                throw APIClientError.invalidResponse
            }
            set.logDebugSummary(mode: "mock")
            self.session = started
            questionSet = set
            answers = []
            currentIndex = 0
            evaluation = nil
            evaluationRetryContext = nil
            try persistence.saveDraft(targetLevel: targetLevel, questionSet: set, answers: [])
            phase = .answering
            operationState = .completed
            startOperationID = nil
        } catch is CancellationError {
            phase = .introduction
            operationState = .idle
        } catch {
            phase = .introduction
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
    }

    func toggleRecording() async {
        errorMessage = nil
        if speech.isListening {
            do {
                timerTask?.cancel()
                let result = try await speech.stop()
                saveAnswer(result)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                promptPlayback.stop()
                try await speech.start()
                startAnswerTimer()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func playPrompt() {
        guard let currentQuestion else { return }
        promptPlayback.play(currentQuestion)
    }

    private func startAnswerTimer() {
        timerTask?.cancel()
        remainingSeconds = 180
        timerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remainingSeconds -= 1
            }
            guard let self, self.speech.isListening else { return }
            await self.toggleRecording()
        }
    }

    private func saveAnswer(_ result: SpeechRecordingResult) {
        guard let question = currentQuestion, let questionSet else { return }
        evaluationRetryContext = nil
        if let existing = answers.first(where: { $0.number == question.number }) {
            AudioFileService.remove(existing.audioURL)
        }
        answers.removeAll { $0.number == question.number }
        let persistedURL = (try? AudioFileService.persistMockAnswer(
            result.audioURL,
            sessionID: session?.sessionId ?? questionSet.setId,
            questionNumber: question.number
        )) ?? result.audioURL
        answers.append(
            RecordedAnswer(
                number: question.number,
                transcript: result.transcript,
                audioPath: persistedURL.path
            )
        )
        answers.sort { $0.number < $1.number }
        try? persistence.saveDraft(
            targetLevel: targetLevel,
            questionSet: questionSet,
            answers: answers
        )
        if questionSet.requiresAdjustmentAfter == question.number,
           !questionSet.isComplete {
            phase = .adjustment
        } else if answers.count == 15 {
            phase = .readyForReward
        } else {
            currentIndex = min(currentIndex + 1, max(0, questionSet.questions.count - 1))
        }
    }

    func previousQuestion() { }

    func evaluateAfterReward() async {
        guard let questionSet, answers.count == 15 else { return }
        if let evaluationTask {
            await evaluationTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performEvaluationGate(questionSet: questionSet)
        }
        evaluationTask = task
        await task.value
        evaluationTask = nil
    }

    private func performEvaluationGate(questionSet: QuestionSet) async {
        errorMessage = nil
        if let evaluationRetryContext {
            await submitEvaluation(context: evaluationRetryContext)
            return
        }
        do {
            let rewardNonce = try await acquireRewardNonce(
                purpose: .mockResult,
                sessionHash: session?.sessionHash ?? questionSet.setHash
            )
            let context = EvaluationRetryContext(
                rewardNonce: rewardNonce,
                requestID: UUID()
            )
            evaluationRetryContext = context
            await submitEvaluation(context: context)
        } catch {
            phase = .readyForReward
            errorMessage = error.localizedDescription
        }
    }

    func retryEvaluation() async {
        guard let evaluationRetryContext else {
            await evaluateAfterReward()
            return
        }
        await submitEvaluation(context: evaluationRetryContext)
    }

    private func submitEvaluation(context: EvaluationRetryContext) async {
        guard let questionSet, let session, answers.count == 15 else { return }
        phase = .analyzing
        operationKind = .mockResult
        operationState = .running(operationId: context.requestID, startedAt: .now)
        errorMessage = nil
        do {
            let result = try await api.evaluateMock(
                sessionId: session.sessionId,
                questionSet: questionSet,
                answers: answers,
                targetLevel: targetLevel,
                rewardNonce: context.rewardNonce,
                requestID: context.requestID
            )
            evaluation = result
            try persistence.saveMock(
                targetLevel: targetLevel,
                questionSet: questionSet,
                answers: answers,
                evaluation: result
            )
            AudioFileService.removeAll(answers)
            evaluationRetryContext = nil
            phase = .completed
            operationState = .completed
        } catch let error as APIClientError where error.isAIUnavailable {
            phase = .readyForReward
            operationState = .recoverableFailure(
                operationId: context.requestID,
                message: error.localizedDescription
            )
            errorMessage = "AI 평가 생성에 실패했습니다. 같은 답변으로 다시 시도해 주세요."
        } catch let error as APIClientError where error.isRewardRequired {
            evaluationRetryContext = nil
            phase = .readyForReward
            errorMessage = error.localizedDescription
        } catch {
            phase = .readyForReward
            errorMessage = error.localizedDescription
        }
    }

    func resetExam() {
        speech.cancel()
        promptPlayback.stop()
        timerTask?.cancel()
        AudioFileService.removeAll(answers)
        if let session { AudioFileService.removeMockSession(sessionID: session.sessionId) }
        try? persistence.clearDraft()
        questionSet = nil
        let hadSession = session != nil
        session = nil
        answers = []
        currentIndex = 0
        evaluation = nil
        errorMessage = hadSession ? "오늘 모의고사를 그만뒀어요. 내일 다시 도전할 수 있어요." : nil
        evaluationRetryContext = nil
        phase = .introduction
    }

    func applyAdjustment(_ adjustment: DifficultyAdjustment) async {
        guard let questionSet, let session else { return }
        if let adjustmentTask {
            await adjustmentTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAdjustment(
                adjustment,
                questionSet: questionSet,
                session: session
            )
        }
        adjustmentTask = task
        await task.value
        adjustmentTask = nil
    }

    private func performAdjustment(
        _ adjustment: DifficultyAdjustment,
        questionSet: QuestionSet,
        session: MockSession
    ) async {
        isApplyingAdjustment = true
        operationKind = .difficultyAdjustment
        let operationID = adjustmentOperationID ?? UUID()
        adjustmentOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        errorMessage = nil
        do {
            let rewardNonce = try await acquireRewardNonce(
                purpose: .mockAdjustment,
                sessionHash: session.sessionHash
            )
            let adjustedSession = try await api.adjustMockSession(
                sessionId: session.sessionId,
                adjustment: adjustment,
                rewardNonce: rewardNonce,
                requestID: operationID
            )
            guard let updated = adjustedSession.questionSet else {
                throw APIClientError.invalidResponse
            }
            updated.logDebugSummary(mode: "mock")
            self.session = adjustedSession
            self.questionSet = updated
            evaluationRetryContext = nil
            currentIndex = min(answers.count, max(0, updated.questions.count - 1))
            try? persistence.saveDraft(
                targetLevel: updated.expectedTargetLevel,
                questionSet: updated,
                answers: answers
            )
            phase = .answering
            operationState = .completed
            adjustmentOperationID = nil
        } catch is CancellationError {
            operationState = .idle
        } catch {
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
        isApplyingAdjustment = false
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
