import SwiftUI
import SwiftData

/// 단어장 탭 안의 이동 경로. 탭이 이미 갖고 있는 NavigationStack을 그대로 쓴다.
enum VocabularyRoute: Hashable {
    case todayStudy
    case review
    case topic(VocabularyTopic)
    case saved
    case mastered
}

/// 단어장 홈. "오늘 뭘 외우지?"에 답하는 것이 이 화면의 전부다.
/// 통계는 여기 두지 않는다 — 통계 탭이 이미 그 일을 한다.
///
/// 이 화면과 그 아래 모든 화면은 **네트워크도 AI도 부르지 않는다.** 단어 데이터는
/// 앱에 담긴 시드(`VocabularyCatalog`)이고, 내 상태는 이 기기의 SwiftData다.
struct VocabularyScreen: View {
    let preferences: AppPreferences
    let persistence: PersistenceService

    @Query private var states: [VocabularyStateRecord]
    @State private var query = ""

    /// 하루 경계는 학습 계획 타임존을 따른다 — 플래너의 "오늘"과 단어장의 "오늘"이
    /// 다른 날을 가리키면 안 된다.
    private var timeZone: TimeZone { preferences.studyPlanSettings?.timeZone ?? .current }
    private var todayLocalDate: String { LocalCalendarDate.text(from: .now, timeZone: timeZone) }

