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
    var showsAdjustmentDialog = false
    var isApplyingAdjustment = false

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
        return questions[questionIndex % questions.count]
    }
    var remainingText: String {
        guard let usage else { return "사용량 확인 중" }
        return "무료 \(usage.freeRemaining) · 광고 보너스 \(usage.bonusRemaining)"
    }

    func load() async {
        guard questionSet == nil else { return }
        phase = .loading
        errorMessage = nil
        do {
            async let usageTask = api.usage()
            async let setTask = api.createPracticeSet(
                request: QuestionSetRequest(
                    initialLevel: initialLevel,
                    background: preferences.backgroundProfile
                )
            )
            usage = try await usageTask
            let set = try await setTask
            set.logDebugSummary(mode: "practice")
            questionSet = set
            phase = .idle
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
        }
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
            do {
                try await speech.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func retryEvaluation() async {
        do {
            try await evaluatePendingRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func evaluatePendingRecording() async throws {
        guard let pendingRecording, let questionSet, let question = currentQuestion else { return }
        if usage?.totalRemaining == 0 {
            try await unlockPracticeCredits()
        }
        phase = .analyzing
        do {
            let result = try await api.evaluatePractice(
                questionSet: questionSet,
                questionNumber: question.number,
                transcript: pendingRecording.transcript,
                targetLevel: targetLevel,
                audioURL: pendingRecording.audioURL
            )
            evaluation = result
            evaluatedTranscript = pendingRecording.transcript
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
        } catch {
            phase = .idle
            throw error
        }
    }

    private func unlockPracticeCredits() async throws {
        let intent = try await api.createRewardIntent(purpose: .practiceCredits)
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
        if let question = currentQuestion,
           let questionSet,
           questionSet.requiresAdjustmentAfter == question.number,
           !questionSet.isComplete {
            showsAdjustmentDialog = true
            phase = .idle
            return
        }
        if let count = questionSet?.questions.count, count > 0 {
            questionIndex = (questionIndex + 1) % count
        }
        phase = .idle
    }

    func nextQuestion() {
        skipQuestion()
    }

    func reloadQuestions() async {
        questionSet = nil
        questionIndex = 0
        showsAdjustmentDialog = false
        await load()
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
            updated.logDebugSummary(mode: "practice")
            self.questionSet = updated
            questionIndex = min(questionIndex + 1, max(0, updated.questions.count - 1))
            showsAdjustmentDialog = false
            phase = .idle
        } catch {
            errorMessage = error.localizedDescription
        }
        isApplyingAdjustment = false
    }
}
