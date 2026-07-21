import SwiftUI

struct PracticeScreen: View {
    let viewModel: PracticeViewModel
    let preferences: AppPreferences
    @ObservedObject private var speech: SpeechRecognitionService
    @ObservedObject private var promptPlayback: PromptPlaybackService
    @State private var showsSetup = false

    init(viewModel: PracticeViewModel, preferences: AppPreferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        _speech = ObservedObject(wrappedValue: viewModel.speech)
        _promptPlayback = ObservedObject(wrappedValue: viewModel.promptPlayback)
    }

    var body: some View {
        Group {
            if viewModel.phase == .completed, let evaluation = viewModel.evaluation {
                PracticeResultView(
                    evaluation: evaluation,
                    targetLevel: viewModel.targetLevel,
                    transcript: viewModel.evaluatedTranscript,
                    next: viewModel.nextQuestion
                )
            } else {
                practiceBody
            }
        }
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
        }
        .sheet(isPresented: $showsSetup) {
            SetupView(preferences: preferences)
        }
        .onChange(of: preferences.initialLevel) {
            Task { await viewModel.reloadQuestions() }
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
        .task { await viewModel.load() }
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
                    QuestionCard(question: question, showsNumber: true, showsRubricFocus: false)
                        .id(question.number)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))

                    promptControls(for: question)

                    VStack(spacing: AppSpacing.md) {
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
                    }
                    .padding(.vertical, AppSpacing.xl)

                    if viewModel.pendingRecording != nil, viewModel.phase != .analyzing {
                        PrimaryButton(title: "분석 다시 시도", systemImage: "arrow.clockwise") {
                            Task { await viewModel.retryEvaluation() }
                        }
                    }
                    Button("다른 질문 받기") { viewModel.skipQuestion() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                BannerAdView()
                    .frame(height: 50)
            }
            .padding(AppSpacing.lg)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.currentQuestion?.number)
        }
        .refreshable { await viewModel.reloadQuestions() }
        .task(id: viewModel.currentQuestion?.number) {
            viewModel.playCurrentPromptAutomatically()
        }
    }

    @ViewBuilder
    private func promptControls(for question: GeneratedQuestion) -> some View {
        HStack {
            Label(
                promptPlayback.isSpeaking ? "질문 듣는 중" : "질문 듣기",
                systemImage: promptPlayback.isSpeaking ? "speaker.wave.2.fill" : "speaker.fill"
            )
            .foregroundStyle(AppPalette.secondaryInk)
            Spacer()
            Button("다시 듣기") { viewModel.replayCurrentPrompt() }
                .disabled(!promptPlayback.canReplay(question) || speech.isListening)
        }
        .font(.subheadline)
    }
}
