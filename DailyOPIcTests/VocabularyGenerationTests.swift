import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// AI 맞춤 단어장(P14.2). 서버 응답 디코딩 · 기기 저장 · 기존 학습 엔진 재사용,
/// 그리고 "조작 1회 = 데일리 토큰 1개"라는 과금 배선을 고정한다.
///
/// `AppEnvironment.api`는 프로토콜이 아니라 구체 `actor APIClient`라 가짜 서버를
/// 넣을 수 없다. 그래서 뷰모델 쪽 계약은 이 저장소가 이미 쓰는 방식(소스 계약 검사,
/// `DailyTokenEnforcementTests` 참고)으로 확인한다. 어느 테스트도 네트워크를 부르지 않는다.
@MainActor
struct VocabularyGenerationTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    // MARK: 픽스처

    /// 서버가 실제로 내려주는 모양 그대로의 JSON(백엔드 응답에서 그대로 가져온 필드 구성).
    /// `createdAt`은 파이썬이 내는 마이크로초 6자리 형식이다 — 앱이 이걸 못 읽으면
    /// 기능 전체가 죽으므로 픽스처에서 그 형태를 유지한다.
    private func payloadJSON(
        setID: String = "c985ffc9040bab5adcd103fa",
        createdAt: String = "2026-08-28T13:16:11.139663Z"
    ) -> Data {
        let types: [(String, [String])] = [
            ("word", ["crowded", "cozy", "spacious", "brew", "aroma",
                      "refill", "seasonal", "chilly", "loyal", "affordable"]),
            ("phrase", ["grab a coffee", "hang out", "wind down", "catch up with",
                        "drop by", "kill time", "stop by", "settle in",
                        "run into", "take a break"]),
            ("pattern", ["I usually go there when", "What I like about it is",
                         "The reason I keep going back is", "If I had to pick one",
                         "It has become part of my routine to",
                         "Compared to other places", "One thing that changed is",
                         "Whenever I get the chance", "The last time I went",
                         "That is why I would say"])
        ]
        var entries: [String] = []
        var index = 0
        for (type, terms) in types {
            for term in terms {
                entries.append("""
                {"id":"ai-\(setID)-\(String(format: "%02d", index))","term":"\(term)",\
                "type":"\(type)","meaningKo":"뜻 \(index)",\
                "exampleEn":"The place I usually go to is \(term).",\
                "exampleKo":"카페 이야기를 할 때 이렇게 말할 수 있어요.",\
                "collocations":[],"topics":["cafes"],"usageRoles":["description"],\
                "recommendedLevels":["IH"],"source":"ai"}
                """)
                index += 1
            }
        }
        let json = """
        {"setId":"\(setID)","topic":"cafes","targetLevel":"IH",\
        "createdAt":"\(createdAt)","entries":[\(entries.joined(separator: ","))],"source":"ai"}
        """
        return Data(json.utf8)
    }

    private func makeSet(
        setID: String = "c985ffc9040bab5adcd103fa",
        createdAt: String = "2026-08-28T13:16:11.139663Z"
    ) throws -> VocabularyGeneratedSet {
        try JSONCoding.decoder.decode(
            VocabularyGeneratedSet.self,
            from: payloadJSON(setID: setID, createdAt: createdAt)
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

    // MARK: 1. 응답 디코딩

    /// 서버가 준 30개짜리 세트를 그대로 읽는다. 날짜는 마이크로초 6자리로 온다.
    @Test func decodesGeneratedSetResponse() throws {
        let set = try makeSet()

        #expect(set.setId == "c985ffc9040bab5adcd103fa")
        #expect(set.id == set.setId)
        #expect(set.topic == .cafes)
        #expect(set.targetLevel == .IH)
        #expect(set.source == "ai")
        #expect(set.entries.count == VocabularyGenerationViewModel.entryCount)
        // 마이크로초 6자리를 읽어 낸다(파이썬이 내는 형식). 밀리초 아래는 버려도 된다.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expected = try #require(formatter.date(from: "2026-08-28T13:16:11Z"))
        #expect(abs(set.createdAt.timeIntervalSince(expected)) < 1)

        let first = try #require(set.entries.first)
        #expect(first.term == "crowded")
        #expect(first.type == .word)
        #expect(first.topics == [.cafes])
        #expect(first.recommendedLevels == [.IH])
        #expect(first.usageRoles == [.description])
        #expect(!first.meaningKo.isEmpty)
        #expect(!first.exampleEn.isEmpty)
        #expect(!first.exampleKo.isEmpty)
    }

    // MARK: 2. 저장 (앱을 껐다 켜도 남는다)

    /// 메모리 저장소가 아니라 파일 저장소로 컨테이너를 두 번 연다.
    /// 앱 재시작을 흉내 내는 유일한 방법이고, 세트가 통째로(30개 전부) 살아남아야 한다.
    @Test func generatedSetSurvivesContainerRestart() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vocab-generation-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ModelConfiguration(url: url)
        let set = try makeSet()

        let first = try ModelContainer(for: Schema.dailyOPIc, configurations: configuration)
        try makeService(first).saveVocabularyGeneratedSet(set)

        // 새 컨테이너 = 재시작. 앞의 인스턴스는 여기서 버린다.
        let second = try ModelContainer(for: Schema.dailyOPIc, configurations: configuration)
        let restored = try makeService(second).vocabularyGeneratedSets()

        #expect(restored.count == 1)
        let record = try #require(restored.first)
        #expect(record.setID == set.setId)
        #expect(record.topic == .cafes)
        #expect(record.targetLevel == .IH)
        #expect(record.entries.count == VocabularyGenerationViewModel.entryCount)
        #expect(record.entries.map(\.id) == set.entries.map(\.id))
        #expect(record.entries.map(\.term) == set.entries.map(\.term))
    }

    /// 같은 조작을 재시도해 같은 세트가 다시 와도 두 줄이 되지 않는다.
    @Test func savingTheSameSetTwiceKeepsOneRow() throws {
        let service = makeService(try makeMemoryContainer())
        let set = try makeSet()

        try service.saveVocabularyGeneratedSet(set)
        try service.saveVocabularyGeneratedSet(set)

        #expect(try service.vocabularyGeneratedSets().count == 1)
    }

    // MARK: 3. id 충돌

    /// 생성 항목 id는 세트 id를 품는다. 세트끼리도, 번들 시드와도 겹치지 않는다.
    @Test func generatedEntryIDsDoNotCollide() throws {
        let service = makeService(try makeMemoryContainer())
        let first = try makeSet(setID: "aaa111", createdAt: "2026-08-27T00:00:00.000000Z")
        let second = try makeSet(setID: "bbb222", createdAt: "2026-08-28T00:00:00.000000Z")
        try service.saveVocabularyGeneratedSet(first)
        try service.saveVocabularyGeneratedSet(second)

        let ids = try service.vocabularyGeneratedSets().flatMap { $0.entries.map(\.id) }
        #expect(ids.count == 2 * VocabularyGenerationViewModel.entryCount)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids).isDisjoint(with: Set(VocabularyCatalog.all.map(\.id))))
        #expect(ids.allSatisfy { $0.hasPrefix("ai-") })
    }

    // MARK: 4. 목록 정렬

    @Test func generatedSetListShowsNewestFirst() throws {
        let service = makeService(try makeMemoryContainer())
        try service.saveVocabularyGeneratedSet(
            makeSet(setID: "older", createdAt: "2026-08-20T09:00:00.000000Z")
        )
        try service.saveVocabularyGeneratedSet(
            makeSet(setID: "newest", createdAt: "2026-08-28T09:00:00.000000Z")
        )
        try service.saveVocabularyGeneratedSet(
            makeSet(setID: "middle", createdAt: "2026-08-24T09:00:00.000000Z")
        )

        let sets = try service.vocabularyGeneratedSets()
        #expect(sets.map(\.setID) == ["newest", "middle", "older"])

        let record = try #require(sets.first)
        #expect(VocabularyGeneratedSetRecord.title(for: record) == "카페 · IH")
        #expect(VocabularyGeneratedSetRecord.dateText(record.createdAt).count == 10)
    }

    // MARK: 5. 상세 구성

    /// 서버가 정한 구성(단어 10 · 표현 10 · 패턴 10)이 화면이 세는 방식 그대로 나온다.
    @Test func setDetailSplitsEntriesByType() throws {
        let set = try makeSet()
        for type in VocabularyItemType.allCases {
            #expect(set.entries(of: type).count == 10)
        }

        let service = makeService(try makeMemoryContainer())
        try service.saveVocabularyGeneratedSet(set)
        let record = try #require(try service.vocabularyGeneratedSets().first)
        for type in VocabularyItemType.allCases {
            #expect(record.entries.filter { $0.type == type }.count == 10)
        }
    }

    // MARK: 6. 기존 학습 · 복습 엔진 재사용

    /// 생성 항목이라고 다른 복습 알고리즘을 쓰지 않는다. 시드와 같은
    /// `VocabularyStudySession` · `VocabularyReviewPolicy` · `VocabularyStateRecord`를 지난다.
    @Test func generatedEntriesRunThroughTheExistingStudyEngine() throws {
        let service = makeService(try makeMemoryContainer())
        let set = try makeSet()
        try service.saveVocabularyGeneratedSet(set)

        var session = VocabularyStudySession(entries: set.entries)
        let entryID = try #require(session.current?.id)
        #expect(entryID.hasPrefix("ai-"))
        session.answer(knewIt: true)
        #expect(session.current?.id != entryID)

        let now = try #require(LocalCalendarDate.date(from: "2026-08-28", timeZone: seoul))
        try service.recordVocabularyAnswer(
            entryID: entryID,
            knewIt: true,
            timeZone: seoul,
            now: now
        )

        let state = try #require(try service.vocabularyStates().first { $0.entryID == entryID })
        #expect(state.status == .reviewing)
        #expect(state.consecutiveSuccessCount == 1)
        // 첫 성공은 1일 뒤. 시드 항목과 완전히 같은 간격 규칙이다.
        #expect(state.nextReviewLocalDate == "2026-08-29")
        #expect(state.lastStudiedLocalDate == "2026-08-28")

        let due = VocabularyDailyProgress.dueIDs(
            states: try service.vocabularyStates(),
            today: "2026-08-29"
        )
        #expect(due == [entryID])
        // 복습 큐가 id로 항목을 되찾을 때 생성 항목도 함께 봐야 한다.
        let resolved = VocabularyCatalog.entries(
            ids: due,
            in: VocabularyCatalog.all + set.entries
        )
        #expect(resolved.map(\.id) == [entryID])
    }

    // MARK: 7. 저장 / 저장 해제

    @Test func generatedEntryCanBeSavedAndUnsaved() throws {
        let service = makeService(try makeMemoryContainer())
        let set = try makeSet()
        try service.saveVocabularyGeneratedSet(set)
        let entry = try #require(set.entries.first)
        let combined = VocabularyCatalog.all + set.entries

        try service.setVocabularySaved(entryID: entry.id, isSaved: true)
        var savedIDs = try service.vocabularyStates().filter(\.isSaved).map(\.entryID)
        #expect(VocabularyCatalog.entries(ids: savedIDs, in: combined).map(\.id) == [entry.id])
        // 시드만 보면 생성 항목이 "저장한 단어"에서 조용히 사라진다.
        #expect(VocabularyCatalog.entries(ids: savedIDs).isEmpty)

        try service.setVocabularySaved(entryID: entry.id, isSaved: false)
        savedIDs = try service.vocabularyStates().filter(\.isSaved).map(\.entryID)
        #expect(savedIDs.isEmpty)
    }

    // MARK: 8. 익힌 단어

    /// 연속 5회 성공이면 시드든 생성 항목이든 똑같이 `.mastered`가 되고,
    /// 합친 목록에서 되찾을 수 있어야 "익힌 단어"에 나타난다.
    @Test func masteredGeneratedEntryAppearsInTheMasteredList() throws {
        let service = makeService(try makeMemoryContainer())
        let set = try makeSet()
        try service.saveVocabularyGeneratedSet(set)
        let entry = try #require(set.entries.first)

        for day in 0..<5 {
            let localDate = "2026-08-\(String(format: "%02d", 20 + day))"
            let now = try #require(LocalCalendarDate.date(from: localDate, timeZone: seoul))
            try service.recordVocabularyAnswer(
                entryID: entry.id,
                knewIt: true,
                timeZone: seoul,
                now: now
            )
        }

        let states = try service.vocabularyStates()
        let mastered = VocabularyCatalog.entries(
            ids: states.filter { $0.status == .mastered }.map(\.entryID),
            in: VocabularyCatalog.all + set.entries
        )
        #expect(mastered.map(\.id) == [entry.id])
    }

    // MARK: 9. 비용은 데일리 토큰 1개

    /// 단어장 전용 화폐를 만들지 않았다. 잔액은 기존 `UsageStatus.totalRemaining`이고
    /// 비용은 1이며, 그 숫자가 CTA 문구에 그대로 실린다.
    @Test func generationCostsExactlyOneDailyToken() throws {
        #expect(VocabularyGenerationViewModel.tokenCost == 1)
        #expect(VocabularyGenerationViewModel.entryCount == 30)

        let sheet = try source("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift")
        #expect(sheet.contains("데일리 토큰 \\(VocabularyGenerationViewModel.tokenCost)개를 사용해요"))
        #expect(sheet.contains("DailyTokenIcon("))
        #expect(sheet.contains("30개 만들기"))
        // 새 화폐·새 구매 경로를 만들지 않았다.
        #expect(!sheet.contains("단어 토큰"))
        #expect(!sheet.contains("Purchase"))

        let viewModel = try source("ViewModels/VocabularyGenerationViewModel.swift")
        #expect(viewModel.contains("usage?.totalRemaining"))
        #expect(viewModel.contains("PaywallView") == false)
        #expect(viewModel.contains(".tokenExhausted"))
    }

    // MARK: 10. 이미 만든 세트를 여는 것은 공짜

    /// 목록 · 상세 · 학습은 저장된 항목을 읽을 뿐이다. AI를 부르는 자리는
    /// 앱 전체에서 뷰모델 한 곳뿐이고, 단어장 화면에는 없다.
    @Test func viewingAnExistingSetNeverRequestsAI() throws {
        let callSites = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("api.generateVocabulary(") }
        #expect(callSites.count == 1)

        let screen = try source("Views/Screens/Main/Vocabulary/VocabularyScreen.swift")
        #expect(!screen.contains("generateVocabulary"))
        // 세트를 여는 경로는 저장된 레코드를 찾는 것뿐이다.
        #expect(screen.contains("generatedSets.first { $0.setID == setID }"))

        let views = try source("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift")
        #expect(!views.contains("generateVocabulary"))
    }

    // MARK: 11. 재시도는 같은 조작

    /// 실패 후 다시 누르는 것은 새 조작이 아니다. 같은 `operationID`를 그대로 보내야
    /// 서버가 이미 만든 세트를 돌려주고 토큰이 두 번 나가지 않는다.
    /// 새 id는 저장까지 끝난 뒤에만 생긴다.
    @Test func retryKeepsTheSameOperationID() throws {
        let viewModel = try source("ViewModels/VocabularyGenerationViewModel.swift")
        #expect(viewModel.contains("requestID: operationID"))
        // 선언 1회 + 성공 뒤 교체 1회. 실패 경로에서 새로 만들면 여기서 걸린다.
        #expect(viewModel.components(separatedBy: "operationID = UUID()").count - 1 == 2)
        let afterSuccess = try #require(
            viewModel.range(of: "try persistence.saveVocabularyGeneratedSet(set")
        )
        let tail = viewModel[afterSuccess.upperBound...]
        #expect(tail.contains("operationID = UUID()"))
        // 연타가 두 번째 조작이 되지 않게 실행 중에는 다시 시작하지 않는다.
        #expect(viewModel.contains("guard !isGenerating else { return }"))
    }

    // MARK: 12. 토큰이 0이면 요청 자체를 시작하지 않는다

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

        let viewModel = try source("ViewModels/VocabularyGenerationViewModel.swift")
        let start = try #require(viewModel.range(of: "private func run("))
        let body = viewModel[start.upperBound...]
        let precheck = try #require(body.range(of: "if hasNoTokens {"))
        let request = try #require(body.range(of: "api.generateVocabulary("))
        // 잔액 확인이 요청보다 먼저다. 확보에 실패하면 요청까지 가지 않는다.
        #expect(precheck.lowerBound < request.lowerBound)
        #expect(body[precheck.upperBound...].contains("guard allowRecovery, await recoverToken() else { return }"))

        let sheet = try source("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift")
        #expect(sheet.contains("AI 맞춤 단어 생성을 위해 데일리 토큰 1개가 필요합니다."))
    }

    // MARK: 13. 탭 구성은 그대로

    @Test func fiveTabNavigationIsUnchanged() {
        #expect(MainTab.allCases.count == 5)
        #expect(MainTab.allCases.map(\.title) == ["데일리", "모의고사", "플래너", "단어장", "통계"])
        #expect(MainTab.vocabulary.rawValue == 3)
    }
}
