import Foundation

enum QuestionType: String, Codable, Sendable {
    case introduction
    case survey
    case unexpected
    case roleplay
    case comparison
    case advanced
    case practice

    var label: String {
        switch self {
        case .introduction: "자기소개"
        case .survey: "설문 주제"
        case .unexpected: "돌발 주제"
        case .roleplay: "롤플레이"
        case .comparison: "비교"
        case .advanced: "심화"
        case .practice: "연습"
        }
    }
}

struct GeneratedQuestion: Codable, Identifiable, Hashable, Sendable {
    let number: Int
    let type: QuestionType
    let comboId: String?
    let topic: String
    let prompt: String
    let difficulty: OPIcLevel
    let rubricFocus: [String]

    var id: String { "\(number)-\(prompt)" }
}

struct QuestionSet: Codable, Sendable {
    let setId: String
    let setToken: String
    let setHash: String
    let questions: [GeneratedQuestion]
    let modelVersion: String
    let generatedAt: Date
    let fallbackUsed: Bool
}

struct QuestionSetRequest: Codable, Sendable {
    let targetLevel: OPIcLevel
    let background: BackgroundProfile
    let recentQuestionHashes: [String]

    init(
        targetLevel: OPIcLevel,
        background: BackgroundProfile,
        recentQuestionHashes: [String] = []
    ) {
        self.targetLevel = targetLevel
        self.background = background
        self.recentQuestionHashes = recentQuestionHashes
    }
}

struct RecordedAnswer: Codable, Identifiable, Sendable {
    let number: Int
    let transcript: String
    let audioPath: String

    var id: Int { number }
    var audioURL: URL { URL(fileURLWithPath: audioPath) }
}
