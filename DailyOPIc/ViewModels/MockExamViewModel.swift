import Foundation
import Observation

@MainActor
@Observable
final class MockExamViewModel {
    private struct EvaluationRetryContext {
        let rewardNonce: String
        let requestID: UUID
    }

    enum Phase: Equatable {
        case introduction
        case survey
        case loading
        case answering
        case adjustment
        case readyForReward
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

    var phase: Phase = .introduction
    var session: MockSession?
    var questionSet: QuestionSet?
    var answers: [RecordedAnswer] = []
    var currentIndex = 0
    var evaluation: MockEvaluation?
    var errorMessage: String?
    var surveyDraft: BackgroundSurvey
    var isApplyingAdjustment = false
    var remainingSeconds = 180
    var operationState: AsyncOperationState = .idle
    var operationKind: AsyncOperationKind = .dataLoading
    var usage: UsageStatus?
    private var evaluationRetryContext: EvaluationRetryContext?
    private var createOperationID: UUID?
    private var startOperationID: UUID?
    private var adjustmentOperationID: UUID?
    /// 이미 시청한 광고의 리워드 논스. 재시도에서 광고를 또 보게 하지 않으려고 들고 있는다.
    private var startRewardNonce: String?
    private var adjustmentRewardNonce: String?
    private var startTask: Task<Void, Never>?
    private var adjustmentTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        api = environment.api
        ads = environment.ads
        preferences = environment.preferences
        persistence = environment.persistence
        surveyDraft = environment.preferences.mockSurvey ?? .defaultSurvey
    }

    var plan: PlanEntitlement { environment.currentPlan }

    /// 오늘 남은 모의고사 횟수(서버 기준). nil이면 아직 미조회.
    var mockRemaining: Int? { usage?.mockRemaining }
    /// 오늘 모의고사 응시 가능 여부(진행 중이거나 남은 횟수 있음).
    var mockAvailable: Bool { usage?.mockAvailable ?? true }
    /// 하루 응시 한도(플랜별). intro 안내 문구용.
    var mockDailyLimit: Int { environment.capabilities?.quotaPolicy.mockSessionsPerDay ?? 1 }
    /// 무료 플랜은 '평생 최초 1회 체험'. 유료는 하루 N회.
    var mockIsTrial: Bool { !environment.currentPlan.isPaid }

    /// 모의고사 가용성/남은 횟수 최신화. 탭 진입·플랜 변경 시 호출.
    func refreshUsage() async {
        usage = try? await api.usage()
    }

    /// 모의고사 광고 게이트용 리워드 논스 획득.
    /// 무료 플랜은 리워드 광고를 시청하고, 유료 플랜은 서버 auto-verify로 광고 없이 통과.
    private func acquireRewardNonce(
        purpose: RewardPurpose,
        sessionHash: String?
    ) async throws -> String {
        let intent = try await api.createRewardIntent(
            purpose: purpose,
            sessionHash: sessionHash,
            requestID: UUID()
        )
        if environment.currentPlan.isPaid {
            return intent.nonce
        }
        try await ads.showRewardedAd(
            userIdentifier: intent.userIdentifier,
            customData: intent.customData
        )
        _ = try await api.waitForReward(nonce: intent.nonce)
        return intent.nonce
    }

    var initialLevel: SelfAssessmentLevel { preferences.initialLevel ?? .level5 }
    var targetLevel: OPIcLevel { questionSet?.expectedTargetLevel ?? preferences.targetLevel ?? .IM2 }
    var currentQuestion: GeneratedQuestion? { questionSet?.questions[safe: currentIndex] }
    var expectedQuestionCount: Int { questionSet?.questions.count ?? 15 }
    var progress: Double { Double(answers.count) / Double(max(1, expectedQuestionCount)) }
    var savedSurvey: BackgroundSurvey? { preferences.mockSurvey }
    var canRetryEvaluation: Bool { evaluationRetryContext != nil }

    /// 서버가 아직 닫지 않은 오늘 회차가 있는가.
    private var hasOpenSession: Bool {
        guard let session else { return false }
        return session.stage != .completed
    }

    /// True when we're sitting on the intro but the server has an in-progress
    /// session — used to show an explicit "이어서 하기" button.
    ///
    /// setId가 없는 회차(awaiting_start_ad·generating_front)는 "이어서" 할 문제가
    /// 아직 존재하지 않는다. 이때 이어서 하기만 노출하면 영원히 실패하는 버튼만
    /// 남으므로, 시작 버튼을 그대로 보여주고 startNewExam이 같은 회차를 이어받게 한다.
    var canResume: Bool {
        phase == .introduction && hasOpenSession && session?.setId != nil
    }

