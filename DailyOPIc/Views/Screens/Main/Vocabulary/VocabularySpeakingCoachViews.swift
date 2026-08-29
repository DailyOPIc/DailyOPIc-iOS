import SwiftUI

/// 단어장 표현 하나로 직접 말해 보는 자리(P14.3).
///
/// 화면 순서가 곧 과금 경계다:
///   1. 지시문 · 발음 듣기 · 녹음 — 0 토큰
///   2. 내가 말한 내용(전사) 확인 · 다시 녹음 — 0 토큰
///   3. [AI에게 분석받기] — **데일리 토큰 1개.** 사용자가 눌러야만 시작한다.
///   4. 결과 · 지난 코칭 다시 보기 — 0 토큰
///
/// 녹음을 멈추는 것으로 AI가 자동으로 불리는 경로는 없다.
struct VocabularySpeakingCoachView: View {
    @State private var viewModel: VocabularyCoachViewModel
    @State private var isShowingHistory = false

    init(entry: VocabularyEntry, environment: AppEnvironment, targetLevel: OPIcLevel?) {
        _viewModel = State(
            initialValue: VocabularyCoachViewModel(
                entry: entry,
                environment: environment,
                targetLevel: targetLevel
            )
        )
    }

    private var speech: SpeechRecognitionService { viewModel.speech }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                promptCard
                if let result = viewModel.result {
                    resultSection(result)
                } else if let transcript = viewModel.pendingTranscript {
                    reviewSection(transcript)
                } else {
                    recorderSection
                }
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                historySection
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("직접 말해보기")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isAnalyzing {
                AILoadingOverlay(
                    kind: .vocabularyCoach,
                    blocksInteraction: true,
                    canContinueInBackground: false
                )
            }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.cancelRecording() }
        .sheet(isPresented: Bindable(viewModel).showsPaywall) {
            PaywallView(source: viewModel.paywallSource)
        }
    }

    // MARK: 1. 지시문 (0 토큰 · AI를 부르지 않는다)

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(viewModel.entry.term)
                .font(AppTypography.title)
                .fixedSize(horizontal: false, vertical: true)
            Text(viewModel.instruction)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
            if let hint = viewModel.topicHint {
                Text(hint)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 2. 녹음 (0 토큰)

    private var recorderSection: some View {
        VStack(spacing: AppSpacing.md) {
            RecordingButton(isRecording: speech.isListening, isDisabled: false) {
                Task { await viewModel.toggleRecording() }
            }
            Text(speech.isListening ? "탭하면 녹음 완료" : "탭하고 말해보기")
                .font(.title3.bold())
            if speech.isListening {
                Text("남은 시간 \(viewModel.remainingSeconds)초")
                    .font(AppTypography.callout)
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.secondaryInk)
                    .accessibilityLabel("남은 녹음 시간 \(viewModel.remainingSeconds)초")
            }
            AnswerPanel(
                finalText: speech.finalTranscript,
                partialText: speech.partialTranscript,
                isRecording: speech.isListening
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 3. 전사 확인 → 명시적 AI 요청 (여기서만 토큰이 나간다)

    private func reviewSection(_ transcript: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("내가 말한 내용", systemImage: "text.alignleft")
                    .font(.headline)
                Text("\"\(transcript)\"")
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            Button { viewModel.recordAgain() } label: {
                Label("다시 녹음", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .minimumTouchTarget()
            .disabled(viewModel.isAnalyzing)
            .accessibilityHint("이 녹음을 지우고 다시 녹음해요. 분석은 하지 않아요.")

            coachCTA
        }
    }

    /// 누르기 전에 비용을 말한다. 화폐는 데일리 토큰 하나뿐이다.
    private var coachCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("AI 말하기 코치")
                .font(AppTypography.sectionTitle)
            Text("이 표현을 자연스럽게 사용했는지 확인해보세요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppSpacing.xs) {
                DailyTokenIcon(size: 18)
                Text("\(VocabularyCoachViewModel.tokenCost)")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "데일리 토큰 \(VocabularyCoachViewModel.tokenCost)개를 사용해요"
            )
            if viewModel.hasNoTokens {
                Text("AI 코칭을 받으려면 데일리 토큰 1개가 필요합니다.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = viewModel.failureMessage {
                Text(message)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(
                title: viewModel.failureMessage == nil ? "AI에게 분석받기" : "다시 시도",
                systemImage: "sparkles",
                isLoading: viewModel.isAnalyzing
            ) {
                // 재시도도 같은 조작이다 — 뷰모델이 같은 요청 id를 그대로 쓴다.
                viewModel.analyze()
            }
            .disabled(!viewModel.canAnalyze)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 4. 결과 (다시 보는 것은 0 토큰)

    private func resultSection(_ result: VocabularySpeakingCoachResult) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label(result.usageAssessment.label, systemImage: result.usageAssessment.systemImage)
                    .font(.headline)
                Text(result.usageFeedbackKo)
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            section("더 자연스럽게") {
                labelled("내가 말한 내용", result.transcript, isSecondary: true)
                labelled("이렇게 말해보세요", result.naturalCorrectionEn)
                Text(result.naturalCorrectionKo)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("OPIc에서 이렇게 이어 말해볼 수 있어요") {
                Text(result.expandedAnswerEn)
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.expandedAnswerKo)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !result.relatedExpressions.isEmpty {
                section("함께 써볼 표현") {
                    // 여기 있는 표현을 보는 것은 공짜다. 자동으로 단어장에 저장하지 않는다.
                    ForEach(result.relatedExpressions, id: \.self) { expression in
                        Text("· \(expression)")
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button { viewModel.recordAgain() } label: {
                Label("다시 말해보기", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .minimumTouchTarget()
            .accessibilityHint("다시 녹음해요. 녹음과 전사는 토큰을 쓰지 않아요.")
        }
    }

    // MARK: 지난 코칭 (0 토큰)

    @ViewBuilder
    private var historySection: some View {
        // 지금 보고 있는 결과 말고 더 있을 때만 보여준다. 별도 히스토리 제품을 만들지 않는다.
        let others = viewModel.history.filter { $0.resultId != viewModel.result?.resultId }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Button { isShowingHistory.toggle() } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Text("이전 코칭 보기")
                            .font(AppTypography.body)
                            .foregroundStyle(AppPalette.ink)
                        Spacer(minLength: 0)
                        Text("\(others.count)개")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                        Image(systemName: isShowingHistory ? "chevron.up" : "chevron.down")
                            .font(.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    .padding(.vertical, AppSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
                .accessibilityLabel("이전 코칭 \(others.count)개 보기")
                if isShowingHistory {
                    ForEach(others) { saved in
                        Button { viewModel.show(saved) } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(saved.usageAssessment.label)
                                    .font(AppTypography.callout)
                                    .foregroundStyle(AppPalette.ink)
                                Text(saved.transcript)
                                    .font(AppTypography.footnote)
                                    .foregroundStyle(AppPalette.secondaryInk)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AppSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .minimumTouchTarget()
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: 조각

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.sectionTitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func labelled(_ title: String, _ text: String, isSecondary: Bool = false) -> some View {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(AppPalette.secondaryInk)
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(isSecondary ? AppPalette.secondaryInk : AppPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
