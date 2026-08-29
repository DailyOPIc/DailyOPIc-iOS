import Foundation
import Testing
@testable import DailyOPIc

/// 데일리 질문 ↔ 단어장 잇기(P14.4).
///
/// 이 파일의 어느 테스트도 네트워크·AI를 부르지 않는다. 그게 이 기능의 요점이다 —
/// 질문 옆에 뜨는 추천은 기기 안 계산이고 값이 0이다. 토큰은 사용자가 "30개 만들기"를
/// 눌러 P14.2 생성을 시작할 때만, 그때도 1개만 나간다.
struct VocabularyQuestionRecommendationTests {

    // MARK: 도우미

    private func entry(
        _ id: String,
        type: VocabularyItemType = .word,
        topics: [VocabularyTopic] = [.cafes],
        roles: [VocabularyUsageRole] = [.description],
        levels: [OPIcLevel] = [],
        source: String = "dailyopic-curated-v1"
    ) -> VocabularyEntry {
        VocabularyEntry(
            id: id,
            term: id,
            type: type,
            meaningKo: "뜻",
            exampleEn: "example",
            exampleKo: "예문",
            topics: topics,
            usageRoles: roles,
            recommendedLevels: levels,
            source: source
        )
    }

    private func question(
        number: Int = 2,
        prompt: String = "Tell me about your favorite cafe.",
        topicId: String?
    ) -> GeneratedQuestion {
        GeneratedQuestion(
            number: number,
            examSection: .survey,
            comboId: nil,
            topic: "cafes",
            prompt: prompt,
            difficulty: .IM2,
            rubricFocus: [],
            questionStyle: .description,
            followUpPrompt: nil,
            topicId: topicId
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

    /// 주석을 뺀 코드만. 계약 검사는 실제로 부르는 것만 봐야 한다 —
    /// "hashValue를 쓰지 않는다"고 적은 주석 때문에 걸리면 안 된다.
    private func code(of file: String) -> String {
        file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let sectionPath = "Views/Screens/Main/Practice/PracticeVocabularySection.swift"
    private let recommenderPath = "Models/VocabularyQuestionRecommendation.swift"

    // MARK: 1. 주제 잇기

    /// 데일리 질문이 들고 있는 topicId는 설문 topicId와 같은 값이고,
    /// `VocabularyTopic`의 rawValue도 그 값에 맞춰 두었다. 그래서 대부분은 그대로 맞는다.
    @Test func mapsDailyQuestionTopicToVocabularyTopic() {
        #expect(VocabularyQuestionTopicMap.topic(for: question(topicId: "cafes")) == .cafes)
        #expect(VocabularyQuestionTopicMap.topic(for: question(topicId: "movies")) == .movies)
        #expect(
            VocabularyQuestionTopicMap.topic(for: question(topicId: "home_neighborhood"))
                == .homeNeighborhood
        )
        // 이름만 다른 설문 주제들.
        #expect(VocabularyQuestionTopicMap.topic(forTopicID: "instruments") == .music)
        #expect(VocabularyQuestionTopicMap.topic(forTopicID: "domestic_travel") == .travel)
        #expect(VocabularyQuestionTopicMap.topic(forTopicID: "gym") == .exercise)
        #expect(VocabularyQuestionTopicMap.topic(forTopicID: "cooking") == .food)
        #expect(VocabularyQuestionTopicMap.topic(forTopicID: "self_introduction") == .dailyLife)
    }

    /// AI가 만든 데일리 질문은 topicId 뒤에 고유화 꼬리를 붙인다. 꼬리는 떼고 본다.
    @Test func stripsTheUniquenessSuffixOfAIQuestionTopics() {
        #expect(VocabularyQuestionTopicMap.topic(forTopicID: "movies_q3_1a2b3c4d") == .movies)
        #expect(
            VocabularyQuestionTopicMap.topic(forTopicID: "family_friends_q7_deadbeef")
                == .familyFriends
        )
    }

    /// 대응하는 단어장 주제가 없으면 없다고 한다. 비슷해 보이는 주제를 지어내지 않는다.
    @Test func unknownQuestionTopicStaysUnknown() {
        for topicID in ["reading", "gaming", "pets", "general_opinion", "roleplay_problem"] {
            #expect(VocabularyQuestionTopicMap.topic(forTopicID: topicID) == nil)
        }
        #expect(VocabularyQuestionTopicMap.topic(for: question(topicId: nil)) == nil)
    }

    // MARK: 2. 고르는 규칙

    @Test func returnsAtMostFive() {
        let entries = (0..<30).map { entry("cafe-\($0)", type: [.word, .phrase, .pattern][$0 % 3]) }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-Tell me about your favorite cafe.",
            topic: .cafes,
            targetLevel: .IM2,
            entries: entries
        )
        #expect(picked.count == 5)
    }

