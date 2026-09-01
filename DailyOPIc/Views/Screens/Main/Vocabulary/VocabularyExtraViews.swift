import SwiftUI

/// 오늘의 단어 20개를 만드는 버튼(P14.6.1). 사용자-facing 생성 입구는 이 하나뿐이라
/// 문구도 값도 여기 한 곳에 둔다 — 화면마다 다른 말로 적히면 값이 달라 보인다.
///
/// 채움 버튼이 아니라 옅은 버튼이다. 오늘 몫을 끝낸 사람에게 가장 큰 버튼이
/// 매번 "토큰 쓰기"면 학습 화면이 결제 화면이 된다 — 값은 분명히 적되 조용히 둔다.
struct VocabularyCreateButton: View {
    /// 화면에 실제로 찍히는 문구. 테스트도 사람도 같은 값을 본다.
    static let title = "단어 \(VocabularyGenerationViewModel.extraEntryCount)개 만들기"

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Text(Self.title)
                    .font(.headline)
                DailyTokenIcon(size: 18)
                Text("\(VocabularyGenerationViewModel.tokenCost)")
                    .font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            // 고정 높이가 아니라 최소 높이다. 큰 글자에서도 문구가 잘리지 않는다.
            .frame(minHeight: 54)
            .foregroundStyle(AppPalette.primary)
            .background(AppPalette.primarySoft)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(
            "\(Self.title), 데일리 토큰 \(VocabularyGenerationViewModel.tokenCost)개 사용"
        )
    }
}

/// 오늘의 단어 20개를 만드는 화면(P14.6).
///
/// 화면 순서가 곧 과금 경계다:
///   1. 이 화면을 여는 것 · 주제 목록을 보는 것 — 0 토큰
///   2. 주제를 고르는 것 · 고른 주제를 바꾸는 것 · 닫는 것 — 0 토큰
///   3. [20개 만들기] — **데일리 토큰 1개.** 사용자가 직접 눌러야만 시작한다.
///
/// `.task`가 하는 일은 잔액을 읽는 것뿐이다. 화면이 그려졌다는 이유로 AI를 부르거나
/// 토큰이 나가는 경로는 없다. 오늘의 기본 20개(시드 카탈로그)는 지금도 그대로 공짜다 —
/// 값이 붙는 것은 **새 단어를 만드는 행위**뿐이다.
struct VocabularyExtraSheet: View {
    let targetLevel: OPIcLevel?
    /// 이미 가진 표현들. 중복을 피해 달라는 힌트로만 쓰인다(상한은 요청 모델이 갖는다).
    let existingTerms: [String]
    /// 만들어진 세트 id를 알린다. 별도 완료 화면 없이 곧장 학습으로 이어 주기 위한 길이다.
    var onCreated: ((String) -> Void)?
    @State private var viewModel: VocabularyGenerationViewModel
    /// 고르지 않은 상태로 시작한다 — 앱이 아무 주제나 대신 고르지 않는다.
    @State private var topic: VocabularyTopic?
    @Environment(\.dismiss) private var dismiss

    init(
        environment: AppEnvironment,
        targetLevel: OPIcLevel?,
        existingTerms: [String],
        onCreated: ((String) -> Void)? = nil
    ) {
        self.targetLevel = targetLevel
        self.existingTerms = existingTerms
        self.onCreated = onCreated
        _viewModel = State(
            initialValue: VocabularyGenerationViewModel(environment: environment)
        )
        // 값을 치르고도 저장하지 못한 조작이 남아 있으면 그 주제를 미리 골라 둔다.
        // 같은 주제로 다시 눌러야 같은 키가 나가 이미 만들어진 세트를 되찾는다.
        // 미리 고르기만 할 뿐 생성을 자동으로 시작하지는 않는다.
        _topic = State(
            initialValue: environment.preferences.pendingVocabularyExtra
                .flatMap { $0.isReplayable() ? $0.topic : nil }
        )
    }

