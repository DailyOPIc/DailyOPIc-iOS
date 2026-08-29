import Foundation
import Observation

/// 단어장 AI 말하기 코치(P14.3)의 앱 쪽 진행 상태.
///
/// 무료: 화면 열기 · 발음 듣기 · 녹음 · 다시 녹음 · 기기 전사(STT) · 전사 확인 ·
/// 저장된 코칭 다시 보기.
/// 과금: **[AI에게 분석받기] 1회 = 데일리 토큰 1개.** 그것뿐이다.
///
/// 녹음을 멈추는 것만으로는 아무것도 요청하지 않는다 — 사용자가 전사를 보고
/// 직접 눌러야 시작한다. 강제는 서버가 하고, 앱의 몫은 넷이다: 누르기 전에 비용을
/// 보여주고, 잔액이 0이면 요청을 시작하지 않고, 서버가 거절하면 기존 부족 UX로
/// 넘기고, 잔액은 서버에서 다시 읽는다.
///
/// 녹음 · 오디오 세션 · 마이크 권한 · STT는 데일리와 **같은**
/// `SpeechRecognitionService`를 쓴다. 두 번째 레코더를 만들지 않는다.
@MainActor
@Observable
final class VocabularyCoachViewModel {
    /// 한 번의 코칭 비용. 화면 문구와 서버 계약이 어긋나지 않게 여기 한 곳에 둔다.
    static let tokenCost = 1
    /// 표현 하나를 한두 문장으로 말하는 연습이다. 데일리 답변(180초)과 달리 짧게 끊는다.
    static let maxAnswerSeconds = 60

    let entry: VocabularyEntry
    let speech = SpeechRecognitionService()

    private let environment: AppEnvironment
    private let api: APIClient
    private let ads: AdService
    private let persistence: PersistenceService
    private let preferences: AppPreferences
    private let targetLevel: OPIcLevel?

    /// 녹음을 멈추고 확정된 전사. 있으면 검토 상태다(아직 아무것도 요청하지 않았다).
    var pendingTranscript: String?
    /// 지금 화면에 보이는 코칭 결과. 저장된 결과를 다시 열 때도 여기에 들어온다.
    var result: VocabularySpeakingCoachResult?
    /// 이 항목의 지난 코칭, 최신이 먼저. 여는 것은 공짜다.
    var history: [VocabularySpeakingCoachResult] = []
    var usage: UsageStatus?
    var operationState: AsyncOperationState = .idle
    var errorMessage: String?
    var showsPaywall = false
    private(set) var paywallSource: PaywallSource = .tokenExhausted
    var remainingSeconds = VocabularyCoachViewModel.maxAnswerSeconds

    private var analysisTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init(entry: VocabularyEntry, environment: AppEnvironment, targetLevel: OPIcLevel?) {
        self.entry = entry
        self.environment = environment
        self.targetLevel = targetLevel
        api = environment.api
        ads = environment.ads
        persistence = environment.persistence
        preferences = environment.preferences
        speech.onInterruption = { [weak self] in self?.handleRecordingInterruption() }
    }

    var instruction: String { VocabularySpeakingPrompt.instruction(for: entry) }
    var topicHint: String? { VocabularySpeakingPrompt.topicHint(for: entry) }
    var dailyTokenCount: Int? { usage?.totalRemaining }
    var isAnalyzing: Bool { operationState.isRunning }
    /// 잔액을 아는데 0일 때만 참. 모를 때(nil)는 막지 않는다 — 최종 판단은 서버다.
    var hasNoTokens: Bool { dailyTokenCount == 0 }
    /// 분석에 보낼 만한 답변인가. 빈 전사·잡음을 유료 요청으로 보내지 않는다.
    var canAnalyze: Bool {
        guard let pendingTranscript else { return false }
        return VocabularySpeakingPrompt.isAnalyzable(pendingTranscript)
    }

    var failureMessage: String? {
        if case let .recoverableFailure(_, message) = operationState { return message }
        return nil
    }

    /// 화면이 뜰 때. 저장된 코칭을 읽고 잔액을 갱신한다 — 어느 쪽도 AI를 부르지 않는다.
    func load() async {
        reloadHistory()
        recoverPendingOperation()
        // 지난 결과가 있으면 바로 보여준다. 다시 보는 것은 공짜다.
        if result == nil, pendingTranscript == nil { result = history.first }
        usage = try? await api.usage()
    }

