import Foundation
import Observation

@MainActor
@Observable
final class PracticeViewModel {
    enum Phase: Equatable {
        case loading
        case idle
        case analyzing
        case completed
    }

    let speech = SpeechRecognitionService()
    let promptPlayback = PromptPlaybackService()
    private let api: APIClient
    private let ads: AdService
    private let preferences: AppPreferences
    private let persistence: PersistenceService

    var phase: Phase = .loading
    var questionSet: QuestionSet?
    var questionIndex = 0
    var usage: UsageStatus?
    var evaluation: PracticeEvaluation?
    var evaluatedTranscript = ""
    var errorMessage: String?
    var pendingRecording: SpeechRecordingResult?
    var showsRefreshDialog = false
    var isRefreshingQuestions = false
    var refreshProgressMessage: String?
    var operationState: AsyncOperationState = .idle
    var operationKind: AsyncOperationKind = .dataLoading
    private var loadTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var loadOperationID = UUID()
    private var evaluationOperationID: UUID?
    private var refreshOperationID: UUID?

    init(environment: AppEnvironment) {
        api = environment.api
        ads = environment.ads
        preferences = environment.preferences
        persistence = environment.persistence
    }

    var initialLevel: SelfAssessmentLevel { preferences.initialLevel ?? .level5 }
    var targetLevel: OPIcLevel { questionSet?.expectedTargetLevel ?? preferences.targetLevel ?? .IM2 }
    var currentQuestion: GeneratedQuestion? {
        guard let questions = questionSet?.questions, !questions.isEmpty else { return nil }
        return questions[min(questionIndex, questions.count - 1)]
    }
    var dailyTokenCount: Int? { usage?.totalRemaining }

    /// Analysis result for a single question, kept so the user can navigate back
    /// to an already-analyzed question and see its saved result (read-only).
    struct AnalyzedResult {
        let evaluation: PracticeEvaluation
        let transcript: String
    }
    private var analyzedResults: [Int: AnalyzedResult] = [:]

    var questionCount: Int { questionSet?.questions.count ?? 0 }
    var analyzedNumbers: Set<Int> { Set(analyzedResults.keys) }
    func isAnalyzed(_ number: Int) -> Bool { analyzedResults[number] != nil }
    /// Saved result for the currently displayed question, if it was analyzed.
    var currentResult: AnalyzedResult? {
        guard let number = currentQuestion?.number else { return nil }
        return analyzedResults[number]
    }
    var canGoPrevious: Bool { questionIndex > 0 }
    var canGoNext: Bool { questionIndex < max(0, questionCount - 1) }

    func goToQuestion(_ index: Int) {
        guard index >= 0, index < questionCount, index != questionIndex else { return }
        clearTransientAnswerState()
        questionIndex = index
        phase = .idle
    }

    func goToPrevious() {
        guard canGoPrevious else { return }
        goToQuestion(questionIndex - 1)
    }

    func goToNext() {
        if canGoNext {
            goToQuestion(questionIndex + 1)
        } else if questionCount > 0 {
            // Past the last question → offer a fresh set via the refresh dialog.
            showsRefreshDialog = true
        }
    }

    private func clearTransientAnswerState() {
        speech.cancel()
        promptPlayback.stop()
        AudioFileService.remove(pendingRecording?.audioURL)
        pendingRecording = nil
        errorMessage = nil
    }

