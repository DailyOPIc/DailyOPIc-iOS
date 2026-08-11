import SwiftUI

struct PracticeResultView: View {
    let evaluation: PracticeEvaluation
    let targetLevel: OPIcLevel
    let transcript: String
    var showsNextButton = true
    /// When embedded inside another ScrollView, skip our own ScrollView and outer
    /// padding so the parent controls scrolling and margins (avoids nested
    /// ScrollViews and doubled insets).
    var isEmbedded = false
    var next: () -> Void = {}

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
        // 결과 분석 항목별 잠금(무료=예상등급+강점). 상위 플랜일수록 해제.
        let unlock = ResultUnlock(plan: environment.currentPlan)
        // 순서: 예상 등급 → 근거 주의 → 잘한 점 → 개선할 점 → 어떻게 고칠지 →
        // 참고 답변 → 다음 행동. 코칭 순서지 대시보드가 아니다.
        return VStack(spacing: AppSpacing.md) {
            LevelResultCard(
                predicted: evaluation.predictedLevel,
                target: targetLevel,
                confidence: evaluation.confidence,
                isPartial: evaluation.isPartial
            )

            FeedbackSection(title: "잘한 점", bullets: evaluation.strengths, tint: AppPalette.successSoft)

            if unlock.showsImprovements {
                FeedbackSection(title: "개선할 점", bullets: evaluation.improvements)
            } else {
                LockedFeedbackSection(title: "개선할 점", requiredPlan: .basic) { showsPaywall = true }
            }

            if unlock.showsRubrics {
                if let rubrics = evaluation.rubrics, !rubrics.isEmpty {
                    RubricBandsView(rubrics: rubrics)
                }
            } else {
                LockedFeedbackSection(title: "항목별 상세 분석", requiredPlan: .basic) { showsPaywall = true }
            }

            if unlock.showsTargetGap {
                if let text = evaluation.targetGap {
                    FeedbackSection(title: "목표 등급까지", text: text)
                }
            } else {
                LockedFeedbackSection(title: "목표 등급까지", requiredPlan: .plus) { showsPaywall = true }
            }

            // 참고할 답변은 접힌 상자 안이 아니라 바로 보이게 둔다.
            if unlock.showsCorrectionAndSample {
                if let text = evaluation.correctedAnswer {
                    FeedbackSection(title: "자연스럽게 고친 답변", text: text, tint: AppPalette.surface)
                }
                if let text = evaluation.sampleAnswer {
                    FeedbackSection(
                        title: "\(targetLevel.rawValue) 수준 예시 답변",
                        text: text,
                        tint: AppPalette.successSoft
                    )
                }
            } else {
                LockedFeedbackSection(title: "교정·모범답안", requiredPlan: .plus) { showsPaywall = true }
            }

            DisclosureGroup("내가 말한 내용 보기") {
                FeedbackSection(title: "내 답변", text: transcript, tint: AppPalette.surface)
                    .padding(.top, AppSpacing.md)
            }
            .cardStyle()

            if !evaluation.disclaimer.isEmpty {
                Text(evaluation.disclaimer)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsNextButton {
                PrimaryButton(title: "다음 질문으로 넘어가기", systemImage: "arrow.right") { next() }
            }
        }
    }
}
