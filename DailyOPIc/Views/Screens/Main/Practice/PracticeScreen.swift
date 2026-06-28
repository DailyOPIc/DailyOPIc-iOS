import SwiftUI

struct PracticeScreen: View {
    let viewModel: PracticeViewModel
    let preferences: AppPreferences
    @ObservedObject private var speech: SpeechRecognitionService
    @State private var showsSetup = false

    init(viewModel: PracticeViewModel, preferences: AppPreferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        _speech = ObservedObject(wrappedValue: viewModel.speech)
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
            if viewModel.showsRefreshDialog {
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
            VStack(spacing: 22) {
                HStack {
                    Text("Self Assessment: ") + Text(viewModel.initialLevel.title).foregroundStyle(AppPalette.primary)
                    Spacer()
                    Text(viewModel.remainingText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                .font(.subheadline.weight(.medium))

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await viewModel.load() }
                    }
                }

                if viewModel.phase == .loading {
                    ProgressView("맞춤 문제를 준비하고 있어요")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let question = viewModel.currentQuestion {
                    QuestionCard(question: question, showsNumber: true, showsRubricFocus: false)

                    VStack(spacing: 14) {
                        RecordingButton(
                            isRecording: speech.isListening,
                            isDisabled: viewModel.phase == .analyzing
                        ) {
                            Task { await viewModel.toggleRecording() }
                        }
                        Text(speech.isListening ? "Tap to Finish" : "Tap to Answer")
                            .font(.title3.bold())
                        Text(
                            speech.isListening
                                ? (speech.transcript.isEmpty ? "영어로 답변해 주세요." : speech.transcript)
                                : "녹음을 시작하려면 탭하세요."
                        )
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 46)
                    }
                    .padding(.vertical, 32)

                    if viewModel.phase == .analyzing {
                        ProgressView("답변을 정교하게 분석하고 있어요")
                    } else if viewModel.pendingRecording != nil {
                        PrimaryButton(title: "평가 다시 시도", systemImage: "arrow.clockwise") {
                            Task { await viewModel.retryEvaluation() }
                        }
                    }
                    Button("다른 질문으로 넘어가기") { viewModel.skipQuestion() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                BannerAdView()
                    .frame(height: 50)
            }
            .padding(20)
        }
        .refreshable { await viewModel.reloadQuestions() }
    }
}
