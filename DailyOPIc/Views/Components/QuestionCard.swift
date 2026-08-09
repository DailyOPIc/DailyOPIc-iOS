import SwiftUI

struct QuestionCard: View {
    let question: GeneratedQuestion
    var showsNumber = false
    var showsRubricFocus = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                if showsNumber {
                    Text("Q\(question.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.primary)
                }
                Spacer()
                Text(question.estimatedLevel?.rawValue ?? question.difficulty.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppPalette.actionOnPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppPalette.primary)
                    .clipShape(Capsule())
                Text(question.questionStyle?.label ?? question.examSection.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            Text(question.prompt)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if showsRubricFocus {
                FlowTags(values: Array(question.rubricFocus.prefix(3)))
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.primarySoft)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(AppPalette.primary.opacity(0.55), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}
