import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 오늘의 추가 20개(P14.6).
///
/// 이 파일이 지키는 약속은 하나다: **새 단어를 만드는 행위만 값을 치른다.**
/// 화면을 열고 주제를 고르고 확인 문구를 읽고 닫는 것은 전부 0 토큰이고,
/// 값이 나가는 순간은 사용자가 직접 [20개 만들기]를 누른 그 한 번뿐이다.
/// 그리고 그 한 번은 앱이 도중에 죽어도 두 번 결제되지 않는다.
///
/// `AppEnvironment.api`가 구체 타입이라 가짜 서버를 넣을 수 없다. 그래서 뷰모델 쪽
/// 배선은 이 저장소가 이미 쓰는 소스 계약 검사로 확인한다(네트워크는 부르지 않는다).
@MainActor
struct VocabularyExtraTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    // MARK: 도우미

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func code(_ file: String) -> String {
        file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let sheetPath = "Views/Screens/Main/Vocabulary/VocabularyExtraViews.swift"
    private let viewModelPath = "ViewModels/VocabularyGenerationViewModel.swift"
    private let screenPath = "Views/Screens/Main/Vocabulary/VocabularyScreen.swift"

    private func makeService() throws -> PersistenceService {
        let container = try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func makeSet(setID: String = "extra-set-1") throws -> VocabularyGeneratedSet {
        let entries = (0..<VocabularyGenerationViewModel.extraEntryCount).map { index in
            """
            {"id":"ai-\(setID)-\(index)","term":"term \(index)","type":"word",\
            "meaningKo":"뜻 \(index)","exampleEn":"An example \(index).",\
            "exampleKo":"예문 \(index).","collocations":[],"topics":["cafes"],\
            "usageRoles":["description"],"recommendedLevels":["IH"],"source":"ai"}
            """
        }
        let json = """
        {"setId":"\(setID)","topic":"cafes","targetLevel":"IH",\
        "createdAt":"2026-08-28T13:16:11.139663Z",\
        "entries":[\(entries.joined(separator: ","))],"source":"ai"}
        """
        return try JSONCoding.decoder.decode(VocabularyGeneratedSet.self, from: Data(json.utf8))
    }

    private func makePreferences() -> AppPreferences {
        let suite = "extra-tests-\(UUID().uuidString)"
        return AppPreferences(defaults: UserDefaults(suiteName: suite)!)
    }

    // MARK: 1. 계약은 정확히 20개다

    /// 만든 묶음은 기본 20개와 같은 크기다. 더 만들어서 남는 것을 버리지 않는다.
    @Test func theExtraContractIsExactlyTwenty() throws {
        #expect(VocabularyGenerationViewModel.extraEntryCount == 20)
        #expect(VocabularyGenerationViewModel.extraEntryCount == VocabularyDailySet.dailyTarget)
        // 앱이 받은 목록을 잘라 20개인 척하지 않는다.
        let viewModel = code(try source(viewModelPath))
        #expect(!viewModel.contains("entries.prefix"))
        #expect(!viewModel.contains("Array(set.entries"))
        let sheet = code(try source(sheetPath))
        #expect(!sheet.contains("entries.prefix"))
    }

    /// 서버가 개수를 소유한다. 앱은 **어느 경로로 보내는지**로만 말한다 —
    /// 요청 본문에는 쓰임새도 개수도 없다(P14.6.1).
    @Test func theTodayRequestCarriesNoPurposeAndNoCount() throws {
        let request = TodayVocabularyGenerationRequest(
            topic: .cafes,
            targetLevel: .IH,
            excludeTerms: []
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(request))
                as? [String: Any]
        )
        #expect(json["purpose"] == nil)
        #expect(json["count"] == nil)
        #expect(json["size"] == nil)
        #expect(Set(json.keys) == ["topic", "targetLevel", "excludeTerms"])
    }

    /// 단어를 만드는 경로는 앱 전체에서 하나뿐이다(P14.6.2). 예전 30개 경로는 없다.
    @Test func theOnlyCreationEndpointIsTheTodayOne() throws {
        let api = code(try source("Services/API/APIClient.swift"))
        #expect(api.contains("path: \"/v1/vocabulary/today/generate\""))
        #expect(!api.contains("path: \"/v1/vocabulary/generate\""))
        #expect(api.contains("func generateTodayVocabulary("))
        #expect(api.contains("request payload: TodayVocabularyGenerationRequest"))
        #expect(!api.contains("func generateVocabulary("))

        let viewModel = code(try source(viewModelPath))
        #expect(viewModel.contains("api.generateTodayVocabulary("))
        #expect(viewModel.contains("request: TodayVocabularyGenerationRequest("))
        // 요청 타입도 하나뿐이라 섞일 갈림길 자체가 없다.
        #expect(!viewModel.contains(": VocabularyGenerationRequest("))
        #expect(!viewModel.contains("if purpose == "))
    }

    /// 저장 표식은 로컬 전용이라 endpoint를 지웠다고 같이 지우지 않는다(P14.6.2 §10).
    /// 예전 기기에 남아 있는 세트가 `custom_set`으로 저장돼 있고, 그 값을 읽어야 한다.
    @Test func theLocalPurposeMarkerSurvivesTheEndpointRemoval() throws {
        #expect(VocabularyGenerationPurpose.customSet.rawValue == "custom_set")
        #expect(VocabularyGenerationPurpose.todayExtra.rawValue == "today_extra")
        let records = code(try source("Models/LocalRecords.swift"))
        #expect(records.contains("var purposeRaw: String = VocabularyGenerationPurpose.customSet.rawValue"))
        // 서버로는 나가지 않는다 — 요청 본문에 쓰임새 필드가 없다.
        let models = code(try source("Models/VocabularyGeneration.swift"))
        #expect(!models.contains("let purpose"))
    }

    // MARK: 2. 과금 경계

    /// 화면을 여는 것으로는 아무것도 시작되지 않는다. `.task`가 하는 일은 잔액 읽기뿐이고,
    /// 생성은 사용자가 직접 누른 버튼 안에서 **한 번만** 불린다.
    @Test func openingTheSheetSpendsNothing() throws {
        let sheet = code(try source(sheetPath))
        #expect(sheet.contains(".task { await viewModel.refreshUsage() }"))
        #expect(!sheet.contains(".onAppear"))
        // 생성 호출은 화면 전체에 딱 하나다.
        #expect(sheet.components(separatedBy: "viewModel.generate(").count - 1 == 1)
        // 그 하나는 버튼 동작 안에 있다 — 화면 순서도 주제 → 확인 → 실행이다.
        let picker = try #require(sheet.range(of: "topicPicker\n"))
        let confirmation = try #require(sheet.range(of: "confirmation\n"))
        let button = try #require(sheet.range(of: "PrimaryButton("))
        let call = try #require(sheet.range(of: "viewModel.generate("))
        #expect(picker.lowerBound < confirmation.lowerBound)
        #expect(confirmation.lowerBound < button.lowerBound)
        #expect(button.lowerBound < call.lowerBound)
        #expect(sheet.contains("어떤 주제로 만들까요?"))
        // 주제를 고르지 않으면 실행 자체가 없다.
        #expect(sheet.contains("isDisabled: topic == nil"))
        #expect(sheet.contains("guard let topic else { return }"))
    }

    /// 누르기 전에 무엇을 얼마에 받는지 말한다. 값은 데일리 토큰 1개다.
    @Test func theConfirmationStatesWhatAndHowMuch() throws {
        let sheet = code(try source(sheetPath))
        #expect(sheet.contains("\\(topic.label) 단어 \\(count)개를 만들까요?"))
        #expect(sheet.contains("데일리 토큰 \\(VocabularyGenerationViewModel.tokenCost)개를 사용해요."))
        #expect(sheet.contains("\\(count)개 만들기"))
        // 지금 잔액도 함께 말한다. 그 값은 이미 읽어 둔 것이고 새 출처를 만들지 않는다.
        #expect(sheet.contains("현재 데일리 토큰 \\(balance)개"))
        #expect(sheet.contains("viewModel.dailyTokenCount"))
        #expect(VocabularyGenerationViewModel.tokenCost == 1)
    }

    /// 부족분을 시드에서 공짜로 뽑아 추가 20개인 척하지 않는다.
    @Test func thereIsNoFreeFallback() throws {
        let sheet = code(try source(sheetPath))
        #expect(!sheet.contains("VocabularyCatalog.entries("))
        #expect(!sheet.contains("VocabularyDailySetPlanner"))
        #expect(!sheet.contains("VocabularyCatalog.all"))
        // 주제 목록만 시드에서 읽는다(전용 주제를 새로 만들지 않는다).
        #expect(sheet.contains("ForEach(VocabularyCatalog.topics)"))
        #expect(VocabularyCatalog.topics == VocabularyTopic.allCases)
    }

    /// 잔액이 0이면 요청도 제공자도 부르지 않는다 — 확인이 먼저다.
    @Test func zeroTokensBlocksBeforeTheRequest() throws {
        let viewModel = code(try source(viewModelPath))
        let guardIndex = try #require(viewModel.range(of: "if hasNoTokens {"))
        let request = try #require(viewModel.range(of: "api.generateTodayVocabulary("))
        #expect(guardIndex.lowerBound < request.lowerBound)
        // 광고·페이월은 기존 부족 UX 그대로다(새 결제 흐름을 만들지 않는다).
        #expect(viewModel.contains("recoverToken()"))
        #expect(viewModel.contains("presentPaywall(from: .tokenExhausted)"))
        #expect(!code(try source(sheetPath)).contains("purchase"))
    }

    // MARK: 3. 조작 하나 = 토큰 하나 (중간에 죽어도)

    /// 같은 주제로 다시 시도하면 같은 키다. 이미 값을 치른 세트를 되찾는다.
    @Test func retryingTheSameTopicKeepsTheSameKey() {
        let started = PendingVocabularyExtraOperation(topic: .cafes)
        let resumed = PendingVocabularyExtraOperation.resume(started, topic: .cafes)
        #expect(resumed.operationID == started.operationID)
    }

    /// 주제를 바꾸면 다른 조작이다 — 카페 20개를 요청해 놓고 여행 20개를 받을 수는 없다.
    @Test func changingTheTopicStartsANewOperation() {
        let started = PendingVocabularyExtraOperation(topic: .cafes)
        let resumed = PendingVocabularyExtraOperation.resume(started, topic: .travel)
        #expect(resumed.operationID != started.operationID)
        #expect(resumed.topic == .travel)
    }

    /// 서버가 결과를 재생해 준다고 보장할 수 없을 만큼 시간이 지났으면 새 조작이다.
    /// (같은 키를 보내 봐야 아무것도 돌아오지 않는 창이라면 되살리는 척하지 않는다.)
    @Test func anExpiredOperationIsNotReplayed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stale = PendingVocabularyExtraOperation(
            topic: .cafes,
            createdAt: now.addingTimeInterval(-PendingVocabularyExtraOperation.safeReplayWindow - 1)
        )
        #expect(!stale.isReplayable(now: now))
        #expect(PendingVocabularyExtraOperation.resume(stale, topic: .cafes, now: now)
            .operationID != stale.operationID)
        // 창 안이면 그대로 이어 쓴다.
        let fresh = PendingVocabularyExtraOperation(
            topic: .cafes,
            createdAt: now.addingTimeInterval(-60)
        )
        #expect(fresh.isReplayable(now: now))
        #expect(PendingVocabularyExtraOperation.resume(fresh, topic: .cafes, now: now)
            .operationID == fresh.operationID)
    }

    /// 진행 기록은 디스크에 남는다. 앱을 다시 열어도 같은 신원이 살아 있다.
    @Test func thePendingOperationSurvivesARelaunch() {
        let suite = "extra-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = AppPreferences(defaults: defaults)
        let pending = PendingVocabularyExtraOperation(topic: .cafes)
        preferences.pendingVocabularyExtra = pending

        let reopened = AppPreferences(defaults: defaults)

        // 날짜는 부호화를 거치며 소수점이 깎인다. 신원(키·주제)이 살아 있는지를 본다.
        #expect(reopened.pendingVocabularyExtra?.operationID == pending.operationID)
        #expect(reopened.pendingVocabularyExtra?.topic == pending.topic)
        #expect(reopened.pendingVocabularyExtra?.isReplayable() == true)
        reopened.pendingVocabularyExtra = nil
        #expect(AppPreferences(defaults: defaults).pendingVocabularyExtra == nil)
    }

    /// 순서가 곧 안전장치다: **남기고 → 보내고 → 저장하고 → 지운다.**
    /// 저장 전에 지우면 값을 치른 세트를 되찾을 신원이 사라진다.
    @Test func thePendingRecordIsWrittenBeforeTheRequest() throws {
        let viewModel = code(try source(viewModelPath))
        let write = try #require(viewModel.range(of: "preferences.pendingVocabularyExtra = pending"))
        let request = try #require(viewModel.range(of: "api.generateTodayVocabulary("))
        let save = try #require(viewModel.range(of: "persistence.saveVocabularyGeneratedSet("))
        let clear = try #require(viewModel.range(of: "preferences.pendingVocabularyExtra = nil"))
        #expect(write.lowerBound < request.lowerBound)
        #expect(request.lowerBound < save.lowerBound)
        #expect(save.lowerBound < clear.lowerBound)
        // 만드는 길이 하나뿐이라 기록을 남기는 데 조건이 없다 — 언제나 남긴다.
        #expect(viewModel.contains("PendingVocabularyExtraOperation.resume("))
        #expect(!viewModel.contains("if purpose == "))
        // 새 복구 체계를 만들지 않았다 — 말하기 코치와 같은 자리, 같은 방식이다.
        #expect(code(try source("Services/Persistence/AppPreferences.swift"))
            .contains("var pendingVocabularyCoach: PendingVocabularyCoachOperation?"))
    }

    /// 성공한 뒤에만 다음 조작이 시작될 수 있다. 다음 추가 20개는 새 키 · 새 토큰이다.
    @Test func eachExtraIsItsOwnOperation() throws {
        let viewModel = code(try source(viewModelPath))
        let save = try #require(viewModel.range(of: "persistence.saveVocabularyGeneratedSet("))
        #expect(viewModel[save.upperBound...].contains("operationID = UUID()"))
        #expect(viewModel.contains("guard !isGenerating else { return }"))
        // 이어서 자동으로 또 만들지 않는다.
        let sheet = code(try source(sheetPath))
        #expect(!sheet.contains("while"))
        #expect(sheet.contains("dismiss()"))
    }

    // MARK: 4. 저장 · 격리

    /// 추가 묶음은 예전 세트와 **같은 저장소**에 쓰임새만 적어 남는다.
    @Test func theExtraSetIsStoredWithItsPurpose() throws {
        let service = try makeService()
        try service.saveVocabularyGeneratedSet(try makeSet(), purpose: .todayExtra)
        try service.saveVocabularyGeneratedSet(try makeSet(setID: "custom-1"))

        let records = try service.vocabularyGeneratedSets()
        let extra = try #require(records.first { $0.setID == "extra-set-1" })
        let custom = try #require(records.first { $0.setID == "custom-1" })
        #expect(extra.purpose == .todayExtra)
        #expect(extra.entries.count == VocabularyGenerationViewModel.extraEntryCount)
        // 쓰임새를 말하지 않고 저장한 것은 예전 그대로 맞춤 세트다.
        #expect(custom.purpose == .customSet)
    }

    /// 추가 학습은 오늘의 기본 20개를 덮어쓰지 않는다.
    @Test func theExtraSetNeverTouchesTodaysAssignment() throws {
        let preferences = makePreferences()
        let assigned = VocabularyDailySet(
            localDate: "2026-08-28",
            entryIDs: (0..<20).map { "seed-\($0)" },
            topic: .cafes
        )
        preferences.vocabularyDailySet = assigned

        let service = try makeService()
        try service.saveVocabularyGeneratedSet(try makeSet(), purpose: .todayExtra)

        #expect(preferences.vocabularyDailySet == assigned)
        // 생성 경로 어디에도 오늘의 배정을 건드리는 코드가 없다.
        let viewModel = code(try source(viewModelPath))
        #expect(!viewModel.contains("vocabularyDailySet"))
        #expect(!code(try source(sheetPath)).contains("vocabularyDailySet"))
    }

    /// 추가 20개도 같은 학습 카드 · 같은 복습 엔진을 쓴다(두 번째 엔진이 없다).
    @Test func theExtraSetUsesTheExistingStudyEngine() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("VocabularyRoute.generatedStudy(setID: set.setID)"))
        #expect(screen.contains("kind: .aiSet"))
        let sheet = code(try source(sheetPath))
        #expect(!sheet.contains("VocabularyStudySession"))
        #expect(!sheet.contains("VocabularyReviewPolicy"))

        // 답한 기록은 시드 단어와 똑같이 남고, 복습 예정일도 같은 규칙으로 잡힌다.
        let service = try makeService()
        let day = try #require(LocalCalendarDate.date(from: "2026-08-28", timeZone: seoul))
        try service.recordVocabularyAnswer(
            entryID: "ai-extra-set-1-0", knewIt: true, timeZone: seoul, now: day
        )
        let states = try service.vocabularyStates()
        let state = try #require(states.first { $0.entryID == "ai-extra-set-1-0" })
        #expect(state.lastStudiedLocalDate == "2026-08-28")
        #expect(state.nextReviewLocalDate != nil)
    }

    /// 오늘 학습한 단어 목록은 기본 배정 + 오늘 만든 추가 묶음 **전부**다.
    /// 가장 최근 묶음만 보여주거나 같은 단어를 두 번 세지 않는다.
    @Test func todaysLearnedListIncludesEveryExtra() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("todayExtraSets.flatMap(\\.entries)"))
        #expect(screen.contains("wasStudied(on: todayLocalDate)"))
        #expect(screen.contains("seen.insert($0.id).inserted"))
        #expect(screen.contains("entries: todayLearnedEntries"))
        // 오늘 만든 것만 센다.
        #expect(screen.contains("$0.purpose == .todayExtra"))
    }

    /// 캘린더의 📕 단어 수는 추가 학습도 그대로 센다 — 화면이 아니라 기록이 진실이다.
    @Test func plannerCountsExtraWordsToo() throws {
        let service = try makeService()
        let day = try #require(LocalCalendarDate.date(from: "2026-08-28", timeZone: seoul))
        for index in 0..<3 {
            try service.recordVocabularyAnswer(
                entryID: "ai-extra-set-1-\(index)", knewIt: true, timeZone: seoul, now: day
            )
        }
        let activities = PlannerActivityCalendar.activities(
            vocabulary: try service.studyActivityRecords(),
            dailyAnsweredAt: [],
            mockCompletedAt: [],
            timeZone: seoul
        )
        #expect(activities["2026-08-28"]?.vocabularyStudied == 3)
    }
}
