import Foundation

enum ConfidenceBand: String, Codable, Sendable {
    case low, medium, high

    var label: String {
        switch self {
        case .low: "낮음"
        case .medium: "보통"
        case .high: "높음"
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
}

enum RubricBand: String, Codable, Sendable {
    case foundation
    case developing
    case functional
    case strong
    case advanced

    var label: String {
        switch self {
        case .foundation: "기초"
        case .developing: "발전 중"
        case .functional: "무난함"
        case .strong: "우수함"
        case .advanced: "탁월함"
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
    let perQuestion: [PerQuestionFeedback]
    let disclaimer: String
    let modelVersion: String
    let promptVersion: String
    let resultStatus: String?
    let rubrics: [RubricAssessment]?
    let warnings: [String]?
    let scoreScaleVersion: String?

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
    let mockSessionStage: String?

    var totalRemaining: Int {
        (dailyAnalysisFreeRemaining ?? freeRemaining)
            + (dailyAnalysisRewardRemaining ?? bonusRemaining)
    }
}

enum RewardPurpose: String, Codable, Sendable {
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
        let practiceDaily: Int?
        let practiceAdBonus: Int?
        let historyDays: Int?
        let analysisDepth: String?
        let gradeTrend: String?
        let weaknessAnalysis: String?
        let reviewSet: Bool?
        let weeklyReport: Bool?
        let mockComparison: String?
        let adsEnabled: Bool?
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
