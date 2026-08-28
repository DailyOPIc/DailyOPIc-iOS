import SwiftUI

/// 맞춤 단어장을 만드는 자리(P14.2). 고르는 것은 주제 하나뿐이다.
///
/// 목표 등급은 여기서 다시 정하지 않는다 — 온보딩에서 정한 값(`AppPreferences`)을
/// 그대로 읽는다. 목표 등급 설정을 단어장에 하나 더 만들면 두 값이 갈라진다.
///
/// 개수(30개)와 구성(10/10/10)은 서버가 정한다. 화면은 그 값을 **말해 줄 뿐**
/// 고르게 하지 않는다.
struct VocabularyGenerationSheet: View {
    let viewModel: VocabularyGenerationViewModel
    let targetLevel: OPIcLevel
    /// 이미 가진 표현들. 중복을 피해 달라는 힌트로만 쓰인다(상한은 요청 모델이 갖는다).
    let existingTerms: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var topic: VocabularyTopic = .cafes

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    topicPicker
                    summaryCard
                    if viewModel.hasNoTokens {
                        Text("AI 맞춤 단어 생성을 위해 데일리 토큰 1개가 필요합니다.")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let message = failureMessage {
                        Text(message)
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
                    PrimaryButton(
                        title: failureMessage == nil ? "30개 만들기" : "다시 시도",
                        isLoading: viewModel.isGenerating
                    ) {
                        // 재시도도 같은 조작이다 — 뷰모델이 같은 요청 id를 그대로 쓴다.
                        viewModel.generate(
                            topic: topic,
                            targetLevel: targetLevel,
                            excluding: existingTerms
                        )
                    }
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle("AI 맞춤 단어장")
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
        .task { await viewModel.refreshUsage() }
        .onChange(of: viewModel.finishedSetID) { _, setID in
            // 세트는 이미 저장됐다. 시트를 닫으면 홈의 "AI 단어장"에서 바로 보인다.
            guard setID != nil else { return }
            viewModel.finishedSetID = nil
            dismiss()
        }
        .sheet(isPresented: Bindable(viewModel).showsPaywall) {
            PaywallView(source: viewModel.paywallSource)
        }
    }

    private var failureMessage: String? {
        if case let .recoverableFailure(_, message) = viewModel.operationState { return message }
        return nil
    }

    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("주제")
                .font(AppTypography.sectionTitle)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppSpacing.sm),
                          GridItem(.flexible(), spacing: AppSpacing.sm)],
                spacing: AppSpacing.sm
            ) {
                ForEach(VocabularyTopic.allCases) { candidate in
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
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityAddTraits(candidate == topic ? [.isSelected] : [])
                }
            }
        }
    }

    /// 누르기 전에 비용을 말한다. 화폐는 데일리 토큰 하나뿐이라 아이콘도 그것 하나다.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("\(topic.label) · 목표 \(targetLevel.rawValue)")
                .font(AppTypography.cardTitle)
            Text("30개의 맞춤 단어와 표현을 만들어요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
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
        .cardStyle()
    }
}

/// 만든 세트 목록. 여기부터 아래는 전부 무료다 — 저장된 항목을 읽을 뿐이다.
struct VocabularyGeneratedSetListView: View {
    let sets: [VocabularyGeneratedSetRecord]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                if sets.isEmpty {
                    Text("아직 만든 단어장이 없어요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .padding(.top, AppSpacing.lg)
                } else {
                    ForEach(sets) { record in
                        NavigationLink(value: VocabularyRoute.generatedSet(setID: record.setID)) {
                            row(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("AI 단어장")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ record: VocabularyGeneratedSetRecord) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(VocabularyGeneratedSetRecord.title(for: record))
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.ink)
                Text("\(record.entries.count)개")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            Spacer(minLength: 0)
            Text(VocabularyGeneratedSetRecord.dateText(record.createdAt))
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// 세트 하나. 무엇이 들어 있는지 종류별로 보여주고 학습으로 넘긴다.
/// 여는 것도 학습하는 것도 토큰을 쓰지 않는다.
struct VocabularyGeneratedSetDetailView: View {
    let record: VocabularyGeneratedSetRecord
    let states: [String: VocabularyStateRecord]

    private var entries: [VocabularyEntry] { record.entries }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(VocabularyGeneratedSetRecord.title(for: record))
                        .font(AppTypography.title)
                    Text("AI 맞춤 단어 \(entries.count)개")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                    ForEach(VocabularyItemType.allCases) { type in
                        Text("\(type.label) \(entries.filter { $0.type == type }.count)")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                .cardStyle()

                NavigationLink(value: VocabularyRoute.generatedStudy(setID: record.setID)) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "book.closed.fill")
                        Text("학습 시작").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(AppPalette.actionOnPrimary)
                    .background(AppPalette.primary)
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
                }
                .buttonStyle(PressableButtonStyle())

                LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            VocabularyEntryRow(entry: entry, state: states[entry.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("AI 단어장")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension VocabularyGeneratedSetRecord {
    /// "카페 · IH". 주제나 등급을 못 읽는 저장본이라도 줄이 비지 않게 한다.
    static func title(for record: VocabularyGeneratedSetRecord) -> String {
        [record.topic?.label, record.targetLevel?.rawValue]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}
