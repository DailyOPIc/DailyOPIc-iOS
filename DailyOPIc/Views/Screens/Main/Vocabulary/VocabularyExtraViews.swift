import SwiftUI

/// 오늘의 단어를 다 끝낸 뒤 20개를 **더** 받는 자리(P14.6).
///
/// 화면 순서가 곧 과금 경계다:
///   1. 이 화면을 여는 것 · 주제 목록을 보는 것 — 0 토큰
///   2. 주제를 고르는 것 · 고른 주제를 바꾸는 것 · 닫는 것 — 0 토큰
///   3. [20개 생성하기] — **데일리 토큰 1개.** 사용자가 직접 눌러야만 시작한다.
///
/// `.task`가 하는 일은 잔액을 읽는 것뿐이다. 화면이 그려졌다는 이유로 AI를 부르거나
/// 토큰이 나가는 경로는 없다. 기본 20개(시드 카탈로그)는 지금도 그대로 공짜다 —
/// 값이 붙는 것은 **새 단어를 만드는 행위**뿐이다.
struct VocabularyExtraSheet: View {
    let targetLevel: OPIcLevel?
    /// 이미 가진 표현들. 중복을 피해 달라는 힌트로만 쓰인다(상한은 요청 모델이 갖는다).
    let existingTerms: [String]
    @State private var viewModel: VocabularyGenerationViewModel
    /// 고르지 않은 상태로 시작한다 — 앱이 아무 주제나 대신 고르지 않는다.
    @State private var topic: VocabularyTopic?
    @Environment(\.dismiss) private var dismiss

    init(
        environment: AppEnvironment,
        targetLevel: OPIcLevel?,
        existingTerms: [String]
    ) {
        self.targetLevel = targetLevel
        self.existingTerms = existingTerms
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
                    PrimaryButton(
                        title: failureMessage == nil ? "\(count)개 생성하기" : "다시 시도",
                        isLoading: viewModel.isGenerating,
                        isDisabled: topic == nil
                    ) {
                        // 주제를 고르지 않았으면 아무것도 시작하지 않는다(토큰도 나가지 않는다).
                        guard let topic else { return }
                        // 재시도도 같은 조작이다 — 뷰모델이 같은 요청 id를 그대로 쓴다.
                        viewModel.generate(
                            topic: topic,
                            targetLevel: targetLevel ?? .IM2,
                            excluding: existingTerms,
                            purpose: .todayExtra
                        )
                    }
                    costLine
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle("오늘 \(count)개 더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
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
            // 세트는 이미 저장됐다. 닫으면 오늘의 단어 카드에 "오늘 추가 학습 0 / 20"이 뜬다.
            guard setID != nil else { return }
            viewModel.finishedSetID = nil
            dismiss()
        }
        .sheet(isPresented: Bindable(viewModel).showsPaywall) {
            PaywallView(source: viewModel.paywallSource)
        }
    }

    /// 주제는 오늘의 단어와 **같은 목록**이다. 추가 학습 전용 주제를 새로 만들지 않는다.
    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("어떤 주제로 더 공부할까요?")
                .font(AppTypography.sectionTitle)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppSpacing.sm),
                          GridItem(.flexible(), spacing: AppSpacing.sm)],
                spacing: AppSpacing.sm
            ) {
                ForEach(VocabularyCatalog.topics) { candidate in
                    Button { topic = candidate } label: {
                        Text(candidate.label)
                            .font(AppTypography.callout)
                            .foregroundStyle(
                                candidate == topic ? AppPalette.actionOnPrimary : AppPalette.ink
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.md)
                            .background(
                                candidate == topic ? AppPalette.primary : AppPalette.surface
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AppRadius.control,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityAddTraits(candidate == topic ? [.isSelected] : [])
                }
            }
        }
    }

    /// 누르기 전에 무엇을 얼마에 받는지 말한다. 고른 주제가 그대로 실린다.
    @ViewBuilder
    private var confirmation: some View {
        if let topic {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("\(topic.label) 단어 \(count)개를 더 학습할까요?")
                    .font(AppTypography.cardTitle)
                Text("새로운 단어를 만드는 데 데일리 토큰 1개를 사용해요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private var messages: some View {
        if viewModel.hasNoTokens {
            Text("새 단어 \(count)개를 만들려면 데일리 토큰 1개가 필요합니다.")
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

    /// 화폐는 데일리 토큰 하나뿐이라 아이콘도 그것 하나다.
    private var costLine: some View {
        HStack(spacing: AppSpacing.xs) {
            DailyTokenIcon(size: 18)
            Text("데일리 토큰 \(VocabularyGenerationViewModel.tokenCost)개를 사용해요.")
                .font(AppTypography.callout)
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
