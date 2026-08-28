import Foundation

/// 단어장 항목의 종류. OPIc 답변에서 쓰이는 단위가 단어 하나만은 아니라서
/// 표현과 답변 패턴을 같은 목록에 둔다.
enum VocabularyItemType: String, Codable, CaseIterable, Identifiable, Sendable {
    case word
    case phrase
    case pattern

    var id: String { rawValue }

    var label: String {
        switch self {
        case .word: "단어"
        case .phrase: "자주 쓰는 표현"
        case .pattern: "답변 패턴"
        }
    }
}

/// 단어장 주제. 원시값은 배경 설문(`BackgroundSurvey`)의 `topicId`와 겹치는 것을
/// 일부러 그대로 맞춰 뒀다(movies · music · cafes · shopping · school 등) — 나중에
/// 설문 선택과 단어를 이어 붙일 때 매핑 표를 새로 만들지 않기 위해서다.
/// 설문에 없는 주제(집과 동네 · 일상 등)만 여기서 새로 정의한다.
enum VocabularyTopic: String, Codable, CaseIterable, Identifiable, Sendable {
    case homeNeighborhood = "home_neighborhood"
    case school
    case work
    case cafes
    case food
    case movies
    case music
    case exercise
    case park
    case shopping
    case travel
    case transportation
    case weather
    case vacation
    case familyFriends = "family_friends"
    case dailyLife = "daily_life"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .homeNeighborhood: "집과 동네"
        case .school: "학교"
        case .work: "직장"
        case .cafes: "카페"
        case .food: "음식/음식점"
        case .movies: "영화"
        case .music: "음악"
        case .exercise: "운동"
        case .park: "공원"
        case .shopping: "쇼핑"
        case .travel: "여행"
        case .transportation: "교통"
        case .weather: "날씨"
        case .vacation: "휴가"
        case .familyFriends: "친구/가족"
        case .dailyLife: "일상"
        }
    }
}

/// 답변에서 그 표현이 맡는 역할. 질문 유형(`QuestionStyle`)과는 다른 축이다 —
/// 저건 "무엇을 묻는가", 이건 "답변의 어느 자리에 넣는가"다.
enum VocabularyUsageRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case description
    case routine
    case frequency
    case preference
    case reason
    case emotion
    case pastExperience
    case comparison
    case change
    case problemSolution
    case transition

    var id: String { rawValue }

    var label: String {
        switch self {
        case .description: "묘사"
        case .routine: "루틴"
        case .frequency: "빈도"
        case .preference: "선호"
        case .reason: "이유"
        case .emotion: "감정"
        case .pastExperience: "경험"
        case .comparison: "비교"
        case .change: "변화"
        case .problemSolution: "문제 해결"
        case .transition: "연결"
        }
    }
}

/// 단어장 한 항목. 앱에 담아 배포하는 **고정 데이터**다(시드 JSON).
/// 서버·AI에서 오지 않으므로 오프라인에서도, 토큰 없이도 똑같이 보인다.
///
/// 발음기호(IPA)는 담지 않는다 — 믿을 수 있는 출처 없이 만들어 낸 발음기호는
/// 틀린 정보다. 발음은 기기 TTS로 들려준다.
struct VocabularyEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let term: String
    let type: VocabularyItemType
    let meaningKo: String
    let exampleEn: String
    let exampleKo: String
    let collocations: [String]
    let topics: [VocabularyTopic]
    let usageRoles: [VocabularyUsageRole]
    let recommendedLevels: [OPIcLevel]
    let source: String
    /// 시드 항목에는 없다. 나중에 사용자·AI가 만든 항목이 같은 모델을 쓸 때를 위한 자리.
    let createdAt: Date?

    init(
        id: String,
        term: String,
        type: VocabularyItemType,
        meaningKo: String,
        exampleEn: String,
        exampleKo: String,
        collocations: [String] = [],
        topics: [VocabularyTopic] = [],
        usageRoles: [VocabularyUsageRole] = [],
        recommendedLevels: [OPIcLevel] = [],
        source: String,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.term = term
        self.type = type
        self.meaningKo = meaningKo
        self.exampleEn = exampleEn
        self.exampleKo = exampleKo
        self.collocations = collocations
        self.topics = topics
        self.usageRoles = usageRoles
        self.recommendedLevels = recommendedLevels
        self.source = source
        self.createdAt = createdAt
    }

    /// 목록에서 주제를 하나만 보여줄 때의 대표 주제. 첫 번째가 그 항목이 실린 주제다.
    var primaryTopic: VocabularyTopic? { topics.first }

    /// 목표 등급에 맞는 항목인가. 권장 등급이 비어 있으면 등급을 가리지 않는 항목으로 본다.
    func matches(targetLevel: OPIcLevel?) -> Bool {
        guard let targetLevel else { return true }
        return recommendedLevels.isEmpty || recommendedLevels.contains(targetLevel)
    }

    /// 검색 대조용 소문자 원문. 영어 표현·한국어 뜻·예문·연어를 한 줄로 붙인다.
    fileprivate var searchHaystack: String {
        ([term, meaningKo, exampleEn, exampleKo] + collocations)
            .joined(separator: " ")
            .lowercased()
    }
}

