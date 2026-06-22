import SwiftUI

struct QuestionCard: View {
    let question: GeneratedQuestion
    var showsNumber = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if showsNumber {
                    Text("QUESTION \(question.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.primary)
                }
                Spacer()
                Text(question.type.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            Text(question.prompt)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            FlowTags(values: Array(question.rubricFocus.prefix(3)))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.primarySoft)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.primary.opacity(0.55), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
