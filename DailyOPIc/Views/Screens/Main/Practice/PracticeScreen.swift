import SwiftUI

struct PracticeScreen: View {
    let viewModel: PracticeViewModel
    let preferences: AppPreferences
    @ObservedObject private var speech: SpeechRecognitionService
    @ObservedObject private var promptPlayback: PromptPlaybackService
    @State private var showsSetup = false
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: PracticeViewModel, preferences: AppPreferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        _speech = ObservedObject(wrappedValue: viewModel.speech)
        _promptPlayback = ObservedObject(wrappedValue: viewModel.promptPlayback)
    }

    var body: some View {
        practiceBody
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GuideEntryButton(preferences: preferences)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSetup = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("학습 설정")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.showsPaywall = true } label: {
                        Image(systemName: viewModel.plan.isPaid ? "crown.fill" : "crown")
                            .foregroundStyle(
                                viewModel.plan.isPaid
                                    ? Color(AppPalette.primary)
                                    : Color(AppPalette.secondaryInk)
                            )
                    }
                    .accessibilityLabel(viewModel.plan.isPaid ? "구독 관리" : "구독 업그레이드")
                }
            }
            .sheet(isPresented: $showsSetup) {
                SetupView(preferences: preferences)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showsPaywall },
                set: { viewModel.showsPaywall = $0 }
            )) {
                PaywallView()
            }
            .onChange(of: preferences.initialLevel) {
                Task { await viewModel.reloadQuestions() }
            }
            // 플랜 변경(결제/복원/해지)·포그라운드 복귀 시 토큰·게이팅 즉시 최신화.
            .onChange(of: viewModel.plan) {
                Task { await viewModel.refreshUsage() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await viewModel.refreshUsage() }
                }
            }
            .overlay {
                if viewModel.operationState.isRunning,
                   viewModel.phase == .analyzing || viewModel.isRefreshingQuestions {
                    AILoadingOverlay(
                        kind: viewModel.operationKind,
                        blocksInteraction: true,
                        canContinueInBackground: true
                    )
                } else if viewModel.showsRefreshDialog {
                    DailyRefreshDialog(
                        isLoading: viewModel.isRefreshingQuestions,
                        progressMessage: viewModel.refreshProgressMessage,
                        select: { adjustment in
                            Task { await viewModel.refreshQuestions(adjustment: adjustment) }
                        },
                        cancel: {
                            guard !viewModel.isRefreshingQuestions else { return }
                            viewModel.showsRefreshDialog = false
                        }
                    )
                }
            }
            .task {
                await viewModel.load()
                await viewModel.refreshUsage()
            }
    }

    private var practiceBody: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                HStack {
                    DailyTokenBadge(count: viewModel.dailyTokenCount)
                    Spacer()
                }

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await viewModel.load() }
                    }
                }

                if viewModel.phase == .loading {
                    VStack(spacing: AppSpacing.md) {
                        AppLoadingIndicator()
                        Text("맞춤 질문을 준비하고 있어요")
                            .font(AppTypography.callout)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if let question = viewModel.currentQuestion {
                    questionProgressBar

                    QuestionCard(question: question, showsNumber: true, showsRubricFocus: false)
                        .id(question.number)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))

                    if let result = viewModel.currentResult {
                        savedResult(result)
                    } else {
                        recorder(for: question)
                    }

                    navigationControls
                }
                BannerAdView()
                    .frame(height: 50)
            }
            .padding(AppSpacing.lg)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.currentQuestion?.number)
        }
        .refreshable { await viewModel.reloadQuestions() }
    }

    // MARK: - Question progress chips

    private var questionProgressBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(0..<viewModel.questionCount, id: \.self) { index in
                    // 실제 문항 번호(데일리 Q2~Q15). index+1이 아니라 세트의 number 사용.
                    let number = viewModel.questionNumber(at: index) ?? (index + 1)
                    let isCurrent = index == viewModel.questionIndex
                    let done = viewModel.isAnalyzed(number)
                    Button {
                        viewModel.goToQuestion(index)
                    } label: {
                        HStack(spacing: 4) {
                            if done {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                            }
                            Text("Q\(number)")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 6)
                        .foregroundStyle(isCurrent ? .white : (done ? AppPalette.primary : AppPalette.secondaryInk))
                        .background(
                            isCurrent ? AppPalette.primary
                                : (done ? AppPalette.primarySoft : AppPalette.surface),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Recorder

    @ViewBuilder
    private func recorder(for question: GeneratedQuestion) -> some View {
        VStack(spacing: AppSpacing.md) {
            PromptPlayButton(
                isSpeaking: promptPlayback.isSpeaking,
                hasStarted: promptPlayback.hasStarted(question),
                isDisabled: speech.isListening
            ) {
                viewModel.playPrompt()
            }

            RecordingButton(
                isRecording: speech.isListening,
                isDisabled: viewModel.phase == .analyzing
            ) {
                Task { await viewModel.toggleRecording() }
            }
            Text(speech.isListening ? "탭하면 답변 완료" : "탭하고 답변하기")
                .font(.title3.bold())
            AnswerPanel(
                finalText: speech.finalTranscript,
                partialText: speech.partialTranscript,
                isRecording: speech.isListening
            )

            if viewModel.pendingRecording != nil, viewModel.phase != .analyzing {
                PrimaryButton(title: "분석 다시 시도", systemImage: "arrow.clockwise") {
                    Task { await viewModel.retryEvaluation() }
                }
            }
        }
        .padding(.vertical, AppSpacing.md)
    }

    @ViewBuilder
    private func savedResult(_ result: PracticeViewModel.AnalyzedResult) -> some View {
        PracticeResultView(
            evaluation: result.evaluation,
            targetLevel: viewModel.targetLevel,
            transcript: result.transcript,
            showsNextButton: false,
            isEmbedded: true
        )
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                viewModel.goToPrevious()
            } label: {
                Label("이전", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canGoPrevious || speech.isListening)

            Button {
                viewModel.goToNext()
            } label: {
                Label(viewModel.canGoNext ? "다음" : "새 질문", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(speech.isListening)
        }
    }
}