    private var stateByID: [String: VocabularyStateRecord] {
        Dictionary(states.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 오늘의 새 단어. 배정이 없거나 어제 것이면 화면이 뜰 때 다시 배정한다.
    private var todayEntries: [VocabularyEntry] {
        guard let set = preferences.vocabularyDailySet, set.covers(todayLocalDate) else {
            return []
        }
        return VocabularyCatalog.entries(ids: set.entryIDs)
    }

    /// 오늘 한 번이라도 답한 항목 수. "3 / 10"의 분자다.
    /// 저장된 기록에서 세므로 같은 세션에서 다시 만난 카드가 진행도를 두 번 올리지 않고,
    /// 앱을 껐다 켜도 같은 숫자가 나온다.
    private var todayStudiedCount: Int {
        VocabularyDailyProgress.attemptedCount(
            assigned: todayEntries.map(\.id),
            states: stateByID,
            today: todayLocalDate
        )
    }

    /// 오늘 아직 답하지 않은 항목. "이어서 학습"은 여기서부터 이어진다.
    private var todayRemaining: [VocabularyEntry] {
        let remaining = VocabularyDailyProgress.remainingIDs(
            assigned: todayEntries.map(\.id),
            states: stateByID,
            today: todayLocalDate
        )
        return VocabularyCatalog.entries(ids: remaining)
    }

    /// 복습할 차례가 된 항목. 예정일이 오늘이거나 지난 것만 — 미래 일정과 아직 배우지
    /// 않은 단어는 들어오지 않는다. 익힘의 30일 유지 복습은 들어온다.
    private var dueEntries: [VocabularyEntry] {
        let dueIDs = VocabularyDailyProgress.dueIDs(states: states, today: todayLocalDate)
        return VocabularyCatalog.entries(ids: dueIDs)
    }

    private var savedEntries: [VocabularyEntry] {
        VocabularyCatalog.entries(ids: states.filter(\.isSaved).map(\.entryID))
    }

    private var masteredEntries: [VocabularyEntry] {
        VocabularyCatalog.entries(ids: states.filter { $0.status == .mastered }.map(\.entryID))
    }

    private var searchResults: [VocabularyEntry] { VocabularyCatalog.search(query) }

    var body: some View {
        ScrollView {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                home
            } else {
                searchList
            }
        }
        .searchable(text: $query, prompt: "단어나 뜻으로 검색")
        .navigationDestination(for: VocabularyRoute.self, destination: destination)
        .navigationDestination(for: VocabularyEntry.self) { entry in
            VocabularyEntryDetailView(
                entry: entry,
                state: stateByID[entry.id],
                persistence: persistence
            )
        }
        .onAppear(perform: assignTodayIfNeeded)
    }

    // MARK: 홈

    private var home: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header
            todayCard
            reviewCard
            topicsSection
            myWordsSection
        }
        .padding(AppSpacing.lg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("단어장")
                .font(AppTypography.title)
            // 목표 등급은 여기서 새로 정하지 않는다. 온보딩에서 정한 값을 그대로 읽는다.
            if let targetLevel = preferences.targetLevel {
                Text("목표 \(targetLevel.rawValue)에 맞춰 추천해요")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                Text("OPIc 답변에서 바로 쓰는 표현만 모았어요")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("오늘의 단어")
                .font(AppTypography.sectionTitle)
            if todayEntries.isEmpty {
                Text("새로 배울 단어를 다 봤어요. 주제별 단어에서 더 골라 보세요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                Text("\(todayStudiedCount) / \(todayEntries.count)")
                    .font(AppTypography.title)
                    .accessibilityLabel(
                        "오늘의 단어 \(todayEntries.count)개 중 \(todayStudiedCount)개 완료"
                    )
                if todayRemaining.isEmpty {
                    Label("오늘 학습 완료", systemImage: "checkmark.circle.fill")
                        .font(AppTypography.callout)
                        .foregroundStyle(AppPalette.primary)
                } else {
                    NavigationLink(value: VocabularyRoute.todayStudy) {
                        primaryLabel(
                            todayStudiedCount > 0 ? "이어서 학습" : "오늘의 단어 시작",
                            systemImage: "book.closed.fill"
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .cardStyle()
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("오늘 복습")
                .font(AppTypography.sectionTitle)
            if dueEntries.isEmpty {
                Text("오늘 복습할 단어가 없어요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                Text("\(dueEntries.count)개")
                    .font(AppTypography.title)
                    .accessibilityLabel("복습할 단어 \(dueEntries.count)개")
                NavigationLink(value: VocabularyRoute.review) {
                    primaryLabel("복습하기", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .cardStyle()
    }

    /// 시드에 실제로 단어가 있는 주제만 보여준다. 빈 칸을 만들지 않는다.
    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("주제별 단어")
                .font(AppTypography.sectionTitle)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppSpacing.sm),
                          GridItem(.flexible(), spacing: AppSpacing.sm)],
                spacing: AppSpacing.sm
            ) {
                ForEach(VocabularyCatalog.topics) { topic in
                    let count = VocabularyCatalog.entries(topic: topic).count
                    NavigationLink(value: VocabularyRoute.topic(topic)) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(topic.label)
                                .font(AppTypography.callout)
                                .foregroundStyle(AppPalette.ink)
                            Text("\(count)개")
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppPalette.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                        .background(AppPalette.surface)
                        .clipShape(
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("\(topic.label) 단어 \(count)개")
                }
            }
        }
    }

    private var myWordsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("내 단어")
                .font(AppTypography.sectionTitle)
            VStack(spacing: 0) {
                myWordsRow(
                    title: "저장한 단어",
                    systemImage: "bookmark.fill",
                    count: savedEntries.count,
                    route: .saved
                )
                Divider()
                myWordsRow(
                    title: "익힌 단어",
                    systemImage: "checkmark.seal.fill",
                    count: masteredEntries.count,
                    route: .mastered
                )
            }
            .cardStyle()
        }
    }

    private func myWordsRow(
        title: String,
        systemImage: String,
        count: Int,
        route: VocabularyRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(AppPalette.primary)
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 0)
                Text("\(count)개")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .accessibilityLabel("\(title) \(count)개")
    }

    // MARK: 검색

    /// AI를 쓰지 않는 로컬 검색이다. 영어 표현·한국어 뜻·예문 안의 단어까지 찾는다.
    private var searchList: some View {
        LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
            if searchResults.isEmpty {
                Text("\"\(query)\"와 맞는 단어가 없어요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .padding(.top, AppSpacing.lg)
            } else {
                Text("\(searchResults.count)개 찾았어요")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                ForEach(searchResults) { entry in
                    NavigationLink(value: entry) {
                        VocabularyEntryRow(entry: entry, state: stateByID[entry.id])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.lg)
    }

    // MARK: 경로

    @ViewBuilder
    private func destination(_ route: VocabularyRoute) -> some View {
        switch route {
        case .todayStudy:
            VocabularyStudyView(
                kind: .newWords,
                entries: todayRemaining,
                persistence: persistence,
                timeZone: timeZone
            )
        case .review:
            VocabularyStudyView(
                kind: .review,
                entries: dueEntries,
                persistence: persistence,
                timeZone: timeZone
            )
        case let .topic(topic):
            VocabularyTopicView(topic: topic, states: stateByID)
        case .saved:
            VocabularyMyWordsView(
                title: "저장한 단어",
                emptyMessage: "아직 저장한 단어가 없어요. 단어를 열어 저장해 보세요.",
                entries: savedEntries,
                states: stateByID
            )
        case .mastered:
            VocabularyMyWordsView(
                title: "익힌 단어",
                emptyMessage: "아직 익힌 단어가 없어요. 오늘의 단어부터 시작해 보세요.",
                entries: masteredEntries,
                states: stateByID
            )
        }
    }

    // MARK: 오늘의 배정

    /// 하루에 한 번만 정한다. 같은 날 다시 들어와도 이미 배정된 목록을 그대로 쓴다 —
    /// 학습을 시작한 뒤 항목이 조용히 바뀌지 않는다.
    ///
    /// 후보는 **한 번도 학습하지 않은** 항목뿐이다. 이미 배운 단어는 복습 시스템의 몫이라
    /// 새 단어인 척 돌아오지 않는다. 남은 후보가 10개보다 적으면 그만큼만 준다.
    private func assignTodayIfNeeded() {
        let today = todayLocalDate
        if let existing = preferences.vocabularyDailySet, existing.covers(today) { return }
        let studied = VocabularyDailyProgress.studiedIDs(states: states)
        preferences.vocabularyDailySet = VocabularyDailySetPlanner.assign(
            localDate: today,
            catalog: VocabularyCatalog.all,
            excluding: studied,
            targetLevel: preferences.targetLevel
        )
    }

    /// `PrimaryButton`은 Button을 직접 만들어서 NavigationLink 라벨로 쓸 수 없다.
    /// 같은 토큰(높이·색·모서리)만 그대로 가져와 링크 라벨을 만든다.
    private func primaryLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .foregroundStyle(AppPalette.actionOnPrimary)
        .background(AppPalette.primary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}
