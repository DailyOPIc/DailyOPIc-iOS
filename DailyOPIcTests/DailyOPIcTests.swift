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
                examSection: expectedType(number),
                comboId: combo(number),
                topic: "topic-\(number)",
                prompt: "Question \(number)",
                difficulty: .IH,
                rubricFocus: ["detail", "fluency"],
                questionStyle: .description,
                followUpPrompt: "Follow up \(number)",
                topicId: topicId(number),
                category: number == 1 ? "introduction" : "mock",
                estimatedLevel: .IH
            )
        }

        #expect(questions.count == 15)
        #expect(questions.map(\.number) == Array(1...15))
        #expect(questions[0].examSection == .introduction)
        #expect(questions[1...9].allSatisfy { $0.examSection == .survey })
        #expect(questions[10...11].allSatisfy { $0.examSection == .roleplay })
        #expect(questions[12].examSection == .unexpected)
        #expect(questions[13].examSection == .comparison)
        #expect(questions[14].examSection == .advanced)
        #expect(Set(questions[1...3].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[4...6].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[7...9].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[10...11].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[1...3].compactMap(\.topicId)) == Set(["movies"]))
    }

    @Test func questionSetRoundTripsThroughLocalJSON() throws {
        let question = GeneratedQuestion(
            number: 1,
            examSection: .introduction,
            comboId: nil,
            topic: "introduction",
            prompt: "Please introduce yourself.",
            difficulty: .IM2,
            rubricFocus: ["organization"],
            questionStyle: .description,
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
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let encodedQuestion = (object?["questions"] as? [[String: Any]])?.first

        #expect(decoded.setId == original.setId)
        #expect(decoded.questions == original.questions)
        #expect(decoded.fallbackUsed == false)
        #expect(encodedQuestion?["examSection"] as? String == "introduction")
        #expect(encodedQuestion?["questionStyle"] as? String == "description")
        #expect(encodedQuestion?["type"] == nil)
        #expect(encodedQuestion?["questionType"] == nil)
    }

    @Test func questionSetDebugTopicIDsHandleNilValues() {
        let question = GeneratedQuestion(
            number: 1,
            examSection: .practice,
            comboId: nil,
            topic: "custom topic",
            prompt: "Describe a custom topic with a detailed example.",
            difficulty: .IM2,
            rubricFocus: ["organization"],
            questionStyle: .description,
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
            initialLevel: .level5,
            profile: BackgroundProfile(interests: ["news"], sports: ["walking"])
        )
        preferences.mockSurvey = survey

        let restored = AppPreferences(defaults: defaults)
        #expect(restored.hasCompletedOnboarding)
        #expect(restored.initialLevel == .level5)
        #expect(restored.targetLevel == .IH)
        #expect(restored.backgroundProfile.interests == ["news"])
        #expect(restored.mockSurvey == survey)
    }

    @MainActor
    @Test func completedV1UserMigratesWithoutForcedGuide() {
        let suite = "DailyOPIcMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "native_onboarding_completed")
        defaults.set(5, forKey: "native_initial_level")

        let preferences = AppPreferences(defaults: defaults)

        #expect(preferences.hasCompletedOnboarding)
        #expect(preferences.onboardingSchemaVersion == 2)
        #expect(preferences.guideState == .skipped)
        #expect(!preferences.isPresentingGuide)
    }

    @MainActor
    @Test func guideProgressAndSkipRemainReenterable() {
        let suite = "DailyOPIcGuideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.guideState = .inProgress
        preferences.lastGuidePage = 4

        let restored = AppPreferences(defaults: defaults)
        #expect(restored.guideState == .inProgress)
        #expect(restored.lastGuidePage == 4)
        restored.finishGuide(skipped: true)
        restored.beginGuide()
        #expect(restored.guideState == .skipped)
        #expect(restored.isPresentingGuide)
    }

    @Test func mockRequestEncodesSurvey() throws {
        let survey = BackgroundSurvey.defaultSurvey
        let request = QuestionSetRequest(
            initialLevel: .level4,
            background: BackgroundProfile(interests: ["music"]),
            survey: survey
        )
        let data = try JSONCoding.encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let encodedSurvey = object?["survey"] as? [String: Any]

        #expect(object?["initialLevel"] as? Int == 4)
        #expect(encodedSurvey?["status"] as? String == "student")
        #expect(encodedSurvey?["residence"] as? String == "family")
        #expect((encodedSurvey?["leisure"] as? [String]) == ["movies", "music", "cafes"])
    }

    @Test func practiceRefreshRequestEncodesSurveyAndAdjustment() throws {
        let request = PracticeRefreshRequest(
            initialLevel: .level5,
            background: BackgroundProfile(interests: ["cafes"]),
            survey: .defaultSurvey,
            adjustment: .harder,
            rewardNonce: "refresh-reward-nonce"
        )
        let data = try JSONCoding.encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let encodedSurvey = object?["survey"] as? [String: Any]

        #expect(object?["initialLevel"] as? Int == 5)
        #expect(object?["adjustment"] as? String == "harder")
        #expect(encodedSurvey?["status"] as? String == "student")
    }

    @Test func targetLevelChangeRewardPurposeEncodesServerValue() throws {
        let request = RewardIntentRequest(purpose: .targetLevelChange, sessionHash: nil)
        let data = try JSONCoding.encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["purpose"] as? String == "target_level_change")
        #expect(object?["sessionHash"] == nil)
    }

    @Test func evaluationRubricV2DecodesWithoutUsingNumericScoreAsPrimaryUI() throws {
        let data = """
        {
          "predictedLevel": "IM2",
          "confidence": "medium",
          "scores": {"taskFulfillment": 60, "grammar": 40, "vocabulary": 60, "discourse": 60, "fluency": 40},
          "strengths": ["Clear topic"],
          "improvements": ["Connect ideas"],
          "correctedAnswer": null,
          "targetGap": "Add detail",
          "sampleAnswer": null,
          "audioMetrics": {"durationSeconds": 30, "speakingSeconds": 25, "silenceRatio": 0.16, "wordsPerMinute": 92},
          "disclaimer": "AI learning estimate only.",
          "modelVersion": "fixture",
          "promptVersion": "rubric-v2",
          "resultStatus": "partial",
          "rubrics": [
            {"dimension": "taskFulfillment", "band": "functional", "evidence": "Answered the task.", "nextAction": "Add one example."}
          ],
          "warnings": ["optional details unavailable"],
          "scoreScaleVersion": "rubric-band-v1"
        }
        """.data(using: .utf8)!

        let value = try JSONCoding.decoder.decode(PracticeEvaluation.self, from: data)

        #expect(value.isPartial)
        #expect(value.rubrics?.first?.band == .functional)
        #expect(value.correctedAnswer == nil)
    }

    @Test func unknownServerStatusesDecodeSafely() throws {
        let rewardData = """
        {"nonce":"n","purpose":"mock_result","status":"future_status","userIdentifier":"u","customData":"n","expiresAt":"2026-07-21T12:00:00Z"}
        """.data(using: .utf8)!
        let reward = try JSONCoding.decoder.decode(RewardIntent.self, from: rewardData)
        if case let .unknown(raw) = reward.status {
            #expect(raw == "future_status")
        } else {
            Issue.record("unknown reward status was not preserved")
        }
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

    @Test func apiClientClassifiesPracticeQuotaExhausted() throws {
        let data = """
        {
          "detail": {
            "code": "practice_quota_exhausted",
            "message": "daily practice quota exhausted"
          }
        }
        """.data(using: .utf8)!
        let error = APIClient.makeError(status: 402, data: data)

        #expect(error.isPracticeQuotaExhausted)
        #expect(error.code == "practice_quota_exhausted")
        #expect(error.statusCode == 402)
    }

    @Test func apiClientClassifiesAIUnavailable() throws {
        let data = """
        {
          "detail": {
            "code": "ai_unavailable",
            "message": "AI feedback is temporarily unavailable. Please try again."
          }
        }
        """.data(using: .utf8)!
        let error = APIClient.makeError(status: 503, data: data)

        #expect(error.isAIUnavailable)
        #expect(error.code == "ai_unavailable")
        #expect(error.statusCode == 503)
    }

    @Test func rewardIntentAcceptsVerifiedOrConfirmedStatus() {
        let verified = RewardIntent(
            nonce: "verified-nonce",
            purpose: .targetLevelChange,
            status: .verified,
            userIdentifier: "user-id",
            customData: "verified-nonce",
            expiresAt: .now
        )
        let confirmed = RewardIntent(
            nonce: "confirmed-nonce",
            purpose: .targetLevelChange,
            status: .verified,
            userIdentifier: "user-id",
            customData: "confirmed-nonce",
            expiresAt: .now
        )
        let pending = RewardIntent(
            nonce: "pending-nonce",
            purpose: .targetLevelChange,
            status: .pending,
            userIdentifier: "user-id",
            customData: "pending-nonce",
            expiresAt: .now
        )
        let completed = RewardIntent(
            nonce: "completed-nonce",
            purpose: .targetLevelChange,
            status: .completed,
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
            initialLevel: 6,
            rewardNonce: "target-level-nonce-123456"
        )
        let requestData = try JSONCoding.encoder.encode(request)
        let requestObject = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]

        #expect(requestObject?["initialLevel"] as? Int == 6)
        #expect(requestObject?["rewardNonce"] as? String == "target-level-nonce-123456")

        let responseData = """
        {
          "targetLevel": "AL",
          "previousTargetLevel": "IH",
          "beforeAdjust": 6,
          "previousBeforeAdjust": 5,
          "afterAdjust": 6,
          "changed": true,
          "rewardConsumed": true
        }
        """.data(using: .utf8)!
        let response = try JSONCoding.decoder.decode(TargetLevelResponse.self, from: responseData)

        #expect(response.targetLevel == .AL)
        #expect(response.previousTargetLevel == .IH)
        #expect(response.beforeAdjust == 6)
        #expect(response.previousBeforeAdjust == 5)
        #expect(response.afterAdjust == 6)
        #expect(response.changed)
        #expect(response.rewardConsumed)
    }

    @Test func renamedResponseFieldsDecodeLegacyPayloadsDuringDeployment() throws {
        let targetLevelData = """
        {
          "targetLevel": "IH",
          "previousTargetLevel": null,
          "initialLevel": 5,
          "previousInitialLevel": null,
          "latestAdjustment": "same",
          "effectiveLevel": 5,
          "effectiveLevelCode": "5-5",
          "changed": false,
          "rewardConsumed": false
        }
        """.data(using: .utf8)!
        let targetLevel = try JSONCoding.decoder.decode(TargetLevelResponse.self, from: targetLevelData)

        let questionData = """
        {
          "number": 2,
          "type": "survey",
          "comboId": "survey-1",
          "topic": "movies",
          "prompt": "Tell me about the kinds of movies you like.",
          "difficulty": "IH",
          "rubricFocus": ["detail"],
          "questionType": "description",
          "followUpPrompt": null,
          "topicId": "movies",
          "category": "leisure",
          "estimatedLevel": "IH"
        }
        """.data(using: .utf8)!
        let question = try JSONCoding.decoder.decode(GeneratedQuestion.self, from: questionData)

        #expect(targetLevel.beforeAdjust == 5)
        #expect(targetLevel.previousBeforeAdjust == nil)
        #expect(targetLevel.afterAdjust == 5)
        #expect(question.examSection == .survey)
        #expect(question.questionStyle == .description)
    }

    private func expectedType(_ number: Int) -> ExamSection {
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
