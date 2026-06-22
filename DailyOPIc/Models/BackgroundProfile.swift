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
