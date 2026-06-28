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
    var showsRefreshDialog = false
    var isRefreshingQuestions = false
    var refreshProgressMessage: String?

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
                    background: preferences.backgroundProfile,
                    survey: preferences.mockSurvey ?? .defaultSurvey
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
        skipQuestion()
    }

    func reloadQuestions() async {
        questionSet = nil
        questionIndex = 0
        showsRefreshDialog = false
        refreshProgressMessage = nil
        await load()
    }

    func refreshQuestions(adjustment: DifficultyAdjustment) async {
        guard !isRefreshingQuestions else { return }
        isRefreshingQuestions = true
        refreshProgressMessage = "새 Daily 문제를 준비하는 중입니다."
        errorMessage = nil
        do {
            let updated = try await refreshAfterEnsuringToken(adjustment: adjustment)
            applyRefreshedQuestionSet(updated)
        } catch let error as APIClientError where error.isPracticeQuotaExhausted {
            do {
                refreshProgressMessage = "토큰이 부족해 리워드 광고를 준비하는 중입니다."
                try await unlockPracticeCredits()
                let updated = try await refreshAfterEnsuringToken(adjustment: adjustment)
                applyRefreshedQuestionSet(updated)
            } catch {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshProgressMessage = nil
        isRefreshingQuestions = false
    }

    private func refreshAfterEnsuringToken(adjustment: DifficultyAdjustment) async throws -> QuestionSet {
        if usage?.totalRemaining == 0 {
            refreshProgressMessage = "토큰이 부족해 리워드 광고를 준비하는 중입니다."
            try await unlockPracticeCredits()
        }
        refreshProgressMessage = "토큰 1개를 사용해 새 문제를 불러오는 중입니다."
        let updated = try await api.refreshPracticeSet(
            request: PracticeRefreshRequest(
                initialLevel: initialLevel,
                background: preferences.backgroundProfile,
                survey: preferences.mockSurvey ?? .defaultSurvey,
                adjustment: adjustment
            )
        )
        usage = try? await api.usage()
        return updated
    }

    private func applyRefreshedQuestionSet(_ updated: QuestionSet) {
        updated.logDebugSummary(mode: "practice")
        questionSet = updated
        questionIndex = 0
        showsRefreshDialog = false
        evaluation = nil
        evaluatedTranscript = ""
        pendingRecording = nil
        phase = .idle
    }
}
