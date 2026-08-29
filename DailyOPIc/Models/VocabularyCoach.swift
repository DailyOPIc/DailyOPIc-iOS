import Foundation

/// 대상 표현을 실제로 어떻게 썼는가(P14.3). 원시값은 백엔드
/// `VocabularyUsageAssessment`와 **글자 그대로** 같다.
///
/// 점수가 아니라 세 갈래 판정이다. 등급·숫자 점수·5개 영역 루브릭은 데일리 분석의
/// 몫이고 코치는 그것을 흉내 내지 않는다 — 두 화면이 서로 다른 등급을 말하면 안 된다.
enum VocabularyUsageAssessment: String, Codable, CaseIterable, Sendable {
    case appropriate
    case needsPolish
    case notUsed

    var label: String {
        switch self {
        case .appropriate: "잘 사용했어요"
        case .needsPolish: "조금 다듬으면 더 자연스러워요"
        case .notUsed: "이번 답변에는 쓰이지 않았어요"
        }
    }

    var systemImage: String {
        switch self {
        case .appropriate: "checkmark.circle"
        case .needsPolish: "wand.and.stars"
        case .notUsed: "arrow.uturn.left.circle"
        }
    }
}

/// AI 말하기 코치 1회 요청.
///
/// 모델 · 프롬프트 · 출력 형식 · 비용(1)은 **서버가 소유한다.** 앱이 보내는 것은
/// 무엇을 연습했는지와 무엇을 말했는지뿐이다.
struct VocabularySpeakingCoachRequest: Encodable, Sendable {
    let entryId: String
    let term: String
    let type: VocabularyItemType
    let transcript: String
    let meaningKo: String?
    let topic: VocabularyTopic?
    let targetLevel: OPIcLevel?

    /// 서버 상한과 같은 값. 넘는 전사는 **보내기 전에** 앱이 자른다 — 서버는 자르지
    /// 않고 거절하므로, 여기서 막지 않으면 사용자가 422만 보게 된다.
    static let transcriptLimit = 600

    /// 시드 · AI 생성 항목 모두 같은 `VocabularyEntry`에서 만든다. 출처별로
    /// 요청을 따로 만들지 않는다.
    init(entry: VocabularyEntry, transcript: String, targetLevel: OPIcLevel?) {
        entryId = entry.id
        term = entry.term
        type = entry.type
        self.transcript = String(
            transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.transcriptLimit)
        )
        meaningKo = entry.meaningKo.isEmpty ? nil : entry.meaningKo
        topic = entry.primaryTopic
        self.targetLevel = targetLevel
    }
}

/// 코칭 1회 결과. 기기에 저장해 두고 다시 열 때 **무료로** 보여준다.
///
/// 여기 없는 것: 예상 등급 · 숫자 점수 · 합불 · 발음 점수.
struct VocabularySpeakingCoachResult: Codable, Identifiable, Hashable, Sendable {
    let resultId: String
    let entryId: String
    let targetTerm: String
    let transcript: String
    let usageAssessment: VocabularyUsageAssessment
    let usageFeedbackKo: String
    let naturalCorrectionEn: String
    let naturalCorrectionKo: String
    let expandedAnswerEn: String
    let expandedAnswerKo: String
    let relatedExpressions: [String]
    let createdAt: Date

    var id: String { resultId }
}

/// 시작했지만 아직 기기에 결과가 남지 않은 코칭 조작 하나(P14.3.1).
///
/// 토큰은 **요청을 보내는 순간** 나간다. 그런데 조작 신원이 화면 메모리에만 있으면 응답을 받기 전에
/// 앱이 죽었을 때 그 신원을 잃고, 사용자가 같은 분석에 토큰을 또 쓰게 된다. 그래서 요청을 보내기
/// **전에** 이 작은 기록을 먼저 남긴다 — 앱을 다시 열면 같은 키로 재시도해서 서버가 이미 만들어 둔
/// 결과를 추가 차감 없이 되찾는다.
///
/// 오디오는 담지 않는다. 늘어나는 목록이 아니라 진행 중인 조작 하나뿐이므로 SwiftData가 아니라
/// `AppPreferences`(UserDefaults)에 둔다.
struct PendingVocabularyCoachOperation: Codable, Equatable, Sendable {
    /// 서버에 보내는 `Idempotency-Key`. 이 값이 같아야 서버가 이미 만든 결과를 돌려준다.
    let operationID: UUID
    let entryID: String
    /// 정규화된 답변 키. 같은 항목이라도 답변이 다르면 다른 조작이다.
    let transcriptKey: String
    /// 재시도에 그대로 다시 보낼 답변 원문.
    let transcript: String
    let createdAt: Date

