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

enum SurveyQuestionType: String, Codable, Sendable {
    case description
    case routine
    case pastExperience = "past_experience"
    case comparison
    case roleplay
    case problemSolving = "problem_solving"
    case opinion

    var label: String {
        switch self {
        case .description: "묘사"
        case .routine: "루틴"
        case .pastExperience: "경험"
        case .comparison: "비교"
        case .roleplay: "롤플레이"
        case .problemSolving: "문제 해결"
        case .opinion: "의견"
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
    let questionType: SurveyQuestionType?
    let followUpPrompt: String?
    let topicId: String?
    let category: String?
    let estimatedLevel: OPIcLevel?

    var id: String { "\(number)-\(prompt)" }

    init(
        number: Int,
        type: QuestionType,
        comboId: String?,
        topic: String,
        prompt: String,
        difficulty: OPIcLevel,
        rubricFocus: [String],
        questionType: SurveyQuestionType? = nil,
        followUpPrompt: String? = nil,
        topicId: String? = nil,
        category: String? = nil,
        estimatedLevel: OPIcLevel? = nil
    ) {
        self.number = number
        self.type = type
        self.comboId = comboId
        self.topic = topic
        self.prompt = prompt
        self.difficulty = difficulty
        self.rubricFocus = rubricFocus
        self.questionType = questionType
        self.followUpPrompt = followUpPrompt
        self.topicId = topicId
        self.category = category
        self.estimatedLevel = estimatedLevel
    }
}

struct QuestionSet: Codable, Sendable {
    let setId: String
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
    let survey: BackgroundSurvey?

    init(
        targetLevel: OPIcLevel,
        background: BackgroundProfile,
        recentQuestionHashes: [String] = [],
        survey: BackgroundSurvey? = nil
    ) {
        self.targetLevel = targetLevel
        self.background = background
        self.recentQuestionHashes = recentQuestionHashes
        self.survey = survey
    }
}

struct RecordedAnswer: Codable, Identifiable, Sendable {
    let number: Int
    let transcript: String
    let audioPath: String

    var id: Int { number }
    var audioURL: URL { URL(fileURLWithPath: audioPath) }
}
