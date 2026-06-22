import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case server(status: Int, code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "서버 응답을 확인할 수 없습니다."
        case let .server(_, _, message):
            message
        }
    }

    var code: String? {
        if case let .server(_, code, _) = self { return code }
        return nil
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

    func waitForReward(nonce: String, timeoutSeconds: Double = 20) async throws -> RewardIntent {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        while clock.now < deadline {
            let reward = try await rewardStatus(nonce: nonce)
            if reward.isVerified { return reward }
            try await Task.sleep(for: .seconds(1))
        }
        throw APIClientError.server(
            status: 408,
            code: "reward_verification_timeout",
            message: "광고 시청 확인이 지연되고 있습니다. 잠시 후 다시 확인해 주세요."
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
        let questions = try encoder.encode(questionSet.questions)
        form.append(name: "questionSet", value: String(decoding: questions, as: UTF8.self))
        form.append(name: "questionNumber", value: String(questionNumber))
        form.append(name: "transcript", value: transcript)
        form.append(name: "targetLevel", value: targetLevel.rawValue)
        form.append(name: "setToken", value: questionSet.setToken)
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
            setToken: questionSet.setToken,
            rewardNonce: rewardNonce,
            questions: questionSet.questions,
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
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = payload?["detail"]
            let object = detail as? [String: Any]
            let code = object?["code"] as? String
            let message = object?["message"] as? String
                ?? detail as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIClientError.server(status: http.statusCode, code: code, message: message)
        }
        return try decoder.decode(Output.self, from: data)
    }
}
