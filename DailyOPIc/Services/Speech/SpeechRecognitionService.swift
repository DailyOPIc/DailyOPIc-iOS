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
    enum RecordingState: String, Sendable { case idle, recording, processing, interrupted, failed }
    enum PermissionState: String, Sendable { case unknown, granted, denied }
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
    @Published private(set) var partialTranscript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var interruptionReason: String?

    /// 시스템 오디오 중단(전화 등)을 소유자에게 알린다. 여기서 녹음을 버리지 않고
    /// 소유자가 stop()으로 지금까지 인식된 답변을 살릴 수 있게 하려는 것.
    var onInterruption: (@MainActor () -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var rawAudioURL: URL?
    private var tapInstalled = false

    override init() {
        super.init()
        recognizer?.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
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
        let granted = speechAuthorized && microphoneAuthorized
        permissionState = granted ? .granted : .denied
        return granted
    }

    func start() async throws {
        guard await preparePermissions() else { throw SpeechError.permissionDenied }
        guard recognizer?.isAvailable == true else { throw SpeechError.unavailable }
        cleanupRecognition()
        transcript = ""
        partialTranscript = ""
        finalTranscript = ""
        errorMessage = nil
        interruptionReason = nil

        do {
            let session = AVAudioSession.sharedInstance()
            // `.default` mode keeps Apple's speech signal processing (AGC, noise
            // suppression) enabled, which improves recognition accuracy vs
            // `.measurement` (which disables that processing).
            try session.setCategory(.record, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            // Add sentence punctuation so the transcript reads naturally and the
            // downstream AI evaluation gets proper sentence boundaries.
            request.addsPunctuation = true
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
            tapInstalled = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        self?.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self?.finalTranscript = result.bestTranscription.formattedString
                            self?.partialTranscript = ""
                        } else {
                            self?.partialTranscript = result.bestTranscription.formattedString
                        }
                    }
                    if let error, self?.isListening == true {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            recordingState = .recording
        } catch {
            if audioEngine.isRunning { audioEngine.stop() }
            removeTapIfNeeded()
            if let rawAudioURL { try? FileManager.default.removeItem(at: rawAudioURL) }
            cleanupRecognition()
            deactivateAudioSession()
            isListening = false
            recordingState = .failed
            throw error
        }
    }

    func stop() async throws -> SpeechRecordingResult {
        guard isListening, let rawAudioURL else { throw SpeechError.audioFailure }
        recordingState = .processing
        audioEngine.stop()
        removeTapIfNeeded()
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        audioFile = nil
        isListening = false
        deactivateAudioSession()

        try await Task.sleep(for: .milliseconds(250))
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try? FileManager.default.removeItem(at: rawAudioURL)
            throw SpeechError.noSpeech
        }
        let compressed = try await compressToM4A(rawAudioURL)
        try? FileManager.default.removeItem(at: rawAudioURL)
        cleanupRecognition()
        recordingState = .idle
        return SpeechRecordingResult(transcript: normalized, audioURL: compressed)
    }

    func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeTapIfNeeded()
        if let rawAudioURL { try? FileManager.default.removeItem(at: rawAudioURL) }
        cleanupRecognition()
        isListening = false
        transcript = ""
        partialTranscript = ""
        finalTranscript = ""
        recordingState = .idle
        deactivateAudioSession()
    }

    private func cleanupRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioFile = nil
        rawAudioURL = nil
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    @objc private nonisolated func handleInterruption(_ notification: Notification) {
        // 중단 시작만 처리한다. .ended까지 같이 받으면 이미 정리된 녹음을 또 건드린다.
        let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard let rawType,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
        // 알림은 임의 스레드로 온다. 상태 변경은 메인에서만.
        Task { @MainActor [weak self] in
            guard let self, self.isListening else { return }
            self.interruptionReason = "통화 등으로 녹음이 중단됐어요."
            self.errorMessage = self.interruptionReason
            self.recordingState = .interrupted
            // 오디오는 시스템이 이미 멈췄다. 여기서 파일을 지우면 사용자가 말한
            // 내용이 조용히 사라지므로, 소유자가 stop()으로 살려내도록 넘긴다.
            if let onInterruption = self.onInterruption {
                onInterruption()
            } else {
                self.cancel()
                self.recordingState = .interrupted
            }
        }
    }

    /// 말하기 평가에 쓰기 충분한 음성용 비트레이트. 서버는 이 파일에서 길이와
    /// 묵음 비율만 재고, 전사는 이미 기기에서 끝난다.
    private static let speechBitRate = 48_000
    private static let transcodeQueue = DispatchQueue(label: "com.dailyopic.audio.transcode")

    /// 녹음 원본(CAF, PCM)을 업로드용 m4a로 변환한다.
    ///
    /// 예전에는 AVAssetExportPresetAppleM4A를 썼는데, 이 프리셋은 비트레이트를
    /// 지정할 수 없고 48kHz 마이크 입력에서 약 256kbps를 만들었다. 그래서 180초
    /// 답변이 5.4MiB까지 커져 서버 업로드 상한에 걸렸다(2분 녹음이 거절된 원인).
    /// 비트레이트를 직접 정하면 길이에 비례해 예측 가능하다: 180초 ≈ 1.1MiB.
    nonisolated private func compressToM4A(_ source: URL) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailyopic-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SpeechError.audioFailure
        }
        let format = try await track.load(.formatDescriptions).first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                // 원본 포맷을 그대로 따라간다. 리샘플링/다운믹스를 요구하면
                // 기기에 따라 인코더가 실패한다.
                AVSampleRateKey: format?.mSampleRate ?? 48_000,
                AVNumberOfChannelsKey: format?.mChannelsPerFrame ?? 1,
                AVEncoderBitRateKey: Self.speechBitRate,
            ]
        )
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            throw SpeechError.audioFailure
        }
        writer.startSession(atSourceTime: .zero)
        await withCheckedContinuation { continuation in
            input.requestMediaDataWhenReady(on: Self.transcodeQueue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? SpeechError.audioFailure
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
