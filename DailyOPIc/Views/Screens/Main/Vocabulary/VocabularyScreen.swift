import SwiftUI
import SwiftData

/// 단어장 탭 안의 이동 경로. 탭이 이미 갖고 있는 NavigationStack을 그대로 쓴다.
enum VocabularyRoute: Hashable {
    /// 오늘의 주제 고르기(P14.5). 여기서 고른 뒤에야 오늘의 단어가 배정된다.
    case todayTopicPicker
    case todayStudy
    case review
    case topic(VocabularyTopic)
    case saved
    case mastered
    /// AI 맞춤 단어장(P14.2). 여는 것도 학습하는 것도 토큰을 쓰지 않는다.
    case generatedSets
    case generatedSet(setID: String)
    case generatedStudy(setID: String)
    /// AI 말하기 코치(P14.3). 화면을 여는 것도 녹음·전사도 토큰을 쓰지 않는다 —
    /// 토큰은 그 안에서 "AI에게 분석받기"를 눌렀을 때만 나간다.
    case speakingCoach(VocabularyEntry)
}

/// 단어장 홈. "오늘 뭘 외우지?"에 답하는 것이 이 화면의 전부다.
/// 통계는 여기 두지 않는다 — 통계 탭이 이미 그 일을 한다.
///
/// 무료 영역(오늘의 단어 · 오늘 복습 · 주제별 · 검색 · 내 단어)은 **네트워크도 AI도
/// 부르지 않는다.** 단어 데이터는 앱에 담긴 시드(`VocabularyCatalog`)와 이미 받아 둔
/// AI 세트이고, 내 상태는 이 기기의 SwiftData다.
///
/// 토큰이 나가는 곳은 둘뿐이다: "AI 맞춤 단어장"을 **만들 때 1개**(P14.2)와,
/// 단어 상세의 "직접 말해보기"에서 **AI 코칭을 요청할 때 1개**(P14.3).
/// 이미 만든 세트를 다시 여는 것도, 녹음·전사도, 받아 둔 코칭을 다시 보는 것도 공짜다.
struct VocabularyScreen: View {
    let preferences: AppPreferences
    let persistence: PersistenceService

    @Environment(AppEnvironment.self) private var environment
    @Query private var states: [VocabularyStateRecord]
    @Query(sort: \VocabularyGeneratedSetRecord.createdAt, order: .reverse)
    private var generatedSets: [VocabularyGeneratedSetRecord]
    @State private var query = ""

    /// 하루 경계는 학습 계획 타임존을 따른다 — 플래너의 "오늘"과 단어장의 "오늘"이
    /// 다른 날을 가리키면 안 된다.
    private var timeZone: TimeZone { preferences.studyPlanSettings?.timeZone ?? .current }
    private var todayLocalDate: String { LocalCalendarDate.text(from: .now, timeZone: timeZone) }