    func load() async {
        guard questionSet == nil else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        phase = .loading
        operationKind = .dataLoading
        operationState = .running(operationId: loadOperationID, startedAt: .now)
        errorMessage = nil
        do {
            async let usageTask = api.usage()
            async let setTask = api.createPracticeSet(
                request: QuestionSetRequest(
                    initialLevel: initialLevel,
                    background: preferences.backgroundProfile,
                    survey: preferences.mockSurvey ?? .defaultSurvey
                ),
                requestID: loadOperationID
            )
            usage = try await usageTask
            let set = try await setTask
            set.logDebugSummary(mode: "practice")
            questionSet = set
            phase = .idle
            operationState = .completed
            loadOperationID = UUID()
        } catch is CancellationError {
            phase = .idle
            operationState = .idle
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: loadOperationID,
                message: error.localizedDescription
            )
        }
    }

    func playPrompt() {
        guard let currentQuestion else { return }
        promptPlayback.play(currentQuestion)
    }

    func toggleRecording() async {
        errorMessage = nil
        if speech.isListening {
            do {
                pendingRecording = try await speech.stop()
                try await evaluatePendingRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            promptPlayback.stop()
            do {
                try await speech.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func retryEvaluation() async {
        if let evaluationTask {
            await evaluationTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            do { try await self?.evaluatePendingRecording() }
            catch is CancellationError { }
            catch { self?.errorMessage = error.localizedDescription }
        }
        evaluationTask = task
        await task.value
        evaluationTask = nil
    }

    private func evaluatePendingRecording() async throws {
        guard let pendingRecording, let questionSet, let question = currentQuestion else { return }
        if usage?.totalRemaining == 0 {
            try await unlockPracticeCredits()
        }
        phase = .analyzing
        operationKind = .speechAnalysis
        let operationID = evaluationOperationID ?? UUID()
        evaluationOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        do {
            let result = try await api.evaluatePractice(
                questionSet: questionSet,
                questionNumber: question.number,
                transcript: pendingRecording.transcript,
                targetLevel: targetLevel,
                audioURL: pendingRecording.audioURL,
                requestID: operationID
            )
            evaluation = result
            evaluatedTranscript = pendingRecording.transcript
            analyzedResults[question.number] = AnalyzedResult(
                evaluation: result,
                transcript: pendingRecording.transcript
            )
            try persistence.savePractice(
                targetLevel: targetLevel,
                question: question,
                transcript: pendingRecording.transcript,
                evaluation: result
            )
            AudioFileService.remove(pendingRecording.audioURL)
            self.pendingRecording = nil
            usage = try? await api.usage()
            phase = .completed
            operationState = .completed
            evaluationOperationID = nil
        } catch is CancellationError {
            phase = .idle
            operationState = .idle
            throw CancellationError()
        } catch {
            phase = .idle
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
            throw error
        }
    }

    private func unlockPracticeCredits() async throws {
        let intent = try await api.createRewardIntent(
            purpose: .practiceCredits,
            requestID: UUID()
        )
        try await ads.showRewardedAd(
            userIdentifier: intent.userIdentifier,
            customData: intent.customData
        )
        _ = try await api.waitForReward(nonce: intent.nonce)
        usage = try await api.usage()
    }

    func skipQuestion() {
        speech.cancel()
        AudioFileService.remove(pendingRecording?.audioURL)
        pendingRecording = nil
        evaluation = nil
        evaluatedTranscript = ""
        errorMessage = nil
        if let count = questionSet?.questions.count, count > 0 {
            if questionIndex >= count - 1 {
                showsRefreshDialog = true
            } else {
                questionIndex += 1
            }
        }
        phase = .idle
    }

    func nextQuestion() {
        goToNext()
    }

    func reloadQuestions() async {
        questionSet = nil
        questionIndex = 0
        analyzedResults = [:]
        evaluation = nil
        showsRefreshDialog = false
        refreshProgressMessage = nil
        await load()
    }

    func refreshQuestions(adjustment: DifficultyAdjustment) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(adjustment: adjustment)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(adjustment: DifficultyAdjustment) async {
        isRefreshingQuestions = true
        operationKind = .questionGeneration
        let operationID = refreshOperationID ?? UUID()
        refreshOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        refreshProgressMessage = "새 질문을 준비하고 있어요."
        errorMessage = nil
        do {
            let updated = try await refreshAfterVerifiedAd(
                adjustment: adjustment,
                operationID: operationID
            )
            applyRefreshedQuestionSet(updated)
            operationState = .completed
            refreshOperationID = nil
        } catch is CancellationError {
            operationState = .idle
        } catch {
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
        refreshProgressMessage = nil
        isRefreshingQuestions = false
    }

    private func refreshAfterVerifiedAd(
        adjustment: DifficultyAdjustment,
        operationID: UUID
    ) async throws -> QuestionSet {
        let intent = try await api.createRewardIntent(
            purpose: .practiceRefresh,
            requestID: UUID()
        )
        try await ads.showRewardedAd(
            userIdentifier: intent.userIdentifier,
            customData: intent.customData
        )
        _ = try await api.waitForReward(nonce: intent.nonce)
        refreshProgressMessage = "새 질문을 준비하고 있어요."
        let updated = try await api.refreshPracticeSet(
            request: PracticeRefreshRequest(
                initialLevel: initialLevel,
                background: preferences.backgroundProfile,
                survey: preferences.mockSurvey ?? .defaultSurvey,
                adjustment: adjustment,
                rewardNonce: intent.nonce
            ),
            requestID: operationID
        )
        usage = try? await api.usage()
        return updated
    }

    private func applyRefreshedQuestionSet(_ updated: QuestionSet) {
        updated.logDebugSummary(mode: "practice")
        questionSet = updated
        questionIndex = 0
        analyzedResults = [:]
        showsRefreshDialog = false
        evaluation = nil
        evaluatedTranscript = ""
        pendingRecording = nil
        phase = .idle
    }
}