    /// 분석 도중 앱이 죽었다면 값을 이미 치른 조작이 남아 있다.
    ///
    /// 여기서는 **아무것도 보내지 않는다.** 화면을 다시 열었다는 이유로 토큰이 나가면 안 되므로,
    /// 그 답변을 검토 상태로 되살려 사용자가 누르면 **같은 키로** 재시도되게만 해 둔다.
    private func recoverPendingOperation() {
        guard let pending = preferences.pendingVocabularyCoach,
              pending.entryID == entry.id else { return }
        // 결과가 이미 저장돼 있으면 그 조작은 끝난 것이다. 서버를 부를 이유가 없다.
        if let saved = try? persistence.vocabularyCoachResult(
            entryID: entry.id,
            transcript: pending.transcript
        ) {
            preferences.pendingVocabularyCoach = nil
            if result == nil { result = saved }
            return
        }
        // 서버가 결과를 되돌려 준다고 보장할 수 있는 기간을 넘겼다. 재생될지 모르는 키를 조용히
        // 다시 보내지 않는다 — 새 분석은 비용이 보이는 CTA에서 사용자가 직접 시작해야 한다.
        guard pending.isReplayable() else {
            preferences.pendingVocabularyCoach = nil
            return
        }
        pendingTranscript = pending.transcript
        operationState = .recoverableFailure(
            operationId: pending.operationID,
            message: "지난 분석이 끝나지 않았어요. 다시 시도하면 토큰을 더 쓰지 않고 결과를 받아와요."
        )
    }

    func refreshUsage() async {
        usage = try? await api.usage()
    }

    private func reloadHistory() {
        history = (try? persistence.vocabularyCoachResults(entryID: entry.id)) ?? []
    }

    // MARK: 녹음 (0 토큰)

