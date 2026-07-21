import SwiftUI

struct GuideEntryButton: View {
    let preferences: AppPreferences

    var body: some View {
        Button {
            preferences.beginGuide()
        } label: {
            Label("도움말", systemImage: "questionmark.circle")
        }
        .accessibilityHint("데일리오픽 사용법과 오픽 시험 안내를 엽니다")
    }
}
