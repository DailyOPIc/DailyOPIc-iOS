import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case rewardRequired(status: Int, code: String?, message: String)
    case server(status: Int, code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "서버 응답을 확인할 수 없습니다."
        case let .rewardRequired(_, _, message):
            message
        case let .server(_, code, message):
            // 오디오 검증 실패는 서버가 영어 원문("audio file is too large")을
            // 내려준다. 사용자에게는 다음에 뭘 하면 되는지만 보여준다.
            code == "invalid_audio" ? "녹음 파일을 처리할 수 없어요. 다시 녹음해 주세요." : message
        }
    }

    var code: String? {
        if case let .rewardRequired(_, code, _) = self { return code }
        if case let .server(_, code, _) = self { return code }
        return nil
    }

    var statusCode: Int? {
        if case let .rewardRequired(status, _, _) = self { return status }
        if case let .server(status, _, _) = self { return status }
        return nil
    }

    var isRewardRequired: Bool {
        if case .rewardRequired = self { return true }
        return false
    }

    var isTargetLevelChangeRewardRequired: Bool {
        isRewardRequired && code == "target_level_change_reward_required"
    }

    var isPracticeQuotaExhausted: Bool {
        statusCode == 402 && code == "practice_quota_exhausted"
    }

    var isRewardQuotaExhausted: Bool {
        statusCode == 402 && code == "reward_quota_exhausted"
    }

    var isAIUnavailable: Bool {
        statusCode == 503 && code == "ai_unavailable"
    }
}

