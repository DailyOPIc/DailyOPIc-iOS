import Foundation

enum ExamSection: String, Codable, Sendable {
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

enum QuestionStyle: String, Codable, Sendable {
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
    let examSection: ExamSection
    let comboId: String?
    let topic: String
    let prompt: String
    let difficulty: OPIcLevel
    let rubricFocus: [String]
    let questionStyle: QuestionStyle?
    let followUpPrompt: String?
    let topicId: String?
    let category: String?
    let estimatedLevel: OPIcLevel?

    var id: String { "\(number)-\(prompt)" }

    init(
        number: Int,
        examSection: ExamSection,
        comboId: String?,
        topic: String,
        prompt: String,
        difficulty: OPIcLevel,
        rubricFocus: [String],
        questionStyle: QuestionStyle? = nil,
        followUpPrompt: String? = nil,
        topicId: String? = nil,
        category: String? = nil,
        estimatedLevel: OPIcLevel? = nil
    ) {
        self.number = number
        self.examSection = examSection
        self.comboId = comboId
        self.topic = topic
        self.prompt = prompt
        self.difficulty = difficulty
        self.rubricFocus = rubricFocus
        self.questionStyle = questionStyle
        self.followUpPrompt = followUpPrompt
        self.topicId = topicId
        self.category = category
        self.estimatedLevel = estimatedLevel
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case examSection
        case comboId
        case topic
        case prompt
        case difficulty
        case rubricFocus
        case questionStyle
        case followUpPrompt
        case topicId
        case category
        case estimatedLevel
        case legacyType = "type"
        case legacyQuestionType = "questionType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        examSection = try container.decodeIfPresent(ExamSection.self, forKey: .examSection)
            ?? container.decode(ExamSection.self, forKey: .legacyType)
        comboId = try container.decodeIfPresent(String.self, forKey: .comboId)
        topic = try container.decode(String.self, forKey: .topic)
        prompt = try container.decode(String.self, forKey: .prompt)
        difficulty = try container.decode(OPIcLevel.self, forKey: .difficulty)
        rubricFocus = try container.decode([String].self, forKey: .rubricFocus)
        questionStyle = try container.decodeIfPresent(QuestionStyle.self, forKey: .questionStyle)
            ?? container.decodeIfPresent(QuestionStyle.self, forKey: .legacyQuestionType)
        followUpPrompt = try container.decodeIfPresent(String.self, forKey: .followUpPrompt)
        topicId = try container.decodeIfPresent(String.self, forKey: .topicId)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        estimatedLevel = try container.decodeIfPresent(OPIcLevel.self, forKey: .estimatedLevel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(examSection, forKey: .examSection)
        try container.encodeIfPresent(comboId, forKey: .comboId)
        try container.encode(topic, forKey: .topic)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(rubricFocus, forKey: .rubricFocus)
        try container.encodeIfPresent(questionStyle, forKey: .questionStyle)
        try container.encodeIfPresent(followUpPrompt, forKey: .followUpPrompt)
        try container.encodeIfPresent(topicId, forKey: .topicId)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(estimatedLevel, forKey: .estimatedLevel)
    }
}

struct QuestionSet: Codable, Sendable {
    let setId: String
    let setHash: String
    let questions: [GeneratedQuestion]
    let modelVersion: String
    let generatedAt: Date
    let fallbackUsed: Bool
    let initialLevel: Int
    let adjustment: DifficultyAdjustment?
    let effectiveLevel: Int
    let effectiveLevelCode: String
    let expectedTargetLevel: OPIcLevel
    let status: String
    let requiresAdjustmentAfter: Int?
    let isComplete: Bool

    init(
        setId: String,
        setHash: String,
        questions: [GeneratedQuestion],
        modelVersion: String,
        generatedAt: Date,
        fallbackUsed: Bool,
        initialLevel: Int = 4,
        adjustment: DifficultyAdjustment? = nil,
        effectiveLevel: Int = 4,
        effectiveLevelCode: String = "4-4",
        expectedTargetLevel: OPIcLevel = .IM2,
        status: String = "complete",
        requiresAdjustmentAfter: Int? = nil,
        isComplete: Bool = true
    ) {
        self.setId = setId
        self.setHash = setHash
        self.questions = questions
        self.modelVersion = modelVersion
        self.generatedAt = generatedAt
        self.fallbackUsed = fallbackUsed
        self.initialLevel = initialLevel
        self.adjustment = adjustment
        self.effectiveLevel = effectiveLevel
        self.effectiveLevelCode = effectiveLevelCode
        self.expectedTargetLevel = expectedTargetLevel
        self.status = status
        self.requiresAdjustmentAfter = requiresAdjustmentAfter
        self.isComplete = isComplete
    }

    var debugTopicIDs: [String] {
        questions.map { $0.topicId ?? "nil" }
    }

    func logDebugSummary(mode: String) {
        #if DEBUG
        print(
            "[DailyOPIc][QuestionSet] mode=\(mode) setId=\(setId) setHash=\(setHash) "
            + "modelVersion=\(modelVersion) fallbackUsed=\(fallbackUsed) "
            + "initialLevel=\(initialLevel) adjustment=\(adjustment?.rawValue ?? "nil") "
            + "effectiveLevelCode=\(effectiveLevelCode) isComplete=\(isComplete) "
            + "topicIds=\(debugTopicIDs)"
        )
        if fallbackUsed {
            print(
                "[DailyOPIc][QuestionSet][Warning] fallbackUsed=true. "
                + "This question set did not come from a successful OpenAI generation."
            )
        }
        #endif
    }
}

struct QuestionSetRequest: Codable, Sendable {
    let initialLevel: Int
    let background: BackgroundProfile
    let recentQuestionHashes: [String]
    let survey: BackgroundSurvey?

    init(
        initialLevel: SelfAssessmentLevel,
        background: BackgroundProfile,
        recentQuestionHashes: [String] = [],
        survey: BackgroundSurvey? = nil
    ) {
        self.initialLevel = initialLevel.rawValue
        self.background = background
        self.recentQuestionHashes = recentQuestionHashes
        self.survey = survey
    }
}

struct QuestionSetAdjustmentRequest: Codable, Sendable {
    let adjustment: DifficultyAdjustment
}

struct PracticeRefreshRequest: Codable, Sendable {
    let initialLevel: Int
    let background: BackgroundProfile
    let recentQuestionHashes: [String]
    let survey: BackgroundSurvey?
    let adjustment: DifficultyAdjustment

    init(
        initialLevel: SelfAssessmentLevel,
        background: BackgroundProfile,
        recentQuestionHashes: [String] = [],
        survey: BackgroundSurvey?,
        adjustment: DifficultyAdjustment
    ) {
        self.initialLevel = initialLevel.rawValue
        self.background = background
        self.recentQuestionHashes = recentQuestionHashes
        self.survey = survey
        self.adjustment = adjustment
    }
}

struct RecordedAnswer: Codable, Identifiable, Sendable {
    let number: Int
    let transcript: String
    let audioPath: String

    var id: Int { number }
    var audioURL: URL { URL(fileURLWithPath: audioPath) }
}
