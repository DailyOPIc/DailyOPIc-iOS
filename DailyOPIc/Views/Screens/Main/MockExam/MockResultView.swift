import SwiftUI

struct MockResultView: View {
    let evaluation: MockEvaluation
    let targetLevel: OPIcLevel
    var showsResetButton = false
    /// When embedded inside another ScrollView, skip our own ScrollView and outer
    /// padding so the parent controls scrolling and margins.
    var isEmbedded = false
    var reset: () -> Void = {}

    var body: some View {
        if isEmbedded {
            content
        } else {
            ScrollView { content.padding(AppSpacing.lg) }
        }
    }

    private var content: some View {
        // 순서: 전체 등급 → 시험 총평 → 잘한 패턴 → 약한 패턴 → 다음에 집중할 것.
        // 잠금 없음: 서버는 모의고사 평가를 플랜과 무관하게 전체로 내려준다
        // (`ai.py: evaluate_mock`은 depth를 아예 쓰지 않는다). 실제로 받는 내용을
        // 플랜을 이유로 가리면 그건 잠금이 아니라 거짓말이다.
        VStack(spacing: AppSpacing.md) {
            LevelResultCard(
                predicted: evaluation.predictedLevel,
                target: targetLevel,
                confidence: evaluation.confidence,
                isPartial: evaluation.isPartial,
                quality: evaluation.answerQuality
            )

            FeedbackSection(title: "시험 총평", text: evaluation.overallFeedback)
            FeedbackSection(title: "잘한 점", bullets: evaluation.strengths, tint: AppPalette.successSoft)
            FeedbackSection(title: "개선할 점", bullets: evaluation.improvements)

            if let rubrics = evaluation.rubrics, !rubrics.isEmpty {
                RubricBandsView(rubrics: rubrics)
            }

            FeedbackSection(title: "목표 등급까지", text: evaluation.targetGap)

            if !evaluation.disclaimer.isEmpty {
                Text(evaluation.disclaimer)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsResetButton {
                PrimaryButton(title: "완료", systemImage: "checkmark", action: reset)
            }
        }
    }
}
