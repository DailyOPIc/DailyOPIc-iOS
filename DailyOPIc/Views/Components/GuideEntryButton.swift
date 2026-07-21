import SwiftUI

struct GuideEntryButton: View {
    let preferences: AppPreferences

    var body: some View {
        Button {
            preferences.beginGuide()
        } label: {
            Label("오픽이 처음이신가요?", systemImage: "questionmark.circle")
        }
        .accessibilityHint("OPIc 학습 가이드를 다시 엽니다")
    }
}
