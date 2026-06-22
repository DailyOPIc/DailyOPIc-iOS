import AVFoundation
import Combine
import Foundation
import Speech

struct SpeechRecordingResult: Sendable {
    let transcript: String
    let audioURL: URL
}

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    enum SpeechError: LocalizedError {
        case permissionDenied
        case unavailable
        case noSpeech
        case audioFailure

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "음성 인식과 마이크 권한을 허용해 주세요."
            case .unavailable:
                "현재 영어 음성 인식을 사용할 수 없습니다."
            case .noSpeech:
                "인식된 영어 답변이 없습니다. 다시 녹음해 주세요."
            case .audioFailure:
                "녹음 파일을 처리할 수 없습니다."
            }
        }
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var rawAudioURL: URL?

    override init() {
        super.init()
        recognizer?.delegate = self
    }

    func preparePermissions() async -> Bool {
        let speechAuthorized: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechAuthorized = true
        case .notDetermined:
            speechAuthorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            speechAuthorized = false
        }

        let microphoneAuthorized: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneAuthorized = true
        case .undetermined:
            microphoneAuthorized = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied:
            microphoneAuthorized = false
        @unknown default:
            microphoneAuthorized = false
        }
        return speechAuthorized && microphoneAuthorized
    }

    func start() async throws {
        guard await preparePermissions() else { throw SpeechError.permissionDenied }
        guard recognizer?.isAvailable == true else { throw SpeechError.unavailable }
        cleanupRecognition()
        transcript = ""
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let rawURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailyopic-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        rawAudioURL = rawURL

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: rawURL, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
            try? self.audioFile?.write(from: buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if let error, self?.isListening == true {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    func stop() async throws -> SpeechRecordingResult {
        guard isListening, let rawAudioURL else { throw SpeechError.audioFailure }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        audioFile = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        try await Task.sleep(for: .milliseconds(250))
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try? FileManager.default.removeItem(at: rawAudioURL)
            throw SpeechError.noSpeech
        }
        let compressed = try await compressToM4A(rawAudioURL)
        try? FileManager.default.removeItem(at: rawAudioURL)
        cleanupRecognition()
        return SpeechRecordingResult(transcript: normalized, audioURL: compressed)
    }

    func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        if let rawAudioURL { try? FileManager.default.removeItem(at: rawAudioURL) }
        cleanupRecognition()
        isListening = false
        transcript = ""
    }

    private func cleanupRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioFile = nil
        rawAudioURL = nil
    }

    private func compressToM4A(_ source: URL) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailyopic-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SpeechError.audioFailure
        }
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        await exporter.export()
        guard exporter.status == .completed else {
            throw exporter.error ?? SpeechError.audioFailure
        }
        return destination
    }

    nonisolated func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        Task { @MainActor in
            if !available { errorMessage = SpeechError.unavailable.localizedDescription }
        }
    }
}