/// 번들 시드에서 읽어 오는 단어장 목록. 상태를 갖지 않는다.
///
/// 파일 하나(`Resources/Vocabulary/vocabulary_seed.json`)만 진실이라, 나중에
/// 600~1000개로 늘릴 때도 이 타입과 화면은 손대지 않는다.
enum VocabularyCatalog {
    /// 시드 파일 이름. 확장을 대비해 이름만 바꿔 끼울 수 있게 한 곳에 둔다.
    static let resourceName = "vocabulary_seed"

    private struct SeedFile: Decodable {
        let version: Int
        let entries: [VocabularyEntry]
    }

    /// 번들 위치를 잡기 위한 표식. `Bundle.main`은 테스트 호스트 구성에 따라 달라질 수
    /// 있어서 앱 번들을 직접 가리킨다.
    private final class BundleMarker {}

    static let all: [VocabularyEntry] = load()

    /// 시드에 **실제로 존재하는** 주제만, 정의된 순서대로. 비어 있는 주제 칸을
    /// 만들지 않기 위해 화면은 이 목록만 본다.
    static let topics: [VocabularyTopic] = {
        let present = Set(all.flatMap(\.topics))
        return VocabularyTopic.allCases.filter(present.contains)
    }()

    static func entries(topic: VocabularyTopic) -> [VocabularyEntry] {
        all.filter { $0.topics.contains(topic) }
    }

    static func entries(topic: VocabularyTopic, type: VocabularyItemType?) -> [VocabularyEntry] {
        let scoped = entries(topic: topic)
        guard let type else { return scoped }
        return scoped.filter { $0.type == type }
    }

    static func entry(id: String) -> VocabularyEntry? {
        all.first { $0.id == id }
    }

    static func entries(ids: [String]) -> [VocabularyEntry] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// 로컬 검색. 영어 표현과 한국어 뜻 어느 쪽으로 쳐도 걸리고, 예문·연어 안에 있는
    /// 단어도 찾는다("relax"로 검색하면 예문에 relax가 있는 항목이 나온다).
    /// AI를 부르지 않는다 — 순수 문자열 대조다.
    static func search(_ query: String, in entries: [VocabularyEntry] = all) -> [VocabularyEntry] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return [] }
        // 표현 자체가 맞은 것을 먼저 보여준다. 예문에만 걸린 항목은 그 뒤로.
        let scored = entries.compactMap { entry -> (Int, VocabularyEntry)? in
            let term = entry.term.lowercased()
            if term.hasPrefix(needle) { return (0, entry) }
            if term.contains(needle) { return (1, entry) }
            if entry.meaningKo.contains(needle) { return (2, entry) }
            if entry.searchHaystack.contains(needle) { return (3, entry) }
            return nil
        }
        return scored
            .enumerated()
            .sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
            .map(\.element.1)
    }

    private static func load() -> [VocabularyEntry] {
        guard let url = Bundle(for: BundleMarker.self)
            .url(forResource: resourceName, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            assertionFailure("단어장 시드(\(resourceName).json)를 번들에서 찾지 못했습니다.")
            return []
        }
        do {
            return try JSONCoding.decoder.decode(SeedFile.self, from: data).entries
        } catch {
            assertionFailure("단어장 시드를 읽지 못했습니다: \(error)")
            return []
        }
    }
}
