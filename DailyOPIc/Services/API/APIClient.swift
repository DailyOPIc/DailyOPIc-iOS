import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case rewardRequired(status: Int, code: String?, message: String)
    case server(status: Int, code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "서버 응답을 확인할 수 없습니다."
        case let .rewardRequired(_, _, message),
             let .server(_, _, message):
            message
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
}

actor APIClient {
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

    func createPracticeSet(request payload: QuestionSetRequest) async throws -> QuestionSet {
        try await sendJSON(path: "/v1/question-sets/practice", method: "POST", body: payload)
    }

    func createMockExam(request payload: QuestionSetRequest) async throws -> QuestionSet {
        try await sendJSON(path: "/v1/mock-exams", method: "POST", body: payload)
    }

    func usage() async throws -> UsageStatus {
        try await send(path: "/v1/usage", method: "GET", body: nil)
    }

    func createRewardIntent(purpose: RewardPurpose, sessionHash: String? = nil) async throws -> RewardIntent {
        try await sendJSON(
            path: "/v1/ad-rewards/intents",
            method: "POST",
            body: RewardIntentRequest(purpose: purpose, sessionHash: sessionHash)
        )
    }

    func rewardStatus(nonce: String) async throws -> RewardIntent {
        try await send(path: "/v1/ad-rewards/\(nonce)", method: "GET", body: nil)
    }

    func updateTargetLevel(_ targetLevel: OPIcLevel, rewardNonce: String? = nil) async throws -> TargetLevelResponse {
        try await sendJSON(
            path: "/v1/users/me/target-level",
            method: "PUT",
            body: TargetLevelRequest(targetLevel: targetLevel, rewardNonce: rewardNonce)
        )
    }

    func waitForReward(
        nonce: String,
        timeoutSeconds: Double = 60,
        onStatus: (@Sendable (RewardIntent) async -> Void)? = nil
    ) async throws -> RewardIntent {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        while clock.now < deadline {
            let reward = try await rewardStatus(nonce: nonce)
            if let onStatus {
                await onStatus(reward)
            }
            if reward.isVerified { return reward }
            try await Task.sleep(for: .seconds(1))
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
        requestID: UUID = UUID()
    ) async throws -> PracticeEvaluation {
        var form = MultipartFormData()
        form.append(name: "setId", value: questionSet.setId)
        form.append(name: "questionNumber", value: String(questionNumber))
        form.append(name: "transcript", value: transcript)
        form.append(name: "targetLevel", value: targetLevel.rawValue)
        try form.append(name: "audio", fileURL: audioURL)
        form.finish()
        return try await sendMultipart(
            path: "/v1/evaluations/practice",
            form: form,
            requestID: requestID
        )
    }

    func evaluateMock(
        questionSet: QuestionSet,
        answers: [RecordedAnswer],
        targetLevel: OPIcLevel,
        rewardNonce: String,
        requestID: UUID = UUID()
    ) async throws -> MockEvaluation {
        let manifest = MockEvaluationManifest(
            targetLevel: targetLevel,
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
            path: "/v1/evaluations/mock",
            form: form,
            requestID: requestID
        )
    }

    private func sendJSON<Input: Encodable, Output: Decodable>(
        path: String,
        method: String,
        body: Input
    ) async throws -> Output {
        try await send(path: path, method: method, body: try encoder.encode(body))
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
        body: Data?
    ) async throws -> Output {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try await addAuthentication(to: &request)
        return try await execute(request)
    }

    private func sendMultipart<Output: Decodable>(
        path: String,
        form: MultipartFormData,
        requestID: UUID
    ) async throws -> Output {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = form.data
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
        guard 200..<300 ~= http.statusCode else {
            throw Self.makeError(status: http.statusCode, data: data)
        }
        return try decoder.decode(Output.self, from: data)
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
