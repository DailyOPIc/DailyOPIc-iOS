import SwiftUI

struct RecordingButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Expanding ring while recording.
                if isRecording {
                    Circle()
                        .stroke(AppPalette.danger.opacity(0.35), lineWidth: 3)
                        .frame(width: 86, height: 86)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isRecording ? AppPalette.actionOnDanger : AppPalette.actionOnPrimary)
                    .frame(width: 86, height: 86)
                    .background(isRecording ? AppPalette.danger : AppPalette.primary)
                    .clipShape(Circle())
                    .shadow(color: (isRecording ? AppPalette.danger : AppPalette.primary).opacity(0.28), radius: 18, y: 10)
                    .scaleEffect(isRecording ? 1.05 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
        .onChange(of: isRecording) { _, recording in
            guard !reduceMotion else { return }
            if recording {
                pulse = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
        .accessibilityLabel(isRecording ? "녹음 종료" : "녹음 시작")
    }
}
