import SwiftUI

/// 목록의 한 줄. 주제·검색·내 단어가 모두 같은 줄을 쓴다.
struct VocabularyEntryRow: View {
    let entry: VocabularyEntry
    let state: VocabularyStateRecord?
    /// 학습 상태와 복습 횟수를 한 줄 더 보여줄지(P14.5.2). "오늘 학습한 단어"에서만 켠다.
    var showsProgress = false

    /// 상태 + 복습 횟수 한 줄. 복습을 한 번도 하지 않았으면 숫자를 붙이지 않는다 —
    /// "복습 0회"는 알려 주는 게 없다.
    static func progressText(_ state: VocabularyStateRecord?) -> String {
        let status = state?.status ?? .new
        let reviews = state?.reviewCount ?? 0
        return reviews > 0 ? "\(status.label) · 복습 \(reviews)회" : status.label
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(entry.term)
                        .font(AppTypography.callout)
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if state?.isSaved == true {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(AppPalette.primary)
                            .accessibilityLabel("저장함")
                    }
                    if state?.status == .mastered {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(AppPalette.primary)
                            .accessibilityLabel("익힘")
                    }
                }
                Text(entry.meaningKo)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if showsProgress {
                    Text(Self.progressText(state))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            Text(entry.type.label)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.primary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(AppPalette.primarySoft, in: Capsule())
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// 한 주제 안의 단어들. 단어 / 자주 쓰는 표현 / 답변 패턴을 걸러 볼 수 있다.
/// 그 주제에 **실제로 있는** 종류만 필터에 나온다.
struct VocabularyTopicView: View {
    let topic: VocabularyTopic
    let states: [String: VocabularyStateRecord]

    @State private var selectedType: VocabularyItemType?

    private var all: [VocabularyEntry] { VocabularyCatalog.entries(topic: topic) }
    private var availableTypes: [VocabularyItemType] {
        let present = Set(all.map(\.type))
        return VocabularyItemType.allCases.filter(present.contains)
    }
    private var visible: [VocabularyEntry] {
        VocabularyCatalog.entries(topic: topic, type: selectedType)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                if availableTypes.count > 1 {
                    Picker("종류", selection: $selectedType) {
                        Text("전체").tag(VocabularyItemType?.none)
                        ForEach(availableTypes) { type in
                            Text(type.label).tag(VocabularyItemType?.some(type))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Text("\(visible.count)개")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                ForEach(visible) { entry in
                    NavigationLink(value: entry) {
                        VocabularyEntryRow(entry: entry, state: states[entry.id])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle(topic.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 저장한 단어 · 익힌 단어 · 오늘 학습한 단어. 세 목록의 차이는 제목과 재료뿐이라
/// 한 화면을 나눠 쓴다 — 단어를 훑어보는 화면을 새로 만들지 않는다.
struct VocabularyMyWordsView: View {
    let title: String
    let emptyMessage: String
    let entries: [VocabularyEntry]
    let states: [String: VocabularyStateRecord]
    /// 줄마다 학습 상태·복습 횟수를 함께 보여줄지. "오늘 학습한 단어"에서만 켠다.
    var showsProgress = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                if entries.isEmpty {
                    Text(emptyMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .padding(.top, AppSpacing.lg)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            VocabularyEntryRow(
                                entry: entry,
                                state: states[entry.id],
                                showsProgress: showsProgress
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 단어 하나의 전체 내용. 학습 카드와 달리 뜻을 처음부터 보여준다 —
/// 여기는 외우는 자리가 아니라 찾아보는 자리다.
struct VocabularyEntryDetailView: View {
    let entry: VocabularyEntry
    let state: VocabularyStateRecord?
    let persistence: PersistenceService

    @StateObject private var playback = PromptPlaybackService()
    /// 저장 여부의 화면 쪽 진실. 저장 기록이 아직 없는 단어도 즉시 반응해야 해서
    /// 로컬 상태로 두고 같은 동작에서 저장소에 써 넣는다.
    @State private var isSaved: Bool

    init(entry: VocabularyEntry, state: VocabularyStateRecord?, persistence: PersistenceService) {
        self.entry = entry
        self.state = state
        self.persistence = persistence
        _isSaved = State(initialValue: state?.isSaved ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                header
                meaning
                speakingPractice
                if !entry.collocations.isEmpty { collocations }
                example
                tags
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.lg)
        }
        .navigationTitle(entry.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleSaved) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(isSaved ? "저장 해제" : "단어 저장")
            }
        }
        .onDisappear { playback.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(entry.term)
                .font(AppTypography.title)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                playback.play(text: entry.term)
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: playback.isSpeaking ? "speaker.wave.2.fill" : "speaker.fill")
                        .symbolEffect(.variableColor, isActive: playback.isSpeaking)
                    Text("발음 듣기").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(AppPalette.primary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppPalette.primarySoft, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .minimumTouchTarget()
            .disabled(playback.isSpeaking)
            .accessibilityLabel("\(entry.term) 발음 듣기")
        }
    }

    private var meaning: some View {
        Text(entry.meaningKo)
            .font(AppTypography.cardTitle)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 직접 말해보기(P14.3). 여는 것도 녹음도 전사도 토큰을 쓰지 않는다 —
    /// 토큰은 그 화면 안에서 "AI에게 분석받기"를 눌렀을 때만 나간다.
    private var speakingPractice: some View {
        NavigationLink(value: VocabularyRoute.speakingCoach(entry)) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "mic.fill")
                Text("직접 말해보기").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(AppPalette.actionOnPrimary)
            .background(AppPalette.primary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(entry.term) 직접 말해보기")
    }

    private var collocations: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("자주 쓰는 표현")
                .font(AppTypography.sectionTitle)
            ForEach(entry.collocations, id: \.self) { collocation in
                Text("· \(collocation)")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var example: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("OPIc에서 이렇게 말해보세요")
                .font(AppTypography.sectionTitle)
            Text(entry.exampleEn)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.exampleKo)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                playback.play(text: entry.exampleEn)
            } label: {
                Label("예문 듣기", systemImage: "speaker.fill")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.primary)
            }
            .buttonStyle(PressableButtonStyle())
            .minimumTouchTarget()
            .disabled(playback.isSpeaking)
        }
        .cardStyle()
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !entry.topics.isEmpty {
                FlowTags(values: entry.topics.map(\.label), filled: false)
            }
            if !entry.usageRoles.isEmpty {
                FlowTags(values: entry.usageRoles.map(\.label), filled: false)
            }
            if !entry.recommendedLevels.isEmpty {
                Text("권장 등급 " + entry.recommendedLevels.map(\.rawValue).joined(separator: " · "))
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    private func toggleSaved() {
        isSaved.toggle()
        try? persistence.setVocabularySaved(entryID: entry.id, isSaved: isSaved)
    }
}
