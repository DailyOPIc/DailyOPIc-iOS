import SwiftUI

struct LevelResultCard: View {
    let predicted: OPIcLevel
    let target: OPIcLevel
    let confidence: ConfidenceBand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPIc 예상 등급")
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(predicted.rawValue)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("목표 \(target.rawValue)")
                    Text("신뢰도 \(confidence.label)")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(AppPalette.primary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct ScoreBars: View {
    let scores: EvaluationScores

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("평가 항목")
                .font(.headline)
            ForEach(scores.items, id: \.0) { label, score in
                VStack(alignment: .leading, spacing: 7) {
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
        VStack(alignment: .leading, spacing: 16) {
            Text("항목별 피드백").font(.headline)
            ForEach(rubrics) { rubric in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(rubric.dimension.label).font(.subheadline.bold())
                        Spacer()
                        Text(rubric.band.label)
                            .font(.caption.bold())
                            .foregroundStyle(AppPalette.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppPalette.primary)
            if items.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}

extension View {
    func cardStyle(alignment: Alignment = .leading) -> some View {
        padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}
