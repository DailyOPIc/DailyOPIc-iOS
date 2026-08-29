import Foundation

/// 데일리 질문 → 단어장 주제 잇기(P14.4).
///
/// 분류 체계를 새로 만들지 않는다. 데일리 질문의 `topicId`는 백그라운드 설문의
/// topicId와 같은 값이고, `VocabularyTopic`의 rawValue도 처음부터 그 값에 맞춰 두었다.
/// 그래서 이 계층이 하는 일은 둘뿐이다 — rawValue 직접 대조와, 설문 주제 중 단어장
/// 주제로 그대로 겹치는 것들의 작은 별칭표.
enum VocabularyQuestionTopicMap {
    /// 이름이 다를 뿐 같은 이야기를 하는 설문 주제들.
    /// 대응하는 단어장 주제가 없는 것(reading·gaming·pets·it 등)은 일부러 비워 둔다.
    /// 억지로 이어 붙이는 것보다 "주제 모름"이 정직하고, 그 경우엔 일반 답변 패턴으로 간다.
    private static let aliases: [String: VocabularyTopic] = [
        "instruments": .music,
        "fashion": .shopping,
        "cooking": .food,
        "food_travel": .food,
        "jogging": .exercise,
        "gym": .exercise,
        "swimming": .exercise,
        "cycling": .exercise,
        "soccer": .exercise,
        "yoga": .exercise,
        "hiking": .exercise,
        "domestic_travel": .travel,
        "overseas_travel": .travel,
        "beach_travel": .travel,
        "mountain_travel": .travel,
        "camping": .travel,
        "staycation": .travel,
        "self_introduction": .dailyLife,
        "unexpected_daily": .dailyLife
    ]

    static func topic(for question: GeneratedQuestion) -> VocabularyTopic? {
        guard let topicId = question.topicId else { return nil }
        return topic(forTopicID: topicId)
    }

    /// AI가 만든 데일리 질문은 topicId 뒤에 `_q3_1a2b3c4d` 같은 고유화 꼬리를 붙인다.
    /// 그래서 뒤에서부터 한 마디씩 떼며 아는 주제를 찾는다. 질문 본문은 보지 않는다 —
    /// 여기서 다루는 것은 서버가 붙여 준 구조화된 topicId뿐이다.
    static func topic(forTopicID topicID: String) -> VocabularyTopic? {
        var parts = topicID.lowercased().split(separator: "_").map(String.init)
        while !parts.isEmpty {
            let candidate = parts.joined(separator: "_")
            if let topic = VocabularyTopic(rawValue: candidate) ?? aliases[candidate] {
                return topic
            }
            parts.removeLast()
        }
        return nil
    }
}

/// 질문 하나에 "이 답변에 써볼 표현"을 골라 주는 순수 계산기(P14.4).
///
/// 네트워크도 AI도 부르지 않는다. 입력은 이미 기기에 있는 것뿐(번들 시드 + 이미 받아
/// 둔 AI 세트)이고, 같은 질문이면 앱을 껐다 켜도 같은 목록이 같은 순서로 나온다.
enum VocabularyQuestionRecommender {
    static let limit = 5

    /// 주제를 모를 때 기댈 역할들. 무슨 질문이든 답변의 뼈대로 얹을 수 있는 것들이다.
    private static let genericRoles: Set<VocabularyUsageRole> = [
        .preference, .reason, .transition, .comparison
    ]

    /// 종류를 돌아가며 뽑을 순서. 단어만 다섯 개 주는 일이 없게 하는 장치다.
    private static let typeOrder: [VocabularyItemType] = [.word, .phrase, .pattern]

    /// - Parameters:
    ///   - questionID: 질문의 고유 식별자. 순서를 돌리는 씨앗으로만 쓴다.
    ///   - topic: 맞춘 단어장 주제. 없으면 일반 답변 패턴으로 대체한다.
    ///   - targetLevel: 목표 등급. 맞는 항목을 먼저 보되, 모자라면 나머지로 채운다.
    ///   - entries: 이 기기가 아는 단어 전부(시드 + 받아 둔 AI 세트).
    static func recommend(
        questionID: String,
        topic: VocabularyTopic?,
        targetLevel: OPIcLevel?,
        entries: [VocabularyEntry],
        limit: Int = limit
    ) -> [VocabularyEntry] {
        guard limit > 0 else { return [] }
        let pool: [VocabularyEntry]
        if let topic {
            pool = entries.filter { $0.topics.contains(topic) }
        } else {
            // 주제를 모르면 질문 문장을 넘겨짚지 않는다. 어디에나 쓰는 답변 패턴만 준다.
            pool = entries.filter {
                $0.type == .pattern && !genericRoles.isDisjoint(with: $0.usageRoles)
            }
        }
        // 입력 순서(세트를 받은 순서 등)에 결과가 흔들리지 않도록 id로 한 번 고정한다.
        let ordered = pool.sorted { $0.id < $1.id }
        let offset = seed(questionID)

        var picked: [VocabularyEntry] = []
        var seen: Set<String> = []
        // 목표 등급에 맞는 것부터. 그것만으로 모자랄 때 나머지 등급으로 채운다.
        let tiers = [
            ordered.filter { $0.matches(targetLevel: targetLevel) },
            ordered.filter { !$0.matches(targetLevel: targetLevel) }
        ]
        for tier in tiers where picked.count < limit {
            let buckets = typeOrder.map { type in
                rotated(tier.filter { $0.type == type }, by: offset)
            }
            var index = 0
            while picked.count < limit, buckets.contains(where: { index < $0.count }) {
                for bucket in buckets where index < bucket.count {
                    let entry = bucket[index]
                    guard seen.insert(entry.id).inserted else { continue }
                    picked.append(entry)
                    if picked.count == limit { break }
                }
                index += 1
            }
        }
        return picked
    }

    /// 질문마다 다른 시작점. `String.hashValue`는 실행마다 값이 달라지므로
    /// (프로세스 시드) 껐다 켜도 같은 목록을 주려면 직접 접어야 한다.
    private static func seed(_ text: String) -> Int {
        var value = 5381
        for byte in text.utf8 {
            value = (value &* 33 &+ Int(byte)) & 0xFFFFF
        }
        return value
    }

    private static func rotated(_ list: [VocabularyEntry], by offset: Int) -> [VocabularyEntry] {
        guard list.count > 1 else { return list }
        let start = offset % list.count
        return Array(list[start...] + list[..<start])
    }
}