    private var count: Int { VocabularyGenerationViewModel.extraEntryCount }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    topicPicker
                    confirmation
                    messages
                    VStack(spacing: AppSpacing.sm) {
                        PrimaryButton(
                            title: failureMessage == nil ? "\(count)개 만들기" : "다시 시도",
                            isLoading: viewModel.isGenerating,
                            isDisabled: topic == nil
                        ) {
                            // 주제를 고르지 않았으면 아무것도 시작하지 않는다(토큰도 나가지 않는다).
                            guard let topic else { return }
                            // 재시도도 같은 조작이다 — 뷰모델이 같은 요청 id를 그대로 쓴다.
                            viewModel.generate(
                                topic: topic,
                                targetLevel: targetLevel ?? .IM2,
                                excluding: existingTerms
                            )
                        }
                        costLine
                    }
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle(VocabularyCreateButton.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .disabled(viewModel.isGenerating)
                }
            }
            .overlay {
                if viewModel.isGenerating {
                    AILoadingOverlay(
                        kind: .vocabularyGeneration,
                        blocksInteraction: true,
                        canContinueInBackground: false
                    )
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isGenerating)
        // 잔액을 읽을 뿐이다. 이 자리에서 생성이 시작되지 않는다.
        .task { await viewModel.refreshUsage() }
        .onChange(of: viewModel.finishedSetID) { _, setID in
            // 세트는 이미 저장됐다. 축하 화면을 하나 더 세우지 않고 그대로 학습으로 보낸다.
            guard let setID else { return }
            viewModel.finishedSetID = nil
            onCreated?(setID)
            dismiss()
        }
        .sheet(isPresented: Bindable(viewModel).showsPaywall) {
            PaywallView(source: viewModel.paywallSource)
        }
    }

    /// 주제는 오늘의 단어와 **같은 목록**이다. 새 단어 전용 주제를 따로 만들지 않는다.
    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("어떤 주제로 만들까요?")
                .font(AppTypography.sectionTitle)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppSpacing.sm),
                          GridItem(.flexible(), spacing: AppSpacing.sm)],
                spacing: AppSpacing.sm
            ) {
                ForEach(VocabularyCatalog.topics) { candidate in
                    Button { topic = candidate } label: { topicLabel(candidate) }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(candidate.label)
                        .accessibilityAddTraits(candidate == topic ? [.isSelected] : [])
                }
            }
        }
    }

    /// 고른 칸은 색만이 아니라 체크로도 말한다 — 색만으로 상태를 전하지 않는다(§26).
    private func topicLabel(_ candidate: VocabularyTopic) -> some View {
        let isSelected = candidate == topic
        return HStack(spacing: AppSpacing.xs) {
            Text(candidate.label)
                .font(AppTypography.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(AppTypography.caption)
            }
        }
        .foregroundStyle(isSelected ? AppPalette.actionOnPrimary : AppPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        // 큰 글자에서도 두 줄까지 늘어날 수 있게 최소 높이만 잡는다.
        .frame(minHeight: 56, alignment: .leading)
        .background(isSelected ? AppPalette.primary : AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .contentShape(Rectangle())
    }

    /// 누르기 전에 무엇을 얼마에 받는지 말한다. 고른 주제와 지금 잔액이 그대로 실린다.
    @ViewBuilder
    private var confirmation: some View {
        if let topic {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("\(topic.label) 단어 \(count)개를 만들까요?")
                    .font(AppTypography.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("데일리 토큰 \(VocabularyGenerationViewModel.tokenCost)개를 사용해요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                // 잔액은 이미 읽어 둔 값이다. 이걸 보여주려고 새로 부르지 않는다.
                if let balance = viewModel.dailyTokenCount {
                    Text("현재 데일리 토큰 \(balance)개")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private var messages: some View {
        if viewModel.hasNoTokens {
            Text("단어 \(count)개를 만들려면 데일리 토큰 1개가 필요합니다.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let failureMessage {
            Text(failureMessage)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 화폐는 데일리 토큰 하나뿐이라 아이콘도 그것 하나다. 버튼 바로 아래에 둔다.
    /// 문장이 아니라 값표다 — 같은 말을 확인 카드가 이미 한 번 했다.
    private var costLine: some View {
        HStack(spacing: AppSpacing.xs) {
            DailyTokenIcon(size: 18)
            Text("\(VocabularyGenerationViewModel.tokenCost)")
                .font(AppTypography.callout.monospacedDigit())
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "데일리 토큰 \(VocabularyGenerationViewModel.tokenCost)개를 사용해요"
        )
    }

    private var failureMessage: String? {
        if case let .recoverableFailure(_, message) = viewModel.operationState { return message }
        return nil
    }
}
