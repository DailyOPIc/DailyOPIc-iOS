import SwiftUI

struct MockExamScreen: View {
    let viewModel: MockExamViewModel
    @ObservedObject private var speech: SpeechRecognitionService

    init(viewModel: MockExamViewModel) {
        self.viewModel = viewModel
        _speech = ObservedObject(wrappedValue: viewModel.speech)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .introduction:
                introduction
            case .loading:
                ProgressView("15문항을 구성하고 있어요")
            case .answering:
                answering
            case .readyForReward:
                rewardGate
            case .analyzing:
                ProgressView("15개 답변을 종합 분석하고 있어요")
            case .completed:
                if let evaluation = viewModel.evaluation {
                    MockResultView(evaluation: evaluation, targetLevel: viewModel.targetLevel) {
                        viewModel.resetExam()
                    }
                }
            }
        }
        .navigationTitle("Mock Exam")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.restoreDraftIfAvailable() }
    }

    private var introduction: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "list.number")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(AppPalette.primary)
                    .padding(.top, 36)
                Text("실전처럼 15문항에 답해보세요")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                Text("자기소개, 설문형 콤보, 돌발, 롤플레이, 비교·심화 문항을 차례로 진행합니다. 답변 중에는 평가하지 않으며 마지막에 종합 평가합니다.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .cardStyle()
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                PrimaryButton(title: "15문항 시작", systemImage: "play.fill") {
                    Task { await viewModel.startNewExam() }
                }
                BannerAdView().frame(height: 50)
            }
            .padding(24)
        }
    }

    private var answering: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text("\(viewModel.currentIndex + 1) / 15")
                        .font(.headline)
                    ProgressView(value: Double(viewModel.currentIndex + 1), total: 15)
                        .tint(AppPalette.primary)
                }
                if let question = viewModel.currentQuestion {
                    QuestionCard(question: question, showsNumber: true)
                }
                if let message = viewModel.errorMessage { ErrorBanner(message: message) }
                RecordingButton(isRecording: speech.isListening, isDisabled: false) {
                    Task { await viewModel.toggleRecording() }
                }
                Text(speech.isListening ? "Tap to Finish" : "Tap to Answer")
                    .font(.title3.bold())
                Text(speech.transcript.isEmpty ? "답변을 녹음하면 다음 문항으로 이동합니다." : speech.transcript)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                if viewModel.currentIndex > 0 && !speech.isListening {
                    Button("이전 문항 다시 답하기") { viewModel.previousQuestion() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .interactiveDismissDisabled(speech.isListening)
    }

    private var rewardGate: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppPalette.primary)
                Text("15개 답변을 모두 녹음했어요")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                Text("리워드 광고를 끝까지 시청하고 AI 종합 평가를 확인하세요. 광고 검증 전에는 평가 요청이 실행되지 않습니다.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .cardStyle()
                if let message = viewModel.errorMessage { ErrorBanner(message: message) }
                PrimaryButton(title: "광고 시청 후 종합 평가", systemImage: "play.rectangle.fill") {
                    Task { await viewModel.evaluateAfterReward() }
                }
                Button("모의고사 삭제") { viewModel.resetExam() }
                    .foregroundStyle(AppPalette.danger)
            }
            .padding(24)
        }
    }
}
