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
                    colors: [.white, AppPalette.primarySoft.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                switch step {
                case .firstQuestion:
                    firstQuestion
                case .guide:
                    OPIcGuideView(preferences: preferences) { skipped in
                        preferences.finishGuide(skipped: skipped)
                        step = .level
                    }
                case .level:
                    levelSelection
                }

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

    private var firstQuestion: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 58))
                .foregroundStyle(AppPalette.primary)
            Text("오픽 시험이 처음이신가요?")
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text("가이드를 건너뛰어도 Daily와 모의고사 이용에는 불이익이 없습니다.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "네, 가이드를 볼게요", systemImage: "book.fill") {
                preferences.isNewToOPIc = true
                preferences.guideState = .inProgress
                step = .guide
            }
            PrimaryButton(title: "아니오, 난이도를 선택할게요", systemImage: "arrow.right") {
                preferences.isNewToOPIc = false
                preferences.guideState = .skipped
                step = .level
            }
            Spacer()
        }
        .padding(24)
    }

    private var levelSelection: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    GuideEntryButton(preferences: preferences)
                }
                Text(preferences.initialLevel == nil ? "OPIc 시작 난이도를 선택해 주세요" : "변경할 시작 난이도를 선택해 주세요")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppPalette.ink)
                Text(guidanceText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)

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
                    title: selectedLevel == nil ? "단계를 선택해 주세요" : "선택한 단계 확인",
                    systemImage: "checkmark.circle.fill",
                    isLoading: isSubmitting,
                    isDisabled: selectedLevel == nil || isSubmitting
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsConfirmation = true
                    }
                }
            }
            .padding(24)
        }
    }

    private var guidanceText: String {
        if preferences.initialLevel == nil {
            return "실제 시험 전 자기평가와 비슷한 학습 시작값입니다. 선택한 단계로 시작하고 Q7 이후 난이도를 한 번 조정합니다."
        }
        return "Self Assessment 단계를 바꾸면 새 문제가 다시 생성됩니다. 변경하려면 보상형 광고를 끝까지 시청해야 합니다."
    }

    private func levelCard(_ level: SelfAssessmentLevel) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            guard !isSubmitting else { return }
            selectedLevel = level
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(AppPalette.primary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(level.title).font(.title2.bold())
                        Spacer()
                        Text(level.estimatedRange)
                            .font(.caption.bold())
                            .foregroundStyle(AppPalette.primary)
                    }
                    Text(level.summary).font(AppTypography.body)
                    Text("추천: \(recommendation(for: level))")
                        .font(.footnote.weight(.semibold))
                    Text("답변 예시: “\(answerExample(for: level))”")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
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

    private func recommendation(for level: SelfAssessmentLevel) -> String {
        switch level.rawValue {
        case 1: "영어 문장으로 답하기를 처음 시작하는 학습자"
        case 2: "익숙한 주제에 짧은 문장 몇 개로 답하는 학습자"
        case 3: "일상 질문에 이유를 덧붙일 수 있는 학습자"
        case 4: "경험을 순서대로 설명하고 싶은 학습자"
        case 5: "구체적인 예시와 비교를 연습하는 학습자"
        default: "복잡한 상황과 의견을 자연스럽게 확장하는 학습자"
        }
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
        progressMessage = "Self Assessment 단계를 저장하는 중입니다."
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
                progressMessage = "광고 검증이 완료됐습니다. 단계 변경을 다시 요청하는 중입니다."
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
        progressMessage = "단계 변경 권한을 준비하는 중입니다."
        print("[DailyOPIc][Rewards] creating target_level_change intent")
        let intent = try await environment.api.createRewardIntent(
            purpose: .targetLevelChange,
            requestID: UUID()
        )
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
    let level: SelfAssessmentLevel
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
                Text(requiresReward ? "Self Assessment 단계를 변경할까요?" : "이 단계로 시작할까요?")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.center)
                Text("\(level.title) · \(level.estimatedRange)에 맞춰 새 문제가 준비됩니다.")
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
            return "Self Assessment 단계를 바꾸면 기존 데일리 문제가 새로 생성됩니다. 보상형 광고를 끝까지 시청한 뒤 변경이 적용됩니다."
        }
        return "선택한 단계를 기준으로 데일리 문제가 생성됩니다. Q7 이후 후반 난이도를 다시 선택합니다."
    }
}
