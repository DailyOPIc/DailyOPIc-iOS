import SwiftUI

/// Tap-to-play control for a question prompt. Label toggles between
/// "질문 듣기" → "다시 듣기" once the prompt has been played, and shows a
/// speaking state while audio is playing.
struct PromptPlayButton: View {
    let isSpeaking: Bool
    let hasStarted: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var title: String {
        if isSpeaking { return "듣는 중…" }
        return hasStarted ? "다시 듣기" : "질문 듣기"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.fill")
                    .symbolEffect(.variableColor, isActive: isSpeaking)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(AppPalette.primary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppPalette.primarySoft, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isDisabled || isSpeaking)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(hasStarted ? "질문 다시 듣기" : "질문 듣기")
    }
}