    /// 진행 중인 회차가 있으면 언제나 포기할 수 있어야 한다. 문제를 못 불러온
    /// 회차(questionSet == nil)도 포함해야 막다른 길이 생기지 않는다.
    var canAbandon: Bool {
        phase != .completed && (questionSet != nil || !answers.isEmpty || hasOpenSession)
    }

    func restoreDraftIfAvailable() async {
        guard questionSet == nil else { return }
        if let current = try? await api.currentMockSession() {
            session = current
            if current.stage == .completed {
                // 서버가 이미 마감한 회차의 로컬 초안은 지운다. 남겨두면 다음
                // 오프라인 실행에서 끝난 시험이 되살아난다.
                if let draft = try? persistence.latestDraft() {
                    AudioFileService.removeAll(draft.answers)
                }
                try? persistence.clearDraft()
                errorMessage = "오늘 모의고사를 이미 완료했어요. 내일 새 모의고사가 열려요."
                return
            }
            await enterResume(current)
            return
        }
        // Offline fallback: resume purely from a valid local draft.
        guard let draft = try? persistence.latestDraft() else { return }
        guard draft.updatedAt >= Date.now.addingTimeInterval(-86_400),
              let draftSet = draft.questionSet else {
            AudioFileService.removeAll(draft.answers)
            try? persistence.clearDraft()
            return
        }
        restore(set: draftSet, from: draft.answers)
    }

    /// Continue an in-progress server session. Recovers locally-saved answers when
    /// a matching draft exists; otherwise resumes from the server's question set
    /// (previously recorded audio can't be recovered, e.g. after reinstall).
    func resume() async {
        var current = session
        if current == nil { current = try? await api.currentMockSession() }
        guard let session = current else {
            errorMessage = "이어서 진행할 모의고사를 찾지 못했어요."
            return
        }
        self.session = session
        guard session.stage != .completed else {
            errorMessage = "오늘 모의고사를 이미 완료했어요. 내일 새 모의고사가 열려요."
            return
        }
        await enterResume(session)
    }

    private func enterResume(_ session: MockSession) async {
        var set = session.questionSet
        if set == nil, session.setId != nil {
            set = (try? await api.currentMockSession())?.questionSet
        }
        guard let set else {
            phase = .introduction
            // 아직 문제가 만들어지지 않은 회차(광고 대기)는 오류가 아니다.
            // 시작 버튼이 그대로 노출되고 startNewExam이 같은 회차를 이어받는다.
            errorMessage = session.setId == nil
                ? nil
                : "이어서 진행할 문제를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
            return
        }
        var recovered: [RecordedAnswer] = []
        if let draft = try? persistence.latestDraft(),
           draft.updatedAt >= Date.now.addingTimeInterval(-86_400),
           let ds = draft.questionSet,
           ds.setId == set.setId, ds.setHash == set.setHash {
            recovered = draft.answers
        }
        restore(set: set, from: recovered)
    }

    /// Shared restore: install the set, keep only valid recovered answers, and pick
    /// the resume phase from how far along the answers are.
    private func restore(set: QuestionSet, from rawAnswers: [RecordedAnswer]) {
        let validAnswers = rawAnswers
            .filter { FileManager.default.fileExists(atPath: $0.audioPath) }
            .filter { (1...15).contains($0.number) }
            .filter { number in set.questions.contains { $0.number == number.number } }
        questionSet = set
        answers = Dictionary(grouping: validAnswers, by: \.number)
            .compactMap { $0.value.first }
            .sorted { $0.number < $1.number }
        currentIndex = min(answers.count, max(0, set.questions.count - 1))
        errorMessage = nil
        if !set.isComplete, answers.count >= (set.requiresAdjustmentAfter ?? 7) {
            phase = .adjustment
        } else {
            phase = answers.count == 15 ? .readyForReward : .answering
        }
        try? persistence.saveDraft(targetLevel: targetLevel, questionSet: set, answers: answers)
    }

    func showSurvey() {
        surveyDraft = preferences.mockSurvey ?? .defaultSurvey
        errorMessage = nil
        phase = .survey
    }

    func startWithSavedSurvey() async {
        await startNewExam(survey: preferences.mockSurvey ?? .defaultSurvey)
    }

