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
        deactivateSession()
    }

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        activatePlaybackSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// The speech recognizer leaves the shared audio session in `.record` mode,
    /// which silences playback. Claim a playback-capable session before speaking
    /// so TTS is audible regardless of the ring/silent switch.
    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
            deactivateSession()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
            deactivateSession()
        }
    }
}
