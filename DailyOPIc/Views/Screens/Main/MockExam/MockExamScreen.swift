import SwiftUI

struct MockExamScreen: View {
    let viewModel: MockExamViewModel
    @ObservedObject private var speech: SpeechRecognitionService
    @ObservedObject private var promptPlayback: PromptPlaybackService
    @State private var showsResetConfirmation = false
    @State private var showsSavedSurveyDialog = false
    @State private var showsPaywall = false
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: MockExamViewModel) {
        self.viewModel = viewModel
        _speech = ObservedObject(wrappedValue: viewModel.speech)
        _promptPlayback = ObservedObject(wrappedValue: viewModel.promptPlayback)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .introduction:
                introduction
            case .survey:
                survey
            case .loading:
                MockLoadingView(message: "15문항을 준비하고 있어요")
            case .answering:
                answering
            case .adjustment:
                adjustment
            case .readyForReward:
                rewardGate
            case .analyzing:
                MockLoadingView(message: "답변을 종합 분석하고 있어요")
            case .completed:
                if let evaluation = viewModel.evaluation {
                    MockResultView(
                        evaluation: evaluation,
                        targetLevel: viewModel.targetLevel,
                        showsResetButton: true
                    ) {
                        viewModel.finishReview()
                    }
                }
            }
        }
        .toolbar {
            if viewModel.canAbandon {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("모의고사 포기") {
                        showsResetConfirmation = true
                    }
                }
            }
        }
        .overlay {
            // 포기 확인은 로딩 오버레이보다 먼저 그린다. 뒤에 두면 진행 중인
            // 작업이 끝날 때까지 포기 버튼이 아무 반응도 없는 것처럼 보인다.
            if showsResetConfirmation {
                ResetMockExamDialog(
                    cancel: { showsResetConfirmation = false },
                    confirm: {
                        showsResetConfirmation = false
                        viewModel.resetExam()
                    }
                )
            } else if viewModel.operationState.isRunning {
                AILoadingOverlay(
                    kind: viewModel.operationKind,
                    blocksInteraction: true,
                    canContinueInBackground: true
                )
            } else if showsSavedSurveyDialog {
                SavedSurveyDialog(
                    cancel: { showsSavedSurveyDialog = false },
                    start: {
                        showsSavedSurveyDialog = false
                        Task { await viewModel.startWithSavedSurvey() }
                    },
                    edit: {
                        showsSavedSurveyDialog = false
                        viewModel.showSurvey()
                    }
                )
            }
        }
        .task {
            await viewModel.restoreDraftIfAvailable()
            await viewModel.refreshUsage()
        }
        .onChange(of: viewModel.plan) {
            Task { await viewModel.refreshUsage() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshUsage() } }
        }
        .sheet(isPresented: $showsPaywall) { PaywallView(source: .mockLimit) }
    }

    private var mockUpsell: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(AppPalette.primary)
            Text(viewModel.mockIsTrial ? "무료 체험을 모두 사용했어요" : "오늘 모의고사를 모두 사용했어요")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppPalette.ink)
            Text(viewModel.plan.isPaid
                 ? "내일 다시 도전하거나, 상위 플랜으로 하루 응시 횟수를 늘려보세요."
                 : "플랜을 업그레이드하면 모의고사를 매일 응시할 수 있어요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "플랜 업그레이드", systemImage: "crown.fill") {
                showsPaywall = true
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppPalette.primarySoft.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private var introduction: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "list.number")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(AppPalette.primary)
                    .padding(.top, AppSpacing.xl)
                Text("실전처럼 15문항에 답해보세요")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                Text(viewModel.mockIsTrial
                     ? "OPIc 모의고사를 최초 1회 무료로 체험해볼 수 있어요. 실전처럼 총 15문항!"
                     : "하루 \(viewModel.mockDailyLimit)회 응시할 수 있어요. 총 15문항, 중간에 멈춰도 오늘 안에는 이어서 진행할 수 있어요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .cardStyle(alignment: .center)
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                if viewModel.canResume {
                    PrimaryButton(title: "이어서 하기", systemImage: "arrow.uturn.forward") {
                        Task { await viewModel.resume() }
                    }
                    Text("진행 중인 오늘의 모의고사를 이어서 볼 수 있어요.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                } else if viewModel.mockAvailable {
                    if let remaining = viewModel.mockRemaining {
                        Text(viewModel.mockIsTrial
                             ? "무료 체험 \(remaining)회 남음"
                             : "오늘 남은 모의고사 \(remaining)회 / 하루 \(viewModel.mockDailyLimit)회")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundStyle(AppPalette.primary)
                    }
                    if viewModel.savedSurvey != nil {
                        PrimaryButton(title: "저장된 설문으로 시작", systemImage: "play.fill") {
                            showsSavedSurveyDialog = true
                        }
                    }
                    PrimaryButton(
                        title: viewModel.savedSurvey == nil ? "설문 선택하고 시작" : "설문 다시 선택",
                        systemImage: "slider.horizontal.3"
                    ) {
                        viewModel.showSurvey()
                    }
                } else {
                    mockUpsell
                }
                BannerAdView().frame(height: 50)
            }
            .padding(AppSpacing.lg)
        }
    }

    private var survey: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("나에 대해 알려주세요")
                        .font(AppTypography.title)
                    Text("관심사를 바탕으로 질문을 만들어요. 상태와 거주 형태를 고르고, 관심 주제를 3개 이상 선택해 주세요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                if let message = viewModel.errorMessage { ErrorBanner(message: message) }
                SingleChoiceSection(
                    title: "현재 상태",
                    options: BackgroundSurvey.statusOptions,
                    selection: Binding(
                        get: { viewModel.surveyDraft.status },
                        set: { viewModel.surveyDraft.status = $0 }
                    )
                )
                SingleChoiceSection(
                    title: "거주 형태",
                    options: BackgroundSurvey.residenceOptions,
                    selection: Binding(
                        get: { viewModel.surveyDraft.residence },
                        set: { viewModel.surveyDraft.residence = $0 }
                    )
                )
                MultiChoiceSection(
                    title: "여가",
                    options: BackgroundSurvey.leisureOptions,
                    selection: Binding(
                        get: { viewModel.surveyDraft.leisure },
                        set: { viewModel.surveyDraft.leisure = $0 }
                    )
                )
                MultiChoiceSection(
                    title: "취미",
                    options: BackgroundSurvey.hobbyOptions,
                    selection: Binding(
                        get: { viewModel.surveyDraft.hobbies },
                        set: { viewModel.surveyDraft.hobbies = $0 }
                    )
                )
                MultiChoiceSection(
                    title: "운동",
                    options: BackgroundSurvey.sportOptions,
                    selection: Binding(
                        get: { viewModel.surveyDraft.sports },
                        set: { viewModel.surveyDraft.sports = $0 }
                    )
                )
                MultiChoiceSection(
                    title: "여행",
                    options: BackgroundSurvey.travelOptions,
                    selection: Binding(
                        get: { viewModel.surveyDraft.travel },
                        set: { viewModel.surveyDraft.travel = $0 }
                    )
                )
                Text("선택한 관심 주제 \(viewModel.surveyDraft.selectedTopicCount)개")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.surveyDraft.isValid ? AppPalette.primary : AppPalette.dangerInk)
                PrimaryButton(
                    title: "15문항 시작",
                    systemImage: "play.fill",
                    isDisabled: !viewModel.surveyDraft.isValid
                ) {
                    Task { await viewModel.startNewExam(survey: viewModel.surveyDraft) }
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    private var answering: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                MockProgressHeader(currentQuestion: viewModel.currentIndex + 1)
                if let question = viewModel.currentQuestion {
                    QuestionCard(question: question, showsNumber: true, showsRubricFocus: false)
                    PromptPlayButton(
                        isSpeaking: promptPlayback.isSpeaking,
                        hasStarted: promptPlayback.hasStarted(question),
                        isDisabled: speech.isListening
                    ) {
                        viewModel.playPrompt()
                    }
                }
                if let message = viewModel.errorMessage { ErrorBanner(message: message) }
                // 녹음을 멈추면 검토 상태로만 넘어간다. 제출해야 다음 문항으로 간다.
                if let pending = viewModel.pendingAnswer {
                    TranscriptReviewPanel(
                        transcript: pending.transcript,
                        submitTitle: "답변 제출",
                        submitIcon: "paperplane.fill",
                        isSubmitting: false,
                        submit: { viewModel.submitPendingAnswer() },
                        reRecord: { viewModel.discardPendingAnswer() }
                    )
                } else {
                    RecordingButton(isRecording: speech.isListening, isDisabled: false) {
                        Task { await viewModel.toggleRecording() }
                    }
                    Text(speech.isListening ? "탭하면 답변 완료" : "탭하고 답변하기")
                        .font(.title3.bold())
                    Text("남은 시간 \(viewModel.remainingSeconds)초")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(viewModel.remainingSeconds <= 20 ? AppPalette.dangerInk : AppPalette.secondaryInk)
                        .accessibilityLabel("남은 시간 \(viewModel.remainingSeconds)초")
                    Text(speech.transcript.isEmpty ? "답변을 마치면 확인하고 제출해요." : speech.transcript)
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                    Text("제출한 문항은 다시 답할 수 없어요.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            .padding(AppSpacing.lg)
        }
        .interactiveDismissDisabled(speech.isListening)
    }

    private var adjustment: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            DifficultyAdjustmentDialog(isLoading: viewModel.isApplyingAdjustment) { adjustment in
                Task { await viewModel.applyAdjustment(adjustment) }
            }
            if let message = viewModel.errorMessage {
                VStack {
                    ErrorBanner(message: message)
                        .padding(.horizontal, AppSpacing.lg)
                    Spacer()
                }
                .padding(.top, AppSpacing.lg)
            }
        }
    }

    private var rewardGate: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppPalette.primary)
                Text("15개 답변을 모두 녹음했어요")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                Text(
                    viewModel.canRetryEvaluation
                        ? "같은 답변으로 AI 종합 평가를 다시 받아볼게요."
                        : "AI가 15개 답변을 분석해 종합 결과를 알려드려요."
                )
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .cardStyle(alignment: .center)
                if let message = viewModel.errorMessage { ErrorBanner(message: message) }
                PrimaryButton(
                    title: viewModel.canRetryEvaluation ? "AI 평가 다시 시도" : "결과보기",
                    systemImage: viewModel.canRetryEvaluation ? "arrow.clockwise" : "doc.text.magnifyingglass"
                ) {
                    Task {
                        if viewModel.canRetryEvaluation {
                            await viewModel.retryEvaluation()
                        } else {
                            await viewModel.evaluateAfterReward()
                        }
                    }
                }
                Button("모의고사 그만두기") { viewModel.resetExam() }
                    .foregroundStyle(AppPalette.dangerInk)
                    .minimumTouchTarget()
            }
            .padding(AppSpacing.lg)
        }
    }
}

