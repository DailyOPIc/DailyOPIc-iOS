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
                Text("AI가 분석한 내용은 실제 OPIc 평가 결과와 다를 수 있습니다.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .cardStyle()
                LevelResultCard(
                    predicted: evaluation.predictedLevel,
                    target: targetLevel,
                    confidence: evaluation.confidence
                )
                if evaluation.isPartial {
                    ErrorBanner(message: "일부 상세 내용을 준비하지 못했어요. 확보된 핵심 결과를 표시합니다.")
                }
                if let rubrics = evaluation.rubrics, !rubrics.isEmpty {
                    RubricBandsView(rubrics: rubrics)
                }
                FeedbackSection(title: "강점", text: evaluation.strengths.joined(separator: "\n• "), tint: AppPalette.successSoft)
                FeedbackSection(title: "우선 개선점", text: evaluation.improvements.joined(separator: "\n• "))
                DisclosureGroup("답변 상세 보기") {
                    VStack(spacing: 14) {
                        FeedbackSection(title: "나의 답변", text: transcript, tint: .white)
                        if let text = evaluation.correctedAnswer, !text.isEmpty {
                            FeedbackSection(title: "자연스러운 교정 답변", text: text, tint: .white)
                        }
                        if let text = evaluation.sampleAnswer, !text.isEmpty {
                            FeedbackSection(title: "\(targetLevel.rawValue) 수준의 샘플 답변", text: text, tint: AppPalette.successSoft)
                        }
                    }
                    .padding(.top, 12)
                }
                .cardStyle()
                if let text = evaluation.targetGap, !text.isEmpty {
                    FeedbackSection(title: "목표 등급과의 차이", text: text)
                }
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
