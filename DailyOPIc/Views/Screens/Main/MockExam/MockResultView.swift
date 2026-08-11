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
        // 순서: 전체 등급 → 시험 총평 → 잘한 패턴 → 약한 패턴 → 다음에 집중할 것 →
        // 문항별 상세 → 마무리 행동.
        return VStack(spacing: AppSpacing.md) {
            LevelResultCard(
                predicted: evaluation.predictedLevel,
                target: targetLevel,
                confidence: evaluation.confidence,
                isPartial: evaluation.isPartial
            )

            if unlock.showsImprovements {
                FeedbackSection(title: "시험 총평", text: evaluation.overallFeedback)
            }

            FeedbackSection(title: "잘한 점", bullets: evaluation.strengths, tint: AppPalette.successSoft)

            if unlock.showsImprovements {
                FeedbackSection(title: "개선할 점", bullets: evaluation.improvements)
            } else {
                LockedFeedbackSection(title: "시험 총평 · 개선할 점", requiredPlan: .basic) { showsPaywall = true }
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

            PerQuestionFeedbackView(items: evaluation.perQuestion)

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