private struct SingleChoiceSection: View {
    let title: String
    let options: [SurveyOption]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(.headline)
            FlexibleChips(options: options, selection: selection) { option in
                selection = option.topicId
            }
        }
        .cardStyle()
    }
}

private struct MultiChoiceSection: View {
    let title: String
    let options: [SurveyOption]
    @Binding var selection: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(selection.count)/6")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            FlexibleChips(options: options, selection: Set(selection)) { option in
                toggle(option.topicId)
            }
        }
        .cardStyle()
    }

    private func toggle(_ topicId: String) {
        if selection.contains(topicId) {
            selection.removeAll { $0 == topicId }
        } else if selection.count < 6 {
            selection.append(topicId)
        }
    }
}

private struct MockProgressHeader: View {
    let currentQuestion: Int
    private let totalQuestions = 15

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("\(currentQuestion) / \(totalQuestions)")
                    .font(.headline)
                Spacer()
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 10)
                    Capsule()
                        .fill(AppPalette.primary)
                        .frame(
                            width: width * CGFloat(currentQuestion) / CGFloat(totalQuestions),
                            height: 10
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentQuestion)
                }
            }
            .frame(height: 10)
        }
    }
}

/// Full-screen loading state for the mock exam, using the branded indicator.
private struct MockLoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            AppLoadingIndicator(dotSize: 12)
            Text(message)
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SavedSurveyDialog: View {
    let cancel: () -> Void
    let start: () -> Void
    let edit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                VStack(spacing: AppSpacing.sm) {
                    Text("저장된 설문으로 시작할까요?")
                        .font(.headline)
                        .foregroundStyle(AppPalette.ink)
                    Text("이전에 고른 관심사로 바로 시작하거나, 다시 수정할 수 있어요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: "그대로 시작", systemImage: "play.fill", action: start)
                Button("설문 수정", action: edit)
                    .font(.headline)
                    .foregroundStyle(AppPalette.primary)
                    .minimumTouchTarget()
                Button("취소", action: cancel)
                    .font(.headline)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .minimumTouchTarget()
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 360)
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

private struct ResetMockExamDialog: View {
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
            VStack(spacing: AppSpacing.md) {
                VStack(spacing: AppSpacing.sm) {
                    Text("지금 진행한 모의고사를 그만둘까요?")
                        .font(.headline)
                        .foregroundStyle(AppPalette.ink)
                    // 포기한 회차는 응시 한도를 소진하지 않는다. 다시 시작할 수 없다고
                    // 안내하면 사실과 다르다.
                    Text("지금까지 녹음한 답변은 사라져요. 새 모의고사는 다시 시작할 수 있어요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: AppSpacing.sm) {
                    Button("계속하기", action: cancel)
                        .font(.headline)
                        .foregroundStyle(AppPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    Button("그만두기", role: .destructive) {
                        confirm()
                    }
                        .font(.headline)
                        .foregroundStyle(AppPalette.actionOnDanger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppPalette.danger)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                }
            }
            .padding(AppSpacing.lg)
            .background(AppPalette.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            .padding(.horizontal, AppSpacing.lg)
            // 배경 탭·"계속하기"와 같은 취소 경로. 파괴적 동작(그만두기)은 이스케이프로 실행되지 않는다.
            .accessibilityAction(.escape, cancel)
        }
    }
}

private struct FlexibleChips<Selection: Equatable>: View {
    let options: [SurveyOption]
    let selection: Selection
    let action: (SurveyOption) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                Button {
                    action(option)
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected(option) ? AppPalette.actionOnPrimary : AppPalette.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected(option) ? AppPalette.primary : AppPalette.primarySoft)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(AppPalette.primary.opacity(isSelected(option) ? 0 : 0.35))
                        }
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
                .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
            }
        }
    }

    private func isSelected(_ option: SurveyOption) -> Bool {
        if let value = selection as? String {
            return value == option.topicId
        }
        if let values = selection as? Set<String> {
            return values.contains(option.topicId)
        }
        return false
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for item in arrangement.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var items: [Arrangement.Item] = []

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            items.append(.init(index: index, origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return Arrangement(items: items, size: CGSize(width: maxWidth, height: y + lineHeight))
    }

    private struct Arrangement {
        struct Item {
            let index: Int
            let origin: CGPoint
            let size: CGSize
        }

        let items: [Item]
        let size: CGSize
    }
}
