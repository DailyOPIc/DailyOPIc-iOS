import SwiftUI

/// Compact pill showing how many daily analyses the user has left.
struct DailyTokenBadge: View {
    let count: Int?

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "bolt.fill")
                .font(.footnote.weight(.bold))
            Text("데일리 토큰")
                .font(AppTypography.caption)
            Text(count.map(String.init) ?? "—")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(AppPalette.primary)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppPalette.primarySoft, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("데일리 토큰 \(count.map(String.init) ?? "확인 중")")
    }
}
