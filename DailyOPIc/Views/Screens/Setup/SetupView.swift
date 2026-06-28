import SwiftUI

struct SetupView: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var ads: AdService
    @State private var alert: SetupAlert?
    @State private var showsGoalLevelDialog = false

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    var body: some View {
        NavigationStack {
            ZStack {
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
                        Text("목표 등급을 변경하면 새 문제가 다시 생성되며, 변경 시 보상형 광고를 끝까지 시청해야 합니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("목표 등급 설정") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsGoalLevelDialog = true
                            }
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

                if showsGoalLevelDialog {
                    GoalLevelRoutingDialog(
                        currentLevel: preferences.targetLevel,
                        confirm: openGoalLevelOnboarding,
                        cancel: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showsGoalLevelDialog = false
                            }
                        }
                    )
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
        showsGoalLevelDialog = false
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

private struct GoalLevelRoutingDialog: View {
    let currentLevel: OPIcLevel?
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(spacing: 18) {
                Image(systemName: "target")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                Text("목표 등급을 변경할까요?")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.center)
                if let currentLevel {
                    Text("현재 목표: \(currentLevel.rawValue)")
                        .font(.headline)
                        .foregroundStyle(AppPalette.primary)
                }
                Text("목표 등급을 바꾸면 기존 데일리 문제가 새로 생성됩니다. 등급을 최종 변경할 때 보상형 광고를 끝까지 시청해야 합니다.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    title: "등급 선택으로 이동",
                    systemImage: "arrow.right.circle.fill",
                    action: confirm
                )
                Button("취소", action: cancel)
                    .font(.headline)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .padding(24)
        }
        .transition(.opacity)
    }
}