    private var stateByID: [String: VocabularyStateRecord] {
        Dictionary(states.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 이 기기가 아는 단어 전부 = 번들 시드 + 이미 받아 둔 AI 세트.
    /// 저장·익힘·복습·검색은 전부 이 목록에서 항목을 되찾는다 — AI로 만든 단어라고
    /// 내 단어 목록에서 빠지지 않는다.
    private var allEntries: [VocabularyEntry] {
        VocabularyCatalog.all + generatedSets.flatMap(\.entries)
    }

    /// 오늘 몫으로 이미 정해진 배정. 어제 것이면 없는 것과 같다.
    /// 여기가 `nil`인 동안에만 주제를 묻는다 — 있으면 다시 묻지 않고 그대로 쓴다.
    private var todaySet: VocabularyDailySet? {
        guard let set = preferences.vocabularyDailySet, set.covers(todayLocalDate) else {
            return nil
        }
        return set
    }

    /// 오늘의 새 단어. 배정은 사용자가 주제를 고른 그 순간에만 만들어진다.
    private var todayEntries: [VocabularyEntry] {
        guard let todaySet else { return [] }
        return VocabularyCatalog.entries(ids: todaySet.entryIDs, in: allEntries)
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
        return VocabularyCatalog.entries(ids: remaining, in: allEntries)
    }

    /// 복습할 차례가 된 항목. 예정일이 오늘이거나 지난 것만 — 미래 일정과 아직 배우지
    /// 않은 단어는 들어오지 않는다. 익힘의 30일 유지 복습은 들어온다.
    private var dueEntries: [VocabularyEntry] {
        let dueIDs = VocabularyDailyProgress.dueIDs(states: states, today: todayLocalDate)
        return VocabularyCatalog.entries(ids: dueIDs, in: allEntries)
    }

    private var savedEntries: [VocabularyEntry] {
        VocabularyCatalog.entries(ids: states.filter(\.isSaved).map(\.entryID), in: allEntries)
    }

    private var masteredEntries: [VocabularyEntry] {
        VocabularyCatalog.entries(
            ids: states.filter { $0.status == .mastered }.map(\.entryID),
            in: allEntries
        )
    }

    /// 검색도 AI 세트를 포함한다. 화면을 하나 더 만들지 않는다.
    private var searchResults: [VocabularyEntry] { VocabularyCatalog.search(query, in: allEntries) }

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
    }

    // MARK: 홈

    private var home: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header
            todayCard
            reviewCard
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
            if todaySet == nil {
                // 하루의 첫 시작 전에는 아무것도 배정하지 않는다(P14.5). 주제는 사용자가 고른다.
                Text("오늘 공부할 주제를 골라 주세요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                NavigationLink(value: VocabularyRoute.todayTopicPicker) {
                    primaryLabel("주제 고르고 시작하기", systemImage: "square.grid.2x2.fill")
                }
                .buttonStyle(PressableButtonStyle())
            } else if todayEntries.isEmpty {
                Text("새로 배울 단어를 다 봤어요. 오늘 복습으로 이어가 보세요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                todayTopicLine
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

    /// 오늘의 주제와 구성. 고른 주제만으로 하루 목표를 채우지 못한 날에는 그 사실을
    /// 그대로 적는다 — 다른 주제에서 채운 단어를 고른 주제인 척 보여주지 않는다.
    @ViewBuilder
    private var todayTopicLine: some View {
        if let topic = todaySet?.topic {
            let onTopic = todayEntries.filter { $0.topics.contains(topic) }.count
            Text(
                onTopic == todayEntries.count
                ? topic.label
                : "\(topic.label) \(onTopic)개 · 다른 주제 \(todayEntries.count - onTopic)개"
            )
            .font(AppTypography.callout)
            .foregroundStyle(AppPalette.secondaryInk)
        }
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

    /// 주제 탐색(`주제별 단어`)과 AI 맞춤 단어장 만들기는 이 홈에서 내렸다(P14.5.1).
    /// 단어장의 주인공은 "오늘의 단어" 하나이고, 주제는 그 시작에서 고르는 입력값이다.
    /// 두 흐름의 화면·라우트·생성 아키텍처는 지우지 않았다 —
    /// 주제 목록은 데일리 질문의 추천(P14.4)이, AI 30개 만들기는 같은 화면의 CTA가 계속 쓴다.

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
        case .todayTopicPicker:
            VocabularyTodayTopicPicker(
                target: VocabularyDailySet.dailyTarget,
                availableCounts: availableTopicCounts,
                onSelect: assignToday
            )
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
        case .generatedSets:
            VocabularyGeneratedSetListView(sets: generatedSets)
        case let .generatedSet(setID):
            if let record = generatedSet(setID) {
                VocabularyGeneratedSetDetailView(record: record, states: stateByID)
            }
        case let .speakingCoach(entry):
            VocabularySpeakingCoachView(
                entry: entry,
                environment: environment,
                targetLevel: preferences.targetLevel
            )
        case let .generatedStudy(setID):
            // AI 항목도 같은 학습 카드·같은 복습 엔진을 쓴다(별도 알고리즘 없음).
            VocabularyStudyView(
                kind: .aiSet,
                entries: generatedSet(setID)?.entries ?? [],
                persistence: persistence,
                timeZone: timeZone
            )
        }
    }

    private func generatedSet(_ setID: String) -> VocabularyGeneratedSetRecord? {
        generatedSets.first { $0.setID == setID }
    }

    // MARK: 오늘의 배정

    /// 하루에 한 번, 사용자가 주제를 고른 그 순간에만 정한다. 같은 날 다시 들어오면
    /// 이미 배정된 목록을 그대로 쓴다 — 주제를 다시 묻지도, 항목이 조용히 바뀌지도 않는다.
    ///
    /// 후보는 **한 번도 학습하지 않은** 항목뿐이다. 이미 배운 단어는 복습 시스템의 몫이라
    /// 새 단어인 척 돌아오지 않는다. 남은 후보가 목표보다 적으면 그만큼만 준다.
    ///
    /// 기기 안 계산이다. AI도 네트워크도 데일리 토큰도 쓰지 않는다.
    private func assignToday(topic: VocabularyTopic) {
        let today = todayLocalDate
        if let existing = preferences.vocabularyDailySet, existing.covers(today) { return }
        preferences.vocabularyDailySet = VocabularyDailySetPlanner.assign(
            localDate: today,
            catalog: VocabularyCatalog.all,
            excluding: VocabularyDailyProgress.studiedIDs(states: states),
            targetLevel: preferences.targetLevel,
            topic: topic
        )
    }

    /// 주제별로 오늘 배정될 수 있는 새 단어 수. 이미 학습한 항목은 빼고 센다 —
    /// 고르기 전에 실제로 몇 개가 나올지 그대로 보여준다.
    private var availableTopicCounts: [VocabularyTopic: Int] {
        let studied = VocabularyDailyProgress.studiedIDs(states: states)
        return VocabularyCatalog.topics.reduce(into: [:]) { counts, topic in
            counts[topic] = VocabularyCatalog.entries(topic: topic)
                .filter { !studied.contains($0.id) }.count
        }
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

/// 오늘의 주제 고르기(P14.5). 하루의 첫 시작 전에 딱 한 번 지나는 화면이다.
///
/// 주제 목록은 단어장이 이미 쓰는 `VocabularyTopic` 그대로다. 고르는 순간 오늘의
/// 묶음이 기기에서 정해진다 — 네트워크도 AI도 데일리 토큰도 쓰지 않는다.
struct VocabularyTodayTopicPicker: View {
    let target: Int
    /// 주제별로 오늘 나올 수 있는 새 단어 수. 목표보다 적으면 그 사실을 미리 말한다.
    let availableCounts: [VocabularyTopic: Int]
    let onSelect: (VocabularyTopic) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("오늘 공부할 주제를 골라 주세요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: AppSpacing.sm),
                              GridItem(.flexible(), spacing: AppSpacing.sm)],
                    spacing: AppSpacing.sm
                ) {
                    ForEach(VocabularyCatalog.topics) { topic in
                        Button {
                            onSelect(topic)
                            dismiss()
                        } label: {
                            label(topic)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(accessibilityText(topic))
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("오늘의 주제")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ topic: VocabularyTopic) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(topic.label)
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.ink)
            Text(subtitle(topic))
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }

    /// 이 주제만으로 목표를 채우지 못하면 고르기 **전에** 말한다. 고른 뒤에 다른 주제
    /// 단어를 이 주제인 척 보여주지 않기 위해서다.
    private func subtitle(_ topic: VocabularyTopic) -> String {
        let available = availableCounts[topic] ?? 0
        if available >= target { return "\(target)개" }
        return "\(available)개 + 다른 주제 \(target - available)개"
    }

    private func accessibilityText(_ topic: VocabularyTopic) -> String {
        "\(topic.label), \(subtitle(topic))"
    }
}
