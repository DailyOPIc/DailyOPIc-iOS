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
            Text("5단계 말하기 루브릭").font(.headline)
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
    let text: String
    var tint = AppPalette.primarySoft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppPalette.primary)
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.ink)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
