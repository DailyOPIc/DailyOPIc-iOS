import SwiftUI

struct SetupView: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var ads: AdService
    @State private var alert: SetupAlert?

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    var body: some View {
        NavigationStack {
            List {
                Section("목표 등급") {
                    HStack {
                        Text("현재 목표 등급")
                        Spacer()
                        Text(preferences.targetLevel?.rawValue ?? "-")
                            .fontWeight(.bold)
                            .foregroundStyle(AppPalette.primary)
                    }
                    if let targetLevel = preferences.targetLevel {
                        Text(targetLevel.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("목표 등급 설정") {
                        openGoalLevelOnboarding()
                    }
                }
                Section("앱") {
                    Button("개인정보처리방침") {
                        openPrivacyPolicy()
                    }
                    Button("광고 개인정보 설정") {
                        Task { await presentAdPrivacyOptions() }
                    }
                    .disabled(!ads.canShowPrivacyOptions)
                    Text(ads.privacyOptionsStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("학습 설정")
            .alert(item: $alert) { item in
                Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    dismissButton: .default(Text("확인"))
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    private func openGoalLevelOnboarding() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            preferences.resetOnboarding()
        }
    }

    private func openPrivacyPolicy() {
        guard let url = AppConfiguration.privacyPolicyURL else {
            alert = SetupAlert(
                title: "링크를 열 수 없어요",
                message: "개인정보처리방침 URL 설정을 확인해 주세요."
            )
            return
        }

        openURL(url) { accepted in
            if !accepted {
                alert = SetupAlert(
                    title: "링크를 열 수 없어요",
                    message: "Safari에서 개인정보처리방침을 열 수 없습니다."
                )
            }
        }
    }

    private func presentAdPrivacyOptions() async {
        do {
            try await ads.presentPrivacyOptions()
        } catch {
            alert = SetupAlert(
                title: "광고 설정을 열 수 없어요",
                message: error.localizedDescription
            )
        }
    }
}

private struct SetupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
