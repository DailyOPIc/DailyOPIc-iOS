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
    private let api: APIClient
    private let ads: AdService
    private let preferences: AppPreferences
    private let persistence: PersistenceService

    var phase: Phase = .introduction
    var questionSet: QuestionSet?
    var answers: [RecordedAnswer] = []
    var currentIndex = 0
    var evaluation: MockEvaluation?
    var errorMessage: String?
    var surveyDraft: BackgroundSurvey
    var isApplyingAdjustment = false
    private var evaluationRetryContext: EvaluationRetryContext?

    init(environment: AppEnvironment) {
        api = environment.api
        ads = environment.ads
        preferences = environment.preferences
        persistence = environment.persistence
        surveyDraft = environment.preferences.mockSurvey ?? .defaultSurvey
    }

    var initialLevel: SelfAssessmentLevel { preferences.initialLevel ?? .level5 }
    var targetLevel: OPIcLevel { questionSet?.expectedTargetLevel ?? preferences.targetLevel ?? .IM2 }
    var currentQuestion: GeneratedQuestion? { questionSet?.questions[safe: currentIndex] }
    var expectedQuestionCount: Int { questionSet?.questions.count ?? 15 }
    var progress: Double { Double(answers.count) / Double(max(1, expectedQuestionCount)) }
    var savedSurvey: BackgroundSurvey? { preferences.mockSurvey }
    var canRetryEvaluation: Bool { evaluationRetryContext != nil }

    func restoreDraftIfAvailable() {
        guard questionSet == nil,
              let draft = try? persistence.latestDraft(),
              let set = draft.questionSet else { return }
        questionSet = set
        answers = draft.answers.sorted { $0.number < $1.number }
        currentIndex = min(answers.count, max(0, set.questions.count - 1))
        if !set.isComplete, answers.count >= (set.requiresAdjustmentAfter ?? 7) {
            phase = .adjustment
        } else {
            phase = answers.count == 15 ? .readyForReward : .answering
        }
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
        phase = .loading
        errorMessage = nil
        evaluationRetryContext = nil
        do {
            preferences.mockSurvey = survey
            let set = try await api.createMockExam(
                request: QuestionSetRequest(
                    initialLevel: initialLevel,
                    background: preferences.backgroundProfile,
                    survey: survey
                )
            )
            set.logDebugSummary(mode: "mock")
            questionSet = set
            answers = []
            currentIndex = 0
            evaluation = nil
            evaluationRetryContext = nil
            try persistence.saveDraft(targetLevel: targetLevel, questionSet: set, answers: [])
            phase = .answering
        } catch {
            phase = .introduction
            errorMessage = error.localizedDescription
        }
    }

    func toggleRecording() async {
        errorMessage = nil
        if speech.isListening {
            do {
                let result = try await speech.stop()
                saveAnswer(result)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                try await speech.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAnswer(_ result: SpeechRecordingResult) {
        guard let question = currentQuestion, let questionSet else { return }
        evaluationRetryContext = nil
        if let existing = answers.first(where: { $0.number == question.number }) {
            AudioFileService.remove(existing.audioURL)
        }
        answers.removeAll { $0.number == question.number }
        answers.append(
            RecordedAnswer(
                number: question.number,
                transcript: result.transcript,
                audioPath: result.audioURL.path
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

    func previousQuestion() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func evaluateAfterReward() async {
        guard let questionSet, answers.count == 15 else { return }
        errorMessage = nil
        if let evaluationRetryContext {
            await submitEvaluation(context: evaluationRetryContext)
            return
        }
        do {
            let intent = try await api.createRewardIntent(
                purpose: .mockResult,
                sessionHash: questionSet.setHash
            )
            try await ads.showRewardedAd(
                userIdentifier: intent.userIdentifier,
                customData: intent.customData
            )
            _ = try await api.waitForReward(nonce: intent.nonce)
            let context = EvaluationRetryContext(
                rewardNonce: intent.nonce,
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
        guard let questionSet, answers.count == 15 else { return }
        phase = .analyzing
        errorMessage = nil
        do {
            let result = try await api.evaluateMock(
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
        } catch let error as APIClientError where error.isAIUnavailable {
            phase = .readyForReward
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
        AudioFileService.removeAll(answers)
        try? persistence.clearDraft()
        questionSet = nil
        answers = []
        currentIndex = 0
        evaluation = nil
        errorMessage = nil
        evaluationRetryContext = nil
        phase = .introduction
    }

    func applyAdjustment(_ adjustment: DifficultyAdjustment) async {
        guard let questionSet, !isApplyingAdjustment else { return }
        isApplyingAdjustment = true
        errorMessage = nil
        do {
            let updated = try await api.applyQuestionSetAdjustment(
                setId: questionSet.setId,
                adjustment: adjustment
            )
            updated.logDebugSummary(mode: "mock")
            self.questionSet = updated
            evaluationRetryContext = nil
            currentIndex = min(answers.count, max(0, updated.questions.count - 1))
            try? persistence.saveDraft(
                targetLevel: updated.expectedTargetLevel,
                questionSet: updated,
                answers: answers
            )
            phase = .answering
        } catch {
            errorMessage = error.localizedDescription
        }
        isApplyingAdjustment = false
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
