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
                Text("AI 분석 결과는 실제 시험 점수와 다를 수 있어요.")
                    .font(AppTypography.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .cardStyle(alignment: .center)
                LevelResultCard(
                    predicted: evaluation.predictedLevel,
                    target: targetLevel,
                    confidence: evaluation.confidence
                )
                if evaluation.isPartial {
                    ErrorBanner(message: "일부 내용을 준비하지 못했어요. 핵심 결과만 보여드릴게요.")
                }
                if let rubrics = evaluation.rubrics, !rubrics.isEmpty {
                    RubricBandsView(rubrics: rubrics)
                }
                FeedbackSection(title: "강점", bullets: evaluation.strengths, tint: AppPalette.successSoft)
                FeedbackSection(title: "개선할 점", bullets: evaluation.improvements)
                DisclosureGroup("답변 자세히 보기") {
                    VStack(spacing: 14) {
                        FeedbackSection(title: "내 답변", text: transcript, tint: AppPalette.surface)
                        if let text = evaluation.correctedAnswer, !text.isEmpty {
                            FeedbackSection(title: "자연스럽게 고친 답변", text: text, tint: AppPalette.surface)
                        }
                        if let text = evaluation.sampleAnswer, !text.isEmpty {
                            FeedbackSection(title: "\(targetLevel.rawValue) 수준 예시 답변", text: text, tint: AppPalette.successSoft)
                        }
                    }
                    .padding(.top, 12)
                }
                .cardStyle()
                if let text = evaluation.targetGap, !text.isEmpty {
                    FeedbackSection(title: "목표 등급까지", text: text)
                }
                Text(evaluation.disclaimer)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                if showsNextButton {
                    PrimaryButton(title: "다음 질문으로 넘어가기", systemImage: "arrow.right") { next() }
                }
            }
            .padding(20)
        }
    }
}
