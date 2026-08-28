import Foundation

/// AI 맞춤 단어장 생성 요청(P14.2).
///
/// 개수 · 구성(10/10/10) · 모델 · 내부 보충 횟수는 **서버가 정한다.** 앱이 보내는
/// 것은 주제 · 목표 등급, 그리고 "이건 이미 있으니 빼 달라"는 제외 힌트뿐이다.
struct VocabularyGenerationRequest: Encodable, Sendable {
    let topic: VocabularyTopic
    let targetLevel: OPIcLevel
    /// 중복 회피용 힌트. 시드 카탈로그 전체를 보내지 않는다 — 서버에도 상한이 있다.
    let excludeTerms: [String]

    /// 프롬프트에 실을 만큼만. 최근에 만든 세트의 표현을 앞에서부터 자른다.
    static let excludeLimit = 120
}

/// 서버가 만들어 준 한 세트. `entries`는 시드와 같은 `VocabularyEntry` 계약이라
/// 학습 · 복습 · 검색 · 저장이 전부 기존 화면 그대로 돌아간다.
///
/// 항목 id는 서버가 `ai-` 접두사로 붙여 준다 — 번들 시드 id와 절대 겹치지 않는다.
struct VocabularyGeneratedSet: Codable, Identifiable, Hashable, Sendable {
    let setId: String
    let topic: VocabularyTopic
    let targetLevel: OPIcLevel
    let createdAt: Date
    let entries: [VocabularyEntry]
    let source: String

    var id: String { setId }

    func entries(of type: VocabularyItemType) -> [VocabularyEntry] {
        entries.filter { $0.type == type }
    }
}
