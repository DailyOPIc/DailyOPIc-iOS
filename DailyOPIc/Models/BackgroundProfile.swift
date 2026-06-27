import Foundation

struct BackgroundProfile: Codable, Equatable, Sendable {
    var occupation: String?
    var studentStatus: String?
    var housing: String?
    var interests: [String]
    var sports: [String]
    var travel: [String]

    init(
        occupation: String? = nil,
        studentStatus: String? = nil,
        housing: String? = nil,
        interests: [String] = [],
        sports: [String] = [],
        travel: [String] = []
    ) {
        self.occupation = occupation
        self.studentStatus = studentStatus
        self.housing = housing
        self.interests = interests
        self.sports = sports
        self.travel = travel
    }

    static let interestOptions = ["music", "movies", "cooking", "news", "games", "reading"]
    static let sportOptions = ["walking", "running", "gym", "cycling", "swimming"]
    static let travelOptions = ["domestic", "overseas", "staycation", "business"]
}

struct SurveyOption: Identifiable, Codable, Hashable, Sendable {
    let topicId: String
    let label: String
    let category: String

    var id: String { topicId }
}

struct BackgroundSurvey: Codable, Equatable, Sendable {
    var status: String
    var residence: String
    var leisure: [String]
    var hobbies: [String]
    var sports: [String]
    var travel: [String]

    init(
        status: String = "",
        residence: String = "",
        leisure: [String] = [],
        hobbies: [String] = [],
        sports: [String] = [],
        travel: [String] = []
    ) {
        self.status = status
        self.residence = residence
        self.leisure = leisure
        self.hobbies = hobbies
        self.sports = sports
        self.travel = travel
    }

    var selectedTopicCount: Int {
        leisure.count + hobbies.count + sports.count + travel.count
    }

    var isValid: Bool {
        !status.isEmpty
            && !residence.isEmpty
            && selectedTopicCount >= 3
            && [leisure, hobbies, sports, travel].allSatisfy { $0.count <= 6 }
    }

    static let defaultSurvey = BackgroundSurvey(
        status: "student",
        residence: "family",
        leisure: ["movies", "music", "cafes"],
        hobbies: [],
        sports: [],
        travel: []
    )

    static let statusOptions = [
        SurveyOption(topicId: "student", label: "학생", category: "status"),
        SurveyOption(topicId: "office_worker", label: "직장인", category: "status"),
        SurveyOption(topicId: "job_seeker", label: "구직", category: "status"),
        SurveyOption(topicId: "status_none", label: "해당 없음", category: "status")
    ]

    static let residenceOptions = [
        SurveyOption(topicId: "alone", label: "혼자", category: "residence"),
        SurveyOption(topicId: "family", label: "가족", category: "residence"),
        SurveyOption(topicId: "roommates", label: "룸메이트", category: "residence"),
        SurveyOption(topicId: "dormitory", label: "기숙사", category: "residence"),
        SurveyOption(topicId: "residence_other", label: "기타", category: "residence")
    ]

    static let leisureOptions = [
        SurveyOption(topicId: "movies", label: "영화", category: "leisure"),
        SurveyOption(topicId: "music", label: "음악", category: "leisure"),
        SurveyOption(topicId: "cafes", label: "카페", category: "leisure"),
        SurveyOption(topicId: "shopping", label: "쇼핑", category: "leisure"),
        SurveyOption(topicId: "reading", label: "독서", category: "leisure"),
        SurveyOption(topicId: "cooking", label: "요리", category: "leisure"),
        SurveyOption(topicId: "gaming", label: "게임", category: "leisure")
    ]

    static let hobbyOptions = [
        SurveyOption(topicId: "photography", label: "사진", category: "hobbies"),
        SurveyOption(topicId: "instruments", label: "악기", category: "hobbies"),
        SurveyOption(topicId: "fashion", label: "패션", category: "hobbies"),
        SurveyOption(topicId: "pets", label: "반려동물", category: "hobbies"),
        SurveyOption(topicId: "it", label: "IT", category: "hobbies"),
        SurveyOption(topicId: "sns", label: "SNS", category: "hobbies")
    ]

    static let sportOptions = [
        SurveyOption(topicId: "jogging", label: "조깅", category: "sports"),
        SurveyOption(topicId: "gym", label: "헬스", category: "sports"),
        SurveyOption(topicId: "swimming", label: "수영", category: "sports"),
        SurveyOption(topicId: "cycling", label: "자전거", category: "sports"),
        SurveyOption(topicId: "soccer", label: "축구", category: "sports"),
        SurveyOption(topicId: "yoga", label: "요가", category: "sports"),
        SurveyOption(topicId: "hiking", label: "등산", category: "sports")
    ]

    static let travelOptions = [
        SurveyOption(topicId: "domestic_travel", label: "국내", category: "travel"),
        SurveyOption(topicId: "overseas_travel", label: "해외", category: "travel"),
        SurveyOption(topicId: "beach_travel", label: "바다", category: "travel"),
        SurveyOption(topicId: "mountain_travel", label: "산", category: "travel"),
        SurveyOption(topicId: "camping", label: "캠핑", category: "travel"),
        SurveyOption(topicId: "staycation", label: "호캉스", category: "travel"),
        SurveyOption(topicId: "food_travel", label: "맛집 여행", category: "travel")
    ]
}
