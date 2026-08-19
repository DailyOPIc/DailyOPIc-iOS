import SwiftUI
import UIKit

struct SetupView: View {
    /// 설정에서 요청하는 루트 화면. 시트가 스스로 열지 않고 요청만 남기는 이유는
    /// 시트가 완전히 닫힌 뒤에 열어야 표시 충돌이 없기 때문이다.
    enum Route { case guide, levelSelection }

    let preferences: AppPreferences
    let route: (Route) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var ads: AdService
    @State private var alert: SetupAlert?
    @State private var showsGoalLevelDialog = false
    @State private var copyFeedbackTrigger = 0
    /// 화면 진입만으로는 절대 열리지 않는다. 의도적으로 눌렀을 때만 true가 된다.
    @State private var isPresentingPaywall = false

    private var appUserID: String? {
        guard let value = environment.store.appUserID, !value.isEmpty else { return nil }
        return value
    }

    init(preferences: AppPreferences, route: @escaping (Route) -> Void) {
        self.preferences = preferences
        self.route = route
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
                    Section("알림") {
                        notificationToggle
                        Text(reminderState.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("구독") {
                        subscriptionRows
                    }
                    Section("앱") {
                        Button {
                            route(.guide)
                            dismiss()
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
                    Section("고객 지원") {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("사용자 식별 ID")
                                .font(.headline)
                            Text("문의나 이용권 지급 요청 시 필요한 ID입니다.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if let appUserID {
                                Text(appUserID)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(AppPalette.secondaryInk)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("사용자 식별 ID")
                                    .accessibilityValue(appUserID)
                            } else {
                                Text("사용자 식별 ID를 불러올 수 없습니다.")
                                    .font(.footnote)
                                    .foregroundStyle(AppPalette.secondaryInk)
                                Button("다시 시도") {
                                    environment.store.refreshAppUserID()
                                }
                            }

                            Button {
                                copyAppUserID()
                            } label: {
                                Label("ID 복사", systemImage: "doc.on.doc")
                            }
                            .disabled(appUserID == nil)
                            .accessibilityHint("고객 지원에 전달할 사용자 식별 ID를 복사합니다.")

                            Text("문의, 구독 지원 또는 이벤트 참여 시 위 사용자 식별 ID를 함께 보내주세요.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, AppSpacing.xs)
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
            .task {
                environment.store.refreshAppUserID()
                // 설정 앱에서 권한을 바꾸고 돌아왔을 수 있다. 여기서 권한을 **묻지는** 않는다.
                await environment.studyReminders.refreshAuthorizationStatus()
            }
            .sheet(isPresented: $isPresentingPaywall) { PaywallView(source: .settings) }
            .sensoryFeedback(.success, trigger: copyFeedbackTrigger)
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

    // MARK: 알림

    private var reminderState: StudyReminderSettingsState {
        .make(
            preference: environment.studyReminders.preference,
            authorization: environment.studyReminders.authorizationStatus
        )
    }

    /// 학습 알림 스위치. **앱 전체에서 여기 하나뿐이다** — 플래너 설정에는 시간만 있다.
    /// 전 플랜이 쓸 수 있으므로 잠금도 Paywall도 없다(P9).
    private var notificationToggle: some View {
        Toggle(
            "학습 알림",
            isOn: Binding(
                get: { reminderState.isOn },
                set: { isOn in Task { await setStudyReminders(isOn) } }
            )
        )
    }

    /// 켜는 것은 **사용자의 명시적 행동**이라 여기서만 시스템 권한을 물을 수 있다.
    /// 거부 상태에서는 다시 묻지 않는다(서비스가 막는다) — 안내 문구로 설정 앱을 가리킨다.
    private func setStudyReminders(_ isOn: Bool) async {
        if isOn {
            await environment.studyReminders.enable()
        } else {
            await environment.studyReminders.disable()
        }
        await environment.studyCalendarViewModel.reconcileReminders()
    }

    // MARK: 구독

    private var subscriptionState: SubscriptionSettingsState {
        .make(
            plan: environment.currentPlan,
            isEntitlementResolved: environment.isEntitlementResolved
        )
    }

    @ViewBuilder
    private var subscriptionRows: some View {
        let state = subscriptionState
        Text(state.planText)
            .foregroundStyle(state.isResolved ? AppPalette.ink : AppPalette.secondaryInk)
        if let title = state.actionTitle {
            Button(title) {
                switch state.action {
                case .paywall: isPresentingPaywall = true
                case .manage: Task { await manageSubscription() }
                case .none: break
                }
            }
        }
    }

    private func manageSubscription() async {
        do {
            try await environment.store.manageSubscriptions()
            await environment.refreshCapabilities()
        } catch {
            alert = SetupAlert(
                title: "구독 관리를 열 수 없어요",
                message: error.localizedDescription
            )
        }
    }

    private func openGoalLevelOnboarding() {
        showsGoalLevelDialog = false
        route(.levelSelection)
        dismiss()
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

    private func copyAppUserID() {
        guard let appUserID, !appUserID.isEmpty else { return }
        UIPasteboard.general.string = appUserID
        copyFeedbackTrigger += 1
        alert = SetupAlert(
            title: "복사 완료",
            message: "사용자 식별 ID가 복사되었습니다."
        )
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

            VStack(spacing: AppSpacing.md) {
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
                    .minimumTouchTarget()
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .padding(AppSpacing.lg)
            // 배경 탭과 같은 취소 경로를 VoiceOver 이스케이프 제스처에도 열어준다.
            .accessibilityAction(.escape, cancel)
        }
        .transition(.opacity)
    }
}
