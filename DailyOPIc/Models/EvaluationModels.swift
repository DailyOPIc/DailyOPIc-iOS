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

struct PracticeEvaluation: Codable, Sendable {
    let predictedLevel: OPIcLevel
    let confidence: ConfidenceBand
    let scores: EvaluationScores
    let strengths: [String]
    let improvements: [String]
    let correctedAnswer: String
    let targetGap: String
    let sampleAnswer: String
    let audioMetrics: AudioMetrics
    let disclaimer: String
    let modelVersion: String
    let promptVersion: String
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
}

struct UsageStatus: Codable, Sendable {
    let date: String
    let freeRemaining: Int
    let bonusRemaining: Int

    var totalRemaining: Int { freeRemaining + bonusRemaining }
}

enum RewardPurpose: String, Codable, Sendable {
    case practiceCredits = "practice_credits"
    case mockResult = "mock_result"
    case targetLevelChange = "target_level_change"
}

struct RewardIntentRequest: Codable, Sendable {
    let purpose: RewardPurpose
    let sessionHash: String?
}

struct TargetLevelRequest: Codable, Sendable {
    let targetLevel: OPIcLevel
    let rewardNonce: String?
}

struct TargetLevelResponse: Codable, Sendable {
    let targetLevel: OPIcLevel
    let previousTargetLevel: OPIcLevel?
    let changed: Bool
    let rewardConsumed: Bool
}

struct RewardIntent: Codable, Sendable {
    let nonce: String
    let purpose: RewardPurpose
    let status: String
    let userIdentifier: String
    let customData: String
    let expiresAt: Date

    var isVerified: Bool { status == "verified" || status == "confirmed" }
    var isPending: Bool { status == "pending" }
}

struct MockEvaluationManifest: Codable, Sendable {
    struct Answer: Codable, Sendable {
        let number: Int
        let transcript: String
    }

    let targetLevel: OPIcLevel
    let setId: String
    let rewardNonce: String
    let answers: [Answer]
}
