import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 단어장 AI 말하기 코치(P14.3). 요청/응답 계약 · 기기 저장 · 재열람 무료 ·
/// "조작 1회 = 데일리 토큰 1개"라는 과금 배선을 고정한다.
///
/// `AppEnvironment.api`는 프로토콜이 아니라 구체 `actor APIClient`라 가짜 서버를
/// 넣을 수 없다. 그래서 뷰모델 쪽 계약은 이 저장소가 이미 쓰는 방식(소스 계약 검사,
/// `DailyTokenEnforcementTests` · `VocabularyGenerationTests` 참고)으로 확인한다.
/// 어느 테스트도 네트워크·제공자를 부르지 않는다.
@MainActor
struct VocabularyCoachTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    // MARK: 픽스처

    private func seedEntry(type: VocabularyItemType = .word) -> VocabularyEntry {
        VocabularyEntry(
            id: "seed-cafes-001",
            term: "crowded",
            type: type,
            meaningKo: "붐비는, 사람이 많은",
            exampleEn: "The café usually gets crowded on weekends.",
            exampleKo: "그 카페는 주말에 보통 붐벼요.",
            collocations: ["get crowded"],
            topics: [.cafes],
            usageRoles: [.description],
            recommendedLevels: [.IH],
            source: "seed"
        )
    }

    /// P14.2가 만들어 준 항목. id에 `ai-` 접두사가 붙는다는 것 말고는 같은 계약이다.
    private func generatedEntry(
        type: VocabularyItemType = .phrase,
        term: String = "spend time with"
    ) -> VocabularyEntry {
        VocabularyEntry(
            id: "ai-c985ffc9040bab5adcd103fa-10",
            term: term,
            type: type,
            meaningKo: "~와 시간을 보내다",
            exampleEn: "I like to spend time with my friends downtown.",
            exampleKo: "저는 친구들과 시내에서 시간을 보내는 걸 좋아해요.",
            topics: [.familyFriends],
            usageRoles: [.routine],
            recommendedLevels: [.IH],
            source: "ai"
        )
    }

    /// 서버가 실제로 내려주는 모양 그대로의 JSON. `createdAt`은 파이썬이 내는
    /// 마이크로초 6자리 형식이다 — 앱이 이걸 못 읽으면 기능 전체가 죽는다.
    private func payloadJSON(
        resultID: String = "3a91f0c7d1b24e6f88ab00c1",
        entryID: String = "seed-cafes-001",
        transcript: String = "My favorite cafe is very crowded because many people go there.",
        assessment: String = "needsPolish",
        createdAt: String = "2026-08-28T13:16:11.139663Z"
    ) -> Data {
        Data("""
        {"resultId":"\(resultID)","entryId":"\(entryID)","targetTerm":"crowded",\
        "transcript":"\(transcript)","usageAssessment":"\(assessment)",\
        "usageFeedbackKo":"의미는 전달되지만 crowded를 쓰는 위치를 조금 다듬으면 더 자연스러워요.",\
        "naturalCorrectionEn":"My favorite cafe gets especially crowded on weekends.",\
        "naturalCorrectionKo":"제가 좋아하는 카페는 주말에 특히 붐벼요.",\
        "expandedAnswerEn":"My favorite cafe gets especially crowded on weekends, \
        but I still go there because it has a cozy atmosphere.",\
        "expandedAnswerKo":"주말에 특히 붐비지만 분위기가 아늑해서 그래도 자주 가요.",\
        "relatedExpressions":["get crowded","especially on weekends","cozy atmosphere"],\
        "createdAt":"\(createdAt)"}
        """.utf8)
    }

    private func makeResult(
        resultID: String = "3a91f0c7d1b24e6f88ab00c1",
        entryID: String = "seed-cafes-001",
        transcript: String = "My favorite cafe is very crowded because many people go there.",
        assessment: String = "needsPolish",
        createdAt: String = "2026-08-28T13:16:11.139663Z"
    ) throws -> VocabularySpeakingCoachResult {
        try JSONCoding.decoder.decode(
            VocabularySpeakingCoachResult.self,
            from: payloadJSON(
                resultID: resultID,
                entryID: entryID,
                transcript: transcript,
                assessment: assessment,
                createdAt: createdAt
            )
        )
    }

    private func makeService(_ container: ModelContainer) -> PersistenceService {
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func makeMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// 저장 왕복 뒤 같은 결과인가.
    ///
    /// `JSONCoding.encoder`는 `.iso8601`(초 단위)이라 저장하면 밀리초 이하가 버려진다.
    /// 앱 전체가 쓰는 규약이고 코칭 시각에 그 정밀도가 필요하지도 않으므로, 시각만
    /// 초 단위로 비교한다. 나머지 필드는 글자 그대로 같아야 한다.
    private func expectSame(
        _ saved: VocabularySpeakingCoachResult?,
        _ expected: VocabularySpeakingCoachResult,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let saved = try #require(saved, sourceLocation: sourceLocation)
        #expect(saved.resultId == expected.resultId, sourceLocation: sourceLocation)
        #expect(saved.entryId == expected.entryId, sourceLocation: sourceLocation)
        #expect(saved.targetTerm == expected.targetTerm, sourceLocation: sourceLocation)
        #expect(saved.transcript == expected.transcript, sourceLocation: sourceLocation)
        #expect(saved.usageAssessment == expected.usageAssessment, sourceLocation: sourceLocation)
        #expect(saved.usageFeedbackKo == expected.usageFeedbackKo, sourceLocation: sourceLocation)
        #expect(
            saved.naturalCorrectionEn == expected.naturalCorrectionEn,
            sourceLocation: sourceLocation
        )
        #expect(
            saved.naturalCorrectionKo == expected.naturalCorrectionKo,
            sourceLocation: sourceLocation
        )
        #expect(saved.expandedAnswerEn == expected.expandedAnswerEn, sourceLocation: sourceLocation)
        #expect(saved.expandedAnswerKo == expected.expandedAnswerKo, sourceLocation: sourceLocation)
        #expect(
            saved.relatedExpressions == expected.relatedExpressions,
            sourceLocation: sourceLocation
        )
        #expect(
            abs(saved.createdAt.timeIntervalSince(expected.createdAt)) < 1,
            sourceLocation: sourceLocation
        )
    }

    /// 소스 계약 검사용. 런타임 소스를 파일로 읽는다(`DailyTokenEnforcementTests`와 같은 방식).
    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runtimeSources() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
        return FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
    }

    // MARK: 1. 요청 인코딩

    /// 앱이 보내는 것은 무엇을 연습했는지와 무엇을 말했는지뿐이다.
    /// 모델명 · 프롬프트 · 출력 스키마 · 비용을 클라이언트가 정하지 않는다.
    @Test func encodesCoachRequest() throws {
        let payload = VocabularySpeakingCoachRequest(
            entry: seedEntry(),
            transcript: "  My favorite cafe is very crowded.  ",
            targetLevel: .IH
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(payload))
                as? [String: Any]
        )

        #expect(json["entryId"] as? String == "seed-cafes-001")
        #expect(json["term"] as? String == "crowded")
        #expect(json["type"] as? String == "word")
        // 앞뒤 공백은 보내기 전에 정리한다.
        #expect(json["transcript"] as? String == "My favorite cafe is very crowded.")
        #expect(json["meaningKo"] as? String == "붐비는, 사람이 많은")
        #expect(json["topic"] as? String == "cafes")
        #expect(json["targetLevel"] as? String == "IH")
        // 서버가 소유하는 값은 요청에 없다.
        for forbidden in ["model", "instructions", "prompt", "schema", "tokenCost", "cost"] {
            #expect(json[forbidden] == nil)
        }
    }

    /// 서버 상한을 넘는 전사는 보내기 전에 앱이 자른다 — 서버는 자르지 않고 거절한다.
    @Test func oversizedTranscriptIsTrimmedToTheServerLimit() throws {
        let payload = VocabularySpeakingCoachRequest(
            entry: seedEntry(),
            transcript: String(repeating: "a", count: 2_000),
            targetLevel: .IH
        )

        #expect(payload.transcript.count == VocabularySpeakingCoachRequest.transcriptLimit)
        #expect(VocabularySpeakingCoachRequest.transcriptLimit == 600)
    }

    /// 목표 등급이 없어도 요청은 성립한다(온보딩 전 사용자).
    @Test func missingTargetLevelIsOmitted() throws {
        let payload = VocabularySpeakingCoachRequest(
            entry: seedEntry(),
            transcript: "It gets crowded.",
            targetLevel: nil
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(payload))
                as? [String: Any]
        )

        #expect(json["targetLevel"] == nil)
    }

    // MARK: 2. 응답 디코딩

    @Test func decodesCoachResponse() throws {
        let result = try makeResult()

        #expect(result.resultId == "3a91f0c7d1b24e6f88ab00c1")
        #expect(result.id == result.resultId)
        #expect(result.entryId == "seed-cafes-001")
        #expect(result.targetTerm == "crowded")
        #expect(result.usageAssessment == .needsPolish)
        #expect(!result.usageFeedbackKo.isEmpty)
        #expect(!result.naturalCorrectionEn.isEmpty)
        #expect(!result.naturalCorrectionKo.isEmpty)
        #expect(!result.expandedAnswerEn.isEmpty)
        #expect(!result.expandedAnswerKo.isEmpty)
        #expect(result.relatedExpressions.count == 3)
        // 마이크로초 6자리를 읽어 낸다(파이썬이 내는 형식).
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expected = try #require(formatter.date(from: "2026-08-28T13:16:11Z"))
        #expect(abs(result.createdAt.timeIntervalSince(expected)) < 1)
    }

    /// 세 갈래 판정 전부 읽는다. 점수·등급 필드는 모델에 아예 없다.
    @Test func decodesEveryUsageAssessment() throws {
        for raw in ["appropriate", "needsPolish", "notUsed"] {
            let result = try makeResult(assessment: raw)
            #expect(result.usageAssessment.rawValue == raw)
            #expect(!result.usageAssessment.label.isEmpty)
        }
        #expect(VocabularyUsageAssessment.allCases.count == 3)

        // 등급·점수를 담는 자리를 만들지 않았다. 데일리 분석과 두 개의 진실을 만들지 않는다.
        let model = try source("Models/VocabularyCoach.swift")
        for forbidden in ["predictedGrade", "score", "rubric", "fluency", "pronunciation"] {
            #expect(!model.contains(forbidden))
        }
    }

    // MARK: 3~4. 조작 신원(멱등 · 앱을 껐다 켜도 남는다)

    /// 실패 후 다시 누르는 것은 새 조작이 아니다. 같은 `operationID`를 그대로 보내야
    /// 서버가 이미 만든 결과를 돌려주고 토큰이 두 번 나가지 않는다.
    @Test func retryKeepsTheSameOperationID() throws {
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        #expect(viewModel.contains("requestID: operationID"))
        // 신원은 더 이상 메모리 변수가 아니다. 디스크에 남은 기록에서 나온다(P14.3.1).
        #expect(!viewModel.contains("operationID = UUID()"))
        // 정의 1회 + 호출 1회. 요청 경로에서 신원을 정하는 자리는 여기 한 곳뿐이다.
        #expect(viewModel.components(separatedBy: "beginOperation(transcript:").count - 1 == 2)
        // 연타가 두 번째 조작이 되지 않게 실행 중에는 다시 시작하지 않는다.
        #expect(viewModel.contains("guard !isAnalyzing, canAnalyze else { return }"))
    }

    /// 순서가 전부다: **저장 → 요청 → 결과 저장 → 대기 기록 정리.**
    /// 요청이 먼저면 그 사이에 앱이 죽었을 때 신원을 잃고 토큰이 또 나가고,
    /// 정리가 먼저면 결과 저장 직전에 죽었을 때 복구할 신원이 사라진다.
    /// 화면 재진입·재렌더링은 새 조작이 아니다(여는 경로가 신원을 만들지 않는다).
    @Test func newAnalysisGetsANewOperationIDOnlyAfterSuccess() throws {
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let run = try #require(viewModel.range(of: "private func run("))
        let body = viewModel[run.upperBound...]
        let begin = try #require(body.range(of: "beginOperation(transcript: transcript)"))
        let request = try #require(body.range(of: "api.coachVocabulary("))
        let save = try #require(
            body.range(of: "try persistence.saveVocabularyCoachResult(coaching)")
        )
        let cleanup = try #require(
            body[save.upperBound...].range(of: "clearPendingOperation(for: transcript)")
        )
        #expect(begin.lowerBound < request.lowerBound)
        #expect(request.lowerBound < save.lowerBound)
        #expect(save.upperBound < cleanup.lowerBound)

        // 신원을 만드는 함수 안에서도 저장이 반환보다 먼저다.
        let beginFunc = try #require(viewModel.range(of: "private func beginOperation("))
        let beginBody = viewModel[beginFunc.upperBound...]
        let write = try #require(beginBody.range(of: "preferences.pendingVocabularyCoach = operation"))
        let ret = try #require(beginBody.range(of: "return operation.operationID"))
        #expect(write.lowerBound < ret.lowerBound)

        // 화면을 다시 여는 경로(`load`)는 저장본을 읽을 뿐 조작을 새로 열지 않는다.
        let load = try #require(viewModel.range(of: "func load() async"))
        let recordAgain = try #require(viewModel.range(of: "func recordAgain()"))
        let between = viewModel[load.upperBound..<recordAgain.lowerBound]
        #expect(!between.contains("beginOperation"))
        #expect(!between.contains("coachVocabulary"))
    }

    // MARK: 4.1 조작 신원의 내구성 (P14.3.1)

    /// 요청을 보내기 전에 기록이 **디스크에** 남아야 한다. 그 사이에 앱이 죽어도
    /// 다음 실행이 같은 키로 재시도할 수 있어야 토큰이 두 번 나가지 않는다.
    @Test func pendingOperationIsSavedBeforeTheRequestIsSent() throws {
        let suite = "vocab-coach-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(defaults.data(forKey: "native_vocabulary_coach_pending") == nil)

        let operation = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        preferences.pendingVocabularyCoach = operation
        // 대입 즉시(요청을 보내기 전에) 값이 디스크에 있다.
        #expect(defaults.data(forKey: "native_vocabulary_coach_pending") != nil)

        // 저장한 것은 재시도에 필요한 것뿐이다. 오디오는 없다.
        let stored = try #require(defaults.data(forKey: "native_vocabulary_coach_pending"))
        let text = try #require(String(data: stored, encoding: .utf8))
        #expect(text.contains("operationID"))
        #expect(text.contains("transcriptKey"))
        #expect(!text.contains("audio"))
    }

    /// UserDefaults 인스턴스를 다시 만들어도(=프로세스 재시작) 값이 남아 있다.
    @Test func pendingOperationSurvivesUserDefaultsRecreation() throws {
        let suite = "vocab-coach-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let operation = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        AppPreferences(defaults: defaults).pendingVocabularyCoach = operation

        let reopened = try #require(UserDefaults(suiteName: suite))
        let restored = try #require(AppPreferences(defaults: reopened).pendingVocabularyCoach)
        #expect(restored.operationID == operation.operationID)
        #expect(restored.entryID == operation.entryID)
        #expect(restored.transcriptKey == operation.transcriptKey)
        #expect(restored.transcript == "It gets crowded on weekends.")
        // `JSONCoding.encoder`는 `.iso8601`(초 단위)이라 밀리초 이하는 버려진다.
        #expect(abs(restored.createdAt.timeIntervalSince(operation.createdAt)) < 1)
        #expect(restored.isReplayable())
    }

    /// 앱을 껐다 켜고 같은 답변을 다시 시도하면 **같은** 신원을 그대로 쓴다.
    /// 공백·대소문자 차이는 같은 답변이다(전사 정규형이 판단한다).
    @Test func retryAfterRestartReusesTheStoredOperationID() throws {
        let stored = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        let resumed = PendingVocabularyCoachOperation.resume(
            stored,
            entryID: "seed-cafes-001",
            transcript: "  it gets   crowded on weekends.  "
        )
        #expect(resumed.operationID == stored.operationID)
        #expect(resumed.createdAt == stored.createdAt)
    }

    /// 답변이 바뀌면 다른 분석이다. 항목이 바뀌어도 마찬가지다. 재개는 하지 않는다.
    @Test func changedTranscriptOrEntryStartsANewOperation() throws {
        let stored = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        let changedAnswer = PendingVocabularyCoachOperation.resume(
            stored,
            entryID: "seed-cafes-001",
            transcript: "The cafe is really busy in the afternoon."
        )
        #expect(changedAnswer.operationID != stored.operationID)

        let changedEntry = PendingVocabularyCoachOperation.resume(
            stored,
            entryID: "ai-c985ffc9040bab5adcd103fa-10",
            transcript: "It gets crowded on weekends."
        )
        #expect(changedEntry.operationID != stored.operationID)

        // 기록이 없으면(성공 후 정리된 상태) 다음 분석은 언제나 새 신원이다.
        let fresh = PendingVocabularyCoachOperation.resume(
            nil,
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        #expect(fresh.operationID != stored.operationID)
    }

    /// 정리는 **같은** 조작만 지운다. 다른 답변·다른 항목의 기록을 함께 날리지 않는다.
    @Test func cleanupMatchesOnlyTheSameOperation() throws {
        let stored = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        #expect(stored.matches(entryID: "seed-cafes-001", transcript: "It gets CROWDED on weekends."))
        #expect(!stored.matches(entryID: "seed-cafes-001", transcript: "Something else entirely."))
        #expect(!stored.matches(entryID: "other-entry", transcript: "It gets crowded on weekends."))

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let clear = try #require(viewModel.range(of: "private func clearPendingOperation("))
        let body = viewModel[clear.upperBound...].prefix(300)
        #expect(body.contains("pending.matches(entryID: entry.id, transcript: transcript)"))
    }

    /// 결과 저장 뒤 정리 전에 앱이 죽은 경우. 화면을 다시 열면 **저장본이 이긴다** —
    /// 남은 기록을 치우고 끝내며, 서버를 부르지 않는다.
    @Test func stalePendingOperationLosesToASavedResult() throws {
        let service = makeService(try makeMemoryContainer())
        let result = try makeResult()
        try service.saveVocabularyCoachResult(result)
        // 대기 기록에 남은 답변으로 조회하면 이미 값을 치른 결과가 나온다.
        #expect(
            try service.vocabularyCoachResult(
                entryID: result.entryId,
                transcript: result.transcript
            ) != nil
        )

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let recover = try #require(viewModel.range(of: "private func recoverPendingOperation("))
        let end = try #require(viewModel.range(of: "func refreshUsage() async"))
        let body = viewModel[recover.upperBound..<end.lowerBound]
        // 저장본 조회가 먼저고, 찾으면 기록을 지우고 거기서 끝난다.
        let lookup = try #require(body.range(of: "persistence.vocabularyCoachResult("))
        let clear = try #require(body.range(of: "preferences.pendingVocabularyCoach = nil"))
        #expect(lookup.lowerBound < clear.lowerBound)
        // 복구 경로 전체가 네트워크를 부르지 않는다.
        #expect(!body.contains("api."))
        #expect(!body.contains("coachVocabulary"))
        #expect(!body.contains("beginOperation"))
    }

    /// 토큰이 0이라 광고·결제 UX를 거쳐 다시 시도해도 신원은 그대로다.
    /// 두 번째 신원을 만들면 이미 예약된 조작이 미아가 되고 토큰이 또 나간다.
    @Test func zeroTokenRecoveryKeepsTheSameOperationID() throws {
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let run = try #require(viewModel.range(of: "private func run("))
        let body = viewModel[run.upperBound...]
        let recovery = try #require(body.range(of: "guard allowRecovery, await recoverToken() else { return }"))
        let begin = try #require(body.range(of: "beginOperation(transcript: transcript)"))
        // 토큰 확보는 신원을 만들기 **전에** 끝난다.
        #expect(recovery.lowerBound < begin.lowerBound)
        // 서버가 거절했을 때도 새 신원이 아니라 같은 경로로 다시 들어간다.
        #expect(body.contains("await run(allowRecovery: false)"))

        // 다시 들어와도 저장된 신원을 재개한다.
        let stored = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        #expect(
            PendingVocabularyCoachOperation.resume(
                stored,
                entryID: "seed-cafes-001",
                transcript: "It gets crowded on weekends."
            ).operationID == stored.operationID
        )
    }

    /// 네트워크 실패 · 타임아웃 · 서버 오류(409 등)에서는 기록을 지우지 않는다.
    /// 기록을 지우는 자리는 셋뿐이다: 저장본 확인 · 만료 · 성공 후 정리.
    @Test func failedRequestKeepsThePendingOperation() throws {
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        #expect(viewModel.components(separatedBy: "pendingVocabularyCoach = nil").count - 1 == 3)

        // 실패 처리 구간(첫 catch부터 함수 끝까지)에는 정리가 없다.
        let firstCatch = try #require(viewModel.range(of: "} catch is CancellationError {"))
        let helpers = try #require(viewModel.range(of: "private func beginOperation("))
        let failures = viewModel[firstCatch.upperBound..<helpers.lowerBound]
        #expect(!failures.contains("pendingVocabularyCoach"))
        // 실패는 같은 신원으로 다시 시도할 수 있는 상태로 남는다.
        #expect(failures.contains("operationId: operationID"))
    }

    /// 서버가 결과를 되돌려 준다고 보장하는 기간(요청 결과 캐시 TTL 24시간)을
    /// 클라이언트 복구 창이 **넘지 않는다**.
    @Test func recoveryWindowStaysInsideTheServerReplayGuarantee() {
        let serverTTL: TimeInterval = 24 * 60 * 60  // REQUEST_RESULT_TTL_HOURS = 24
        #expect(PendingVocabularyCoachOperation.safeReplayWindow < serverTTL)

        let created = Date(timeIntervalSince1970: 1_756_000_000)
        let operation = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends.",
            createdAt: created
        )
        #expect(operation.isReplayable(now: created.addingTimeInterval(60)))
        #expect(operation.isReplayable(now: created.addingTimeInterval(22 * 60 * 60)))
        #expect(!operation.isReplayable(now: created.addingTimeInterval(serverTTL)))
        #expect(!operation.isReplayable(now: created.addingTimeInterval(7 * 24 * 60 * 60)))
    }

    /// 창을 넘긴 기록은 **자동으로 보내지 않는다.** 조용히 새 조작을 만들어 토큰을
    /// 쓰지도 않는다 — 지우고 끝내며, 새 분석은 비용이 보이는 CTA에서 시작한다.
    @Test func expiredPendingOperationIsDroppedWithoutSending() throws {
        let expired = PendingVocabularyCoachOperation(
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends.",
            createdAt: Date(timeIntervalSinceNow: -25 * 60 * 60)
        )
        #expect(!expired.isReplayable())

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let recover = try #require(viewModel.range(of: "private func recoverPendingOperation("))
        let end = try #require(viewModel.range(of: "func refreshUsage() async"))
        let body = viewModel[recover.upperBound..<end.lowerBound]
        let expiry = try #require(body.range(of: "guard pending.isReplayable() else {"))
        let restore = try #require(body.range(of: "pendingTranscript = pending.transcript"))
        // 만료 검사가 검토 상태 복원보다 먼저다. 만료면 복원 자체를 하지 않는다.
        #expect(expiry.lowerBound < restore.lowerBound)

        // 만료된 기록을 재개하지도 않는다. 새 분석은 새 신원이고, 그건 사용자가 누른 결과다.
        let resumed = PendingVocabularyCoachOperation.resume(
            expired,
            entryID: "seed-cafes-001",
            transcript: "It gets crowded on weekends."
        )
        #expect(resumed.operationID != expired.operationID)
    }

    /// 녹음 · 다시 녹음 · 전사는 여전히 0 토큰이고, 대기 기록을 만들지도 않는다.
    /// 화면을 여는 것만으로 요청이 나가지도 않는다.
    @Test func recordingAndReopeningCreateNoPendingOperation() throws {
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let recording = try #require(viewModel.range(of: "func toggleRecording() async"))
        let analyze = try #require(viewModel.range(of: "func analyze() {"))
        let body = viewModel[recording.upperBound..<analyze.lowerBound]
        #expect(!body.contains("pendingVocabularyCoach"))
        #expect(!body.contains("beginOperation"))
        #expect(!body.contains("coachVocabulary"))

        // 대기 기록을 쓰는 자리는 뷰모델 하나뿐이다.
        let writers = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("pendingVocabularyCoach = ") }
        // 뷰모델 + 저장소(AppPreferences)의 프로퍼티 정의.
        #expect(writers.count == 2)
    }

    // MARK: 5. 토큰이 0이면 요청 자체를 시작하지 않는다

    @Test func zeroTokenPrecheckStopsBeforeTheRequest() throws {
        let empty = UsageStatus(
            date: "20260828",
            freeRemaining: 0,
            bonusRemaining: 0,
            serverDateKey: "20260828",
            resetsAt: nil,
            dailyAnalysisFreeRemaining: nil,
            dailyAnalysisRewardRemaining: nil,
            dailyRefreshRemaining: nil,
            mockAvailable: nil,
            mockRemaining: nil,
            mockSessionStage: nil
        )
        #expect(empty.totalRemaining == 0)

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let start = try #require(viewModel.range(of: "private func run("))
        let body = viewModel[start.upperBound...]
        let precheck = try #require(body.range(of: "if hasNoTokens {"))
        let request = try #require(body.range(of: "api.coachVocabulary("))
        // 잔액 확인이 요청보다 먼저다. 확보에 실패하면 요청까지 가지 않는다.
        #expect(precheck.lowerBound < request.lowerBound)
        #expect(body[precheck.upperBound...].contains("guard allowRecovery, await recoverToken() else { return }"))

        // 부족 UX는 기존 경로 그대로다. 단어장 전용 구매 경로를 만들지 않았다.
        #expect(viewModel.contains(".practiceCredits"))
        #expect(viewModel.contains(".tokenExhausted"))
        #expect(!viewModel.contains("Purchase"))
        #expect(!viewModel.contains("단어 토큰"))

        let view = try source("Views/Screens/Main/Vocabulary/VocabularySpeakingCoachViews.swift")
        #expect(view.contains("AI 코칭을 받으려면 데일리 토큰 1개가 필요합니다."))
    }

    // MARK: 6. 녹음 · 전사 자체는 AI를 부르지 않는다

    /// 앱 전체에서 코치 API를 부르는 자리는 뷰모델 한 곳뿐이고, 그 자리는
    /// `analyze()`(사용자가 CTA를 누른 경로) 뒤에만 있다.
    @Test func recordingAndTranscriptionNeverRequestCoaching() throws {
        let callSites = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("api.coachVocabulary(") }
        #expect(callSites.count == 1)

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        // 뷰모델 안에서 `analyze()`는 **선언만** 있다. 녹음 종료 · 중단 · 다시 녹음 ·
        // 타이머 만료가 스스로 분석을 시작하는 경로가 하나도 없다는 뜻이다.
        #expect(viewModel.components(separatedBy: "analyze()").count - 1 == 1)
        #expect(viewModel.contains("func analyze() {"))
        // 분석은 사용자가 CTA를 누를 때만 시작된다.
        let view = try source("Views/Screens/Main/Vocabulary/VocabularySpeakingCoachViews.swift")
        #expect(view.contains("viewModel.analyze()"))
        // 녹음 종료 · 다시 녹음 경로가 제공자를 부르지 않는다.
        for function in ["private func finishRecording(", "func recordAgain()"] {
            let start = try #require(viewModel.range(of: function))
            let body = viewModel[start.upperBound...].prefix(700)
            #expect(!body.contains("coachVocabulary"))
        }
        // 전사가 실패하면 분석하지 않고 다시 녹음하게 한다.
        #expect(viewModel.contains("pendingTranscript = nil"))

        // 녹음·오디오 세션·권한·STT는 데일리와 같은 서비스를 그대로 쓴다.
        #expect(viewModel.contains("let speech = SpeechRecognitionService()"))
        #expect(!viewModel.contains("AVAudioEngine"))

        let speechServices = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("class SpeechRecognitionService") }
        #expect(speechServices.count == 1)
    }

    /// 빈 전사·잡음은 유료 요청으로 보내지 않는다.
    @Test func emptyOrTrivialTranscriptIsNotAnalyzable() {
        #expect(!VocabularySpeakingPrompt.isAnalyzable(""))
        #expect(!VocabularySpeakingPrompt.isAnalyzable("   \n  "))
        #expect(!VocabularySpeakingPrompt.isAnalyzable("a"))
        #expect(VocabularySpeakingPrompt.isAnalyzable("It gets crowded."))
    }

    // MARK: 7~8. 저장 (앱을 껐다 켜도 남고, 다시 여는 것은 공짜)

    /// 메모리 저장소가 아니라 파일 저장소로 컨테이너를 두 번 연다.
    /// 앱 재시작을 흉내 내는 유일한 방법이고, 이미 값을 치른 결과가 살아남아야 한다.
    @Test func coachResultSurvivesContainerRestart() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vocab-coach-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ModelConfiguration(url: url)
        let result = try makeResult()

        let first = try ModelContainer(for: Schema.dailyOPIc, configurations: configuration)
        try makeService(first).saveVocabularyCoachResult(result)

        // 새 컨테이너 = 재시작. 앞의 인스턴스는 여기서 버린다.
        let second = try ModelContainer(for: Schema.dailyOPIc, configurations: configuration)
        let restored = try makeService(second).vocabularyCoachResults(entryID: result.entryId)

        #expect(restored.count == 1)
        try expectSame(restored.first, result)
    }

    /// 저장된 결과를 다시 여는 경로는 저장소 조회뿐이다 — 화면에도 AI 호출이 없다.
    @Test func reopeningASavedResultNeverRequestsAI() throws {
        let service = makeService(try makeMemoryContainer())
        let result = try makeResult()
        try service.saveVocabularyCoachResult(result)

        try expectSame(try service.vocabularyCoachResults(entryID: result.entryId).first, result)

        let view = try source("Views/Screens/Main/Vocabulary/VocabularySpeakingCoachViews.swift")
        #expect(!view.contains("coachVocabulary"))
        #expect(view.contains("viewModel.show(saved)"))

        let list = try source("Views/Screens/Main/Vocabulary/VocabularyListViews.swift")
        #expect(!list.contains("coachVocabulary"))
        let screen = try source("Views/Screens/Main/Vocabulary/VocabularyScreen.swift")
        #expect(!screen.contains("coachVocabulary"))
    }

    /// 같은 조작을 재시도해 같은 결과가 다시 와도 두 줄이 되지 않는다.
    @Test func savingTheSameResultTwiceKeepsOneRow() throws {
        let service = makeService(try makeMemoryContainer())
        let result = try makeResult()

        try service.saveVocabularyCoachResult(result)
        try service.saveVocabularyCoachResult(result)

        #expect(try service.vocabularyCoachResults(entryID: result.entryId).count == 1)
    }

    /// 오디오를 저장소에 쌓지 않는다. 코칭에 필요한 것은 텍스트다.
    @Test func coachRecordStoresTextNotAudio() throws {
        let records = try source("Models/LocalRecords.swift")
        let start = try #require(records.range(of: "final class VocabularyCoachResultRecord"))
        let body = records[start.upperBound...]
        #expect(!body.contains("audioURL"))
        #expect(!body.contains("audioData"))

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        // 전사를 확정한 자리에서 녹음 파일을 바로 버린다.
        #expect(viewModel.contains("AudioFileService.remove(recording.audioURL)"))
    }

    // MARK: 9~13. 시드 · AI 생성 항목, 세 종류 모두 같은 구현을 지난다

    @Test func seedAndGeneratedEntriesUseTheSameRequestPath() throws {
        for entry in [seedEntry(), generatedEntry()] {
            let payload = VocabularySpeakingCoachRequest(
                entry: entry,
                transcript: "I go there a lot.",
                targetLevel: .IH
            )
            #expect(payload.entryId == entry.id)
            #expect(payload.term == entry.term)
            #expect(payload.type == entry.type)
        }
        #expect(generatedEntry().id.hasPrefix("ai-"))
        #expect(!seedEntry().id.hasPrefix("ai-"))

        // 출처별로 화면이나 요청을 따로 만들지 않았다.
        let view = try source("Views/Screens/Main/Vocabulary/VocabularySpeakingCoachViews.swift")
        #expect(!view.contains("source == \"ai\""))
        #expect(!view.contains("hasPrefix(\"ai-\")"))
    }

    /// 저장·조회도 시드 id와 생성 id를 가리지 않는다.
    @Test func generatedEntryResultsAreStoredAndFoundToo() throws {
        let service = makeService(try makeMemoryContainer())
        let entry = generatedEntry()
        let result = try makeResult(resultID: "gen-result-1", entryID: entry.id)

        try service.saveVocabularyCoachResult(result)

        try expectSame(try service.vocabularyCoachResults(entryID: entry.id).first, result)
        #expect(try service.vocabularyCoachResults(entryID: entry.id).count == 1)
        #expect(try service.vocabularyCoachResults(entryID: "seed-cafes-001").isEmpty)
    }

    /// 지시문은 종류별로 결정적이다. 지시문 한 줄을 만들려고 AI를 부르지 않는다.
    @Test func speakingPromptIsLocalAndDeterministic() throws {
        let word = seedEntry(type: .word)
        let phrase = generatedEntry(type: .phrase, term: "spend time with")
        let pattern = generatedEntry(type: .pattern, term: "one of my favorite places")

        #expect(
            VocabularySpeakingPrompt.instruction(for: word)
                == "crowded를 사용해서 한두 문장으로 말해보세요."
        )
        #expect(
            VocabularySpeakingPrompt.instruction(for: phrase)
                == "spend time with를 사용해서 한두 문장으로 말해보세요."
        )
        #expect(
            VocabularySpeakingPrompt.instruction(for: pattern)
                == "one of my favorite places 표현을 사용해서 한두 문장으로 말해보세요."
        )
        // 같은 입력이면 언제나 같은 결과.
        #expect(
            VocabularySpeakingPrompt.instruction(for: word)
                == VocabularySpeakingPrompt.instruction(for: word)
        )
        // 주제 힌트도 로컬이다. 주제가 없으면 아무것도 붙이지 않는다.
        #expect(VocabularySpeakingPrompt.topicHint(for: word) == "카페 이야기를 떠올리면 말하기 쉬워요.")
        let noTopic = VocabularyEntry(
            id: "x",
            term: "cozy",
            type: .word,
            meaningKo: "아늑한",
            exampleEn: "The room is cozy.",
            exampleKo: "그 방은 아늑해요.",
            source: "seed"
        )
        #expect(VocabularySpeakingPrompt.topicHint(for: noTopic) == nil)

        // 예문을 그대로 따라 읽게 하지 않는다 — 받아쓰기가 아니라 실제 사용이 목표다.
        let model = try source("Models/VocabularyCoach.swift")
        #expect(!model.contains("exampleEn"))
    }

    /// 실제로 세 종류 항목 모두 코치 화면 경로를 탈 수 있다(경로가 항목 종류를 가리지 않는다).
    @Test func everyVocabularyTypeReachesTheCoachRoute() throws {
        for type in VocabularyItemType.allCases {
            let entry = generatedEntry(type: type, term: "term-\(type.rawValue)")
            let route = VocabularyRoute.speakingCoach(entry)
            if case let .speakingCoach(carried) = route {
                #expect(carried == entry)
            } else {
                Issue.record("경로가 항목을 잃었다")
            }
        }

        let list = try source("Views/Screens/Main/Vocabulary/VocabularyListViews.swift")
        // 진입점은 단어 상세의 CTA 하나. 종류별 분기가 없다.
        #expect(list.contains("VocabularyRoute.speakingCoach(entry)"))
        #expect(list.contains("직접 말해보기"))
    }

    // MARK: 14. 결과 이력 · 최신 결과 조회

    @Test func coachHistoryShowsNewestFirst() throws {
        let service = makeService(try makeMemoryContainer())
        try service.saveVocabularyCoachResult(
            makeResult(resultID: "older", createdAt: "2026-08-20T09:00:00.000000Z")
        )
        try service.saveVocabularyCoachResult(
            makeResult(resultID: "newest", createdAt: "2026-08-28T09:00:00.000000Z")
        )
        try service.saveVocabularyCoachResult(
            makeResult(resultID: "middle", createdAt: "2026-08-24T09:00:00.000000Z")
        )

        let history = try service.vocabularyCoachResults(entryID: "seed-cafes-001")
        #expect(history.map(\.resultId) == ["newest", "middle", "older"])
        // 일부러 다시 분석해 만든 결과가 조용히 사라지지 않는다.
        #expect(history.count == 3)
    }

    // MARK: 15. 같은 답변을 실수로 두 번 유료 분석하지 않는다

    /// 다시 녹음했지만 결국 같은 말을 했다면 이미 값을 치른 결과가 있다.
    /// 표기(대소문자 · 공백)만 다른 경우도 같은 답변으로 본다.
    @Test func sameCompletedAttemptIsReusedInsteadOfPaidAgain() throws {
        let service = makeService(try makeMemoryContainer())
        let transcript = "My favorite cafe is very crowded because many people go there."
        let result = try makeResult(transcript: transcript)
        try service.saveVocabularyCoachResult(result)

        try expectSame(
            try service.vocabularyCoachResult(
                entryID: result.entryId,
                transcript: "  MY FAVORITE cafe   is very crowded because many people go there. "
            ),
            result
        )
        // 다른 답변은 재사용하지 않는다 — 새 분석이 필요하다.
        #expect(
            try service.vocabularyCoachResult(
                entryID: result.entryId,
                transcript: "I went to the park with my dog."
            ) == nil
        )
        // 다른 항목의 같은 답변도 재사용하지 않는다.
        #expect(
            try service.vocabularyCoachResult(entryID: "other-entry", transcript: transcript) == nil
        )

        // 뷰모델은 유료 요청 **전에** 이 조회를 먼저 한다.
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        let start = try #require(viewModel.range(of: "private func run("))
        let body = viewModel[start.upperBound...]
        let lookup = try #require(body.range(of: "persistence.vocabularyCoachResult("))
        let request = try #require(body.range(of: "api.coachVocabulary("))
        #expect(lookup.lowerBound < request.lowerBound)
    }

    @Test func transcriptKeyIgnoresCaseAndWhitespaceOnly() {
        #expect(
            VocabularySpeakingPrompt.transcriptKey("  It   GETS crowded.\n")
                == "it gets crowded."
        )
        #expect(VocabularySpeakingPrompt.transcriptKey("   ").isEmpty)
    }

    // MARK: 16. 코칭을 보는 것은 학습 상태를 건드리지 않는다

    /// 저장 · 익힘 · 복습 일정은 `VocabularyStateRecord`의 몫이다. 코칭 결과가
    /// 생기거나 다시 열려도 그 값은 그대로여야 한다.
    @Test func viewingCoachingDoesNotTouchStudyState() throws {
        let service = makeService(try makeMemoryContainer())
        let entry = seedEntry()
        let now = try #require(LocalCalendarDate.date(from: "2026-08-28", timeZone: seoul))
        try service.setVocabularySaved(entryID: entry.id, isSaved: true, now: now)
        try service.recordVocabularyAnswer(
            entryID: entry.id,
            knewIt: true,
            timeZone: seoul,
            now: now
        )
        let before = try #require(try service.vocabularyStates().first { $0.entryID == entry.id })
        let snapshot = (
            before.statusRaw,
            before.isSaved,
            before.consecutiveSuccessCount,
            before.failureCount,
            before.nextReviewLocalDate,
            before.lastStudiedLocalDate
        )

        try service.saveVocabularyCoachResult(makeResult(entryID: entry.id))
        _ = try service.vocabularyCoachResults(entryID: entry.id)
        _ = try service.vocabularyCoachResult(entryID: entry.id, transcript: "anything")

        let after = try #require(try service.vocabularyStates().first { $0.entryID == entry.id })
        #expect(after.statusRaw == snapshot.0)
        #expect(after.isSaved == snapshot.1)
        #expect(after.consecutiveSuccessCount == snapshot.2)
        #expect(after.failureCount == snapshot.3)
        #expect(after.nextReviewLocalDate == snapshot.4)
        #expect(after.lastStudiedLocalDate == snapshot.5)
        #expect(try service.vocabularyStates().count == 1)

        // 코칭이 준 "함께 써볼 표현"을 새 단어장 항목으로 자동 저장하지 않는다.
        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        #expect(!viewModel.contains("setVocabularySaved"))
        #expect(!viewModel.contains("recordVocabularyAnswer"))
        #expect(!viewModel.contains("saveVocabularyGeneratedSet"))
    }

    // MARK: 비용은 데일리 토큰 1개

    /// 단어장 전용 화폐를 만들지 않았다. 잔액은 기존 `UsageStatus.totalRemaining`이고
    /// 비용은 1이며, 그 숫자가 CTA 문구에 그대로 실린다.
    @Test func coachingCostsExactlyOneDailyToken() throws {
        #expect(VocabularyCoachViewModel.tokenCost == 1)
        // 표현 하나를 한두 문장으로 말하는 연습이다. 데일리 답변(180초)보다 짧게 끊는다.
        #expect(VocabularyCoachViewModel.maxAnswerSeconds == 60)
        #expect(VocabularyCoachViewModel.maxAnswerSeconds < PracticeViewModel.maxAnswerSeconds)

        let view = try source("Views/Screens/Main/Vocabulary/VocabularySpeakingCoachViews.swift")
        #expect(view.contains("DailyTokenIcon("))
        #expect(view.contains("데일리 토큰 \\(VocabularyCoachViewModel.tokenCost)개를 사용해요"))
        #expect(view.contains("AI에게 분석받기"))
        // 비용 표시가 CTA보다 앞에 온다 — 누르기 전에 알아야 한다.
        let card = try #require(view.range(of: "private var coachCTA: some View"))
        let body = view[card.upperBound...]
        let cost = try #require(body.range(of: "DailyTokenIcon("))
        let cta = try #require(body.range(of: "title: viewModel.failureMessage == nil"))
        #expect(cost.lowerBound < cta.lowerBound)

        let viewModel = try source("ViewModels/VocabularyCoachViewModel.swift")
        #expect(viewModel.contains("usage?.totalRemaining"))
    }

    /// 로딩 문구도 기존 AI 로딩 관례를 쓴다. 제공자 이름을 노출하지 않는다.
    @Test func loadingUsesTheExistingAIOverlay() throws {
        #expect(AsyncOperationKind.vocabularyCoach.title == "표현을 자연스럽게 썼는지 확인하고 있어요")

        let view = try source("Views/Screens/Main/Vocabulary/VocabularySpeakingCoachViews.swift")
        #expect(view.contains("AILoadingOverlay("))
        #expect(view.contains("kind: .vocabularyCoach"))
        for forbidden in ["OpenAI", "openai", "gpt", "model:"] {
            #expect(!view.contains(forbidden))
        }
    }

    // MARK: 탭 구성은 그대로

    @Test func fiveTabNavigationIsUnchanged() {
        #expect(MainTab.allCases.count == 5)
        #expect(MainTab.allCases.map(\.title) == ["데일리", "모의고사", "플래너", "단어장", "통계"])
        #expect(MainTab.vocabulary.rawValue == 3)
    }
}
