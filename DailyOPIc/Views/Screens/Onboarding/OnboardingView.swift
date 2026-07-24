import SwiftUI

struct OnboardingView: View {
    private enum Step { case firstQuestion, guide, level }
    let environment: AppEnvironment
    @State private var selectedLevel: SelfAssessmentLevel?
    @State private var showsConfirmation = false
    @State private var isSubmitting = false
    @State private var progressMessage: String?
    @State private var errorMessage: String?
    @State private var updateOperationID: UUID?
    @State private var step: Step

    private var preferences: AppPreferences { environment.preferences }

    init(environment: AppEnvironment) {
        self.environment = environment
        if environment.preferences.isPresentingLevelSelection {
            _step = State(initialValue: .level)
        } else if environment.preferences.isNewToOPIc == nil {
            _step = State(initialValue: .firstQuestion)
        } else if environment.preferences.isNewToOPIc == true,
                  environment.preferences.guideState == .inProgress {
            _step = State(initialValue: .guide)
        } else {
            _step = State(initialValue: .level)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), AppPalette.primarySoft.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Group {
                    switch step {
                    case .firstQuestion:
                        firstQuestion
                    case .guide:
                        OPIcGuideView(preferences: preferences) { skipped in
                            preferences.finishGuide(skipped: skipped)
                            withAnimation(.easeInOut(duration: 0.25)) { step = .level }
                        }
                    case .level:
                        levelSelection
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))

                if showsConfirmation, let selectedLevel {
                    TargetLevelConfirmationDialog(
                        level: selectedLevel,
                        requiresReward: requiresReward(for: selectedLevel),
                        isPaidPlan: environment.currentPlan.isPaid,
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

    private var firstQuestion: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 58))
                .foregroundStyle(AppPalette.primary)
            Text("오픽이 처음이신가요?")
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text("간단한 안내를 먼저 볼 수 있어요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "안내 보기", systemImage: "book.fill") {
                preferences.isNewToOPIc = true
                preferences.guideState = .inProgress
                withAnimation(.easeInOut(duration: 0.25)) { step = .guide }
            }
            Button("바로 시작할게요") {
                preferences.isNewToOPIc = false
                preferences.guideState = .skipped
                withAnimation(.easeInOut(duration: 0.25)) { step = .level }
            }
            .font(.headline)
            .foregroundStyle(AppPalette.primary)
            Spacer()
        }
        .padding(AppSpacing.lg)
    }

    private var levelSelection: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    Spacer()
                    GuideEntryButton(preferences: preferences)
                }
                Text(preferences.initialLevel == nil ? "시작 난이도를 골라주세요" : "난이도를 바꿔볼까요?")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppPalette.ink)
                Text(guidanceText)
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

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
                }

                if let progressMessage {
                    ProgressBanner(message: progressMessage)
                }

                ForEach(SelfAssessmentLevel.allCases) { level in
                    levelCard(level)
                }

                PrimaryButton(
                    title: selectedLevel == nil ? "난이도를 선택해 주세요" : "이 난이도로 시작",
                    systemImage: "checkmark.circle.fill",
                    isLoading: isSubmitting,
                    isDisabled: selectedLevel == nil || isSubmitting
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsConfirmation = true
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    private var guidanceText: String {
        if preferences.initialLevel == nil {
            return "지금 실력과 비슷한 단계를 고르면 돼요. 나중에 언제든 바꿀 수 있어요."
        }
        return "난이도를 바꾸면 새 질문이 만들어져요. 변경하려면 광고를 끝까지 봐야 해요."
    }

    private func levelCard(_ level: SelfAssessmentLevel) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedLevel = level
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(AppPalette.primary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(level.title).font(.title3.bold())
                        Spacer()
                        Text(level.estimatedRange)
                            .font(.caption.bold())
                            .foregroundStyle(AppPalette.primary)
                    }
                    Text(level.summary)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                    if isSelected {
                        Text("예: “\(answerExample(for: level))”")
                            .font(AppTypography.footnote.italic())
                            .foregroundStyle(AppPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(isSelected ? AppPalette.primarySoft : AppPalette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .stroke(
                        AppPalette.primary.opacity(isSelected ? 0.75 : 0.18),
                        lineWidth: isSelected ? 1.8 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func answerExample(for level: SelfAssessmentLevel) -> String {
        switch level.rawValue {
        case 1: "I like music. It is fun."
        case 2: "I listen to music at home because it helps me relax."
        case 3: "Last weekend, I found a new artist and listened with my friend."
        case 4: "What I enjoy most is discovering artists when friends recommend them."
        case 5: "My taste has changed; I used to prefer pop, whereas I now enjoy jazz."
        default: "Although streaming is convenient, live performances remain memorable because the audience shapes the experience."
        }
    }

    private func requiresReward(for level: SelfAssessmentLevel) -> Bool {
        guard let current = preferences.initialLevel else { return false }
        return current != level
    }

    @MainActor
    private func submitSelection(_ level: SelfAssessmentLevel) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        progressMessage = "난이도를 저장하고 있어요."
        print("[DailyOPIc][TargetLevel] update requested initialLevel=\(level.rawValue)")
        do {
            try await saveTargetLevel(level, rewardNonce: nil)
            finishSelection(level)
        } catch let error as APIClientError where error.isTargetLevelChangeRewardRequired {
            print(
                "[DailyOPIc][TargetLevel] reward required initialLevel=\(level.rawValue) "
                + "status=\(error.statusCode ?? -1) code=\(error.code ?? "missing")"
            )
            do {
                let rewardNonce = try await rewardNonceForTargetLevelChange()
                progressMessage = "확인됐어요. 난이도를 바꾸고 있어요."
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

    private func saveTargetLevel(_ level: SelfAssessmentLevel, rewardNonce: String?) async throws {
        let operationID = updateOperationID ?? UUID()
        updateOperationID = operationID
        _ = try await environment.api.updateInitialLevel(
            level,
            rewardNonce: rewardNonce,
            requestID: operationID
        )
    }

    private func rewardNonceForTargetLevelChange() async throws -> String {
        progressMessage = "잠시만요, 준비하고 있어요."
        print("[DailyOPIc][Rewards] creating target_level_change intent")
        let intent = try await environment.api.createRewardIntent(
            purpose: .targetLevelChange,
            requestID: UUID()
        )
        print(
            "[DailyOPIc][Rewards] intent created nonce=\(intent.nonce) "
            + "status=\(intent.status)"
        )
        // 유료 플랜은 광고 없이 서버 auto-verify로 즉시 변경(하루 1회).
        if environment.currentPlan.isPaid {
            return intent.nonce
        }
        progressMessage = "광고를 불러오고 있어요."
        try await environment.ads.showRewardedAd(
            userIdentifier: intent.userIdentifier,
            customData: intent.customData
        )
        print("[DailyOPIc][Rewards] rewarded ad earned. waiting for SSV nonce=\(intent.nonce)")
        progressMessage = "광고 시청을 확인하고 있어요."
        _ = try await environment.api.waitForReward(nonce: intent.nonce) { reward in
            print("[DailyOPIc][Rewards] poll nonce=\(reward.nonce) status=\(reward.status)")
            guard reward.isPending else { return }
            await MainActor.run {
                progressMessage = "광고 시청을 확인하고 있어요."
            }
        }
        return intent.nonce
    }

    private func finishSelection(_ level: SelfAssessmentLevel) {
        print("[DailyOPIc][TargetLevel] update completed initialLevel=\(level.rawValue)")
        preferences.completeOnboarding(initialLevel: level, profile: preferences.backgroundProfile)
        preferences.isPresentingLevelSelection = false
        updateOperationID = nil
        progressMessage = nil
        isSubmitting = false
        withAnimation(.easeOut(duration: 0.18)) {
            showsConfirmation = false
        }
    }

    private func failSelection(_ error: Error) {
        print("[DailyOPIc][TargetLevel] update failed error=\(error.localizedDescription)")
        if let apiError = error as? APIClientError, apiError.isRewardQuotaExhausted {
            errorMessage = "난이도 변경은 하루 한 번만 가능해요. 내일 다시 시도해 주세요."
        } else {
            errorMessage = "\(error.localizedDescription) 다시 시도해 주세요."
        }
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
        HStack(alignment: .center, spacing: 12) {
            AppLoadingIndicator(dotSize: 8)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppPalette.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppPalette.primarySoft.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }
}

private struct TargetLevelConfirmationDialog: View {
    let level: SelfAssessmentLevel
    let requiresReward: Bool
    let isPaidPlan: Bool
    let isSubmitting: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    /// 유료 플랜은 광고 없이 하루 1회 무료 변경, 무료 플랜은 광고 시청 변경.
    private var paidChange: Bool { requiresReward && isPaidPlan }
    private var adChange: Bool { requiresReward && !isPaidPlan }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSubmitting { cancel() }
                }

            VStack(spacing: AppSpacing.md) {
                Image(systemName: adChange ? "play.rectangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                Text(requiresReward ? "난이도를 바꿀까요?" : "이 난이도로 시작할까요?")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.center)
                Text("\(level.title) · \(level.estimatedRange)")
                    .font(.headline)
                    .foregroundStyle(AppPalette.primary)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    title: paidChange ? "무료로 바꾸기" : (adChange ? "광고 보고 바꾸기" : "시작하기"),
                    systemImage: paidChange ? "checkmark.seal.fill" : (adChange ? "play.rectangle.fill" : "mic.fill"),
                    isLoading: isSubmitting,
                    isDisabled: isSubmitting,
                    action: confirm
                )
                Button("다시 고르기") { cancel() }
                    .font(.headline)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .disabled(isSubmitting)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .padding(AppSpacing.lg)
        }
        .transition(.opacity)
    }

    private var message: String {
        if paidChange {
            return "난이도를 바꾸면 새 질문이 만들어져요. 유료 플랜은 하루 1회 광고 없이 무료로 변경할 수 있어요."
        }
        if adChange {
            return "난이도를 바꾸면 새 질문이 만들어져요. 광고를 끝까지 보면 바뀐 난이도가 적용돼요. (하루 1회)"
        }
        return "고른 난이도로 질문이 만들어져요. 모의고사 중간에 한 번 조정할 수 있어요."
    }
}
