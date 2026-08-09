import SwiftUI

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppPalette.danger)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("재시도", action: retry)
                    .font(.footnote.weight(.bold))
            }
        }
        .padding(AppSpacing.md)
        .background(AppPalette.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}
