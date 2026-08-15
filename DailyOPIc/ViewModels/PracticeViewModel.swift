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
    let promptPlayback = PromptPlaybackService()
    private let api: APIClient
    private let ads: AdService
    private let preferences: AppPreferences
    private let persistence: PersistenceService
    private let environment: AppEnvironment
    /// 유료 플랜 한도 소진 등 결제 유도가 필요할 때 true.
    var showsPaywall = false
    /// 페이월을 연 지점(분석 전용). `showsPaywall`을 직접 켜지 말고 `presentPaywall(from:)`을 쓴다.
    private(set) var paywallSource: PaywallSource = .settings

    func presentPaywall(from source: PaywallSource) {
        paywallSource = source
        showsPaywall = true
    }

    var phase: Phase = .loading
    var questionSet: QuestionSet?
    var questionIndex = 0
    var usage: UsageStatus?
    var evaluation: PracticeEvaluation?
    var evaluatedTranscript = ""
    var errorMessage: String?
    var pendingRecording: SpeechRecordingResult?
    /// 답변 최대 180초. 모의고사와 같은 제한을 연습에도 적용한다.
    var remainingSeconds = PracticeViewModel.maxAnswerSeconds
    static let maxAnswerSeconds = 180
    var showsRefreshDialog = false
    var isRefreshingQuestions = false
    var refreshProgressMessage: String?
    var operationState: AsyncOperationState = .idle
    var operationKind: AsyncOperationKind = .dataLoading
    /// 현재 세트를 만들 때 사용한 자가진단 난이도. 설정에서 난이도를 바꾸면
    /// "난이도를 바꾸면 지금 질문이 새로 만들어져요"라는 약속대로 세트를 다시
    /// 받아야 한다. 예전에는 난이도 재선택이 루트 분기를 바꿔 ViewModel이 통째로
    /// 사라지면서 우연히 처리됐지만, 이제 세션이 살아남으므로 명시적으로 비교한다.
    private var loadedInitialLevel: SelfAssessmentLevel?
    private var loadTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var loadOperationID = UUID()
    private var evaluationOperationID: UUID?
    private var refreshOperationID: UUID?

    init(environment: AppEnvironment) {
        self.environment = environment
        api = environment.api
        ads = environment.ads
        preferences = environment.preferences
        persistence = environment.persistence
        speech.onInterruption = { [weak self] in self?.handleRecordingInterruption() }
    }

    var plan: PlanEntitlement { environment.currentPlan }

    var initialLevel: SelfAssessmentLevel { preferences.initialLevel ?? .level5 }
    var targetLevel: OPIcLevel { questionSet?.expectedTargetLevel ?? preferences.targetLevel ?? .IM2 }
    var currentQuestion: GeneratedQuestion? {
        guard let questions = questionSet?.questions, !questions.isEmpty else { return nil }
        return questions[min(questionIndex, questions.count - 1)]
    }
    var dailyTokenCount: Int? { usage?.totalRemaining }

    /// Analysis result for a single question, kept so the user can navigate back
    /// to an already-analyzed question and see its saved result (read-only).
    struct AnalyzedResult {
        let evaluation: PracticeEvaluation
        let transcript: String
    }
    private var analyzedResults: [Int: AnalyzedResult] = [:]

    var questionCount: Int { questionSet?.questions.count ?? 0 }
    var analyzedNumbers: Set<Int> { Set(analyzedResults.keys) }
    func isAnalyzed(_ number: Int) -> Bool { analyzedResults[number] != nil }
    /// 진행바 등에서 사용할 실제 문항 번호(데일리는 Q2~Q15). 인덱스+1이 아님.
    func questionNumber(at index: Int) -> Int? {
        guard let questions = questionSet?.questions, questions.indices.contains(index) else {
            return nil
        }
        return questions[index].number
    }

    /// 사용량(토큰) 재조회. 플랜 변경·탭 재진입·포그라운드 복귀 시 호출.
    func refreshUsage() async {
        usage = try? await api.usage()
    }
    /// Saved result for the currently displayed question, if it was analyzed.
    var currentResult: AnalyzedResult? {
        guard let number = currentQuestion?.number else { return nil }
        return analyzedResults[number]
    }
    var canGoPrevious: Bool { questionIndex > 0 }
    var canGoNext: Bool { questionIndex < max(0, questionCount - 1) }

    func goToQuestion(_ index: Int) {
        guard index >= 0, index < questionCount, index != questionIndex else { return }
        clearTransientAnswerState()
        questionIndex = index
        phase = .idle
    }

    func goToPrevious() {
        guard canGoPrevious else { return }
        goToQuestion(questionIndex - 1)
    }

    func goToNext() {
        if canGoNext {
            goToQuestion(questionIndex + 1)
        } else if questionCount > 0 {
            // Past the last question → offer a fresh set via the refresh dialog.
            showsRefreshDialog = true
        }
    }

    private func clearTransientAnswerState() {
        timerTask?.cancel()
        timerTask = nil
        remainingSeconds = Self.maxAnswerSeconds
        speech.cancel()
        promptPlayback.stop()
        AudioFileService.remove(pendingRecording?.audioURL)
        pendingRecording = nil
        errorMessage = nil
    }

    func load() async {
        if let loadedInitialLevel, loadedInitialLevel != initialLevel {
            await reloadQuestions()
            return
        }
        guard questionSet == nil else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        phase = .loading
        operationKind = .dataLoading
        operationState = .running(operationId: loadOperationID, startedAt: .now)
        errorMessage = nil
        do {
            async let usageTask = api.usage()
            async let setTask = api.createPracticeSet(
                request: QuestionSetRequest(
                    initialLevel: initialLevel,
                    background: preferences.backgroundProfile,
                    survey: preferences.mockSurvey ?? .defaultSurvey
                ),
                requestID: loadOperationID
            )
            usage = try await usageTask
            let set = try await setTask
            set.logDebugSummary(mode: "practice")
            questionSet = set
            loadedInitialLevel = initialLevel
            phase = .idle
            operationState = .completed
            loadOperationID = UUID()
        } catch is CancellationError {
            phase = .idle
            operationState = .idle
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: loadOperationID,
                message: error.localizedDescription
            )
        }
    }

    func playPrompt() {
        guard let currentQuestion else { return }
        promptPlayback.play(currentQuestion)
    }

    func toggleRecording() async {
        errorMessage = nil
        if speech.isListening {
            // 녹음 종료는 제출이 아니다. 검토 상태(pendingRecording)로만 넘어가고,
            // AI 분석은 사용자가 "분석하기"를 눌러야 시작한다.
            await finishRecording()
        } else {
            promptPlayback.stop()
            // 검토 중인 녹음을 두고 다시 녹음하면 그건 재녹음이다. 임시 파일을 정리한다.
            AudioFileService.remove(pendingRecording?.audioURL)
            pendingRecording = nil
            do {
                try await speech.start()
                startAnswerTimer()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 답변 180초 제한. 시간이 다 되면 녹음만 멈추고 검토 상태로 간다.
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
            // 시간이 다 돼도 제출은 하지 않는다. 검토 후 사용자가 분석을 누른다.
            await self.finishRecording()
        }
    }

    /// 녹음을 멈추고 인식 결과를 확정한다. 분석 요청은 하지 않는다.
    private func finishRecording(interruptedMessage: String? = nil) async {
        guard speech.isListening else { return }
        timerTask?.cancel()
        timerTask = nil
        do {
            pendingRecording = try await speech.stop()
            errorMessage = interruptedMessage
        } catch {
            // 살릴 인식 결과가 없으면(무음 등) 솔직하게 다시 녹음하게 한다.
            pendingRecording = nil
            errorMessage = error.localizedDescription
        }
    }

    /// 시스템 오디오 중단(전화 등). 여기까지 인식된 답변을 살려 검토 상태로 보낸다.
    /// AVAudioEngine 세션은 이어붙일 수 없으므로 "이어서 녹음"은 제공하지 않는다.
    private func handleRecordingInterruption() {
        Task { @MainActor [weak self] in
            await self?.finishRecording(
                interruptedMessage: "통화 등으로 녹음이 중단됐어요. 여기까지 인식된 답변을 분석하거나 다시 녹음해 주세요."
            )
        }
    }

    /// 검토한 답변을 AI 분석에 보낸다. "분석하기"와 "분석 다시 시도"가 같은 경로다.
    func analyzePendingRecording() async {
        if let evaluationTask {
            await evaluationTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            do { try await self?.evaluatePendingRecording() }
            catch is CancellationError { }
            catch { self?.errorMessage = error.localizedDescription }
        }
        evaluationTask = task
        await task.value
        evaluationTask = nil
    }

    /// 다시 녹음. 분석 요청도, 새 질문 요청도 하지 않으므로 토큰이 소모되지 않는다.
    func discardPendingRecording() {
        AudioFileService.remove(pendingRecording?.audioURL)
        pendingRecording = nil
        // 인식 텍스트를 비워 이전 답변이 새 녹음 화면에 남지 않게 한다.
        speech.cancel()
        errorMessage = nil
        remainingSeconds = Self.maxAnswerSeconds
        phase = .idle
    }

    private func evaluatePendingRecording() async throws {
        guard let pendingRecording, let questionSet, let question = currentQuestion else { return }
        // 토큰 모델: 토큰은 세트를 받을 때 소모되고, 세트 내 평가는 무제한. 여기서 쿼터 확인하지 않음.
        phase = .analyzing
        operationKind = .speechAnalysis
        let operationID = evaluationOperationID ?? UUID()
        evaluationOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        do {
            let result = try await api.evaluatePractice(
                questionSet: questionSet,
                questionNumber: question.number,
                transcript: pendingRecording.transcript,
                targetLevel: targetLevel,
                audioURL: pendingRecording.audioURL,
                requestID: operationID
            )
            evaluation = result
            evaluatedTranscript = pendingRecording.transcript
            analyzedResults[question.number] = AnalyzedResult(
                evaluation: result,
                transcript: pendingRecording.transcript
            )
            try persistence.savePractice(
                targetLevel: targetLevel,
                question: question,
                transcript: pendingRecording.transcript,
                evaluation: result
            )
            // 캘린더 완료 집계. 세트를 받은 것이 아니라 분석이 성공한 순간에 센다.
            // 세트당 한 번만 기록되므로 재분석·결과 재진입은 중복되지 않는다.
            // 기록 실패가 학습 흐름을 막아선 안 되므로 오류는 삼킨다.
            _ = try? persistence.recordStudySetCompletion(setId: questionSet.setId)
            AudioFileService.remove(pendingRecording.audioURL)
            self.pendingRecording = nil
            usage = try? await api.usage()
            phase = .completed
            operationState = .completed
            evaluationOperationID = nil
        } catch is CancellationError {
            phase = .idle
            operationState = .idle
            throw CancellationError()
        } catch {
            phase = .idle
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
            throw error
        }
    }

    private func unlockPracticeCredits() async throws {
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
        goToNext()
    }

    func reloadQuestions() async {
        questionSet = nil
        loadedInitialLevel = nil
        questionIndex = 0
        analyzedResults = [:]
        evaluation = nil
        showsRefreshDialog = false
        refreshProgressMessage = nil
        await load()
    }

    func refreshQuestions(adjustment: DifficultyAdjustment) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(adjustment: adjustment)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(adjustment: DifficultyAdjustment) async {
        isRefreshingQuestions = true
        operationKind = .questionGeneration
        let operationID = refreshOperationID ?? UUID()
        refreshOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        refreshProgressMessage = "새 질문을 준비하고 있어요."
        errorMessage = nil
        do {
            // 토큰 모델: 새 문제 세트 = 토큰 1개. 광고/리워드 없이 바로 요청.
            let updated = try await requestRefreshedSet(
                adjustment: adjustment,
                operationID: operationID
            )
            applyRefreshedQuestionSet(updated)
            operationState = .completed
            refreshOperationID = nil
        } catch is CancellationError {
            operationState = .idle
        } catch let error as APIClientError where error.isPracticeQuotaExhausted {
            await handleRefreshQuotaExhausted(adjustment: adjustment)
        } catch {
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
        refreshProgressMessage = nil
        isRefreshingQuestions = false
    }

    /// 토큰 소진 시: 무료는 광고 보너스 세트로 재시도, 유료는 상위 플랜 결제 유도.
    private func handleRefreshQuotaExhausted(adjustment: DifficultyAdjustment) async {
        guard !environment.currentPlan.isPaid else {
            showsRefreshDialog = false
            presentPaywall(from: .tokenExhausted)
            operationState = .idle
            return
        }
        do {
            try await unlockPracticeCredits()  // 광고 → 보너스 세트 토큰
            let updated = try await requestRefreshedSet(
                adjustment: adjustment,
                operationID: UUID()  // 재시도는 새 idempotency key
            )
            applyRefreshedQuestionSet(updated)
            operationState = .completed
            refreshOperationID = nil
        } catch is CancellationError {
            operationState = .idle
        } catch let error as APIClientError
            where error.isPracticeQuotaExhausted || error.isRewardQuotaExhausted {
            // 광고 보너스까지 소진. 지금 세트는 그대로 두고 상위 플랜 안내로 넘긴다.
            showsRefreshDialog = false
            presentPaywall(from: .tokenExhausted)
            operationState = .idle
        } catch {
            errorMessage = error.localizedDescription
            operationState = .idle
        }
    }

    private func requestRefreshedSet(
        adjustment: DifficultyAdjustment,
        operationID: UUID
    ) async throws -> QuestionSet {
        refreshProgressMessage = "새 질문을 준비하고 있어요."
        let updated = try await api.refreshPracticeSet(
            request: PracticeRefreshRequest(
                initialLevel: initialLevel,
                background: preferences.backgroundProfile,
                survey: preferences.mockSurvey ?? .defaultSurvey,
                adjustment: adjustment
            ),
            requestID: operationID
        )
        usage = try? await api.usage()
        return updated
    }

    private func applyRefreshedQuestionSet(_ updated: QuestionSet) {
        updated.logDebugSummary(mode: "practice")
        questionSet = updated
        loadedInitialLevel = initialLevel
        questionIndex = 0
        analyzedResults = [:]
        showsRefreshDialog = false
        evaluation = nil
        evaluatedTranscript = ""
        pendingRecording = nil
        phase = .idle
    }
}
