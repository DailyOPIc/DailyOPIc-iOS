import AVFoundation
import Combine
import Foundation

@MainActor
final class PromptPlaybackService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    /// Question numbers whose prompt has been played at least once, so the UI can
    /// toggle the button label between "질문 듣기" and "다시 듣기".
    @Published private(set) var startedNumbers: Set<Int> = []
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Play the prompt on demand. No auto-play; callers invoke this from a button.
    /// Replayable without limit.
    func play(_ question: GeneratedQuestion) {
        startedNumbers.insert(question.number)
        speak(question.prompt)
    }

    func hasStarted(_ question: GeneratedQuestion) -> Bool {
        startedNumbers.contains(question.number)
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
