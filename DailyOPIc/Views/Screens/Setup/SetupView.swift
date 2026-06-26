import SwiftUI

struct SetupView: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var ads: AdService
    @State private var level: OPIcLevel
    @State private var alert: SetupAlert?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        _level = State(initialValue: preferences.targetLevel ?? .IH)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("목표 등급") {
                    Picker("목표 등급", selection: $level) {
                        ForEach(OPIcLevel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text(level.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("앱") {
                    Button("온보딩 다시 보기") {
                        preferences.resetOnboarding()
                        dismiss()
                    }
                    Button("개인정보처리방침") {
                        openPrivacyPolicy()
                    }
                    Button("광고 개인정보 설정") {
                        Task { await presentAdPrivacyOptions() }
                    }
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
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        preferences.targetLevel = level
                        dismiss()
                    }
                }
            }
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