    /// 서버가 같은 키의 결과를 돌려준다고 **보장할 수 있는** 기간.
    /// 서버 요청 결과 캐시 TTL은 24시간이므로 그보다 짧게 잡아 시계 오차만큼 여유를 둔다.
    /// 이 창을 넘긴 기록은 자동으로 다시 보내지 않는다 — 재생될지 알 수 없는 키를 던지면
    /// 사용자도 모르게 두 번째 토큰이 나갈 수 있다.
    static let safeReplayWindow: TimeInterval = 23 * 60 * 60

    init(
        operationID: UUID = UUID(),
        entryID: String,
        transcript: String,
        createdAt: Date = .now
    ) {
        self.operationID = operationID
        self.entryID = entryID
        transcriptKey = VocabularySpeakingPrompt.transcriptKey(transcript)
        self.transcript = transcript
        self.createdAt = createdAt
    }

    /// 같은 항목 · 같은 답변인가. 답변이 바뀌었으면 더 이상 같은 AI 조작이 아니다.
    func matches(entryID: String, transcript: String) -> Bool {
        self.entryID == entryID
            && transcriptKey == VocabularySpeakingPrompt.transcriptKey(transcript)
    }

    /// 같은 키로 다시 보내도 안전한가(= 서버가 결과를 재생해 줄 창 안인가).
    func isReplayable(now: Date = .now) -> Bool {
        // 시계가 뒤로 간 경우(음수 나이)도 창 안이면 살린다. 그때 신원을 버리면
        // 이미 값을 치른 분석에 토큰이 또 나갈 수 있다.
        abs(now.timeIntervalSince(createdAt)) < Self.safeReplayWindow
    }

    /// 이 답변에 쓸 조작 신원을 고른다.
    ///
    /// 저장된 기록이 **같은 항목 · 같은 답변**이고 아직 재생 창 안이면 그 신원을 그대로 이어 쓴다
    /// (앱이 죽었다 살아난 경우 = 이미 값을 치른 조작). 답변이 바뀌었거나 창을 넘겼으면 새 조작이다.
    static func resume(
        _ stored: PendingVocabularyCoachOperation?,
        entryID: String,
        transcript: String,
        now: Date = .now
    ) -> PendingVocabularyCoachOperation {
        if let stored,
           stored.matches(entryID: entryID, transcript: transcript),
           stored.isReplayable(now: now) {
            return stored
        }
        return PendingVocabularyCoachOperation(
            entryID: entryID,
            transcript: transcript,
            createdAt: now
        )
    }
}

/// 말하기 지시문. **AI를 부르지 않는다** — 지시문 한 줄을 만들려고 토큰을 쓰지 않는다.
/// 같은 항목이면 항상 같은 문장이 나오는 순수 함수다.
enum VocabularySpeakingPrompt {
    /// "crowded를 사용해서 한두 문장으로 말해보세요."
    ///
    /// 예문을 그대로 따라 읽게 하지 않는다 — 목표는 받아쓰기가 아니라 실제 사용이다.
    static func instruction(for entry: VocabularyEntry) -> String {
        switch entry.type {
        case .word, .phrase:
            "\(entry.term)를 사용해서 한두 문장으로 말해보세요."
        case .pattern:
            "\(entry.term) 표현을 사용해서 한두 문장으로 말해보세요."
        }
    }

    /// 주제가 있으면 붙이는 로컬 힌트. 없으면 아무것도 보여주지 않는다.
    static func topicHint(for entry: VocabularyEntry) -> String? {
        guard let topic = entry.primaryTopic else { return nil }
        return "\(topic.label) 이야기를 떠올리면 말하기 쉬워요."
    }

    /// 같은 답변인지 판정하는 정규형. 대소문자 · 앞뒤 공백 · 중복 공백을 무시한다.
    /// 같은 답변을 실수로 두 번 유료 분석하지 않기 위한 조회 키다.
    static func transcriptKey(_ transcript: String) -> String {
        transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// 분석에 보낼 만한 답변인가. 빈 답변·한 단어짜리 잡음을 유료 요청으로 보내지 않는다.
    static func isAnalyzable(_ transcript: String) -> Bool {
        transcriptKey(transcript).count >= 3
    }
}
