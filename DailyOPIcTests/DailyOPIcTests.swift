import Foundation
import Testing
@testable import DailyOPIc

struct DailyOPIcTests {
    @Test func levelOrderIsStable() {
        #expect(OPIcLevel.NL.rank < OPIcLevel.IM2.rank)
        #expect(OPIcLevel.IM2.rank < OPIcLevel.IH.rank)
        #expect(OPIcLevel.IH.rank < OPIcLevel.AL.rank)
    }

    @Test func mockBlueprintContainsExactlyFifteenQuestions() throws {
        let questions = (1...15).map { number in
            GeneratedQuestion(
                number: number,
                type: expectedType(number),
                comboId: combo(number),
                topic: "topic-\(number)",
                prompt: "Question \(number)",
                difficulty: .IH,
                rubricFocus: ["detail", "fluency"],
                questionType: .description,
                followUpPrompt: "Follow up \(number)",
                topicId: topicId(number),
                category: number == 1 ? "introduction" : "mock",
                estimatedLevel: .IH
            )
        }

        #expect(questions.count == 15)
        #expect(questions.map(\.number) == Array(1...15))
        #expect(questions[0].type == .introduction)
        #expect(questions[1...9].allSatisfy { $0.type == .survey })
        #expect(questions[10...11].allSatisfy { $0.type == .roleplay })
        #expect(questions[12].type == .unexpected)
        #expect(questions[13].type == .comparison)
        #expect(questions[14].type == .advanced)
        #expect(Set(questions[1...3].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[4...6].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[7...9].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[10...11].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[1...3].compactMap(\.topicId)) == Set(["movies"]))
    }

    @Test func questionSetRoundTripsThroughLocalJSON() throws {
        let question = GeneratedQuestion(
            number: 1,
            type: .introduction,
            comboId: nil,
            topic: "introduction",
            prompt: "Please introduce yourself.",
            difficulty: .IM2,
            rubricFocus: ["organization"],
            questionType: .description,
            followUpPrompt: "Add one detail.",
            topicId: "self_introduction",
            category: "introduction",
            estimatedLevel: .IM2
        )
        let original = QuestionSet(
            setId: "set-1",
            setToken: "signed-token",
            setHash: "hash",
            questions: [question],
            modelVersion: "fixture",
            generatedAt: .now,
            fallbackUsed: false
        )
        let data = try JSONCoding.encoder.encode(original)
        let decoded = try JSONCoding.decoder.decode(QuestionSet.self, from: data)

        #expect(decoded.setId == original.setId)
        #expect(decoded.questions == original.questions)
        #expect(decoded.fallbackUsed == false)
    }

    @MainActor
    @Test func onboardingAndMockSurveyPersist() {
        let suite = "DailyOPIcTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let survey = BackgroundSurvey(
            status: "student",
            residence: "family",
            leisure: ["movies", "music", "cafes"],
            hobbies: ["it"],
            sports: [],
            travel: []
        )

        preferences.completeOnboarding(
            level: .IH,
            profile: BackgroundProfile(interests: ["news"], sports: ["walking"])
        )
        preferences.mockSurvey = survey

        let restored = AppPreferences(defaults: defaults)
        #expect(restored.hasCompletedOnboarding)
        #expect(restored.targetLevel == .IH)
        #expect(restored.backgroundProfile.interests == ["news"])
        #expect(restored.mockSurvey == survey)
    }

    @Test func mockRequestEncodesSurvey() throws {
        let survey = BackgroundSurvey.defaultSurvey
        let request = QuestionSetRequest(
            targetLevel: .IM2,
            background: BackgroundProfile(interests: ["music"]),
            survey: survey
        )
        let data = try JSONCoding.encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let encodedSurvey = object?["survey"] as? [String: Any]

        #expect(encodedSurvey?["status"] as? String == "student")
        #expect(encodedSurvey?["residence"] as? String == "family")
        #expect((encodedSurvey?["leisure"] as? [String]) == ["movies", "music", "cafes"])
    }

    private func expectedType(_ number: Int) -> QuestionType {
        switch number {
        case 1: .introduction
        case 2...10: .survey
        case 11...12: .roleplay
        case 13: .unexpected
        case 14: .comparison
        default: .advanced
        }
    }

    private func combo(_ number: Int) -> String? {
        switch number {
        case 2...4: "survey-1"
        case 5...7: "survey-2"
        case 8...10: "survey-3"
        case 11...12: "roleplay"
        default: nil
        }
    }

    private func topicId(_ number: Int) -> String? {
        switch number {
        case 2...4: "movies"
        case 5...7: "music"
        case 8...10: "cafes"
        default: nil
        }
    }
}
