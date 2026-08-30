import SwiftUI
import SwiftData

/// 단어장 탭 안의 이동 경로. 탭이 이미 갖고 있는 NavigationStack을 그대로 쓴다.
enum VocabularyRoute: Hashable {
    /// 오늘의 주제 고르기(P14.5). 여기서 고른 뒤에야 오늘의 단어가 배정된다.
    case todayTopicPicker
    case todayStudy
    /// 오늘 배정된 단어 다시 보기(P14.5.2). 오늘 학습을 끝낸 뒤에만 나온다.
    case todayLearned
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

/// 단어장 홈 = **오늘의 단어** + 그 아래 작은 줄 하나(저장한 단어)다.
/// 검색·큰 제목·복습 진입점·주제 둘러보기·AI 맞춤 단어장·익힌 단어는 홈에서 내렸다 —
/// 통계는 통계 탭이, 학습 기록은 플래너 캘린더가 이미 그 일을 한다.
///
/// 저장한 단어만 돌아온 이유(P14.6): 오늘의 카드에서 **사용자가 직접 ♡를 누른** 단어는
/// 나중에 다시 찾아볼 수 있어야 한다. 두 번째 학습 카드가 아니라 작은 보조 줄이다.
///
/// 내린 것은 **홈의 진입점뿐이고 기능이 아니다**: 복습 엔진(`VocabularyReviewPolicy` ·
/// 예정일 · 익힘 · 복습 횟수)도, 저장·익힘 상태와 그 목록 화면도 그대로 살아 있다.
/// 오늘의 카드에서 저장하면 저장되고, 오늘 학습한 단어 보기에서 그 상태가 보인다.
///
/// 오늘의 기본 20개로 가는 길은 **전부 무료다**: 주제 고르기 · 배정 · 학습 · 뜻 보기 ·
/// 듣기 · 알아요/몰라요 · 저장 · 복습 상태 갱신 어느 것도 네트워크도 AI도 부르지 않는다.
/// 단어는 앱에 담긴 시드(`VocabularyCatalog`)와 이미 받아 둔 AI 세트이고,
/// 내 상태는 이 기기의 SwiftData다.
///
/// 토큰이 나가는 곳은 둘뿐이고, 둘 다 사용자가 직접 눌러야 시작한다:
///   - 단어 상세의 "직접 말해보기"에서 AI 코칭을 요청할 때 1개(P14.3)
///   - 오늘 20개를 **더 만들** 때 1개(P14.6). 만들어 둔 20개를 학습·저장·복습하는 것은 공짜다.
/// 시드에서 부족분을 뽑아 추가 20개인 척 공짜로 주는 경로는 없다 — 추가 20개는 언제나
/// 새로 만든 단어다.
struct VocabularyScreen: View {
    let preferences: AppPreferences
    let persistence: PersistenceService

    @Environment(AppEnvironment.self) private var environment
    /// 추가 20개를 만들 주제를 고르는 화면. 여는 것도 닫는 것도 0 토큰이다.
    @State private var isShowingExtraSheet = false
    @Query private var states: [VocabularyStateRecord]
    @Query(sort: \VocabularyGeneratedSetRecord.createdAt, order: .reverse)
    private var generatedSets: [VocabularyGeneratedSetRecord]

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

    /// 오늘 만든 추가 세트(P14.6), 최신이 먼저. 기본 20개(`vocabularyDailySet`)와는
    /// 완전히 별개다 — 추가 학습이 오늘의 배정을 덮어쓰지 않는다.
    private var todayExtraSets: [VocabularyGeneratedSetRecord] {
        generatedSets.filter {
            $0.purpose == .todayExtra
                && LocalCalendarDate.text(from: $0.createdAt, timeZone: timeZone) == todayLocalDate
        }
    }

    /// 지금 이어서 학습할 추가 묶음 = 가장 최근에 만든 것. 진행도는 이 묶음 것이다.
    private var extraEntries: [VocabularyEntry] { todayExtraSets.first?.entries ?? [] }

    private var extraStudiedCount: Int {
        VocabularyDailyProgress.attemptedCount(
            assigned: extraEntries.map(\.id),
            states: stateByID,
            today: todayLocalDate
        )
    }

    private var extraRemainingCount: Int {
        VocabularyDailyProgress.remainingIDs(
            assigned: extraEntries.map(\.id),
            states: stateByID,
            today: todayLocalDate
        ).count
    }

    /// 오늘 실제로 학습한 단어 전부 = 기본 배정 + 오늘 만든 추가 묶음에서 답한 것.
    /// 가장 최근 묶음만 보여주지 않는다 — 하루에 추가 20개를 여러 번 했으면 전부 나온다.
    /// 같은 단어가 두 곳에 있어도 한 줄이다.
    private var todayLearnedEntries: [VocabularyEntry] {
        let extras = todayExtraSets.flatMap(\.entries).filter {
            stateByID[$0.id]?.wasStudied(on: todayLocalDate) == true
        }
        var seen = Set<String>()
        return (todayEntries + extras).filter { seen.insert($0.id).inserted }
    }

