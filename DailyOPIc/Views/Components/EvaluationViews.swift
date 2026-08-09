import SwiftUI

struct LevelResultCard: View {
    let predicted: OPIcLevel
    let target: OPIcLevel
    let confidence: ConfidenceBand
    /// The grade is the hero element of this card, so it stays larger than any
    /// text style while still scaling with Dynamic Type via UIFontMetrics.
    @ScaledMetric(relativeTo: .largeTitle) private var gradeSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("OPIc 예상 등급")
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(predicted.rawValue)
                    .font(.system(size: gradeSize, weight: .bold, design: .rounded))
                Spacer()
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("목표 \(target.rawValue)")
                    Text("신뢰도 \(confidence.label)")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(AppPalette.actionOnPrimary)
        .padding(AppSpacing.lg)
        .background(AppPalette.primary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

struct ScoreBars: View {
    let scores: EvaluationScores

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("평가 항목")
                .font(.headline)
            ForEach(scores.items, id: \.0) { label, score in
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text(label)
                        Spacer()
                        Text("\(score)/100")
                            .foregroundStyle(AppPalette.primary)
                    }
                    .font(.subheadline.weight(.semibold))
                    ProgressView(value: Double(score), total: 100)
                        .tint(AppPalette.primary)
                }
            }
        }
        .cardStyle()
    }
}

struct RubricBandsView: View {
    let rubrics: [RubricAssessment]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("항목별 피드백").font(.headline)
            ForEach(rubrics) { rubric in
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text(rubric.dimension.label).font(.subheadline.bold())
                        Spacer()
                        Text(rubric.band.label)
                            .font(.caption.bold())
                            .foregroundStyle(AppPalette.primary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppPalette.primarySoft)
                            .clipShape(Capsule())
                    }
                    Text(rubric.evidence).font(.subheadline)
                    Label(rubric.nextAction, systemImage: "arrow.right.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                if rubric.id != rubrics.last?.id { Divider() }
            }
        }
        .cardStyle()
    }
}

struct FeedbackSection: View {
    let title: String
    private let items: [String]
    var tint = AppPalette.primarySoft

    /// Single free-text block.
    init(title: String, text: String, tint: Color = AppPalette.primarySoft) {
        self.title = title
        self.items = [text]
        self.tint = tint
    }

    /// Bulleted list; each entry gets its own leading bullet (fixes the
    /// previous "\n• " join that dropped the first item's bullet).
    init(title: String, bullets: [String], tint: Color = AppPalette.primarySoft) {
        self.title = title
        self.items = bullets
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppPalette.primary)
            if items.count > 1 {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                            Text("•")
                            Text(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.ink)
                .textSelection(.enabled)
            } else {
                Text(items.first ?? "")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

extension View {
    func cardStyle(alignment: Alignment = .leading) -> some View {
        padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

/// 결과 분석 화면의 플랜별 잠금 해제 사다리.
/// 무료=예상등급+강점, 베이직=+개선점·루브릭, 플러스=+목표갭·교정·모범, 프로=+항목별 피드백.
struct ResultUnlock {
    let plan: PlanEntitlement

    var showsImprovements: Bool { plan >= .basic }
    var showsRubrics: Bool { plan >= .basic }
    var showsTargetGap: Bool { plan >= .plus }
    var showsCorrectionAndSample: Bool { plan >= .plus }
    var showsPerQuestion: Bool { plan >= .pro }
}

/// 유료 잠금 섹션. 탭하면 페이월을 연다.
struct LockedFeedbackSection: View {
    let title: String
    let requiredPlan: PlanEntitlement
    let onUpgrade: () -> Void

    var body: some View {
        Button(action: onUpgrade) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.subheadline)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("\(requiredPlan.displayName)에서 잠금 해제")
                        .font(AppTypography.caption.weight(.semibold))
                }
                .foregroundStyle(AppPalette.primary)
                Text("업그레이드하면 이 항목을 볼 수 있어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.primarySoft.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .buttonStyle(.plain)
    }
}
