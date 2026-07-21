import SwiftUI

struct MockResultView: View {
    let evaluation: MockEvaluation
    let targetLevel: OPIcLevel
    var showsResetButton = false
    let reset: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("AI 학습 분석은 실제 OPIc 평가 결과와 다를 수 있습니다.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .cardStyle()
                LevelResultCard(
                    predicted: evaluation.predictedLevel,
                    target: targetLevel,
                    confidence: evaluation.confidence
                )
                if evaluation.isPartial {
                    ErrorBanner(message: "일부 상세 내용을 준비하지 못했어요. 핵심 결과를 표시합니다.")
                }
                if let rubrics = evaluation.rubrics, !rubrics.isEmpty {
                    RubricBandsView(rubrics: rubrics)
                }
                FeedbackSection(title: "종합 피드백", text: evaluation.overallFeedback)
                FeedbackSection(title: "강점", text: evaluation.strengths.joined(separator: "\n• "), tint: AppPalette.successSoft)
                FeedbackSection(title: "우선 개선점", text: evaluation.improvements.joined(separator: "\n• "))
                FeedbackSection(title: "목표 등급과의 차이", text: evaluation.targetGap)
                Text(evaluation.disclaimer)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                if showsResetButton {
                    PrimaryButton(title: "완료", systemImage: "checkmark", action: reset)
                }
            }
            .padding(20)
        }
    }
}
