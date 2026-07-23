import SwiftUI

struct MockResultView: View {
    let evaluation: MockEvaluation
    let targetLevel: OPIcLevel
    var showsResetButton = false
    /// When embedded inside another ScrollView, skip our own ScrollView and outer
    /// padding so the parent controls scrolling and margins.
    var isEmbedded = false
    var reset: () -> Void = {}

    @Environment(AppEnvironment.self) private var environment
    @State private var showsPaywall = false

    var body: some View {
        Group {
            if isEmbedded {
                content
            } else {
                ScrollView { content.padding(AppSpacing.lg) }
            }
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private var content: some View {
        let unlock = ResultUnlock(plan: environment.currentPlan)
        return VStack(spacing: AppSpacing.md) {
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
            FeedbackSection(title: "강점", bullets: evaluation.strengths, tint: AppPalette.successSoft)

            if unlock.showsImprovements {
                FeedbackSection(title: "종합 피드백", text: evaluation.overallFeedback)
                FeedbackSection(title: "개선할 점", bullets: evaluation.improvements)
            } else {
                LockedFeedbackSection(title: "종합 피드백 · 개선할 점", requiredPlan: .basic) { showsPaywall = true }
            }

            if unlock.showsRubrics {
                if let rubrics = evaluation.rubrics, !rubrics.isEmpty {
                    RubricBandsView(rubrics: rubrics)
                }
            } else {
                LockedFeedbackSection(title: "항목별 상세 분석", requiredPlan: .basic) { showsPaywall = true }
            }

            if unlock.showsTargetGap {
                FeedbackSection(title: "목표 등급까지", text: evaluation.targetGap)
            } else {
                LockedFeedbackSection(title: "목표 등급까지", requiredPlan: .plus) { showsPaywall = true }
            }

            Text(evaluation.disclaimer)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            if showsResetButton {
                PrimaryButton(title: "완료", systemImage: "checkmark", action: reset)
            }
        }
    }
}
