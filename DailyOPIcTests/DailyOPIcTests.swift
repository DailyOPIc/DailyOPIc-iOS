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
                rubricFocus: ["detail", "fluency"]
            )
        }

        #expect(questions.count == 15)
        #expect(questions.map(\.number) == Array(1...15))
        #expect(questions[0].type == .introduction)
        #expect(questions[10...12].allSatisfy { $0.type == .roleplay })
        #expect(questions[13].type == .comparison)
        #expect(questions[14].type == .advanced)
        #expect(Set(questions[1...3].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[4...6].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[7...9].compactMap(\.comboId)).count == 1)
        #expect(Set(questions[10...12].compactMap(\.comboId)).count == 1)
    }

    @Test func questionSetRoundTripsThroughLocalJSON() throws {
        let question = GeneratedQuestion(
            number: 1,
            type: .introduction,
            comboId: nil,
            topic: "introduction",
            prompt: "Please introduce yourself.",
            difficulty: .IM2,
            rubricFocus: ["organization"]
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
    @Test func onboardingPersistsOnlyNativeProfile() {
        let suite = "DailyOPIcTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)

        preferences.completeOnboarding(
            level: .IH,
            profile: BackgroundProfile(interests: ["news"], sports: ["walking"])
        )

        let restored = AppPreferences(defaults: defaults)
        #expect(restored.hasCompletedOnboarding)
        #expect(restored.targetLevel == .IH)
        #expect(restored.backgroundProfile.interests == ["news"])
    }

    private func expectedType(_ number: Int) -> QuestionType {
        switch number {
        case 1: .introduction
        case 2...7: .survey
        case 8...10: .unexpected
        case 11...13: .roleplay
        case 14: .comparison
        default: .advanced
        }
    }

    private func combo(_ number: Int) -> String? {
        switch number {
        case 2...4: "survey-a"
        case 5...7: "survey-b"
        case 8...10: "unexpected"
        case 11...13: "roleplay"
        default: nil
        }
    }
}
