import Foundation

enum ConfidenceBand: String, Codable, Sendable {
    case low, medium, high

    /// confidence는 서버가 계산한 값이 아니라 AI의 자기 보고다(docs/DESIGN_DECISIONS.md T4:
    /// 평가 프롬프트에 confidence 판단 기준이 한 줄도 없다). 그래서 "신뢰도 높음"처럼
    /// 확신을 광고하지 않는다. AI가 스스로 불확실하다고 한 경우만 사용자에게 알린다.
    var cautionMessage: String? {
        switch self {
        case .low: "AI가 이 답변만으로는 판단이 어렵다고 했어요. 예상 등급은 참고로만 봐주세요."
        case .medium, .high: nil
        }
    }
}

struct EvaluationScores: Codable, Sendable {
    let taskFulfillment: Int
    let grammar: Int
    let vocabulary: Int
    let discourse: Int
    let fluency: Int

    var items: [(String, Int)] {
        [
            ("과제 충족", taskFulfillment),
            ("문법", grammar),
            ("어휘", vocabulary),
            ("담화 구성", discourse),
            ("유창성", fluency)
        ]
    }
}

struct AudioMetrics: Codable, Sendable {
    let durationSeconds: Double
    let speakingSeconds: Double
    let silenceRatio: Double
    let wordsPerMinute: Double
    /// 서버가 실제로 오디오를 측정했는지(false) 전사 길이로 추정했는지(true).
    /// 구버전 서버 응답에는 없으므로 옵셔널.
    let isEstimated: Bool?
}

/// 등급을 얼마나 믿을 수 있는지에 대한 **서버 판정**. 판정 기준은 백엔드
/// `app/services/answer_quality.py` 한 곳에만 있고, 앱은 렌더링만 한다.
/// 클라이언트가 자체 임계값을 만들면 앱 버전마다 결과가 갈린다.
enum AnswerQuality: String, Codable, Sendable {
    case gradable
    case lowEvidence = "low_evidence"
    case insufficient

    /// 등급을 숫자/글자로 단언해도 되는가.
    var showsGrade: Bool { self != .insufficient }

    var cautionMessage: String? {
        switch self {
        case .gradable: nil
        case .lowEvidence: "이 답변만으로는 근거가 충분하지 않아요. 예상 등급은 참고로만 봐주세요."
        // 분석이 끝난 문항은 다시 녹음할 수 없다(결과 화면에 재녹음 경로가 없고,
        // 모의고사는 문항이 지나간다). 없는 동작을 안내하지 않는다.
        case .insufficient: "답변에서 영어 문장을 찾지 못했어요. 다음 답변은 영어로 조금 더 길게 말해 주세요."
        }
    }
}

enum RubricBand: String, Codable, Sendable {
    case foundation
    case developing
    case functional
    case strong
    case advanced

    /// 서버 밴드 5단계를 그대로 1:1로 옮긴 정성 표현. 숫자 점수(20/40/60/80/95)는
    /// 밴드를 되돌린 값일 뿐이라 화면에 쓰지 않는다(docs/DESIGN_DECISIONS.md T4).
    var label: String {
        switch self {
        case .foundation: "집중 필요"
        case .developing: "개선 필요"
        case .functional: "보통"
        case .strong: "좋음"
        case .advanced: "매우 좋음"
        }
    }

    /// 밴드 순서(약함 → 강함). 5단계 표시와 정렬에 쓴다.
    static let ordered: [RubricBand] = [.foundation, .developing, .functional, .strong, .advanced]

    var step: Int { Self.ordered.firstIndex(of: self) ?? 0 }

    /// 서버가 밴드를 되돌려 만든 0~100 점수(20/40/60/80/95)를 다시 밴드로 되돌린다.
    /// 그 사이 값은 여러 회차를 평균 내며 생긴 것이라 "68점" 같은 정밀도는 가짜다.
    static func nearest(toScore score: Int) -> RubricBand {
        let table: [(band: RubricBand, score: Int)] = [
            (.foundation, 20), (.developing, 40), (.functional, 60), (.strong, 80), (.advanced, 95),
        ]
        return table.min { abs($0.score - score) < abs($1.score - score) }?.band ?? .functional
    }