    func toggleRecording() async {
        errorMessage = nil
        if speech.isListening {
            // 녹음 종료는 제출이 아니다. 검토 상태로만 넘어가고, AI 분석은
            // 사용자가 "AI에게 분석받기"를 눌러야 시작한다.
            await finishRecording()
        } else {
            pendingTranscript = nil
            // 새로 말하기 시작하면 지난 결과는 치운다(저장본은 그대로 남는다).
            result = nil
            operationState = .idle
            do {
                try await speech.start()
                startAnswerTimer()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 답변 60초 제한. 시간이 다 되면 녹음만 멈추고 검토 상태로 간다.
    private func startAnswerTimer() {
        timerTask?.cancel()
        remainingSeconds = Self.maxAnswerSeconds
        timerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remainingSeconds -= 1
            }
            guard let self, self.speech.isListening else { return }
            await self.finishRecording()
        }
    }

    /// 녹음을 멈추고 전사를 확정한다. 분석 요청은 하지 않는다.
    ///
    /// 오디오 파일은 여기서 버린다 — 코치는 전사만 보내고, 녹음 원본을 저장소에
    /// 쌓아 둘 이유가 없다.
    private func finishRecording(interruptedMessage: String? = nil) async {
        guard speech.isListening else { return }
        timerTask?.cancel()
        timerTask = nil
        do {
            let recording = try await speech.stop()
            AudioFileService.remove(recording.audioURL)
            pendingTranscript = recording.transcript
            errorMessage = interruptedMessage
        } catch {
            // 살릴 인식 결과가 없으면(무음 등) 솔직하게 다시 녹음하게 한다.
            // 전사 실패로 AI를 부르지도, 토큰을 쓰지도 않는다.
            pendingTranscript = nil
            errorMessage = error.localizedDescription
        }
    }

    private func handleRecordingInterruption() {
        Task { @MainActor [weak self] in
            await self?.finishRecording(
                interruptedMessage: "통화 등으로 녹음이 중단됐어요. 여기까지 인식된 내용을 분석하거나 다시 녹음해 주세요."
            )
        }
    }

    /// 다시 말해보기. 녹음도 전사도 토큰을 쓰지 않는다.
    func recordAgain() {
        speech.cancel()
        pendingTranscript = nil
        result = nil
        errorMessage = nil
        operationState = .idle
        remainingSeconds = Self.maxAnswerSeconds
    }

    /// 저장된 지난 코칭을 다시 연다. 0 토큰이다.
    func show(_ saved: VocabularySpeakingCoachResult) {
        result = saved
        pendingTranscript = nil
        operationState = .idle
    }

    // MARK: AI 코칭 (명시적 요청 1회 = 데일리 토큰 1개)

    /// 화면이 CTA를 누른 자리. 이미 돌고 있으면 아무 일도 하지 않는다 —
    /// 연타가 두 번째 조작(=두 번째 차감)이 되지 않게 여기서 막는다.
    func analyze() {
        guard !isAnalyzing, canAnalyze else { return }
        if let analysisTask { analysisTask.cancel() }
        errorMessage = nil
        analysisTask = Task { await run() }
    }

    private func run(allowRecovery: Bool = true) async {
        guard let transcript = pendingTranscript,
              VocabularySpeakingPrompt.isAnalyzable(transcript) else { return }
        // 같은 답변에 대한 코칭이 이미 있으면 그것을 보여준다. 같은 말을 두 번
        // 유료로 분석하지 않는다(다시 녹음했다가 결국 같은 말을 한 경우).
        if let saved = try? persistence.vocabularyCoachResult(
            entryID: entry.id,
            transcript: transcript
        ) {
            clearPendingOperation(for: transcript)
            result = saved
            pendingTranscript = nil
            operationState = .completed
            return
        }
        // 잔액이 0이면 서버도 AI도 부르지 않는다. 먼저 토큰을 확보해야 시작한다.
        if hasNoTokens {
            guard allowRecovery, await recoverToken() else { return }
        }
        // 요청을 보내기 **전에** 조작 신원을 디스크에 남긴다. 이 두 줄의 순서가 뒤집히면
        // 그 사이에 앱이 죽었을 때 신원을 잃고 같은 분석에 토큰이 또 나간다.
        let operationID = beginOperation(transcript: transcript)
        operationState = .running(operationId: operationID, startedAt: .now)
        let payload = VocabularySpeakingCoachRequest(
            entry: entry,
            transcript: transcript,
            targetLevel: targetLevel
        )
        do {
            let coaching = try await api.coachVocabulary(
                request: payload,
                requestID: operationID
            )
            // 결과를 먼저 durable하게 저장하고, 그 다음에야 조작을 닫는다. 순서가 반대면
            // 저장 직전에 앱이 죽었을 때 복구할 신원이 사라진다.
            try persistence.saveVocabularyCoachResult(coaching)
            reloadHistory()
            clearPendingOperation(for: transcript)
            usage = try? await api.usage()
            result = coaching
            pendingTranscript = nil
            operationState = .completed
        } catch is CancellationError {
            operationState = .idle
        } catch let error as APIClientError where error.isPracticeQuotaExhausted {
            // 서버와의 경합에서 졌다. 결과를 지어내지 않고 잔액을 다시 읽은 뒤 부족 UX로.
            usage = try? await api.usage()
            operationState = .idle
            // 복구는 한 번만 시도한다. 광고를 봐도 또 거절당하면 거기서 멈춘다.
            if allowRecovery, await recoverToken() {
                await run(allowRecovery: false)
            }
        } catch let error as APIClientError where error.isAIUnavailable {
            // 서버가 이미 환불했다. 같은 조작 id로 다시 시도할 수 있다.
            usage = try? await api.usage()
            operationState = .recoverableFailure(
                operationId: operationID,
                message: "코칭을 만들지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        } catch {
            usage = try? await api.usage()
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
    }

    /// 이 답변에 대한 조작 신원. 이미 시작해 둔 같은 조작이 있으면 **그것을 그대로 쓴다** —
    /// 재시도가 새 조작이 되면 이미 값을 치른 분석에 토큰이 또 나간다.
    ///
    /// 없으면 새로 만들어 **요청을 보내기 전에** 저장한다. 답변이 바뀌었으면 더 이상 같은
    /// 분석이 아니므로 새 신원이고, 재생 보장 창을 넘긴 기록도 새 신원이다(그 요청은
    /// 비용이 보이는 CTA를 사용자가 직접 누른 결과다).
    private func beginOperation(transcript: String) -> UUID {
        let operation = PendingVocabularyCoachOperation.resume(
            preferences.pendingVocabularyCoach,
            entryID: entry.id,
            transcript: transcript
        )
        preferences.pendingVocabularyCoach = operation
        return operation.operationID
    }

    /// 결과가 기기에 남은 뒤에만 부른다. 다른 답변의 기록까지 지우지 않는다.
    private func clearPendingOperation(for transcript: String) {
        guard let pending = preferences.pendingVocabularyCoach,
              pending.matches(entryID: entry.id, transcript: transcript) else { return }
        preferences.pendingVocabularyCoach = nil
    }

    /// 토큰 부족 복구. 새 세트 · 데일리 분석 · 맞춤 단어장이 쓰는 것과 **같은** 경로다:
    /// 무료는 광고 보너스 1개, 유료는 상위 플랜 안내. 단어장 전용 구매 경로는 없다.
    private func recoverToken() async -> Bool {
        guard !environment.currentPlan.isPaid else {
            presentPaywall(from: .tokenExhausted)
            return false
        }
        do {
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
            return (dailyTokenCount ?? 0) > 0
        } catch is CancellationError {
            return false
        } catch let error as APIClientError
            where error.isPracticeQuotaExhausted || error.isRewardQuotaExhausted {
            presentPaywall(from: .tokenExhausted)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func presentPaywall(from source: PaywallSource) {
        paywallSource = source
        showsPaywall = true
    }

    func cancelRecording() {
        timerTask?.cancel()
        timerTask = nil
        speech.cancel()
    }
}
