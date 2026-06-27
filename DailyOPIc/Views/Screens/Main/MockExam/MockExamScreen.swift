import SwiftUI

struct MockExamScreen: View {
    let viewModel: MockExamViewModel
    @ObservedObject private var speech: SpeechRecognitionService
    @State private var showsResetConfirmation = false

    init(viewModel: MockExamViewModel) {
        self.viewModel = viewModel
        _speech = ObservedObject(wrappedValue: viewModel.speech)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .introduction:
                introduction
            case .survey:
                survey
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
        .toolbar {
            if canResetExam {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("모의고사 다시하기") {
                        showsResetConfirmation = true
                    }
                }
            }
        }
        .overlay {
            if showsResetConfirmation {
                ResetMockExamDialog(
                    cancel: { showsResetConfirmation = false },
                    confirm: {
                        showsResetConfirmation = false
                        viewModel.resetExam()
                    }
                )
            }
        }
        .task { viewModel.restoreDraftIfAvailable() }
    }

    private var canResetExam: Bool {
        viewModel.questionSet != nil || !viewModel.answers.isEmpty || viewModel.evaluation != nil
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
                Text("OPIc 유형 기반 모의고사입니다. Background Survey 선택값을 바탕으로 자기소개, 관심 주제 콤보, 롤플레이, 비교·의견 문항을 차례로 진행합니다.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .cardStyle()
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                if viewModel.savedSurvey != nil {
                    PrimaryButton(title: "이전 설문으로 바로 시작", systemImage: "play.fill") {
                        Task { await viewModel.startWithSavedSurvey() }
                    }
                }
                PrimaryButton(
                    title: viewModel.savedSurvey == nil ? "Background Survey 선택" : "설문 다시 선택",
                    systemImage: "slider.horizontal.3"
                ) {
                    viewModel.showSurvey()
                }
                BannerAdView().frame(height: 50)
            }
            .padding(24)
        }
    }

    private var survey: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background Survey")
                        .font(AppTypography.title)
                    Text("관심 주제를 바탕으로 15문항을 구성합니다. 상태와 거주 형태를 선택하고, 관심 주제는 전체 3개 이상 선택해 주세요.")
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
                    .foregroundStyle(viewModel.surveyDraft.isValid ? AppPalette.primary : AppPalette.danger)
                PrimaryButton(
                    title: "15문항 시작",
                    systemImage: "play.fill",
                    isDisabled: !viewModel.surveyDraft.isValid
                ) {
                    Task { await viewModel.startNewExam(survey: viewModel.surveyDraft) }
                }
            }
            .padding(24)
        }
    }

    private var answering: some View {
        ScrollView {
            VStack(spacing: 22) {
                MockProgressHeader(currentQuestion: viewModel.currentIndex + 1)
                if let question = viewModel.currentQuestion {
                    QuestionCard(question: question, showsNumber: true, showsRubricFocus: false)
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

private struct SingleChoiceSection: View {
    let title: String
    let options: [SurveyOption]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
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
    private let adMarkers = [5, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(currentQuestion) / \(totalQuestions)")
                    .font(.headline)
                Spacer()
                Label("노란 점: 광고 예정", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
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
                    ForEach(adMarkers, id: \.self) { marker in
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle().stroke(AppPalette.ink.opacity(0.28), lineWidth: 1)
                            }
                            .position(
                                x: width * CGFloat(marker) / CGFloat(totalQuestions),
                                y: 5
                            )
                            .accessibilityLabel("\(marker)번 뒤 광고 예정")
                    }
                }
            }
            .frame(height: 14)
        }
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
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("모의고사를 다시 시작할까요?")
                        .font(.headline)
                        .foregroundStyle(AppPalette.ink)
                    Text("녹음한 답변과 임시 저장된 모의고사가 삭제됩니다.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button("취소", action: cancel)
                        .font(.headline)
                        .foregroundStyle(AppPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button("다시 시작", role: .destructive) {
                        confirm()
                    }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppPalette.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(22)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            .padding(.horizontal, 26)
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
                        .foregroundStyle(isSelected(option) ? .white : AppPalette.primary)
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
