import SwiftUI

/// 단어 학습 카드. 뜻을 먼저 떠올리고(1단계), 확인한 뒤(2단계) 스스로 판정한다.
///
/// 카드 묶음은 화면에 들어올 때 한 번 정해진다. 답할 때마다 목록이 줄어들면
/// 남은 개수가 눈앞에서 흔들린다.
///
/// 발음은 기기 내장 TTS(`PromptPlaybackService`)다 — 네트워크·AI·데일리 토큰과 무관하다.
struct VocabularyStudyView: View {
    let title: String
    let entries: [VocabularyEntry]
    let persistence: PersistenceService

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = PromptPlaybackService()
    @State private var index = 0
    @State private var isRevealed = false
    @State private var knownCount = 0

    private var current: VocabularyEntry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else if let current {
                card(current)
            } else {
                summary
            }
        }
        .navigationTitle(title)
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

    private var progressLine: some View {
        Text("\(index + 1) / \(entries.count)")
            .font(AppTypography.footnote)
            .foregroundStyle(AppPalette.secondaryInk)
            .accessibilityLabel("\(entries.count)개 중 \(index + 1)번째")
    }

    private func termBlock(_ entry: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(entry.type.label)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.primary)
            Text(entry.term)
                .font(AppTypography.title)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            pronunciationButton(entry)
        }
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
        try? persistence.recordVocabularyAnswer(entryID: entry.id, knewIt: knewIt)
        if knewIt { knownCount += 1 }
        playback.stop()
        isRevealed = false
        index += 1
    }

    // MARK: 마무리 · 빈 상태

    private var summary: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppPalette.primary)
            Text("\(entries.count)개를 모두 봤어요")
                .font(AppTypography.cardTitle)
            Text("알아요 \(knownCount)개 · 몰라요 \(entries.count - knownCount)개")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
            PrimaryButton(title: "단어장으로 돌아가기") { dismiss() }
                .padding(.top, AppSpacing.md)
        }
        .padding(AppSpacing.lg)
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
