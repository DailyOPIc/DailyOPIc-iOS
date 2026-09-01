import Foundation

/// 저장된 세트가 어느 경로에서 만들어졌는지 구분하는 **로컬 표식**.
///
/// 서버로 나가지 않는다 — 어떤 세트를 만들지는 요청 필드가 아니라 endpoint가 정한다.
/// 저장된 기록을 읽을 때만 쓰이므로 raw 값을 바꾸면 기존 저장분이 깨진다.
enum VocabularyGenerationPurpose: String, Codable, Sendable {
    /// P14.2에서 만들어 둔 세트. 만드는 경로는 P14.6.2에서 없앴고, 예전 기기에
    /// 남아 있을 수 있는 기록을 읽기 위해 raw 값만 그대로 둔다.
    case customSet = "custom_set"
    /// 오늘의 단어 만들기 20개(P14.6).
    case todayExtra = "today_extra"
}

/// 단어 만들기 요청(P14.6). 앱이 단어를 만드는 **유일한** 요청이다.
///
/// 개수(20 = 7/7/6) · 구성 · 모델 · 내부 보충 횟수는 **서버가 소유한다**. 앱이 보내는
/// 것은 주제 · 목표 등급, 그리고 "이건 이미 있으니 빼 달라"는 제외 힌트뿐이다.
struct TodayVocabularyGenerationRequest: Encodable, Sendable {
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

/// 추가 20개 생성이 진행 중이라는 작은 기록(P14.6).
///
/// 토큰은 **요청을 보내는 순간** 나간다. 조작 신원이 화면 메모리에만 있으면 응답 전에
/// 앱이 죽었을 때 그 신원을 잃고, 사용자가 이미 값을 치른 20개에 토큰을 또 쓰게 된다.
/// 그래서 요청 **전에** 이 기록을 먼저 남긴다 — 다시 열어 같은 주제로 시도하면 같은 키가
/// 나가고 서버가 이미 만든 세트를 추가 차감 없이 돌려준다.
///
/// 두 번째 복구 체계가 아니라 P14.3.1 말하기 코치와 **같은 방식**이다: 진행 중인 조작
/// 하나뿐이라 SwiftData가 아니라 `AppPreferences`(UserDefaults)에 둔다.
struct PendingVocabularyExtraOperation: Codable, Equatable, Sendable {
    /// 서버에 보내는 `Idempotency-Key`.
    let operationID: UUID
    /// 주제가 바뀌면 더 이상 같은 조작이 아니다.
    let topic: VocabularyTopic
    let createdAt: Date

    /// 서버가 같은 키의 결과를 돌려준다고 **보장할 수 있는** 기간(서버 캐시 TTL 24시간보다 짧게).
    static let safeReplayWindow: TimeInterval = 23 * 60 * 60

    init(operationID: UUID = UUID(), topic: VocabularyTopic, createdAt: Date = .now) {
        self.operationID = operationID
        self.topic = topic
        self.createdAt = createdAt
    }

    /// 같은 키로 다시 보내도 안전한가(= 서버가 결과를 재생해 줄 창 안인가).
    func isReplayable(now: Date = .now) -> Bool {
        abs(now.timeIntervalSince(createdAt)) < Self.safeReplayWindow
    }

    /// 이 생성에 쓸 조작 신원을 고른다. 저장된 기록이 **같은 주제**이고 아직 재생 창
    /// 안이면 그대로 이어 쓴다(= 이미 값을 치른 조작). 아니면 새 조작이다.
    static func resume(
        _ stored: PendingVocabularyExtraOperation?,
        topic: VocabularyTopic,
        now: Date = .now
    ) -> PendingVocabularyExtraOperation {
        if let stored, stored.topic == topic, stored.isReplayable(now: now) { return stored }
        return PendingVocabularyExtraOperation(topic: topic, createdAt: now)
    }
}
