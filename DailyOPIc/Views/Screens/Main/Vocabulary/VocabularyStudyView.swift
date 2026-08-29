import SwiftUI
import SwiftData

/// 학습 세션의 종류. 오늘의 단어와 복습은 진행도도 마무리 문구도 섞이지 않는다.
/// AI 맞춤 세트도 같은 카드·같은 복습 엔진을 쓴다 — 다른 건 제목뿐이다.
enum VocabularyStudyKind {
    case newWords
    case review
    case aiSet

    var title: String {
        switch self {
        case .newWords: "오늘의 단어"
        case .review: "오늘 복습"
        case .aiSet: "AI 맞춤 단어"
        }
    }

    var completionTitle: String {
        switch self {
        case .newWords: "오늘의 단어 완료"
        case .review: "오늘 복습 완료"
        case .aiSet: "AI 맞춤 단어 완료"
        }
    }

    func completionMessage(count: Int) -> String {
        switch self {
        case .newWords: "\(count)개의 단어와 표현을 학습했어요."
        case .review: "\(count)개의 표현을 복습했어요."
        case .aiSet: "\(count)개의 맞춤 단어와 표현을 학습했어요."
        }
    }
}

/// 단어 학습 카드. 뜻을 먼저 떠올리고(1단계), 확인한 뒤(2단계) 스스로 판정한다.
///
/// 순서는 `VocabularyStudySession`이 정한다 — 화면은 큐를 직접 주무르지 않는다.
/// 틀린 항목은 세션 안에서 한 번 더 나오고, 그 이상은 나오지 않는다.
///
/// 발음은 기기 내장 TTS(`PromptPlaybackService`)다 — 네트워크·AI·데일리 토큰과 무관하다.
struct VocabularyStudyView: View {
    let kind: VocabularyStudyKind
    let persistence: PersistenceService
    /// 하루 경계는 학습 계획 타임존을 따른다.
    let timeZone: TimeZone

    @Environment(\.dismiss) private var dismiss
    /// 저장 여부는 카드 안에서 켜고 끌 수 있다(P14.5). 화면이 따로 들고 있지 않고
    /// 저장소를 그대로 읽는다 — 학습 상태와 같은 기록 하나(`VocabularyStateRecord`)다.
    @Query private var states: [VocabularyStateRecord]
    @StateObject private var playback = PromptPlaybackService()
    @State private var session: VocabularyStudySession
    @State private var isRevealed = false
    /// 세션이 처음 받은 항목 수. 진행도 표시("3 / 10")의 분모다.
    private let plannedCount: Int

    init(
        kind: VocabularyStudyKind,
        entries: [VocabularyEntry],
        persistence: PersistenceService,
        timeZone: TimeZone
    ) {
        self.kind = kind
        self.persistence = persistence
        self.timeZone = timeZone
        plannedCount = entries.count
        _session = State(initialValue: VocabularyStudySession(entries: entries))
    }

    var body: some View {
        Group {
            if plannedCount == 0 {
                emptyState
            } else if let current = session.current {
                card(current)
            } else {
                summary
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { playback.stop() }
    }

    // MARK: 카드

    private func card(_ entry: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            progressLine
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    termBlock(entry)
                    if isRevealed {
                        meaningBlock(entry)
                    } else {
                        Text("뜻을 떠올려보세요.")
                            .font(AppTypography.body)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, AppSpacing.lg)
            }
            controls(entry)
        }
        .padding(AppSpacing.lg)
    }

    /// 다시 나온 카드는 진행도를 되돌리지 않는다 — 이미 답한 개수를 센다.
    private var progressLine: some View {
        Text("\(session.attemptedCount) / \(plannedCount)")
            .font(AppTypography.footnote)
            .foregroundStyle(AppPalette.secondaryInk)
            .accessibilityLabel("\(plannedCount)개 중 \(session.attemptedCount)개 완료")
    }