    /// 색만으로 등급을 구분하지 않도록 밴드마다 다른 기호를 함께 쓴다.
    var icon: String {
        switch self {
        case .foundation: "exclamationmark.circle.fill"
        case .developing: "arrow.up.circle.fill"
        case .functional: "equal.circle.fill"
        case .strong: "hand.thumbsup.fill"
        case .advanced: "star.fill"
        }
    }
}

enum RubricDimension: String, Codable, Sendable {
    case taskFulfillment
    case grammar
    case vocabulary
    case discourse
    case fluency

    var label: String {
        switch self {
        case .taskFulfillment: "질문 이해"
        case .grammar: "문법"
        case .vocabulary: "어휘"
        case .discourse: "말의 흐름"
        case .fluency: "유창성"
        }
    }
}

struct RubricAssessment: Codable, Identifiable, Sendable {
    let dimension: RubricDimension
    let band: RubricBand
    let evidence: String
    let nextAction: String

    var id: RubricDimension { dimension }
}

struct PracticeEvaluation: Codable, Sendable {
    let predictedLevel: OPIcLevel
    let confidence: ConfidenceBand
    let scores: EvaluationScores
    let strengths: [String]
    let improvements: [String]
    let correctedAnswer: String?
    let targetGap: String?
    let sampleAnswer: String?
    let audioMetrics: AudioMetrics
    let disclaimer: String
    let modelVersion: String
    let promptVersion: String
    let resultStatus: String?
    let rubrics: [RubricAssessment]?
    let warnings: [String]?
    let scoreScaleVersion: String?
    let answerQuality: AnswerQuality?

    var isPartial: Bool { resultStatus == "partial" }
}

struct PerQuestionFeedback: Codable, Identifiable, Sendable {
    let number: Int
    let feedback: String
    let sampleAnswer: String

    var id: Int { number }
}

struct MockEvaluation: Codable, Sendable {
    let predictedLevel: OPIcLevel
    let confidence: ConfidenceBand
    let scores: EvaluationScores
    let strengths: [String]
    let improvements: [String]
    let targetGap: String
    let overallFeedback: String
    /// 서버 프롬프트가 문항별 피드백을 금지하고 있어 항상 비어 있다.
    /// 계약 호환을 위해 디코딩만 하고 화면에는 쓰지 않는다.
    let perQuestion: [PerQuestionFeedback]
    let disclaimer: String
    let modelVersion: String
    let promptVersion: String
    let resultStatus: String?
    let rubrics: [RubricAssessment]?
    let warnings: [String]?
    let scoreScaleVersion: String?
    let answerQuality: AnswerQuality?

    var isPartial: Bool { resultStatus == "partial" }
}

struct UsageStatus: Codable, Sendable {
    let date: String
    let freeRemaining: Int
    let bonusRemaining: Int
    let serverDateKey: String?
    let resetsAt: Date?
    let dailyAnalysisFreeRemaining: Int?
    let dailyAnalysisRewardRemaining: Int?
    let dailyRefreshRemaining: Int?
    let mockAvailable: Bool?
    let mockRemaining: Int?
    let mockSessionStage: String?

    var totalRemaining: Int {
        (dailyAnalysisFreeRemaining ?? freeRemaining)
            + (dailyAnalysisRewardRemaining ?? bonusRemaining)
    }
}

enum RewardPurpose: String, Codable, Sendable, CaseIterable {
    case practiceCredits = "practice_credits"
    case practiceRefresh = "practice_refresh"
    case mockStart = "mock_start"
    case mockAdjustment = "mock_adjustment"
    case mockResult = "mock_result"
    case targetLevelChange = "target_level_change"
}

struct RewardIntentRequest: Codable, Sendable {
    let purpose: RewardPurpose
    let sessionHash: String?
}

struct TargetLevelRequest: Codable, Sendable {
    let initialLevel: Int
    let rewardNonce: String?
}

struct TargetLevelResponse: Codable, Sendable {
    let targetLevel: OPIcLevel
    let previousTargetLevel: OPIcLevel?
    let beforeAdjust: Int
    let previousBeforeAdjust: Int?
    let afterAdjust: Int
    let changed: Bool
    let rewardConsumed: Bool

