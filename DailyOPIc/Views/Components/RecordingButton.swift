import SwiftUI

struct RecordingButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .background(isRecording ? AppPalette.danger : AppPalette.primary)
                .clipShape(Circle())
                .shadow(color: AppPalette.primary.opacity(0.28), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(isRecording ? "녹음 종료" : "녹음 시작")
    }
}
