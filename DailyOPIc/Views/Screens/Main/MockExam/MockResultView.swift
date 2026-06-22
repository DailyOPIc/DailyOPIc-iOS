import SwiftUI

struct MockResultView: View {
    let evaluation: MockEvaluation
    let targetLevel: OPIcLevel
    var showsResetButton = true
    let reset: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LevelResultCard(
                    predicted: evaluation.predictedLevel,
                    target: targetLevel,
                    confidence: evaluation.confidence
                )
                ScoreBars(scores: evaluation.scores)
                FeedbackSection(title: "종합 피드백", text: evaluation.overallFeedback)
                FeedbackSection(title: "강점", text: evaluation.strengths.joined(separator: "\n• "), tint: AppPalette.successSoft)
                FeedbackSection(title: "우선 개선점", text: evaluation.improvements.joined(separator: "\n• "))
                FeedbackSection(title: "목표 등급과의 차이", text: evaluation.targetGap)
                VStack(alignment: .leading, spacing: 14) {
                    Text("문항별 피드백과 샘플 답변")
                        .font(.title3.bold())
                    ForEach(evaluation.perQuestion) { item in
                        DisclosureGroup("QUESTION \(item.number)") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.feedback)
                                Divider()
                                Text("목표 수준 샘플")
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.primary)
                                Text(item.sampleAnswer)
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 12)
                        }
                        .padding(16)
                        .background(AppPalette.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(evaluation.disclaimer)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                if showsResetButton {
                    PrimaryButton(title: "새 모의고사", systemImage: "arrow.clockwise", action: reset)
                }
            }
            .padding(20)
        }
    }
}
