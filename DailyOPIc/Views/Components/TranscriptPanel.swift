import SwiftUI

/// Shows the user's spoken answer as recognized speech text.
struct AnswerPanel: View {
    let finalText: String
    let partialText: String
    let isRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label(
                isRecording ? "듣고 있어요" : "내 답변",
                systemImage: isRecording ? "waveform" : "text.alignleft"
            )
            .font(.headline)
            if finalText.isEmpty && partialText.isEmpty {
                Text(isRecording ? "영어로 답변해 주세요." : "녹음을 시작하면 답변이 여기에 표시돼요.")
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if !finalText.isEmpty { Text(finalText) }
                    if !partialText.isEmpty {
                        Text(partialText)
                            .foregroundStyle(AppPalette.secondaryInk.opacity(0.65))
                    }
                }
            }
        }
        .font(AppTypography.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
