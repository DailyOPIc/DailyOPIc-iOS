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
                    Section("난이도") {
                        HStack {
                            Text("현재 난이도")
                            Spacer()
                            Text(preferences.initialLevel?.title ?? "-")
                                .fontWeight(.bold)
                                .foregroundStyle(AppPalette.primary)
                        }
                        if let initialLevel = preferences.initialLevel {
                            Text("\(initialLevel.estimatedRange) · \(initialLevel.summary)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("난이도를 바꾸면 새 질문이 만들어져요. 변경하려면 광고를 끝까지 봐야 해요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("난이도 바꾸기") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsGoalLevelDialog = true
                            }
                        }
                    }
                    Section("앱") {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                preferences.beginGuide()
                            }
                        } label: {
                            Label("도움말 다시 보기", systemImage: "questionmark.circle")
                        }
                        Button("개인정보처리방침") {
                            openPrivacyPolicy()
                        }
                        if ads.canShowPrivacyOptions {
                            Button("광고 개인정보 설정") {
                                Task { await presentAdPrivacyOptions() }
                            }
                        }
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
                Text("난이도를 바꿀까요?")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.center)
                if let currentLevel {
                    Text("현재 예상 등급 \(currentLevel.rawValue)")
                        .font(.headline)
                        .foregroundStyle(AppPalette.primary)
                }
                Text("난이도를 바꾸면 지금 질문이 새로 만들어져요. 최종 변경할 때 광고를 끝까지 봐야 해요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    title: "난이도 선택하기",
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
