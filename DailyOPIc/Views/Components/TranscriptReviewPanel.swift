import SwiftUI

/// 녹음을 멈춘 뒤의 검토 상태. 제출(분석)과 다시 녹음을 사용자가 직접 고른다.
/// 녹음 종료만으로는 아무것도 제출되지 않는다는 것을 화면으로도 분명히 한다.
struct TranscriptReviewPanel: View {
    let transcript: String
    let submitTitle: String
    let submitIcon: String
    let isSubmitting: Bool
    let submit: () -> Void
    let reRecord: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // 색이 아니라 아이콘+문구로 상태를 알린다.
            Label("녹음을 멈췄어요", systemImage: "checkmark.circle")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("답변을 확인하고 제출하거나, 다시 녹음할 수 있어요.")
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            AnswerPanel(finalText: transcript, partialText: "", isRecording: false)

            PrimaryButton(
                title: submitTitle,
                systemImage: submitIcon,
                isLoading: isSubmitting,
                action: submit
            )
            Button(action: reRecord) {
                Label("다시 녹음", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .minimumTouchTarget()
            .disabled(isSubmitting)
            .accessibilityHint("이 녹음을 지우고 처음부터 다시 녹음해요. 분석은 하지 않아요.")
        }
    }
}