actor APIClient {
    enum RequestTimeout {
        static let read: TimeInterval = 15
        static let generation: TimeInterval = 90
        static let evaluation: TimeInterval = 180
        static let rewardVerification: TimeInterval = 60
    }
    private let baseURL: URL
    private let session: URLSession
    private let authentication: AuthenticationService
    private let encoder = JSONCoding.encoder
    private let decoder = JSONCoding.decoder

    init(
        baseURL: URL = AppConfiguration.apiBaseURL,
        session: URLSession = .shared,
        authentication: AuthenticationService
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authentication = authentication
    }

    func capabilities() async throws -> Capabilities {
        try await send(path: "/v1/capabilities", method: "GET", body: nil)
    }

    func createPracticeSet(
        request payload: QuestionSetRequest,
        requestID: UUID
    ) async throws -> QuestionSet {
        try await sendJSON(
            path: "/v1/question-sets/practice",
            method: "POST",
            body: payload,
            requestID: requestID,
            timeout: RequestTimeout.generation
        )
    }

    func refreshPracticeSet(
        request payload: PracticeRefreshRequest,
        requestID: UUID
    ) async throws -> QuestionSet {
        try await sendJSON(
            path: "/v1/question-sets/practice/refresh",
            method: "POST",
            body: payload,
            requestID: requestID,
            timeout: RequestTimeout.generation
        )
    }

    func createMockSession(
        request payload: QuestionSetRequest,
        requestID: UUID
    ) async throws -> MockSession {
        try await sendJSON(
            path: "/v1/mock-exams/sessions",
            method: "POST",
            body: payload,
            requestID: requestID,
            timeout: RequestTimeout.read
        )
    }

    func currentMockSession() async throws -> MockSession {
        try await send(path: "/v1/mock-exams/current", method: "GET", body: nil)
    }

    /// 진행 중인 회차를 서버에서도 닫는다. 이미 닫힌 회차에 다시 호출해도 안전하다.
    func abandonMockSession(sessionId: String) async throws -> MockSession {
        try await send(path: "/v1/mock-exams/\(sessionId)/abandon", method: "POST", body: nil)
    }

    func startMockSession(
        sessionId: String,
        rewardNonce: String,
        requestID: UUID
    ) async throws -> MockSession {
        try await sendJSON(
            path: "/v1/mock-exams/\(sessionId)/start",
            method: "POST",
            body: MockSessionRewardRequest(rewardNonce: rewardNonce),
            requestID: requestID,
            timeout: RequestTimeout.generation
        )
    }

    func adjustMockSession(
        sessionId: String,
        adjustment: DifficultyAdjustment,
        rewardNonce: String,
        requestID: UUID
    ) async throws -> MockSession {
        try await sendJSON(
            path: "/v1/mock-exams/\(sessionId)/adjustment",
            method: "POST",
            body: MockSessionAdjustmentRequest(
                adjustment: adjustment,
                rewardNonce: rewardNonce
            ),
            requestID: requestID,
            timeout: RequestTimeout.generation
        )
    }

    func usage() async throws -> UsageStatus {
        try await send(path: "/v1/usage", method: "GET", body: nil)
    }

    func createRewardIntent(
        purpose: RewardPurpose,
        sessionHash: String? = nil,
        requestID: UUID
    ) async throws -> RewardIntent {
        do {
            return try await sendJSON(
                path: "/v1/ad-rewards/intents",
                method: "POST",
                body: RewardIntentRequest(purpose: purpose, sessionHash: sessionHash),
                requestID: requestID,
                timeout: RequestTimeout.read
            )
        } catch let error as APIClientError where error.isRewardQuotaExhausted {
            // 리워드 한도 초과는 용도마다 다음 행동이 다르다. 서버 message를 그대로
            // 띄우면 구버전 서버에서는 영어 원문("daily reward quota exhausted")이
            // 그대로 노출된다. 코드는 그대로 두고 문구만 갈아끼운다.
            throw APIClientError.server(
                status: 402,
                code: error.code,
                message: Self.rewardQuotaMessage(for: purpose)
            )
        }
    }

    static func rewardQuotaMessage(for purpose: RewardPurpose) -> String {
        switch purpose {
        case .practiceCredits:
            "오늘 받을 수 있는 추가 학습 보상을 모두 사용했어요. 내일 다시 받을 수 있어요."
        case .practiceRefresh:
            "오늘 문제 새로고침 기회를 모두 사용했어요. 지금 세트는 계속 풀 수 있어요."
        case .mockStart:
            "오늘 모의고사 시작 기회를 모두 사용했어요. 내일 다시 시작할 수 있어요."
        case .mockAdjustment:
            "오늘 난이도 조정 기회를 모두 사용했어요. 조정 없이 계속 진행할 수 있어요."
        case .mockResult:
            "오늘 결과 확인 기회를 모두 사용했어요. 녹음한 답변은 저장해 두었으니 내일 다시 '결과 보기'를 눌러 주세요."
        case .targetLevelChange:
            "난이도 변경은 하루 한 번만 가능해요. 내일 다시 시도해 주세요."
        }
    }

    func rewardStatus(nonce: String) async throws -> RewardIntent {
        try await send(path: "/v1/ad-rewards/\(nonce)", method: "GET", body: nil)
    }

    func updateInitialLevel(
        _ initialLevel: SelfAssessmentLevel,
        rewardNonce: String? = nil,
        requestID: UUID
    ) async throws -> TargetLevelResponse {
        try await sendJSON(
            path: "/v1/users/me/target-level",
            method: "PUT",
            body: TargetLevelRequest(initialLevel: initialLevel.rawValue, rewardNonce: rewardNonce),
            requestID: requestID,
            timeout: RequestTimeout.read
        )
    }

    /// 학습 계획 설정. 캘린더를 쓴 적 없는 사용자는 오류가 아니라 `configured == false`.
    func studyPlan() async throws -> StudyPlanResponse {
        try await send(path: "/v1/users/me/study-plan", method: "GET", body: nil)
    }

    /// 설정 전체를 덮어쓴다(멱등). 목표 등급은 여기가 아니라 target-level이 진실이다.
    func updateStudyPlan(
        _ settings: StudyPlanSettings,
        requestID: UUID
    ) async throws -> StudyPlanResponse {
        try await sendJSON(
            path: "/v1/users/me/study-plan",
            method: "PUT",
            body: StudyPlanRequest(settings: settings),
            requestID: requestID,
            timeout: RequestTimeout.read
        )
    }

    func operation(id: UUID) async throws -> OperationResult {
        try await send(path: "/v1/operations/\(id.uuidString)", method: "GET", body: nil)
    }

    func waitForReward(
        nonce: String,
        maxAttempts: Int = 15,
        pollIntervalSeconds: Double = 2,
        onStatus: (@Sendable (RewardIntent) async -> Void)? = nil
    ) async throws -> RewardIntent {
        for attempt in 1...max(1, maxAttempts) {
            let reward = try await rewardStatus(nonce: nonce)
            if let onStatus {
                await onStatus(reward)
            }
            if reward.isVerified { return reward }
            if attempt < maxAttempts {
                try await Task.sleep(for: .seconds(pollIntervalSeconds))
            }
        }
        throw APIClientError.server(
            status: 408,
            code: "reward_verification_timeout",
            message: rewardVerificationTimeoutMessage
        )
    }

    func evaluatePractice(
        questionSet: QuestionSet,
        questionNumber: Int,
        transcript: String,
        targetLevel: OPIcLevel,
        audioURL: URL,
        requestID: UUID
    ) async throws -> PracticeEvaluation {
        var form = MultipartFormData()
        form.append(name: "setId", value: questionSet.setId)
        form.append(name: "questionNumber", value: String(questionNumber))
        form.append(name: "transcript", value: transcript)
        form.append(name: "targetLevel", value: questionSet.expectedTargetLevel.rawValue)
        try form.append(name: "audio", fileURL: audioURL)
        form.finish()
        return try await sendMultipart(
            path: "/v2/evaluations/practice",
            form: form,
            requestID: requestID,
            timeout: RequestTimeout.evaluation
        )
    }

    func evaluateMock(
        sessionId: String,
        questionSet: QuestionSet,
        answers: [RecordedAnswer],
        targetLevel: OPIcLevel,
        rewardNonce: String,
        requestID: UUID
    ) async throws -> MockEvaluation {
        let manifest = MockEvaluationManifest(
            targetLevel: questionSet.expectedTargetLevel,
            setId: questionSet.setId,
            rewardNonce: rewardNonce,
            answers: answers.sorted { $0.number < $1.number }.map {
                .init(number: $0.number, transcript: $0.transcript)
            }
        )
        var form = MultipartFormData()
        let manifestData = try encoder.encode(manifest)
        form.append(name: "manifest", value: String(decoding: manifestData, as: UTF8.self))
        for answer in answers.sorted(by: { $0.number < $1.number }) {
            try form.append(
                name: "audioFiles",
                fileURL: answer.audioURL,
                filename: "answer-\(answer.number).m4a"
            )
        }
        form.finish()
        return try await sendMultipart(
            path: "/v1/mock-exams/\(sessionId)/evaluate",
            form: form,
            requestID: requestID,
            timeout: RequestTimeout.evaluation
        )
    }

    private func sendJSON<Input: Encodable, Output: Decodable>(
        path: String,
        method: String,
        body: Input,
        requestID: UUID? = nil,
        timeout: TimeInterval = RequestTimeout.read
    ) async throws -> Output {
        try await send(
            path: path,
            method: method,
            body: try encoder.encode(body),
            requestID: requestID,
            timeout: timeout
        )
    }

    private var rewardVerificationTimeoutMessage: String {
        #if DEBUG
        if Self.needsPublicSSVCallbackWarning(for: baseURL) {
            return "로컬 서버는 AdMob SSV를 직접 받을 수 없습니다. Cloud Run 또는 HTTPS 터널 callback URL을 설정해 주세요."
        }
        #endif
        return "광고는 완료됐지만 서버 검증이 아직 도착하지 않았습니다. 잠시 후 다시 시도해 주세요."
    }

    private static func needsPublicSSVCallbackWarning(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        if url.scheme?.lowercased() != "https" { return true }
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts[0] == 172, (16...31).contains(parts[1]) {
            return true
        }
        return false
    }

    private func send<Output: Decodable>(
        path: String,
        method: String,
        body: Data?,
        requestID: UUID? = nil,
        timeout: TimeInterval = RequestTimeout.read
    ) async throws -> Output {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let requestID {
            request.setValue(requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        }
        try await addAuthentication(to: &request)
        return try await execute(request)
    }

    private func sendMultipart<Output: Decodable>(
        path: String,
        form: MultipartFormData,
        requestID: UUID,
        timeout: TimeInterval
    ) async throws -> Output {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = form.data
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        try await addAuthentication(to: &request)
        return try await execute(request)
    }

    private func addAuthentication(to request: inout URLRequest) async throws {
        for (key, value) in try await authentication.headers() {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func execute<Output: Decodable>(_ request: URLRequest) async throws -> Output {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if http.statusCode == 401, Self.isRefreshableAuthenticationError(data: data) {
            var retryRequest = request
            for (key, value) in try await authentication.headers(forceRefreshAuthToken: true) {
                retryRequest.setValue(value, forHTTPHeaderField: key)
            }
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIClientError.invalidResponse
            }
            guard 200..<300 ~= retryHTTP.statusCode else {
                throw Self.makeError(status: retryHTTP.statusCode, data: retryData)
            }
            return try decoder.decode(Output.self, from: retryData)
        }
        guard 200..<300 ~= http.statusCode else {
            throw Self.makeError(status: http.statusCode, data: data)
        }
        return try decoder.decode(Output.self, from: data)
    }

    nonisolated private static func isRefreshableAuthenticationError(data: Data) -> Bool {
        let error = makeError(status: 401, data: data)
        return error.code == "invalid_id_token" || error.code == "expired_id_token"
    }

    nonisolated static func makeError(status: Int, data: Data) -> APIClientError {
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let detail = payload?["detail"]
        let object = detail as? [String: Any]
        let code = object?["code"] as? String
        let message = object?["message"] as? String
            ?? detail as? String
            ?? HTTPURLResponse.localizedString(forStatusCode: status)

        if status == 402, isRewardRequiredCode(code) {
            return .rewardRequired(status: status, code: code, message: message)
        }
        return .server(status: status, code: code, message: message)
    }

    nonisolated private static func isRewardRequiredCode(_ code: String?) -> Bool {
        guard let code else { return false }
        return code == "target_level_change_reward_required"
            || code == "mock_reward_required"
            || code.hasSuffix("_reward_required")
    }
}
