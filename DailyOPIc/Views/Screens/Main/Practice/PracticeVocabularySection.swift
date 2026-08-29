import SwiftData
import SwiftUI

/// 데일리 질문 아래에서 단어장으로 건너가는 자리(P14.4).
enum PracticeVocabularyRoute: Hashable {
    /// 주제를 알 때 — 단어장의 주제 화면을 그대로 연다.
    case topic(VocabularyTopic)
    /// 주제를 모를 때 — 방금 추천한 표현만 목록으로 본다(단어장의 목록 화면 재사용).
    case questionExpressions([VocabularyEntry])
}

/// 질문 카드 바로 아래 붙는 "이 질문에 써볼 표현"(P14.4).
///
/// **여기 보이는 것은 전부 무료다.** 추천은 이 기기 안의 계산이고(네트워크도 AI도
/// 부르지 않는다) 재료는 앱에 담긴 시드와 이미 받아 둔 AI 세트뿐이다. 표현을 열어
/// 보는 것도, 단어장으로 건너가는 것도, 듣는 것도 토큰을 쓰지 않는다.
///
/// 토큰이 나가는 곳은 하나뿐 — 맨 아래 "같은 주제 표현 30개 만들기"를 눌러 P14.2
/// 생성을 시작할 때 1개다. 화면이 추천을 보여 준다는 이유로는 아무것도 나가지 않는다.
struct PracticeVocabularySection: View {
    let question: GeneratedQuestion
    let targetLevel: OPIcLevel?

    @Environment(AppEnvironment.self) private var environment
    @Query private var states: [VocabularyStateRecord]
    @Query(sort: \VocabularyGeneratedSetRecord.createdAt, order: .reverse)
    private var generatedSets: [VocabularyGeneratedSetRecord]
    @State private var isPresentingGeneration = false
    /// 누르기 전까지 만들지 않는다. 데일리 화면에 네트워크 클라이언트를 붙들 이유가 없다.
    @State private var generation: VocabularyGenerationViewModel?

    private var stateByID: [String: VocabularyStateRecord] {
        Dictionary(states.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 이 기기가 아는 단어 전부. 단어장 홈과 같은 재료다.
    private var allEntries: [VocabularyEntry] {
        VocabularyCatalog.all + generatedSets.flatMap(\.entries)
    }

    private var topic: VocabularyTopic? { VocabularyQuestionTopicMap.topic(for: question) }

    private var recommendations: [VocabularyEntry] {
        VocabularyQuestionRecommender.recommend(
            questionID: question.id,
            topic: topic,
            targetLevel: targetLevel,
            entries: allEntries
        )
    }

    var body: some View {
        let entries = recommendations
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("이 질문에 써볼 표현")
                    .font(AppTypography.callout.weight(.semibold))
                    .foregroundStyle(AppPalette.ink)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(entries) { entry in
                            NavigationLink(value: entry) { chip(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                NavigationLink(value: listRoute(entries)) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("단어장에서 보기")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.primary)
                }
                .minimumTouchTarget()

                generationCTA
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .navigationDestination(for: PracticeVocabularyRoute.self, destination: destination)
            .navigationDestination(for: VocabularyEntry.self) { entry in
                VocabularyEntryDetailView(
                    entry: entry,
                    state: stateByID[entry.id],
                    persistence: environment.persistence
                )
            }
            .sheet(isPresented: $isPresentingGeneration) {
                if let generation {
                    VocabularyGenerationSheet(
                        viewModel: generation,
                        targetLevel: environment.preferences.targetLevel ?? .IM2,
                        existingTerms: generatedSets.flatMap { $0.entries.map(\.term) },
                        // 주제를 알면 미리 골라 둔다. 모르면 아무것도 골라 두지 않는다 —
                        // 넘겨짚은 주제로 몰래 만들어 주지 않는다.
                        source: .dailyQuestion(topic: topic)
                    )
                }
            }
        }
    }

    private func chip(_ entry: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.term)
                .font(AppTypography.footnote.weight(.semibold))
                .foregroundStyle(AppPalette.ink)
            Text(entry.meaningKo)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: 240, alignment: .leading)
        .background(AppPalette.primarySoft)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.term), \(entry.type.label), \(entry.meaningKo)")
    }

    /// 30개 만들기는 P14.2 생성 그대로다 — 이 화면이 요청 경로를 새로 만들지 않는다.
    private var generationCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("더 다양한 표현이 필요해요?")
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            Button {
                if generation == nil {
                    generation = VocabularyGenerationViewModel(environment: environment)
                }
                isPresentingGeneration = true
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "sparkles").font(.caption)
                    Text(topic.map { "\($0.label) 표현 30개 만들기" } ?? "AI 맞춤 표현 30개 만들기")
                        .font(AppTypography.footnote)
                    Spacer(minLength: AppSpacing.sm)
                    // 누르기 전에 비용을 말한다.
                    DailyTokenIcon(size: 16)
                    Text("\(VocabularyGenerationViewModel.tokenCost)")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(AppPalette.primary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.primarySoft, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .minimumTouchTarget()
            .accessibilityLabel(
                "AI 맞춤 표현 30개 만들기, 데일리 토큰 \(VocabularyGenerationViewModel.tokenCost)개 사용"
            )
        }
    }

    @ViewBuilder
    private func destination(_ route: PracticeVocabularyRoute) -> some View {
        switch route {
        case let .topic(topic):
            VocabularyTopicView(topic: topic, states: stateByID)
        case let .questionExpressions(entries):
            VocabularyMyWordsView(
                title: "이 질문에 써볼 표현",
                emptyMessage: "추천할 표현을 찾지 못했어요.",
                entries: entries,
                states: stateByID
            )
        }
    }

    private func listRoute(_ entries: [VocabularyEntry]) -> PracticeVocabularyRoute {
        topic.map { .topic($0) } ?? .questionExpressions(entries)
    }
}
