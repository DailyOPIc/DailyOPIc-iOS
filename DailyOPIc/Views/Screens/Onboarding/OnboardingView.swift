import SwiftUI

struct OnboardingView: View {
    let environment: AppEnvironment
    @State private var visibleLevel: OPIcLevel
    @State private var selectedLevel: OPIcLevel?
    @State private var showsConfirmation = false
    @State private var isSubmitting = false
    @State private var progressMessage: String?
    @State private var errorMessage: String?

    private var preferences: AppPreferences { environment.preferences }

    init(environment: AppEnvironment) {
        self.environment = environment
        _visibleLevel = State(initialValue: environment.preferences.targetLevel ?? .IH)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.white, AppPalette.primarySoft.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                levelSelection

                if showsConfirmation, let selectedLevel {
                    TargetLevelConfirmationDialog(
                        level: selectedLevel,
                        requiresReward: requiresReward(for: selectedLevel),
                        isSubmitting: isSubmitting,
                        confirm: {
                            Task { await submitSelection(selectedLevel) }
                        },
                        cancel: {
                            guard !isSubmitting else { return }
                            withAnimation(.easeOut(duration: 0.18)) {
                                showsConfirmation = false
                            }
                        }
                    )
                }
            }
        }
    }

    private var levelSelection: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 32)
            Text(preferences.targetLevel == nil ? "목표 오픽 등급을 선택하세요" : "변경할 목표 등급을 선택하세요")
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink)
            Text(guidanceText)
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let message = errorMessage {
                ErrorBanner(
                    message: message,
                    retry: selectedLevel.map { level in
                        {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsConfirmation = true
                            }
                            Task { await submitSelection(level) }
                        }
                    }
                )
                .padding(.horizontal, 24)
            }

            if let progressMessage {
                ProgressBanner(message: progressMessage)
                    .padding(.horizontal, 24)
            }

            TabView(selection: $visibleLevel) {
                ForEach(OPIcLevel.allCases) { level in
                    levelCard(level)
                    .padding(.horizontal, 28)
                    .tag(level)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 430)
            PrimaryButton(
                title: selectedLevel == nil ? "등급을 선택해 주세요" : "DailyOPIc 시작",
                systemImage: "mic.fill",
                isLoading: isSubmitting,
                isDisabled: selectedLevel == nil || isSubmitting
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsConfirmation = true
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 20)
        }
    }

    private var guidanceText: String {
        if preferences.targetLevel == nil {
            return "선택한 목표 등급을 바탕으로 데일리 문제가 준비됩니다."
        }
        return "목표 등급을 바꾸면 새 문제가 다시 생성됩니다. 변경하려면 보상형 광고를 끝까지 시청해야 합니다."
    }

    private func levelCard(_ level: OPIcLevel) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            guard !isSubmitting else { return }
            selectedLevel = level
        } label: {
            VStack(spacing: 26) {
                Text(level.rawValue)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.primary)
                Text(level.description)
                    .font(.title3)
                    .foregroundStyle(AppPalette.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Text(isSelected ? "선택됨" : "선택")
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : AppPalette.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isSelected ? AppPalette.primary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(AppPalette.primary.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
                    }
            }
            .padding(30)
            .background(isSelected ? AppPalette.primarySoft : Color(.secondarySystemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        AppPalette.primary.opacity(isSelected ? 0.75 : 0.22),
                        lineWidth: isSelected ? 1.8 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func requiresReward(for level: OPIcLevel) -> Bool {
        guard let current = preferences.targetLevel else { return false }
        return current != level
    }

    @MainActor
    private func submitSelection(_ level: OPIcLevel) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        progressMessage = "목표 등급을 저장하는 중입니다."
        print("[DailyOPIc][TargetLevel] update requested level=\(level.rawValue)")
        do {
            try await saveTargetLevel(level, rewardNonce: nil)
            finishSelection(level)
        } catch let error as APIClientError where error.isTargetLevelChangeRewardRequired {
            print(
                "[DailyOPIc][TargetLevel] reward required level=\(level.rawValue) "
                + "status=\(error.statusCode ?? -1) code=\(error.code ?? "missing")"
            )
            do {
                let rewardNonce = try await rewardNonceForTargetLevelChange()
                progressMessage = "광고 검증이 완료됐습니다. 목표 등급 변경을 다시 요청하는 중입니다."
                print("[DailyOPIc][TargetLevel] retrying update with reward nonce=\(rewardNonce)")
                try await saveTargetLevel(level, rewardNonce: rewardNonce)
                finishSelection(level)
            } catch {
                failSelection(error)
            }
        } catch {
            failSelection(error)
        }
    }

    private func saveTargetLevel(_ level: OPIcLevel, rewardNonce: String?) async throws {
        _ = try await environment.api.updateTargetLevel(level, rewardNonce: rewardNonce)
    }

    private func rewardNonceForTargetLevelChange() async throws -> String {
        progressMessage = "목표 등급 변경 권한을 준비하는 중입니다."
        print("[DailyOPIc][Rewards] creating target_level_change intent")
        let intent = try await environment.api.createRewardIntent(purpose: .targetLevelChange)
        print(
            "[DailyOPIc][Rewards] intent created nonce=\(intent.nonce) "
            + "status=\(intent.status)"
        )
        progressMessage = "리워드 광고를 불러오는 중입니다."
        try await environment.ads.showRewardedAd(
            userIdentifier: intent.userIdentifier,
            customData: intent.customData
        )
        print("[DailyOPIc][Rewards] rewarded ad earned. waiting for SSV nonce=\(intent.nonce)")
        progressMessage = "광고 시청 확인 중입니다. SSV 콜백을 기다리는 중입니다."
        _ = try await environment.api.waitForReward(nonce: intent.nonce) { reward in
            print("[DailyOPIc][Rewards] poll nonce=\(reward.nonce) status=\(reward.status)")
            guard reward.isPending else { return }
            await MainActor.run {
                progressMessage = "광고 시청 확인 중입니다. SSV 콜백 대기 중입니다."
            }
        }
        return intent.nonce
    }

    private func finishSelection(_ level: OPIcLevel) {
        print("[DailyOPIc][TargetLevel] update completed level=\(level.rawValue)")
        preferences.completeOnboarding(level: level, profile: preferences.backgroundProfile)
        progressMessage = nil
        isSubmitting = false
        withAnimation(.easeOut(duration: 0.18)) {
            showsConfirmation = false
        }
    }

    private func failSelection(_ error: Error) {
        print("[DailyOPIc][TargetLevel] update failed error=\(error.localizedDescription)")
        errorMessage = "\(error.localizedDescription) 다시 시도해 주세요."
        progressMessage = nil
        isSubmitting = false
        withAnimation(.easeOut(duration: 0.18)) {
            showsConfirmation = false
        }
    }
}

private struct ProgressBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .tint(AppPalette.primary)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppPalette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppPalette.primarySoft.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TargetLevelConfirmationDialog: View {
    let level: OPIcLevel
    let requiresReward: Bool
    let isSubmitting: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSubmitting { cancel() }
                }

            VStack(spacing: 18) {
                Image(systemName: requiresReward ? "play.rectangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                Text(requiresReward ? "목표 등급을 변경할까요?" : "이 등급으로 시작할까요?")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.center)
                Text("\(level.rawValue) 목표에 맞춰 새 문제가 준비됩니다.")
                    .font(.headline)
                    .foregroundStyle(AppPalette.primary)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    title: requiresReward ? "광고 시청 후 변경" : "시작하기",
                    systemImage: requiresReward ? "play.rectangle.fill" : "mic.fill",
                    isLoading: isSubmitting,
                    isDisabled: isSubmitting,
                    action: confirm
                )
                Button("다시 선택") { cancel() }
                    .font(.headline)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .disabled(isSubmitting)
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

    private var message: String {
        if requiresReward {
            return "목표 등급을 바꾸면 기존 데일리 문제가 새로 생성됩니다. 보상형 광고를 끝까지 시청한 뒤 변경이 적용됩니다."
        }
        return "선택한 등급을 기준으로 데일리 문제가 생성됩니다. 나중에 등급을 바꾸려면 보상형 광고 시청이 필요합니다."
    }
}
