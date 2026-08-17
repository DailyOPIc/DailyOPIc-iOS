import StoreKit
import SwiftUI

struct PracticeScreen: View {
    let viewModel: PracticeViewModel
    let preferences: AppPreferences
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var speech: SpeechRecognitionService
    @ObservedObject private var promptPlayback: PromptPlaybackService
    @State private var showsSetup = false
    @State private var pendingSetupRoute: SetupView.Route?
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
                    GuideEntryButton { preferences.beginGuide() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSetup = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("학습 설정")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.presentPaywall(from: .settings) } label: {
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
            .sheet(isPresented: $showsSetup, onDismiss: applyPendingSetupRoute) {
                SetupView(preferences: preferences) { pendingSetupRoute = $0 }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showsPaywall },
                set: { viewModel.showsPaywall = $0 }
            )) {
                PaywallView(source: viewModel.paywallSource)
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
            // 분석에 성공한 결과가 화면에 올라온 뒤에만 리뷰를 요청한다. 표식은 한 번 쓰고
            // 비우므로 같은 결과를 다시 봐도 재요청하지 않고, 자격이 안 되면 아무 일도 없다.
            .task(id: viewModel.freshResultToken) {
                guard viewModel.freshResultToken != nil else { return }
                viewModel.freshResultToken = nil
                environment.appReview.requestReviewIfEligible(
                    context: .successfulPracticeResult
                ) { requestReview() }
            }
    }

    /// 설정 시트가 완전히 닫힌 뒤에 루트 플로우를 연다. 시트가 떠 있는 동안
    /// fullScreenCover를 요청하면 표시 충돌이 나므로, 지연 대신 onDismiss로
    /// 순서를 고정한다.
    private func applyPendingSetupRoute() {
        switch pendingSetupRoute {
        case .guide: preferences.beginGuide()
        case .levelSelection: preferences.resetOnboarding()
        case nil: break
        }
        pendingSetupRoute = nil
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
                // 배너 없음: 말하기가 진행되는 화면이다. 광고는 통계·모의고사 인트로처럼
                // 흐름을 끊지 않는 곳에만 둔다.
            }
            .padding(AppSpacing.lg)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.currentQuestion?.number)
        }
        .refreshable { await viewModel.reloadQuestions() }
    }

    // MARK: - Question progress chips

    private var questionProgressBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // sm(8) is DESIGN.md §14.1's chip gap and §30.1's minimum gap
            // between adjacent 44pt hit areas; xs(4) would leave them 4pt apart.
            HStack(spacing: AppSpacing.sm) {
                ForEach(0..<viewModel.questionCount, id: \.self) { index in
                    // 실제 문항 번호(데일리 Q2~Q15). index+1이 아니라 세트의 number 사용.
                    let number = viewModel.questionNumber(at: index) ?? (index + 1)
                    let isCurrent = index == viewModel.questionIndex
                    let done = viewModel.isAnalyzed(number)
                    Button {
                        viewModel.goToQuestion(index)
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            if done {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                            }
                            Text("Q\(number)")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 6)
                        .foregroundStyle(isCurrent ? AppPalette.actionOnPrimary : (done ? AppPalette.primary : AppPalette.secondaryInk))
                        .background(
                            isCurrent ? AppPalette.primary
                                : (done ? AppPalette.primarySoft : AppPalette.surface),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .minimumTouchTarget()
                    .accessibilityLabel("\(number)번 문항, \(done ? "분석 완료" : "아직 답하지 않음")")
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Recorder

    @ViewBuilder
    private func recorder(for question: GeneratedQuestion) -> some View {
        VStack(spacing: AppSpacing.md) {
            // 녹음을 멈추면 검토 상태로만 넘어간다. 분석은 사용자가 눌러야 시작한다.
            if let pending = viewModel.pendingRecording {
                TranscriptReviewPanel(
                    transcript: pending.transcript,
                    submitTitle: viewModel.phase == .analyzing ? "분석 중" : "분석하기",
                    submitIcon: "sparkles",
                    isSubmitting: viewModel.phase == .analyzing,
                    submit: { Task { await viewModel.analyzePendingRecording() } },
                    reRecord: { viewModel.discardPendingRecording() }
                )
            } else {
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
                if speech.isListening {
                    Text("남은 시간 \(viewModel.remainingSeconds)초")
                        .font(AppTypography.callout)
                        .monospacedDigit()
                        .foregroundStyle(AppPalette.secondaryInk)
                        .accessibilityLabel("남은 답변 시간 \(viewModel.remainingSeconds)초")
                }
                AnswerPanel(
                    finalText: speech.finalTranscript,
                    partialText: speech.partialTranscript,
                    isRecording: speech.isListening
                )
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
