import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 단어장 시드·검색·주제·하루치 배정(P14). 어느 테스트도 네트워크·AI를 부르지 않는다.
/// 복습 일정과 세션 큐(P14.1)는 `VocabularyReviewTests`에 있다.
struct VocabularyTests {

    // MARK: 시드 데이터

    /// 번들 원본을 직접 세어 카탈로그와 비교한다. 디코딩이 항목을 조용히 흘리면 여기서 걸린다.
    @Test func catalogLoadsEverySeedEntry() throws {
        let url = try #require(
            Bundle(for: PersistenceService.self)
                .url(forResource: VocabularyCatalog.resourceName, withExtension: "json")
        )
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let entries = try #require((raw as? [String: Any])?["entries"] as? [[String: Any]])
        #expect(!entries.isEmpty)
        #expect(VocabularyCatalog.all.count == entries.count)
    }

    @Test func identifiersAreUniqueAndStable() {
        let ids = VocabularyCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(!id.trimmingCharacters(in: .whitespaces).isEmpty)
            // 배정과 저장이 id로 이어지므로 공백이 섞이면 안 된다.
            #expect(!id.contains(" "))
        }
    }

    @Test func termsAreNotRepeated() {
        let terms = VocabularyCatalog.all.map { $0.term.lowercased() }
        #expect(Set(terms).count == terms.count)
    }

    @Test func everyEntryCarriesTheTextTheCardNeeds() {
        for entry in VocabularyCatalog.all {
            #expect(!entry.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!entry.meaningKo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!entry.exampleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!entry.exampleKo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!entry.topics.isEmpty)
            #expect(!entry.source.isEmpty)
        }
    }

    /// 단어 · 자주 쓰는 표현 · 답변 패턴이 모두 디코딩된다.
    @Test func allThreeItemTypesDecode() {
        let present = Set(VocabularyCatalog.all.map(\.type))
        #expect(present == Set(VocabularyItemType.allCases))
    }

    @Test func knownEntryDecodesEveryField() throws {
        let entry = try #require(VocabularyCatalog.entry(id: "cafe-crowded"))
        #expect(entry.term == "crowded")
        #expect(entry.type == .word)
        #expect(entry.meaningKo.contains("붐비는"))
        #expect(entry.topics.contains(.cafes))
        #expect(!entry.collocations.isEmpty)
        #expect(entry.recommendedLevels.contains(.IM2))
        // 발음기호는 담지 않는다(§ 발음은 TTS로).
        #expect(entry.createdAt == nil)
    }

    // MARK: 주제

    /// 빈 주제 칸을 만들지 않는다 — 화면이 읽는 목록은 실제 데이터에서만 나온다.
    @Test func topicListOnlyIncludesTopicsThatHaveEntries() {
        for topic in VocabularyCatalog.topics {
            #expect(!VocabularyCatalog.entries(topic: topic).isEmpty)
        }
        let missing = Set(VocabularyTopic.allCases).subtracting(VocabularyCatalog.topics)
        for topic in missing {
            #expect(VocabularyCatalog.entries(topic: topic).isEmpty)
        }
    }

    @Test func topicFilterReturnsOnlyThatTopic() throws {
        let topic = try #require(VocabularyCatalog.topics.first)
        let entries = VocabularyCatalog.entries(topic: topic)
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.topics.contains(topic) })
    }

    @Test func typeFilterNarrowsWithinTheTopic() {
        for topic in VocabularyCatalog.topics {
            let all = VocabularyCatalog.entries(topic: topic)
            #expect(VocabularyCatalog.entries(topic: topic, type: nil).count == all.count)
            var counted = 0
            for type in VocabularyItemType.allCases {
                let scoped = VocabularyCatalog.entries(topic: topic, type: type)
                #expect(scoped.allSatisfy { $0.type == type && $0.topics.contains(topic) })
                counted += scoped.count
            }
            #expect(counted == all.count)
        }
    }

    // MARK: 검색 (로컬 · 토큰 0)

    @Test func searchFindsEnglishTerm() {
        let results = VocabularyCatalog.search("crowded")
        #expect(results.contains { $0.id == "cafe-crowded" })
        // 표현 자체가 맞은 항목이 먼저 온다.
        #expect(results.first?.term.lowercased().contains("crowded") == true)
    }

    @Test func searchFindsKoreanMeaning() {
        let results = VocabularyCatalog.search("붐비는")
        #expect(results.contains { $0.id == "cafe-crowded" })
    }

    /// 예문 속 단어도 찾는다: "relax"로 검색하면 예문에 relax가 있는 항목이 나온다.
    @Test func searchReachesIntoExamples() throws {
        let results = VocabularyCatalog.search("relax")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy {
            ([$0.term, $0.meaningKo, $0.exampleEn, $0.exampleKo] + $0.collocations)
                .joined(separator: " ")
                .lowercased()
                .contains("relax")
        })
    }

    @Test func searchIgnoresCaseAndSurroundingSpace() {
        let plain = VocabularyCatalog.search("crowded").map(\.id)
        #expect(VocabularyCatalog.search("  CROWDED ").map(\.id) == plain)
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(VocabularyCatalog.search("").isEmpty)
        #expect(VocabularyCatalog.search("   ").isEmpty)
    }

    // MARK: 오늘의 단어

    @Test func todaysSetHasTenDistinctEntries() {
        let set = VocabularyDailySetPlanner.assign(
            localDate: "2026-03-05",
            catalog: VocabularyCatalog.all
        )
        #expect(set.entryIDs.count == VocabularyDailySet.dailyTarget)
        #expect(Set(set.entryIDs).count == set.entryIDs.count)
        // 배정된 id는 모두 실제 항목으로 되살아난다.
        #expect(VocabularyCatalog.entries(ids: set.entryIDs).count == set.entryIDs.count)
    }

    /// 같은 로컬 날짜면 몇 번을 다시 계산해도 같은 10개다(앱을 껐다 켜도 바뀌지 않는 근거).
    @Test func sameLocalDayGivesTheSameTenEntries() {
        let first = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: VocabularyCatalog.all)
        let second = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: VocabularyCatalog.all)
        #expect(first == second)
        #expect(first.covers("2026-03-05"))
        #expect(!first.covers("2026-03-06"))
    }

    @Test func nextDayMovesTheSelection() {
        let today = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: VocabularyCatalog.all)
        let tomorrow = VocabularyDailySetPlanner.assign(localDate: "2026-03-06", catalog: VocabularyCatalog.all)
        #expect(today.entryIDs != tomorrow.entryIDs)
    }

    /// 이미 학습한 항목은 새 단어 후보에서 빠진다(P14.1 · 상세는 VocabularyReviewTests).
    @Test func studiedEntriesAreLeftOut() {
        let plain = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: VocabularyCatalog.all)
        let excluded = Set(plain.entryIDs.prefix(3))
        let next = VocabularyDailySetPlanner.assign(
            localDate: "2026-03-05",
            catalog: VocabularyCatalog.all,
            excluding: excluded
        )
        #expect(next.entryIDs.allSatisfy { !excluded.contains($0) })
        #expect(next.entryIDs.count == VocabularyDailySet.dailyTarget)
    }

    /// 후보가 목표보다 적어도 같은 항목을 두 번 담지 않는다.
    @Test func shortCatalogNeverRepeatsAnEntry() {
        let small = Array(VocabularyCatalog.all.prefix(4))
        let set = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: small)
        #expect(set.entryIDs.count == small.count)
        #expect(Set(set.entryIDs).count == set.entryIDs.count)
    }

    @Test func emptyCatalogGivesAnEmptySet() {
        let set = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: [])
        #expect(set.entryIDs.isEmpty)
        // 비어 있어도 "오늘 몫은 정했다"는 사실은 남는다.
        #expect(set.covers("2026-03-05"))
    }

    /// 하루치가 한 주제로만 채워지지 않는다.
    @Test func todaysSetSpansSeveralTopics() {
        let set = VocabularyDailySetPlanner.assign(localDate: "2026-03-05", catalog: VocabularyCatalog.all)
        let topics = Set(VocabularyCatalog.entries(ids: set.entryIDs).compactMap(\.primaryTopic))
        #expect(topics.count >= 5)
    }

    /// 목표 등급에 맞는 항목이 충분하면 하루치는 전부 그 등급 것이다.
    @Test func targetLevelEntriesComeFirst() {
        let set = VocabularyDailySetPlanner.assign(
            localDate: "2026-03-05",
            catalog: VocabularyCatalog.all,
            targetLevel: .IH
        )
        #expect(VocabularyCatalog.entries(ids: set.entryIDs).allSatisfy { $0.matches(targetLevel: .IH) })
    }

    /// 목표 등급 항목이 모자라면 나머지로 채워 10개를 지킨다.
    @Test func targetLevelSetIsStillFilledToTheDailyTarget() {
        let set = VocabularyDailySetPlanner.assign(
            localDate: "2026-03-05",
            catalog: VocabularyCatalog.all,
            targetLevel: .AL
        )
        #expect(set.entryIDs.count == VocabularyDailySet.dailyTarget)
        #expect(Set(set.entryIDs).count == set.entryIDs.count)
        let entries = VocabularyCatalog.entries(ids: set.entryIDs)
        #expect(entries.contains { $0.matches(targetLevel: .AL) })
    }

    @Test func levelAgnosticEntryMatchesAnyTarget() {
        let entry = VocabularyEntry(
            id: "x", term: "x", type: .word, meaningKo: "x",
            exampleEn: "x", exampleKo: "x", source: "test"
        )
        #expect(entry.matches(targetLevel: .NL))
        #expect(entry.matches(targetLevel: nil))
    }

    @Test func dayIndexCountsForwardFromTheEpoch() {
        #expect(VocabularyDailySetPlanner.dayIndex(of: "2000-01-01") == 0)
        #expect(VocabularyDailySetPlanner.dayIndex(of: "2000-01-11") == 10)
        #expect(VocabularyDailySetPlanner.dayIndex(of: "1999-12-31") == -1)
    }

    // MARK: 내 단어 저장 (기기 저장소)

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func makeService(_ container: ModelContainer) -> PersistenceService {
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    @MainActor
    @Test func savedWordSurvivesARestart() throws {
        let container = try makeContainer()
        try makeService(container).setVocabularySaved(entryID: "cafe-crowded", isSaved: true)

        // 같은 저장소를 새 서비스로 다시 연다 = 앱 재시작.
        let states = try makeService(container).vocabularyStates()
        #expect(states.count == 1)
        #expect(states.first?.entryID == "cafe-crowded")
        #expect(states.first?.isSaved == true)
        #expect(states.first?.status == .new)
    }

    @MainActor
    @Test func unsavingKeepsOneRecord() throws {
        let container = try makeContainer()
        let service = makeService(container)
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: true)
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: false)
        let states = try service.vocabularyStates()
        #expect(states.count == 1)
        #expect(states.first?.isSaved == false)
    }

    @MainActor
    @Test func schemaCarriesTheVocabularyRecord() {
        #expect(Schema.dailyOPIc.entities.map(\.name).contains("VocabularyStateRecord"))
    }

    // MARK: 탭

    /// 탭 순서: 데일리 · 모의고사 · 플래너 · 단어장 · 통계. 단어장은 플래너와 통계 사이다.
    @Test func vocabularyTabSitsBetweenPlannerAndProgress() {
        #expect(MainTab.allCases.map(\.title) == ["데일리", "모의고사", "플래너", "단어장", "통계"])
        #expect(MainTab.vocabulary.rawValue == MainTab.planner.rawValue + 1)
        #expect(MainTab.progress.rawValue == MainTab.vocabulary.rawValue + 1)
        #expect(MainTab.vocabulary.systemImage == "book.closed.fill")
    }

    @Test func everyTabHasItsOwnTagAndIcon() {
        let tags = MainTab.allCases.map(\.rawValue)
        #expect(Set(tags).count == tags.count)
        let icons = MainTab.allCases.map(\.systemImage)
        #expect(Set(icons).count == icons.count)
    }
}
