import SwiftUI

struct AuthRecoveryView: View {
    /// Raw underlying error, kept for a collapsible "details" section only.
    let message: String
    let retry: () -> Void
    @State private var showsDetail = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(AppPalette.primary)
            Text("잠시 연결에 문제가 있어요")
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text("네트워크 상태를 확인하고 다시 시도해 주세요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)

            if !message.isEmpty {
                DisclosureGroup("자세히 보기", isExpanded: $showsDetail) {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(AppTypography.footnote)
                .tint(AppPalette.secondaryInk)
                .padding(.horizontal, AppSpacing.sm)
            }

            Spacer()
            PrimaryButton(title: "다시 시도", systemImage: "arrow.clockwise", action: retry)
        }
        .padding(AppSpacing.xl)
    }
}
