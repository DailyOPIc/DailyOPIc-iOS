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

    @Test func questionSetDebugTopicIDsHandleNilValues() {
        let question = GeneratedQuestion(
            number: 1,
            type: .practice,
            comboId: nil,
            topic: "custom topic",
            prompt: "Describe a custom topic with a detailed example.",
            difficulty: .IM2,
            rubricFocus: ["organization"],
            questionType: .description,
            followUpPrompt: nil,
            topicId: nil,
            category: "practice",
            estimatedLevel: .IM2
        )
        let set = QuestionSet(
            setId: "set-1",
            setHash: "hash",
            questions: [question],
            modelVersion: "test-model",
            generatedAt: .now,
            fallbackUsed: false
        )

        #expect(set.debugTopicIDs == ["nil"])
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

    @Test func targetLevelChangeRewardPurposeEncodesServerValue() throws {
        let request = RewardIntentRequest(purpose: .targetLevelChange, sessionHash: nil)
        let data = try JSONCoding.encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["purpose"] as? String == "target_level_change")
        #expect(object?["sessionHash"] == nil)
    }

    @Test func apiClientClassifiesTargetLevelRewardRequired() throws {
        let data = """
        {
          "detail": {
            "code": "target_level_change_reward_required",
            "message": "verified target level change reward is required"
          }
        }
        """.data(using: .utf8)!
        let error = APIClient.makeError(status: 402, data: data)

        #expect(error.isRewardRequired)
        #expect(error.isTargetLevelChangeRewardRequired)
        #expect(error.code == "target_level_change_reward_required")
        #expect(error.statusCode == 402)
    }

    @Test func rewardIntentAcceptsVerifiedOrConfirmedStatus() {
        let verified = RewardIntent(
            nonce: "verified-nonce",
            purpose: .targetLevelChange,
            status: "verified",
            userIdentifier: "user-id",
            customData: "verified-nonce",
            expiresAt: .now
        )
        let confirmed = RewardIntent(
            nonce: "confirmed-nonce",
            purpose: .targetLevelChange,
            status: "confirmed",
            userIdentifier: "user-id",
            customData: "confirmed-nonce",
            expiresAt: .now
        )
        let pending = RewardIntent(
            nonce: "pending-nonce",
            purpose: .targetLevelChange,
            status: "pending",
            userIdentifier: "user-id",
            customData: "pending-nonce",
            expiresAt: .now
        )
        let completed = RewardIntent(
            nonce: "completed-nonce",
            purpose: .targetLevelChange,
            status: "completed",
            userIdentifier: "user-id",
            customData: "completed-nonce",
            expiresAt: .now
        )

        #expect(verified.isVerified)
        #expect(confirmed.isVerified)
        #expect(completed.isVerified)
        #expect(pending.isPending)
        #expect(!pending.isVerified)
    }

    @Test func targetLevelRequestAndResponseRoundTrip() throws {
        let request = TargetLevelRequest(
            targetLevel: .AL,
            rewardNonce: "target-level-nonce-123456"
        )
        let requestData = try JSONCoding.encoder.encode(request)
        let requestObject = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]

        #expect(requestObject?["targetLevel"] as? String == "AL")
        #expect(requestObject?["rewardNonce"] as? String == "target-level-nonce-123456")

        let responseData = """
        {
          "targetLevel": "AL",
          "previousTargetLevel": "IH",
          "changed": true,
          "rewardConsumed": true
        }
        """.data(using: .utf8)!
        let response = try JSONCoding.decoder.decode(TargetLevelResponse.self, from: responseData)

        #expect(response.targetLevel == .AL)
        #expect(response.previousTargetLevel == .IH)
        #expect(response.changed)
        #expect(response.rewardConsumed)
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
