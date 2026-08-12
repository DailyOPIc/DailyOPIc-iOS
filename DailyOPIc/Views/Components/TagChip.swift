import SwiftUI

struct TagChip: View {
    let text: String
    var filled = true

    var body: some View {
        Text(text.hasPrefix("#") ? text : "#\(text)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? AppPalette.actionOnPrimary : AppPalette.primary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(filled ? AppPalette.primary : AppPalette.primarySoft)
            .clipShape(Capsule())
    }
}

struct FlowTags: View {
    let values: [String]
    var filled = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(values, id: \.self) { TagChip(text: $0, filled: filled) }
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(values, id: \.self) { TagChip(text: $0, filled: filled) }
            }
        }
    }
}
