import SwiftUI

struct TranscriptPanel: View {
    let finalText: String
    let partialText: String
    let isRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                isRecording ? "실시간 답변" : "답변 transcript",
                systemImage: isRecording ? "waveform" : "text.alignleft"
            )
            .font(.headline)
            if finalText.isEmpty && partialText.isEmpty {
                Text(isRecording ? "영어로 답변해 주세요." : "녹음을 시작하면 답변이 표시됩니다.")
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
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
