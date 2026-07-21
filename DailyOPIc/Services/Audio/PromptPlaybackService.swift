import AVFoundation
import Combine
import Foundation

@MainActor
final class PromptPlaybackService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var playedQuestionNumbers: Set<Int> = []
    private var replayedQuestionNumbers: Set<Int> = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func playAutomatically(_ question: GeneratedQuestion) {
        guard !playedQuestionNumbers.contains(question.number) else { return }
        playedQuestionNumbers.insert(question.number)
        speak(question.prompt)
    }

    func replayOnce(_ question: GeneratedQuestion) {
        guard !replayedQuestionNumbers.contains(question.number) else { return }
        replayedQuestionNumbers.insert(question.number)
        speak(question.prompt)
    }

    func canReplay(_ question: GeneratedQuestion) -> Bool {
        !replayedQuestionNumbers.contains(question.number) && !isSpeaking
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in isSpeaking = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in isSpeaking = false }
    }
}