    /// 중복 회피 힌트. 오늘 배정된 기본 단어 → 이미 받아 둔 AI 세트 → 이미 학습한 단어
    /// 순서로 담는다(상한은 요청 모델이 갖는다). 새 중복 판별 시스템을 만들지 않는다.
    private var extraExistingTerms: [String] {
        let studied = VocabularyDailyProgress.studiedIDs(states: states)
        let ordered = todayEntries
            + generatedSets.flatMap(\.entries)
            + allEntries.filter { studied.contains($0.id) }
        var seen = Set<String>()
        return ordered.map(\.term).filter { seen.insert($0.lowercased()).inserted }
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

    var body: some View {
        ScrollView { home }
            .sheet(isPresented: $isShowingExtraSheet) {
                VocabularyExtraSheet(
                    environment: environment,
                    targetLevel: preferences.targetLevel,
                    existingTerms: extraExistingTerms
                )
            }
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
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            todayCard
            savedRow
        }
        .padding(AppSpacing.lg)
    }

    /// 오늘의 단어 아래 작은 줄 하나(P14.6). 두 번째 학습 카드가 아니라 "카드에서 내가
    /// 눌러 저장한 단어를 나중에 다시 찾아보는 길"이다. 익힌 단어 · 주제별 둘러보기 ·
    /// 검색은 여전히 홈에 없다.
    private var savedRow: some View {
        NavigationLink(value: VocabularyRoute.saved) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "heart.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.primary)
                Text("저장한 단어")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 0)
                Text("\(savedEntries.count)개")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .accessibilityLabel("저장한 단어 \(savedEntries.count)개")
        .accessibilityHint("저장한 단어를 다시 봅니다")
    }

    /// 이 화면의 주인공. 하루의 상태는 셋뿐이다 — 아직 안 골랐다 / 하는 중 / 다 했다.
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
                Text("오늘 배정할 새 단어가 더 없어요.")
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
                    todayDoneActions
                } else {
                    NavigationLink(value: VocabularyRoute.todayStudy) {
                        primaryLabel(
                            todayStudiedCount > 0 ? "이어 학습하기" : "오늘의 단어 시작",
                            systemImage: "book.closed.fill"
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .cardStyle()
    }

    /// 오늘 몫을 다 끝낸 뒤. 방금 한 것을 되돌아보는 길과, 더 하고 싶을 때의 길을 함께 둔다.
    private var todayDoneActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("오늘 학습 완료", systemImage: "checkmark.circle.fill")
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.primary)
            NavigationLink(value: VocabularyRoute.todayLearned) {
                primaryLabel("오늘 학습한 단어 보기", systemImage: "list.bullet")
            }
            .buttonStyle(PressableButtonStyle())
            extraWordsCTA
        }
    }

    /// "오늘 20개 더"(P14.6). 여기서 값이 나가는 자리는 **새 단어를 만들 때 1개** 하나뿐이다.
    /// 이 버튼을 누르면 주제를 고르는 화면이 열릴 뿐이고, 만들어 둔 20개를 학습하는 것은
    /// 기본 20개와 똑같이 공짜다. 기본 20개 완료 표시는 추가 학습과 상관없이 그대로다.
    @ViewBuilder
    private var extraWordsCTA: some View {
        if let set = todayExtraSets.first, extraRemainingCount > 0 {
            Text("오늘 추가 학습 \(extraStudiedCount) / \(extraEntries.count)")
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.secondaryInk)
            NavigationLink(value: VocabularyRoute.generatedStudy(setID: set.setID)) {
                primaryLabel(
                    extraStudiedCount > 0 ? "추가 단어 이어 학습하기" : "추가 단어 학습 시작",
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(PressableButtonStyle())
        } else {
            if !extraEntries.isEmpty {
                Label(
                    "오늘 추가 학습 \(extraEntries.count) / \(extraEntries.count) 완료",
                    systemImage: "checkmark.circle.fill"
                )
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.primary)
            }
            PrimaryButton(title: "오늘 \(VocabularyDailySet.dailyTarget)개 더 학습하기") {
                isShowingExtraSheet = true
            }
            HStack(spacing: AppSpacing.xs) {
                DailyTokenIcon(size: 16)
                Text("새 단어를 만들 때 데일리 토큰 1개")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    /// 주제와 구성. 고른 주제만으로 하루 목표를 채우지 못한 날에는 그 사실을
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
                timeZone: timeZone,
                // 완료 화면의 "20개 더"는 홈으로 돌아와 주제 고르기를 연다.
                // 시트는 이 화면 한 곳에서만 띄운다(두 번째 생성 입구를 만들지 않는다).
                onRequestExtra: { isShowingExtraSheet = true }
            )
        case .todayLearned:
            // 오늘 배정된 기본 목록 + 오늘 추가로 학습한 단어. 다시 세거나 추측하지 않는다.
            VocabularyMyWordsView(
                title: "오늘 학습한 단어",
                emptyMessage: "오늘 학습한 단어가 아직 없어요.",
                entries: todayLearnedEntries,
                states: stateByID,
                showsProgress: true
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
        let set = VocabularyDailySetPlanner.assign(
            localDate: today,
            catalog: VocabularyCatalog.all,
            excluding: VocabularyDailyProgress.studiedIDs(states: states),
            targetLevel: preferences.targetLevel,
            topic: topic
        )
        preferences.vocabularyDailySet = set
        // 플래너 캘린더가 "오늘 다 했는가"를 판단할 분모. 배정 순간 한 번만 남긴다.
        try? persistence.setVocabularyDailyGoal(localDate: today, count: set.entryIDs.count)
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