    private enum CodingKeys: String, CodingKey {
        case targetLevel
        case previousTargetLevel
        case beforeAdjust
        case previousBeforeAdjust
        case afterAdjust
        case changed
        case rewardConsumed
        case legacyInitialLevel = "initialLevel"
        case legacyPreviousInitialLevel = "previousInitialLevel"
        case legacyEffectiveLevel = "effectiveLevel"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetLevel = try container.decode(OPIcLevel.self, forKey: .targetLevel)
        previousTargetLevel = try container.decodeIfPresent(OPIcLevel.self, forKey: .previousTargetLevel)
        beforeAdjust = try container.decodeIfPresent(Int.self, forKey: .beforeAdjust)
            ?? container.decode(Int.self, forKey: .legacyInitialLevel)
        previousBeforeAdjust = try container.decodeIfPresent(Int.self, forKey: .previousBeforeAdjust)
            ?? container.decodeIfPresent(Int.self, forKey: .legacyPreviousInitialLevel)
        afterAdjust = try container.decodeIfPresent(Int.self, forKey: .afterAdjust)
            ?? container.decode(Int.self, forKey: .legacyEffectiveLevel)
        changed = try container.decode(Bool.self, forKey: .changed)
        rewardConsumed = try container.decode(Bool.self, forKey: .rewardConsumed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetLevel, forKey: .targetLevel)
        try container.encodeIfPresent(previousTargetLevel, forKey: .previousTargetLevel)
        try container.encode(beforeAdjust, forKey: .beforeAdjust)
        try container.encodeIfPresent(previousBeforeAdjust, forKey: .previousBeforeAdjust)
        try container.encode(afterAdjust, forKey: .afterAdjust)
        try container.encode(changed, forKey: .changed)
        try container.encode(rewardConsumed, forKey: .rewardConsumed)
    }
}

struct RewardIntent: Codable, Sendable {
    let nonce: String
    let purpose: RewardPurpose
    let status: RewardStatus
    let userIdentifier: String
    let customData: String
    let expiresAt: Date

    var isVerified: Bool { status == .verified || status == .completed }
    var isPending: Bool { status == .pending }
}

enum RewardStatus: Codable, Equatable, Sendable, CustomStringConvertible {
    case pending
    case verified
    case completed
    case failed
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "pending": self = .pending
        case "verified", "confirmed": self = .verified
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String {
        switch self {
        case .pending: "pending"
        case .verified: "verified"
        case .completed: "completed"
        case .failed: "failed"
        case let .unknown(value): value
        }
    }
}

struct Capabilities: Codable, Sendable {
    struct QuotaPolicy: Codable, Sendable {
        let dailyAnalysisFree: Int
        let dailyRefreshRewards: Int
        let mockSessionsPerDay: Int
        let mockRewardGates: Int
        // 플랜별 기능 게이트(신규 필드는 구 서버 호환을 위해 옵셔널).
        // 등급 추이·취약 유형·주간 리포트는 전 플랜 무료라 게이트 자체가 없다.
        let practiceDaily: Int?
        let practiceAdBonus: Int?
        let historyDays: Int?
        let analysisDepth: String?
        let reviewSet: Bool?
        let adsEnabled: Bool?
        // 캘린더 자동화 깊이(G4). 캘린더 자체는 전 플랜 개방이라 클라이언트가
        // `calendarEnabled`로 화면을 잠그지 않는다 → 읽지 않는 값을 디코드하지 않는다.
        let calendarAutoReplan: Bool?
        let calendarEvaluationAdaptive: Bool?
        let calendarExamBackplan: Bool?
        /// 학습 알림(P4). 이 필드를 모르는 구 서버가 있을 수 있으므로 옵셔널이고,
        /// 없다고 해서 capabilities 전체 디코딩이 실패하지 않는다.
        let calendarStudyReminder: Bool?
    }

    let minimumSupportedAppVersion: String
    let questionGenerationV2: Bool
    let mockSessionV2: Bool
    let evaluationRubricV2: Bool
    let practiceRefresh: Bool
    let guideSchemaVersion: Int
    let plan: String?
    let quotaPolicy: QuotaPolicy
}

struct OperationResult: Codable, Sendable {
    let operationId: String
    let operation: String
    let status: String
    let result: [String: JSONValue]?
    let retryable: Bool
    let updatedAt: Date?
}

enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct MockEvaluationManifest: Codable, Sendable {
    struct Answer: Codable, Sendable {
        let number: Int
        let transcript: String
    }

    let targetLevel: OPIcLevel?
    let setId: String
    let rewardNonce: String
    let answers: [Answer]
}