    private func termBlock(_ entry: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.type.label)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.primary)
                Spacer(minLength: 0)
                saveButton(entry)
            }
            Text(entry.term)
                .font(AppTypography.title)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            pronunciationButton(entry)
        }
    }

    private func isSaved(_ entry: VocabularyEntry) -> Bool {
        states.first { $0.entryID == entry.id }?.isSaved ?? false
    }

    /// 카드에서 바로 저장하기(P14.5). 저장은 학습 판정과 **별개 채널**이다 —
    /// 저장했다고 익힘이 되지 않고, 저장을 풀어도 복습 기록은 그대로 남는다.
    private func saveButton(_ entry: VocabularyEntry) -> some View {
        let saved = isSaved(entry)
        return Button {
            try? persistence.setVocabularySaved(entryID: entry.id, isSaved: !saved)
        } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(AppPalette.primary)
        }
        .buttonStyle(PressableButtonStyle())
        .minimumTouchTarget()
        .accessibilityLabel(saved ? "저장 해제" : "저장")
        .accessibilityAddTraits(saved ? [.isSelected] : [])
    }

    /// 발음 듣기. 기기 음성이라 무료이고, 반복 재생에 제한이 없다.
    private func pronunciationButton(_ entry: VocabularyEntry) -> some View {
        Button {
            playback.play(text: entry.term)
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: playback.isSpeaking ? "speaker.wave.2.fill" : "speaker.fill")
                    .symbolEffect(.variableColor, isActive: playback.isSpeaking)
                Text("발음 듣기")
                    .font(.subheadline.weight(.semibold))
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

    private func meaningBlock(_ entry: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(entry.meaningKo)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.collocations.isEmpty {
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
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("OPIc에서 이렇게 말해보세요")
                    .font(AppTypography.sectionTitle)
                Text(entry.exampleEn)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                // 한국어 번역은 보조 정보다. 영어 문장보다 앞서지 않는다.
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
        }
    }

    /// 버튼으로만 조작한다. 제스처만으로 넘기게 만들지 않는다(§9 접근성).
    @ViewBuilder
    private func controls(_ entry: VocabularyEntry) -> some View {
        if isRevealed {
            HStack(spacing: AppSpacing.sm) {
                answerButton(title: "몰라요", isPrimary: false) { answer(entry, knewIt: false) }
                answerButton(title: "알아요", isPrimary: true) { answer(entry, knewIt: true) }
            }
        } else {
            PrimaryButton(title: "뜻 보기") { isRevealed = true }
        }
    }

    private func answerButton(
        title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(isPrimary ? AppPalette.actionOnPrimary : AppPalette.primary)
                .background(isPrimary ? AppPalette.primary : AppPalette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func answer(_ entry: VocabularyEntry, knewIt: Bool) {
        // 저장 실패가 학습을 막지는 않는다. 다음 카드로는 넘어간다.
        try? persistence.recordVocabularyAnswer(
            entryID: entry.id,
            knewIt: knewIt,
            timeZone: timeZone
        )
        playback.stop()
        isRevealed = false
        session.answer(knewIt: knewIt)
    }

    // MARK: 마무리 · 빈 상태

    /// 점수도 등급도 없다. 무엇을 했고 무엇을 다시 볼지만 알려 준다.
    private var summary: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppPalette.primary)
            Text(kind.completionTitle)
                .font(AppTypography.cardTitle)
            Text(kind.completionMessage(count: session.attemptedCount))
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppSpacing.lg) {
                summaryCount(title: "알아요", value: session.knownCount)
                summaryCount(title: "다시 볼 표현", value: session.forgottenCount)
            }
            if kind == .newWords {
                extraStudyCTA
                    .padding(.top, AppSpacing.md)
            }
            PrimaryButton(title: "단어장으로 돌아가기") { dismiss() }
                .padding(.top, kind == .newWords ? 0 : AppSpacing.md)
        }
        .padding(AppSpacing.lg)
    }

    /// 오늘 몫을 끝낸 뒤의 다음 걸음(P14.5). 이번 단계에서는 **아직 열지 않는다** —
    /// 누를 수 없는 버튼이라 이 화면에서 AI가 불리는 일도, 데일리 토큰이 나가는 일도 없다.
    /// 다음 단계에서 여기에 "주제 고르기 → 20개 불러오기"가 붙는다.
    private var extraStudyCTA: some View {
        VStack(spacing: AppSpacing.xs) {
            PrimaryButton(
                title: "오늘 \(VocabularyDailySet.dailyTarget)개 더 학습하기",
                isDisabled: true
            ) {}
            Text("다음 업데이트에서 열려요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
    }

    private func summaryCount(title: String, value: Int) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
            Text("\(value)")
                .font(AppTypography.cardTitle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)개")
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("지금 학습할 단어가 없어요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
            PrimaryButton(title: "단어장으로 돌아가기") { dismiss() }
        }
        .padding(AppSpacing.lg)
    }
}