    func startNewExam(survey: BackgroundSurvey) async {
        guard survey.isValid else {
            errorMessage = "상태와 거주 형태를 선택하고 관심 주제를 3개 이상 선택해 주세요."
            phase = .survey
            return
        }
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart(survey: survey)
        }
        startTask = task
        await task.value
        // 그 사이 포기로 취소돼 새 작업이 들어왔다면 그것을 지우면 안 된다.
        if startTask == task { startTask = nil }
    }

    private func performStart(survey: BackgroundSurvey) async {
        phase = .loading
        operationKind = .questionGeneration
        let operationID = startOperationID ?? UUID()
        startOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        errorMessage = nil
        evaluationRetryContext = nil
        let createID = createOperationID ?? UUID()
        createOperationID = createID
        do {
            preferences.mockSurvey = survey
            let session = try await api.createMockSession(
                request: QuestionSetRequest(
                    initialLevel: initialLevel,
                    background: preferences.backgroundProfile,
                    survey: survey
                ),
                requestID: createID
            )
            // An in-progress session already exists today → resume it instead of
            // dead-ending with a 409 error banner.
            guard session.stage == .awaitingStartAd else {
                self.session = session
                await enterResume(session)
                operationState = .completed
                createOperationID = nil
                startOperationID = nil
                return
            }
            // 재시도라면 이미 본 광고의 논스를 그대로 쓴다. 서버는 실패한 요청의
            // 논스를 consumed=false로 되돌리므로 재사용이 정상 경로이고,
            // 정말 못 쓰는 논스면 402로 내려와 아래에서 버린다.
            let rewardNonce: String
            if let cached = startRewardNonce {
                rewardNonce = cached
            } else {
                rewardNonce = try await acquireRewardNonce(
                    purpose: .mockStart,
                    sessionHash: session.sessionHash
                )
                startRewardNonce = rewardNonce
            }
            let started = try await api.startMockSession(
                sessionId: session.sessionId,
                rewardNonce: rewardNonce,
                requestID: operationID
            )
            // 마지막 await 이후 포기가 들어왔을 수 있다. 정리된 화면을 되살리지 않는다.
            guard !Task.isCancelled else {
                operationState = .idle
                return
            }
            guard let set = started.questionSet else {
                throw APIClientError.invalidResponse
            }
            set.logDebugSummary(mode: "mock")
            self.session = started
            questionSet = set
            answers = []
            currentIndex = 0
            evaluation = nil
            evaluationRetryContext = nil
            try persistence.saveDraft(targetLevel: targetLevel, questionSet: set, answers: [])
            phase = .answering
            operationState = .completed
            createOperationID = nil
            startOperationID = nil
            startRewardNonce = nil
        } catch {
            // 포기(resetExam)로 취소된 경우엔 이미 정리된 화면을 덮어쓰지 않는다.
            guard !Task.isCancelled else {
                operationState = .idle
                return
            }
            // 서버가 논스를 거부했으면 재사용해도 계속 실패한다. 그때만 광고를 다시 본다.
            if (error as? APIClientError)?.isRewardRequired == true { startRewardNonce = nil }
            phase = .introduction
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
    }

    func toggleRecording() async {
        errorMessage = nil
        if speech.isListening {
            do {
                timerTask?.cancel()
                let result = try await speech.stop()
                saveAnswer(result)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                promptPlayback.stop()
                try await speech.start()
                startAnswerTimer()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func playPrompt() {
        guard let currentQuestion else { return }
        promptPlayback.play(currentQuestion)
    }

    private func startAnswerTimer() {
        timerTask?.cancel()
        remainingSeconds = 180
        timerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remainingSeconds -= 1
            }
            guard let self, self.speech.isListening else { return }
            await self.toggleRecording()
        }
    }

    private func saveAnswer(_ result: SpeechRecordingResult) {
        guard let question = currentQuestion, let questionSet else { return }
        evaluationRetryContext = nil
        if let existing = answers.first(where: { $0.number == question.number }) {
            AudioFileService.remove(existing.audioURL)
        }
        answers.removeAll { $0.number == question.number }
        let persistedURL = (try? AudioFileService.persistMockAnswer(
            result.audioURL,
            sessionID: session?.sessionId ?? questionSet.setId,
            questionNumber: question.number
        )) ?? result.audioURL
        answers.append(
            RecordedAnswer(
                number: question.number,
                transcript: result.transcript,
                audioPath: persistedURL.path
            )
        )
        answers.sort { $0.number < $1.number }
        try? persistence.saveDraft(
            targetLevel: targetLevel,
            questionSet: questionSet,
            answers: answers
        )
        if questionSet.requiresAdjustmentAfter == question.number,
           !questionSet.isComplete {
            phase = .adjustment
        } else if answers.count == 15 {
            phase = .readyForReward
        } else {
            currentIndex = min(currentIndex + 1, max(0, questionSet.questions.count - 1))
        }
    }

    func previousQuestion() { }

    func evaluateAfterReward() async {
        // 조용히 return하면 "결과보기"가 죽은 버튼이 된다.
        guard let questionSet, answers.count == 15 else {
            errorMessage = Self.incompleteAnswersMessage
            return
        }
        if let evaluationTask {
            await evaluationTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performEvaluationGate(questionSet: questionSet)
        }
        evaluationTask = task
        await task.value
        if evaluationTask == task { evaluationTask = nil }
    }

    /// 오프라인 초안으로 복원했을 때는 session이 비어 있다. 채점 전에 반드시 복구해야
    /// 광고만 소비하고 아무 일도 못 하는 상태가 생기지 않는다.
    private func resolvedSession() async -> MockSession? {
        if let session { return session }
        session = try? await api.currentMockSession()
        return session
    }

    private static let missingSessionMessage =
        "모의고사 회차를 찾지 못했어요. 네트워크를 확인하고 다시 시도해 주세요."
    private static let incompleteAnswersMessage =
        "답변 15개를 모두 확인하지 못했어요. 모의고사를 다시 시작해 주세요."

    private func performEvaluationGate(questionSet: QuestionSet) async {
        errorMessage = nil
        if let evaluationRetryContext {
            await submitEvaluation(context: evaluationRetryContext)
            return
        }
        // 광고를 보여주기 전에 회차부터 확인한다.
        guard await resolvedSession() != nil else {
            phase = .readyForReward
            errorMessage = Self.missingSessionMessage
            return
        }
        do {
            let rewardNonce = try await acquireRewardNonce(
                purpose: .mockResult,
                sessionHash: session?.sessionHash ?? questionSet.setHash
            )
            let context = EvaluationRetryContext(
                rewardNonce: rewardNonce,
                requestID: UUID()
            )
            evaluationRetryContext = context
            await submitEvaluation(context: context)
        } catch {
            phase = .readyForReward
            errorMessage = error.localizedDescription
        }
    }

    func retryEvaluation() async {
        guard let evaluationRetryContext else {
            await evaluateAfterReward()
            return
        }
        await submitEvaluation(context: evaluationRetryContext)
    }

    private func submitEvaluation(context: EvaluationRetryContext) async {
        // 여기서 조용히 return하면 "다시 시도" 버튼이 아무 일도 하지 않는 죽은 버튼이 된다.
        guard let questionSet, answers.count == 15 else {
            phase = .readyForReward
            errorMessage = Self.incompleteAnswersMessage
            return
        }
        guard let session = await resolvedSession() else {
            phase = .readyForReward
            errorMessage = Self.missingSessionMessage
            return
        }
        phase = .analyzing
        operationKind = .mockResult
        operationState = .running(operationId: context.requestID, startedAt: .now)
        errorMessage = nil
        do {
            let result = try await api.evaluateMock(
                sessionId: session.sessionId,
                questionSet: questionSet,
                answers: answers,
                targetLevel: targetLevel,
                rewardNonce: context.rewardNonce,
                requestID: context.requestID
            )
            guard !Task.isCancelled else {
                operationState = .idle
                return
            }
            evaluation = result
            try persistence.saveMock(
                targetLevel: targetLevel,
                questionSet: questionSet,
                answers: answers,
                evaluation: result
            )
            AudioFileService.removeAll(answers)
            evaluationRetryContext = nil
            phase = .completed
            operationState = .completed
        } catch let error as APIClientError where error.isAIUnavailable {
            phase = .readyForReward
            operationState = .recoverableFailure(
                operationId: context.requestID,
                message: error.localizedDescription
            )
            errorMessage = "AI 평가 생성에 실패했습니다. 같은 답변으로 다시 시도해 주세요."
        } catch let error as APIClientError where error.isRewardRequired {
            evaluationRetryContext = nil
            phase = .readyForReward
            errorMessage = error.localizedDescription
        } catch {
            guard !Task.isCancelled else {
                operationState = .idle
                return
            }
            phase = .readyForReward
            errorMessage = error.localizedDescription
        }
    }

    /// 진행 중인 작업을 모두 멈춘다. 남겨두면 포기한 뒤에 뒤늦게 끝난 요청이
    /// phase·evaluation을 되살려 화면이 뒤집힌다.
    private func cancelPendingOperations() {
        timerTask?.cancel()
        timerTask = nil
        startTask?.cancel()
        startTask = nil
        adjustmentTask?.cancel()
        adjustmentTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        operationState = .idle
    }

    func resetExam() {
        let abandoned = session
        cancelPendingOperations()
        speech.cancel()
        promptPlayback.stop()
        AudioFileService.removeAll(answers)
        if let abandoned { AudioFileService.removeMockSession(sessionID: abandoned.sessionId) }
        try? persistence.clearDraft()
        questionSet = nil
        session = nil
        answers = []
        currentIndex = 0
        evaluation = nil
        // 포기는 응시 한도를 쓰지 않는다. "내일"이라고 안내하면 사실과 다르다.
        errorMessage = abandoned != nil ? "모의고사를 그만뒀어요. 준비되면 새로 시작할 수 있어요." : nil
        evaluationRetryContext = nil
        createOperationID = nil
        startOperationID = nil
        adjustmentOperationID = nil
        // 이미 소비한 광고 기회는 복구하지 않는다. 논스만 버린다.
        startRewardNonce = nil
        adjustmentRewardNonce = nil
        phase = .introduction
        // 회차 소유권은 서버에 있다. 로컬만 지우면 다음 /current 조회에서
        // 같은 회차가 되살아나 "그만뒀다"는 안내와 어긋난다.
        guard let abandoned, abandoned.stage != .completed else { return }
        Task { @MainActor [weak self] in
            _ = try? await self?.api.abandonMockSession(sessionId: abandoned.sessionId)
            await self?.refreshUsage()
        }
    }

    /// 결과 확인 후 처음(intro) 화면으로 돌아간다. 그만두기와 달리 긍정 안내를 표시.
    func finishReview() {
        cancelPendingOperations()
        speech.cancel()
        promptPlayback.stop()
        questionSet = nil
        session = nil
        answers = []
        currentIndex = 0
        evaluation = nil
        evaluationRetryContext = nil
        errorMessage = nil
        phase = .introduction
    }

    func applyAdjustment(_ adjustment: DifficultyAdjustment) async {
        guard let questionSet else { return }
        // 오프라인 초안으로 복원하면 session이 비어 있다. 그대로 return하면
        // 난이도 선택 버튼이 죽은 버튼이 되므로 먼저 회차를 복구한다.
        guard let session = await resolvedSession() else {
            errorMessage = Self.missingSessionMessage
            return
        }
        if let adjustmentTask {
            await adjustmentTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAdjustment(
                adjustment,
                questionSet: questionSet,
                session: session
            )
        }
        adjustmentTask = task
        await task.value
        if adjustmentTask == task { adjustmentTask = nil }
    }

    private func performAdjustment(
        _ adjustment: DifficultyAdjustment,
        questionSet: QuestionSet,
        session: MockSession
    ) async {
        isApplyingAdjustment = true
        operationKind = .difficultyAdjustment
        let operationID = adjustmentOperationID ?? UUID()
        adjustmentOperationID = operationID
        operationState = .running(operationId: operationID, startedAt: .now)
        errorMessage = nil
        do {
            // 시작과 같은 규칙: 이미 본 광고의 논스를 재사용하고, 서버가 거부할 때만 새로 받는다.
            let rewardNonce: String
            if let cached = adjustmentRewardNonce {
                rewardNonce = cached
            } else {
                rewardNonce = try await acquireRewardNonce(
                    purpose: .mockAdjustment,
                    sessionHash: session.sessionHash
                )
                adjustmentRewardNonce = rewardNonce
            }
            let adjustedSession = try await api.adjustMockSession(
                sessionId: session.sessionId,
                adjustment: adjustment,
                rewardNonce: rewardNonce,
                requestID: operationID
            )
            guard !Task.isCancelled else {
                operationState = .idle
                isApplyingAdjustment = false
                return
            }
            guard let updated = adjustedSession.questionSet else {
                throw APIClientError.invalidResponse
            }
            updated.logDebugSummary(mode: "mock")
            self.session = adjustedSession
            self.questionSet = updated
            evaluationRetryContext = nil
            currentIndex = min(answers.count, max(0, updated.questions.count - 1))
            try? persistence.saveDraft(
                targetLevel: updated.expectedTargetLevel,
                questionSet: updated,
                answers: answers
            )
            phase = .answering
            operationState = .completed
            adjustmentOperationID = nil
            adjustmentRewardNonce = nil
        } catch {
            guard !Task.isCancelled else {
                operationState = .idle
                isApplyingAdjustment = false
                return
            }
            if (error as? APIClientError)?.isRewardRequired == true {
                adjustmentRewardNonce = nil
            }
            errorMessage = error.localizedDescription
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
        isApplyingAdjustment = false
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
