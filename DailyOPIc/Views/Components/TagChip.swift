import SwiftUI

struct TagChip: View {
    let text: String
    var filled = true

    var body: some View {
        Text(text.hasPrefix("#") ? text : "#\(text)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Color.white : AppPalette.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(filled ? AppPalette.primary : AppPalette.primarySoft)
            .clipShape(Capsule())
    }
}

struct FlowTags: View {
    let values: [String]
    var filled = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { TagChip(text: $0, filled: filled) }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { TagChip(text: $0, filled: filled) }
            }
        }
    }
}
