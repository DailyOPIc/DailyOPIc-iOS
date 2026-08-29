import Foundation
import Testing
@testable import DailyOPIc

/// 데일리는 데일리만 한다(P14.5.2).
///
/// P14.4에서 데일리 질문 아래에 붙였던 "이 질문에 써볼 표현"은 내렸다. 답하기 전에
/// 표현을 훑는 흐름 자체가 나쁜 것은 아니었지만, 질문에 답하는 화면에서 단어장으로
/// 새는 길을 만들면 세 탭의 역할이 다시 섞인다 — 단어는 단어장 탭 한 곳에서만 다룬다.
///
/// 이 파일은 예전 `VocabularyQuestionRecommendationTests`를 대신한다.
/// 그 테스트들은 "추천이 잘 골라지는가"를 지켰는데, 그 기능이 제품에서 사라졌으므로
/// 더 이상 지킬 진실이 아니다. 대신 **없어졌다는 사실**과 **데일리 흐름은 그대로라는
/// 사실**을 여기서 지킨다.
struct DailyVocabularyIsolationTests {

    // MARK: 도우미

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path)
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
    /// "추천을 더 이상 그리지 않는다"고 적은 주석 때문에 걸리면 안 된다.
    private func code(_ file: String) -> String {
        file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let screenPath = "Views/Screens/Main/Practice/PracticeScreen.swift"

    // MARK: 1. 데일리 질문 화면에 단어장이 없다

    @Test func theQuestionScreenNoLongerShowsVocabulary() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains("PracticeVocabularySection"))
        #expect(!screen.contains("이 질문에 써볼 표현"))
        // 추천 chip도, 단어장에서 보기도, 단어 상세로 가는 길도 없다.
        #expect(!screen.contains("VocabularyEntry"))
        #expect(!screen.contains("VocabularyTopicView"))
        #expect(!screen.contains("VocabularyMyWordsView"))
        #expect(!screen.contains("VocabularyEntryDetailView"))
    }

    /// 데일리 화면에서 AI 단어 생성으로 가는 길도 없다. 토큰이 나가는 버튼이
    /// 질문에 답하는 화면에 있으면 안 된다.
    @Test func theQuestionScreenNoLongerOffersWordGeneration() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains("VocabularyGenerationSheet"))
        #expect(!screen.contains("VocabularyGenerationViewModel"))
        #expect(!screen.contains("DailyTokenIcon"))
    }

    /// P14.4 전용 코드는 통째로 사라졌다. 아무도 부르지 않는 파일을 남겨 두면
    /// 다음 사람이 "왜 안 보이지?" 하며 되살린다.
    @Test func theRecommenderIsGoneEverywhere() throws {
        #expect(!exists("Models/VocabularyQuestionRecommendation.swift"))
        #expect(!exists("Views/Screens/Main/Practice/PracticeVocabularySection.swift"))
        let mentions = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter {
                code($0).contains("VocabularyQuestionRecommender")
                || code($0).contains("VocabularyQuestionTopicMap")
                || code($0).contains("PracticeVocabularySection")
            }
        #expect(mentions.isEmpty)
    }

    // MARK: 2. 데일리 흐름은 그대로

    /// 질문 → 녹음 → 결과. P14.4가 끼어들기 전의 순서 그대로다.
    @Test func theAnswerFlowIsUntouched() throws {
        let screen = try source(screenPath)
        #expect(screen.contains("QuestionCard(question: question"))
        #expect(screen.contains("questionProgressBar"))
        #expect(screen.contains("recorder(for: question)"))
        #expect(screen.contains("savedResult(result)"))
        #expect(screen.contains("navigationControls"))
        let cardIndex = try #require(screen.range(of: "QuestionCard(question: question")).lowerBound
        let recorderIndex = try #require(screen.range(of: "recorder(for: question)")).lowerBound
        #expect(cardIndex < recorderIndex)
    }

    /// 설정 시트 진입점도 그대로다. 데일리 탭은 앱 전체 설정으로 가는 길을 계속 갖는다.
    @Test func theAppSettingsEntryPointSurvives() throws {
        #expect(try source(screenPath).contains("SetupView(preferences: preferences)"))
    }

    // MARK: 3. 생성 아키텍처는 지우지 않았다

    /// 데일리에서 CTA만 뺐고 P14.2 생성 자체는 그대로 있다(P14.6에서 다시 쓴다).
    /// 값도 그대로 1개다 — 지금은 부르는 화면이 없을 뿐이다.
    @Test func generationArchitectureStaysIntactButUncalled() throws {
        #expect(VocabularyGenerationViewModel.tokenCost == 1)
        #expect(exists("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift"))
        let generators = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("class VocabularyGenerationViewModel") }
        #expect(generators.count == 1)
        // 자동으로 부르는 곳이 생기면 안 된다. 생성은 언제나 사용자가 시작한다.
        let callers = try runtimeSources()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .filter { code($0).contains("VocabularyGenerationSheet(") }
        #expect(callers.isEmpty)
    }

    // MARK: 4. 탭 구성은 그대로

    @Test func fiveTabNavigationIsUnchanged() {
        #expect(MainTab.allCases.count == 5)
        #expect(MainTab.allCases.map(\.title) == ["데일리", "모의고사", "플래너", "단어장", "통계"])
        #expect(MainTab.vocabulary.rawValue == 3)
    }
}