    @Test func neverRepeatsTheSameEntry() {
        // 같은 항목이 시드와 AI 세트 양쪽에 있어도 두 번 뜨면 안 된다.
        let entries = (0..<4).flatMap { _ in (0..<3).map { entry("cafe-\($0)") } }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: nil,
            entries: entries
        )
        #expect(Set(picked.map(\.id)).count == picked.count)
        #expect(picked.count == 3)
    }

    /// 같은 질문이면 몇 번을 계산하든, 재료가 어떤 순서로 들어오든 같은 목록이 나온다.
    /// (`shuffled()`를 쓰면 여기서 걸린다.)
    @Test func sameQuestionAlwaysGivesTheSameList() {
        let entries = (0..<12).map { entry("cafe-\($0)", type: [.word, .phrase, .pattern][$0 % 3]) }
        let first = VocabularyQuestionRecommender.recommend(
            questionID: "5-How often do you go to a cafe?",
            topic: .cafes,
            targetLevel: .IM2,
            entries: entries
        )
        for _ in 0..<5 {
            let again = VocabularyQuestionRecommender.recommend(
                questionID: "5-How often do you go to a cafe?",
                topic: .cafes,
                targetLevel: .IM2,
                entries: entries.shuffled()
            )
            #expect(again.map(\.id) == first.map(\.id))
        }
    }

    /// 질문마다 시작점이 달라야 매일 같은 다섯 개만 보지 않는다.
    @Test func differentQuestionsStartAtDifferentPlaces() {
        let entries = (0..<12).map { entry("cafe-\($0)", type: [.word, .phrase, .pattern][$0 % 3]) }
        let heads = (2...12).map { number in
            VocabularyQuestionRecommender.recommend(
                questionID: "\(number)-prompt \(number)",
                topic: .cafes,
                targetLevel: nil,
                entries: entries
            ).first?.id
        }
        #expect(Set(heads.compactMap { $0 }).count > 1)
    }

    /// 주제가 정확히 맞는 항목만 쓴다. 남는 자리는 비워 두지 다른 주제로 채우지 않는다.
    @Test func recommendsOnlyEntriesOfTheQuestionTopic() {
        let entries = (0..<3).map { entry("cafe-\($0)") }
            + (0..<10).map { entry("movie-\($0)", topics: [.movies]) }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: nil,
            entries: entries
        )
        #expect(picked.count == 3)
        #expect(picked.allSatisfy { $0.topics.contains(.cafes) })
    }

    @Test func prefersEntriesForTheTargetLevel() {
        let entries = (0..<3).map { entry("ih-\($0)", levels: [.IH]) }
            + (0..<3).map { entry("il-\($0)", levels: [.IL]) }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: .IH,
            entries: entries,
            limit: 3
        )
        #expect(picked.allSatisfy { $0.recommendedLevels == [.IH] })
    }

    /// 목표 등급 항목이 모자라면 나머지로 채운다 — 자리를 비워 두지 않는다.
    @Test func fillsUpWithOtherLevelsWhenTargetLevelRunsOut() {
        let entries = [entry("ih-0", levels: [.IH])]
            + (0..<4).map { entry("il-\($0)", type: .phrase, levels: [.IL]) }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: .IH,
            entries: entries
        )
        #expect(picked.count == 5)
        #expect(picked.first?.id == "ih-0")
    }

    /// 비슷비슷한 단어 다섯 개를 주지 않는다. 단어·표현·패턴을 돌아가며 뽑는다.
    @Test func mixesWordsPhrasesAndPatterns() {
        let entries = (0..<5).map { entry("w-\($0)", type: .word) }
            + (0..<5).map { entry("p-\($0)", type: .phrase) }
            + (0..<5).map { entry("t-\($0)", type: .pattern) }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: nil,
            entries: entries
        )
        #expect(Set(picked.map(\.type)).count == 3)
        for type in VocabularyItemType.allCases {
            #expect(picked.filter { $0.type == type }.count <= 2)
        }
    }

    /// 한 종류만 있으면 그 종류로만 채운다(패턴만 있는 주제도 빈손이 되면 안 된다).
    @Test func worksWhenOnlyOneTypeExists() {
        let entries = (0..<6).map { entry("t-\($0)", type: .pattern) }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: nil,
            entries: entries
        )
        #expect(picked.count == 5)
        #expect(picked.allSatisfy { $0.type == .pattern })
    }

    // MARK: 3. 재료 — 시드만 있어도 된다

    /// AI 단어장을 한 번도 만들지 않은 사용자도 추천을 받는다. 시드가 바닥이다.
    @Test func worksWithTheBundledSeedAlone() {
        for topic in VocabularyTopic.allCases {
            let picked = VocabularyQuestionRecommender.recommend(
                questionID: "2-\(topic.rawValue) question",
                topic: topic,
                targetLevel: .IM2,
                entries: VocabularyCatalog.all
            )
            #expect(!picked.isEmpty)
            #expect(picked.count <= 5)
            #expect(picked.allSatisfy { $0.topics.contains(topic) })
        }
    }

    /// 만들어 둔 AI 항목도 주제가 맞으면 함께 쓴다 — 만든 값을 놀리지 않는다.
    @Test func usesGeneratedEntriesWhenTheirTopicMatches() {
        let generated = (0..<10).map {
            entry("ai-cafe-\($0)", type: .phrase, topics: [.cafes], source: "ai")
        }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: .IM2,
            entries: VocabularyCatalog.all + generated
        )
        #expect(picked.count == 5)
        #expect(picked.contains { $0.source == "ai" })
        #expect(picked.allSatisfy { $0.topics.contains(.cafes) })
    }

    /// 주제가 다른 AI 항목은 주제가 맞는 시드를 밀어내지 못한다.
    @Test func unrelatedGeneratedEntriesNeverBeatExactTopicSeed() {
        let generated = (0..<30).map {
            entry("ai-movie-\($0)", type: [.word, .phrase, .pattern][$0 % 3],
                  topics: [.movies], source: "ai")
        }
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "2-q",
            topic: .cafes,
            targetLevel: .IM2,
            entries: VocabularyCatalog.all + generated
        )
        #expect(!picked.isEmpty)
        #expect(picked.allSatisfy { $0.topics.contains(.cafes) })
        #expect(picked.allSatisfy { !$0.id.hasPrefix("ai-movie") })
    }

    // MARK: 4. 주제를 모를 때

    /// 주제를 모르면 질문 문장을 넘겨짚지 않는다. 어디에나 얹을 수 있는 답변 패턴만 준다.
    @Test func unknownTopicFallsBackToGeneralAnswerPatterns() {
        let picked = VocabularyQuestionRecommender.recommend(
            questionID: "13-\(question(topicId: nil).prompt)",
            topic: nil,
            targetLevel: .IM2,
            entries: VocabularyCatalog.all
        )
        #expect(picked.count == 5)
        #expect(picked.allSatisfy { $0.type == .pattern })
        let generalRoles: Set<VocabularyUsageRole> = [.preference, .reason, .transition, .comparison]
        #expect(picked.allSatisfy { !generalRoles.isDisjoint(with: $0.usageRoles) })
        #expect(Set(picked.map(\.id)).count == 5)
    }

    /// 주제를 모르는 질문에서도 목록은 흔들리지 않는다.
    @Test func unknownTopicRecommendationIsStableToo() {
        let first = VocabularyQuestionRecommender.recommend(
            questionID: "13-unexpected",
            topic: nil,
            targetLevel: nil,
            entries: VocabularyCatalog.all
        )
        let again = VocabularyQuestionRecommender.recommend(
            questionID: "13-unexpected",
            topic: nil,
            targetLevel: nil,
            entries: VocabularyCatalog.all.shuffled()
        )
        #expect(first.map(\.id) == again.map(\.id))
    }

    // MARK: 5. 값이 0이라는 것

    /// 추천 계산은 순수 계산이다 — 네트워크도 AI도 토큰도 없다.
    @Test func recommendationComputationTouchesNothingRemote() throws {
        let file = code(of: try source(recommenderPath))
        for forbidden in [
            "URLSession", "APIClient", "AppEnvironment", "await", "async",
            "reserve", "DailyToken", "shuffled", "hashValue", "random"
        ] {
            #expect(!file.contains(forbidden), "추천 계산이 \(forbidden)에 기대면 안 된다")
        }
    }

    /// 화면이 추천을 보여 준다는 이유로는 아무것도 요청하지 않는다.
    /// 생성은 사용자가 버튼을 눌렀을 때 시작하는 P14.2 조작뿐이다.
    @Test func showingRecommendationsStartsNoOperation() throws {
        let file = code(of: try source(sectionPath))
        for forbidden in [".task", ".onAppear", "viewModel.generate", "analyze", "reserve"] {
            #expect(!file.contains(forbidden), "\(forbidden)이(가) 화면 표시만으로 실행되면 안 된다")
        }
        // 생성 뷰모델조차 버튼을 누르기 전에는 만들지 않는다.
        #expect(file.contains("if generation == nil"))
    }

    /// 표현을 누르면 단어장이 이미 쓰는 상세 화면이 열린다. 두 번째 상세 화면은 없다.
    @Test func tappingAnExpressionOpensTheExistingDetailScreen() throws {
        let file = try source(sectionPath)
        #expect(file.contains("navigationDestination(for: VocabularyEntry.self)"))
        #expect(file.contains("VocabularyEntryDetailView("))
        let declarations = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("struct VocabularyEntryDetailView") }
        #expect(declarations.count == 1)
    }

    /// "단어장에서 보기"도 이미 있는 목록 화면을 재사용한다. 새 탭도 새 목록도 만들지 않는다.
    @Test func vocabularyLinkReusesExistingListScreens() throws {
        let file = try source(sectionPath)
        #expect(file.contains("VocabularyTopicView("))
        #expect(file.contains("VocabularyMyWordsView("))
        #expect(!file.contains("TabView"))
    }

    // MARK: 6. 30개 만들기 — P14.2 그대로

    /// 주제를 알면 생성 화면에 그 주제가 미리 골라져 있다.
    @Test func knownTopicPreselectsTheGenerator() throws {
        #expect(
            VocabularyGenerationSheet.initialSelection(.dailyQuestion(topic: .movies)) == .movies
        )
        let movies = try #require(VocabularyQuestionTopicMap.topic(for: question(topicId: "movies")))
        #expect(VocabularyGenerationSheet.initialSelection(.dailyQuestion(topic: movies)) == .movies)
        // 데일리에서 열 때 질문 주제를 그대로 넘긴다.
        #expect(try source(sectionPath).contains("source: .dailyQuestion(topic: topic)"))
    }

    /// 주제를 모르면 아무 주제도 골라 두지 않는다 — 화면의 초기 선택이 실제로 비어 있다.
    /// (예전 구현은 `initialTopic ?? .cafes`라 주제를 모를 때도 카페가 골라져 있었다.)
    @Test func unknownTopicDoesNotInventATopicForTheGenerator() throws {
        for topicID in ["reading", "gaming", "pets", "general_opinion", "roleplay_service"] {
            let mapped = VocabularyQuestionTopicMap.topic(forTopicID: topicID)
            #expect(mapped == nil)
            #expect(VocabularyGenerationSheet.initialSelection(.dailyQuestion(topic: mapped)) == nil)
        }
        #expect(VocabularyGenerationSheet.initialSelection(.dailyQuestion(topic: nil)) == nil)

        let sheet = code(of: try source("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift"))
        // 고르지 않은 상태를 기본 주제로 메우지 않는다.
        #expect(sheet.contains("@State private var topic: VocabularyTopic?"))
        #expect(sheet.contains("_topic = State(initialValue: Self.initialSelection(source))"))
        #expect(!sheet.contains("initialValue: initialTopic ?? "))
        // 고르지 않은 채로는 만들 수 없다.
        #expect(sheet.contains("isDisabled: topic == nil"))
        #expect(sheet.contains("guard let topic else { return }"))

        let file = try source(sectionPath)
        #expect(!file.contains("topic ?? ."))
        #expect(!file.contains("initialTopic"))
    }

    /// 기본 주제가 골라진 채로 여는 예전 경로(`.vocabularyTab`)는 그대로다.
    /// 단어장 홈에서는 이 시트를 더 이상 열지 않지만(P14.5.1) 계약은 손대지 않았다 —
    /// 인자 없이 부르면 여전히 카페가 골라진 채로 열린다.
    @Test func vocabularyTabGeneratorKeepsItsDefaultTopic() throws {
        #expect(VocabularyGenerationSheet.initialSelection(.vocabularyTab) == .cafes)
        let sheet = try source("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift")
        #expect(sheet.contains("source: Source = .vocabularyTab"))
        #expect(sheet.contains("case .vocabularyTab: .cafes"))
        #expect(!sheet.contains("initialTopic"))
    }

    /// 생성 경로도 값도 그대로다. 데일리에서 들어와도 요청은 하나, 토큰은 1개다.
    @Test func generationStillCostsExactlyOneToken() throws {
        #expect(VocabularyGenerationViewModel.tokenCost == 1)
        let file = try source(sectionPath)
        #expect(file.contains("VocabularyGenerationSheet("))
        #expect(file.contains("VocabularyGenerationViewModel(environment: environment)"))
        #expect(file.contains("DailyTokenIcon("))
        // 두 번째 뷰모델도, 두 번째 요청 경로도 만들지 않는다.
        #expect(!file.contains("APIClient"))
        let generators = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("class VocabularyGenerationViewModel") }
        #expect(generators.count == 1)
    }

    // MARK: 7. 데일리 흐름은 그대로

    /// 추천은 질문 카드와 녹음 사이에 끼어들 뿐, 녹음·저장 결과 흐름을 건드리지 않는다.
    @Test func practiceScreenKeepsItsAnswerFlow() throws {
        let screen = try source("Views/Screens/Main/Practice/PracticeScreen.swift")
        #expect(screen.contains("PracticeVocabularySection("))
        #expect(screen.contains("recorder(for: question)"))
        #expect(screen.contains("savedResult(result)"))
        let sectionIndex = try #require(screen.range(of: "PracticeVocabularySection(")).lowerBound
        let recorderIndex = try #require(screen.range(of: "recorder(for: question)")).lowerBound
        #expect(sectionIndex < recorderIndex)
    }

    // MARK: 8. 탭 구성은 그대로

    @Test func fiveTabNavigationIsUnchanged() {
        #expect(MainTab.allCases.count == 5)
        #expect(MainTab.allCases.map(\.title) == ["데일리", "모의고사", "플래너", "단어장", "통계"])
        #expect(MainTab.vocabulary.rawValue == 3)
    }
}
