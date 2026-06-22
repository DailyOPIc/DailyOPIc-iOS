import Foundation
import Observation

@MainActor
@Observable
final class MockExamViewModel {
    enum Phase: Equatable {
        case introduction
        case loading
        case answering
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

    init(environment: AppEnvironment) {
        api = environment.api
        ads = environment.ads
        preferences = environment.preferences
        persistence = environment.persistence
    }

    var targetLevel: OPIcLevel { preferences.targetLevel ?? .IM2 }
    var currentQuestion: GeneratedQuestion? { questionSet?.questions[safe: currentIndex] }
    var progress: Double { Double(answers.count) / 15.0 }

    func restoreDraftIfAvailable() {
        guard questionSet == nil,
              let draft = try? persistence.latestDraft(),
              let set = draft.questionSet else { return }
        questionSet = set
        answers = draft.answers.sorted { $0.number < $1.number }
        currentIndex = min(answers.count, 14)
        phase = answers.count == 15 ? .readyForReward : .answering
    }

    func startNewExam() async {
        phase = .loading
        errorMessage = nil
        do {
            let set = try await api.createMockExam(
                request: QuestionSetRequest(
                    targetLevel: targetLevel,
                    background: preferences.backgroundProfile
                )
            )
            questionSet = set
            answers = []
            currentIndex = 0
            evaluation = nil
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
        if answers.count == 15 {
            phase = .readyForReward
        } else {
            currentIndex = min(currentIndex + 1, 14)
        }
    }

    func previousQuestion() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func evaluateAfterReward() async {
        guard let questionSet, answers.count == 15 else { return }
        errorMessage = nil
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
            phase = .analyzing
            let result = try await api.evaluateMock(
                questionSet: questionSet,
                answers: answers,
                targetLevel: targetLevel,
                rewardNonce: intent.nonce
            )
            evaluation = result
            try persistence.saveMock(
                targetLevel: targetLevel,
                questionSet: questionSet,
                answers: answers,
                evaluation: result
            )
            AudioFileService.removeAll(answers)
            phase = .completed
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
        phase = .introduction
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
