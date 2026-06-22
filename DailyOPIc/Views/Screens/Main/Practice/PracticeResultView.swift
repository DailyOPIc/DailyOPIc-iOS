import SwiftUI

struct PracticeResultView: View {
    let evaluation: PracticeEvaluation
    let targetLevel: OPIcLevel
    let transcript: String
    var showsNextButton = true
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FeedbackSection(title: "나의 답변", text: transcript, tint: .white)
                LevelResultCard(
                    predicted: evaluation.predictedLevel,
                    target: targetLevel,
                    confidence: evaluation.confidence
                )
                ScoreBars(scores: evaluation.scores)
                FeedbackSection(title: "강점", text: evaluation.strengths.joined(separator: "\n• "), tint: AppPalette.successSoft)
                FeedbackSection(title: "우선 개선점", text: evaluation.improvements.joined(separator: "\n• "))
                FeedbackSection(title: "자연스러운 교정 답변", text: evaluation.correctedAnswer, tint: .white)
                FeedbackSection(title: "\(targetLevel.rawValue) 수준의 샘플 답변", text: evaluation.sampleAnswer, tint: AppPalette.successSoft)
                FeedbackSection(title: "목표 등급과의 차이", text: evaluation.targetGap)
                Text(evaluation.disclaimer)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                if showsNextButton {
                    PrimaryButton(title: "다음 질문으로 넘어가기", systemImage: "arrow.right") { next() }
                }
            }
            .padding(20)
        }
    }
}
