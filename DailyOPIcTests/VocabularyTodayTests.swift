import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 오늘의 단어 V2(P14.5). 주제 고르기 → 하루 20개 → 같은 날 고정 → 카드 안 저장 →
/// 완료 화면까지를 고정된 날짜로만 검증한다.
///
/// 이 파일의 어느 테스트도 네트워크·AI를 부르지 않는다. 그게 이 기능의 요점이다 —
/// 기본 오늘의 단어는 배정도 학습도 저장도 값이 0이다. 데일리 토큰은 여전히
/// "AI 맞춤 단어장 만들기"(P14.2)와 "AI에게 분석받기"(P14.3)에서만 나간다.
@MainActor
struct VocabularyTodayTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let today = "2026-08-28"

    // MARK: 도우미

    private func moment(_ localDate: String, hour: Int = 9) throws -> Date {
        let day = try #require(LocalCalendarDate.date(from: localDate, timeZone: seoul))
        return try #require(
            LocalCalendarDate.calendar(timeZone: seoul).date(byAdding: .hour, value: hour, to: day)
        )
    }

    private func makeService() throws -> PersistenceService {
        let container = try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func state(_ service: PersistenceService, _ entryID: String) throws -> VocabularyStateRecord {
        try #require(try service.vocabularyStates().first { $0.entryID == entryID })
    }

    private func assign(
        _ topic: VocabularyTopic?,
        localDate: String? = nil,
        excluding excluded: Set<String> = []
    ) -> VocabularyDailySet {
        VocabularyDailySetPlanner.assign(
            localDate: localDate ?? today,
            catalog: VocabularyCatalog.all,
            excluding: excluded,
            topic: topic
        )
    }

    /// 런타임 소스를 파일로 읽는다(`DailyTokenEnforcementTests`와 같은 방식).
    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 주석을 뺀 코드만. 계약 검사는 실제로 부르는 것만 봐야 한다 —
    /// "토큰을 쓰지 않는다"고 적은 주석 때문에 걸리면 안 된다.
    private func code(_ file: String) -> String {
        file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 홈이 실제로 그리는 범위(`home` 선언부터 라우트 목적지 직전까지).
    /// 라우트 목적지는 사용자-facing 홈이 아니라서 이 범위 밖이다.
    private func homeBody(_ screen: String) throws -> String {
        let start = try #require(screen.range(of: "private var home: some View"))
        let end = try #require(screen.range(of: "private func destination("))
        return String(screen[start.lowerBound..<end.lowerBound])
    }

    private let screenPath = "Views/Screens/Main/Vocabulary/VocabularyScreen.swift"
    private let studyPath = "Views/Screens/Main/Vocabulary/VocabularyStudyView.swift"
    private let plannerPath = "Views/Screens/Main/Calendar/PlannerHomeView.swift"
    private let tabPath = "Views/Screens/Main/MainTabView.swift"

    // MARK: 1. 하루 배정

    @Test func dailyTargetIsTwenty() {
        #expect(VocabularyDailySet.dailyTarget == 20)
    }

    /// 주제를 고르기 전에는 아무것도 배정하지 않는다. 화면이 뜨는 것만으로 오늘의
    /// 묶음이 생기면 사용자는 고를 기회를 잃는다.
    @Test func nothingIsAssignedBeforeTheUserPicksATopic() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains(".onAppear(perform: assignToday"))
        #expect(!screen.contains("assignTodayIfNeeded"))
        // 배정은 주제를 받는 함수 하나에서만 일어난다.
        #expect(screen.contains("private func assignToday(topic: VocabularyTopic)"))
        #expect(screen.contains("VocabularyDailySetPlanner.assign"))
        #expect(
            screen.components(separatedBy: "VocabularyDailySetPlanner.assign").count - 1 == 1
        )
        // 배정이 없는 동안 화면이 묻는 것은 주제뿐이다.
        #expect(screen.contains("case todayTopicPicker"))
        #expect(screen.contains("onSelect: assignToday"))
    }

    /// 주제를 고르면 그 자리에서 20개가 정해진다.
    @Test func pickingATopicAssignsExactlyTwentyEntries() {
        let set = assign(.cafes)
        #expect(set.entryIDs.count == VocabularyDailySet.dailyTarget)
        #expect(Set(set.entryIDs).count == set.entryIDs.count)
        #expect(set.topic == .cafes)
        #expect(set.covers(today))
    }

    /// 같은 날이면 몇 번을 다시 계산해도 같은 id 20개다(앱을 껐다 켜도 같은 근거).
    @Test func sameLocalDayGivesTheSameTwentyIdentifiers() {
        #expect(assign(.cafes) == assign(.cafes))
        #expect(assign(.cafes).entryIDs == assign(.cafes).entryIDs)
    }

    /// 화면은 `covers`가 참이면 다시 묻지도, 다시 계산하지도 않는다.
    @Test func sameDayReentryNeitherAsksTheTopicAgainNorReassigns() throws {
        let set = assign(.travel)
        #expect(set.covers(today))
        let screen = code(try source(screenPath))
        // 오늘 몫이 있으면 `todaySet`이 값을 주고, 주제 고르기는 그때만 뜬다.
        #expect(screen.contains("guard let set = preferences.vocabularyDailySet, set.covers(todayLocalDate)"))
        #expect(screen.contains("if todaySet == nil {"))
        // 배정 함수 자체도 오늘 몫이 있으면 그대로 둔다.
        #expect(screen.contains("if let existing = preferences.vocabularyDailySet, existing.covers(today) { return }"))
    }

    /// 어제 배정은 오늘을 덮지 않는다 — 다음 날에는 다시 고를 수 있다.
    @Test func nextDayCanBeAssignedAgain() {
        let yesterday = assign(.cafes, localDate: "2026-08-27")
        #expect(!yesterday.covers(today))
        let fresh = assign(.movies)
        #expect(fresh.covers(today))
        #expect(fresh.topic == .movies)
    }

    /// 저장은 UserDefaults의 JSON 한 덩어리다. 주제까지 같이 살아 돌아온다.
    @Test func todaysAssignmentSurvivesEncodingWithItsTopic() throws {
        let set = assign(.food)
        let restored = try JSONDecoder().decode(
            VocabularyDailySet.self, from: try JSONEncoder().encode(set)
        )
        #expect(restored == set)
        #expect(restored.topic == .food)
    }

    /// 주제가 없던 예전 저장본도 그대로 읽힌다(P14.5 이전에 배정된 하루).
    @Test func storedAssignmentWithoutATopicStillDecodes() throws {
        let json = #"{"localDate":"2026-08-28","entryIDs":["cafe-crowded"]}"#
        let set = try JSONDecoder().decode(VocabularyDailySet.self, from: Data(json.utf8))
        #expect(set.topic == nil)
        #expect(set.entryIDs == ["cafe-crowded"])
        #expect(set.covers(today))
    }

    // MARK: 2. 주제 구성(시드 현실)

    /// 시드는 한 주제에 20개가 없다. 이 사실을 감추지 않고 테스트로 고정해 둔다.
    @Test func noSeedTopicAloneReachesTheDailyTarget() {
        for topic in VocabularyCatalog.topics {
            #expect(VocabularyCatalog.entries(topic: topic).count < VocabularyDailySet.dailyTarget)
        }
    }

    /// 고른 주제를 **먼저 다 쓰고**, 모자란 만큼만 다른 주제에서 채운다.
    @Test func chosenTopicIsUsedFirstAndOnlyTheGapIsFilled() {
        let available = VocabularyCatalog.entries(topic: .cafes)
        let set = assign(.cafes)
        let entries = VocabularyCatalog.entries(ids: set.entryIDs)
        let onTopic = entries.filter { $0.topics.contains(.cafes) }
        #expect(Set(onTopic.map(\.id)) == Set(available.map(\.id)))
        #expect(entries.count - onTopic.count == VocabularyDailySet.dailyTarget - available.count)
    }

    /// 채운 항목을 고른 주제인 척 보여주지 않는다. 화면이 구성을 나눠서 적고,
    /// 고르기 화면은 고르기 **전에** 몇 개가 나올지 말한다.
    @Test func filledEntriesAreNotLabelledAsTheChosenTopic() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("다른 주제 \\(todayEntries.count - onTopic)개"))
        #expect(screen.contains("\\(available)개 + 다른 주제 \\(target - available)개"))
    }

    /// 이미 학습한 항목은 주제를 골라도 새 단어로 돌아오지 않는다.
    @Test func studiedEntriesStayOutOfTheChosenTopic() {
        let plain = assign(.cafes)
        let studied = Set(plain.entryIDs.prefix(5))
        let next = assign(.cafes, excluding: studied)
        #expect(next.entryIDs.allSatisfy { !studied.contains($0) })
        #expect(next.entryIDs.count == VocabularyDailySet.dailyTarget)
    }

    /// 주제를 고르지 않은 배정(예전 저장본·다른 호출부)은 예전 그대로 돈다.
    @Test func topiclessAssignmentKeepsTheOldBehaviour() {
        let set = assign(nil)
        #expect(set.topic == nil)
        #expect(set.entryIDs.count == VocabularyDailySet.dailyTarget)
        let topics = Set(VocabularyCatalog.entries(ids: set.entryIDs).compactMap(\.primaryTopic))
        #expect(topics.count >= 5)
    }

    // MARK: 3. 학습(기존 엔진 그대로)

    /// 분모는 배정된 20개다. 같은 세션에서 다시 나온 카드가 진행도를 두 번 올리지 않는다.
    @Test func twentyAttemptsFinishTheDay() {
        let entries = Array(VocabularyCatalog.entries(ids: assign(.cafes).entryIDs))
        #expect(entries.count == 20)
        var session = VocabularyStudySession(entries: entries)
        session.answer(knewIt: false)   // 한 번 틀린 항목은 세션 안에서 한 번 더 나온다.
        while !session.isFinished { session.answer(knewIt: true) }
        #expect(session.attemptedCount == 20)
        #expect(session.forgottenCount == 1)
    }

    /// 복습 규칙은 P14.1 그대로다. 오늘의 단어라고 다른 상태 기계를 쓰지 않는다.
    @Test func todaysWordsUseTheSameReviewPolicy() throws {
        let service = try makeService()
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: try moment(today)
        )
        let record = try state(service, "cafe-crowded")
        #expect(record.status == .reviewing)
        #expect(record.consecutiveSuccessCount == 1)
        #expect(record.nextReviewLocalDate == "2026-08-29")
        #expect(record.wasStudied(on: today))
    }

    // MARK: 4. 카드 안 저장

    /// 카드에서 저장한다. 저장은 학습 판정과 별개 채널이다.
    @Test func savingFromTheCardDoesNotTouchReviewState() throws {
        let service = try makeService()
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: true)
        let record = try state(service, "cafe-crowded")
        #expect(record.isSaved)
        #expect(record.status == .new)
        #expect(record.nextReviewLocalDate == nil)
        #expect(!record.hasBeenStudied)
    }

    /// 저장을 풀어도 복습 기록은 지워지지 않는다.
    @Test func unsavingKeepsTheReviewHistory() throws {
        let service = try makeService()
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: try moment(today)
        )
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: true)
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: false)
        let record = try state(service, "cafe-crowded")
        #expect(!record.isSaved)
        #expect(record.status == .reviewing)
        #expect(record.consecutiveSuccessCount == 1)
        #expect(record.nextReviewLocalDate == "2026-08-29")
    }

    /// 익혔다고 저장되지 않는다.
    @Test func masteringDoesNotSaveTheEntry() throws {
        let service = try makeService()
        for day in 0..<VocabularyReviewPolicy.masteryThreshold {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true, timeZone: seoul,
                now: try moment(String(format: "2026-08-%02d", 10 + day))
            )
        }
        let record = try state(service, "cafe-crowded")
        #expect(record.status == .mastered)
        #expect(!record.isSaved)
    }

    /// 저장 버튼은 학습 카드 안에 있고, 저장소는 기존 것 하나뿐이다.
    @Test func theStudyCardCarriesTheSaveToggle() throws {
        let study = code(try source(studyPath))
        #expect(study.contains("persistence.setVocabularySaved(entryID: entry.id, isSaved: !saved)"))
        #expect(study.contains("heart.fill"))
        #expect(study.contains("saveButton(entry)"))
    }

    // MARK: 5. 완료 화면

    @Test func completionCopyMatchesTheDailyTarget() {
        #expect(VocabularyStudyKind.newWords.completionTitle == "오늘의 단어 완료")
        #expect(
            VocabularyStudyKind.newWords.completionMessage(count: VocabularyDailySet.dailyTarget)
            == "20개의 단어와 표현을 학습했어요."
        )
    }

    /// "오늘 20개 더 학습하기"는 자리를 잡아 두되 이번 단계에서는 열지 않는다.
    /// 눌리지 않으므로 이 화면에서 AI가 불릴 일도, 토큰이 나갈 일도 없다.
    @Test func extraStudyCTAExistsButSpendsNothingYet() throws {
        let study = code(try source(studyPath))
        #expect(study.contains("오늘 \\(VocabularyDailySet.dailyTarget)개 더 학습하기"))
        #expect(study.contains("isDisabled: true"))
        #expect(!study.contains("VocabularyGenerationViewModel"))
        #expect(!study.contains("tokenCost"))
        #expect(!study.contains("generate("))
        #expect(!study.contains("vocabulary/generate"))
    }

    // MARK: 6. 플래너는 단어장으로 보내지 않는다(P14.5.2)

    /// 플래너에 있던 "단어 학습하기" 바로가기는 내렸다. 플래너는 캘린더이지
    /// 다른 탭으로 보내는 허브가 아니다 — 단어는 단어장 탭 한 곳에서 시작한다.
    @Test func plannerNoLongerShortcutsIntoVocabulary() throws {
        let planner = code(try source(plannerPath))
        #expect(!planner.contains("단어 학습하기"))
        #expect(!planner.contains("onStartVocabulary"))
        #expect(!planner.contains("오늘의 학습"))
        #expect(!code(try source(tabPath)).contains("onStartVocabulary"))
    }

    /// 플래너를 열거나 그 화면을 그리는 것으로는 아무것도 만들어지지 않는다.
    @Test func openingThePlannerCreatesNothing() throws {
        let planner = code(try source(plannerPath))
        #expect(!planner.contains("VocabularyDailySetPlanner"))
        #expect(!planner.contains("vocabularyDailySet"))
        #expect(!planner.contains("tokenCost"))
        #expect(!planner.contains("generate("))
    }

    // MARK: 7. 단어장 홈의 제품 초점(P14.5.1)

    /// 홈에서 "주제별 단어" 탐색을 내렸다. 주제는 이제 오늘의 단어를 시작하는
    /// 입력값이지 그 자체로 둘러보는 목적지가 아니다.
    @Test func homeNoLongerBrowsesTopics() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains("주제별 단어"))
        #expect(!screen.contains("VocabularyRoute.topic("))
        #expect(!screen.contains("topicsSection"))
    }

    /// 홈에서 "AI 맞춤 단어장 만들기"를 내렸다. 홈에서 P14.2 생성 시트를 여는 길이 없다.
    @Test func homeNoLongerOffersAIGeneration() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains("AI 맞춤 단어장"))
        #expect(!screen.contains("VocabularyGenerationSheet"))
        #expect(!screen.contains("VocabularyGenerationViewModel"))
        #expect(!screen.contains("맞춤 단어 만들기"))
    }

    /// 홈에 남는 것은 오늘의 단어 하나다(P14.5.2). 검색·큰 제목·목표 안내·복습 카드는 내렸다.
    @Test func homeKeepsOnlyTodaysWords() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("Text(\"오늘의 단어\")"))
        #expect(screen.contains("todayCard"))
        // 홈이 그리는 것은 오늘의 카드 하나뿐이다.
        #expect(screen.contains("todayCard.padding(AppSpacing.lg)"))
        // 검색은 통째로 사라졌다 — 입력창도, 결과 목록도, 검색 상태도 없다.
        #expect(!screen.contains("단어나 뜻으로 검색"))
        #expect(!screen.contains(".searchable("))
        #expect(!screen.contains("searchList"))
        #expect(!screen.contains("VocabularyCatalog.search("))
        // 큰 제목과 목표 안내도 없다.
        #expect(!screen.contains("Text(\"단어장\")"))
        #expect(!screen.contains("에 맞춰 추천해요"))
        // 복습 카드도, 그 자리를 대신하던 작은 줄도 없다.
        #expect(!screen.contains("reviewCard"))
        #expect(!screen.contains("오늘 복습"))
    }

    /// 홈에는 복습으로 들어가는 길이 하나도 없다(P14.5.2 재작업). 남은 due 목록은
    /// 라우트가 쓰는 내부 값일 뿐 사용자에게 보이는 CTA가 아니다.
    @Test func homeHasNoReviewEntryPoint() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains("오늘 복습할 단어"))
        #expect(!screen.contains("reviewLine"))
        #expect(!screen.contains("NavigationLink(value: VocabularyRoute.review)"))
        // 홈 본문 안에는 dueEntries조차 등장하지 않는다.
        let home = try homeBody(screen)
        #expect(!home.contains("dueEntries"))
        #expect(!home.contains("VocabularyRoute.review"))
    }

    /// 홈에서 "내 단어"(저장한 단어 · 익힌 단어)를 내렸다. 단어장 홈 = 오늘의 단어다.
    @Test func homeHasNoMyWordsSection() throws {
        let screen = code(try source(screenPath))
        #expect(!screen.contains("내 단어"))
        #expect(!screen.contains("myWordsSection"))
        #expect(!screen.contains("myWordsRow"))
        #expect(!screen.contains("NavigationLink(value: VocabularyRoute.saved)"))
        #expect(!screen.contains("NavigationLink(value: VocabularyRoute.mastered)"))
        // 홈이 그리는 범위 안에는 저장/익힘 목록도, 그 문구도 없다.
        // (같은 문구가 남아 있는 곳은 라우트 목적지의 화면 제목뿐이다.)
        let home = try homeBody(screen)
        #expect(!home.contains("savedEntries"))
        #expect(!home.contains("masteredEntries"))
        #expect(!home.contains("저장한 단어"))
        #expect(!home.contains("익힌 단어"))
    }

    /// 홈에서 진입점을 내렸다고 복습을 없앤 것이 아니다. 라우트·화면·엔진(1·3·7·14·30일)과
    /// 예정일 계산은 그대로 살아 있다 — 진입점 제거 ≠ 시스템 삭제다.
    @Test func reviewEngineSurvivesWithoutAHomeEntry() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("case review"))
        #expect(screen.contains("case .review:"))
        #expect(screen.contains("kind: .review"))
        #expect(screen.contains("VocabularyDailyProgress.dueIDs(states: states, today: todayLocalDate)"))
        #expect(VocabularyReviewPolicy.intervalDaysBySuccess == [1, 3, 7, 14, 30])
        #expect(VocabularyReviewPolicy.masteryThreshold == 5)
        // 상태 모델의 복습 필드도 그대로다.
        let record = try source("Models/LocalRecords.swift")
        #expect(record.contains("var nextReviewLocalDate: String?"))
        #expect(record.contains("var reviewCount: Int = 0"))
    }

    /// 예정일 계산이 실제로 도는지 값으로 확인한다(문자열 검사가 아니다).
    /// 한 번 맞히면 1일 뒤, 두 번 연속이면 3일 뒤다.
    @Test func reviewSchedulingStillRunsEndToEnd() throws {
        let service = try makeService()
        try service.recordVocabularyAnswer(
            entryID: "e1", knewIt: true, timeZone: seoul, now: try moment("2026-01-10")
        )
        #expect(try state(service, "e1").nextReviewLocalDate == "2026-01-11")
        try service.recordVocabularyAnswer(
            entryID: "e1", knewIt: true, timeZone: seoul, now: try moment("2026-01-11")
        )
        #expect(try state(service, "e1").nextReviewLocalDate == "2026-01-14")
    }

    /// 저장·익힘도 홈에서만 내렸다. 화면·라우트·저장소는 그대로고, 저장 토글은
    /// 오늘의 카드에서 여전히 동작한다.
    @Test func savedAndMasteredStayInternal() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("case saved"))
        #expect(screen.contains("case mastered"))
        #expect(screen.contains("case .saved:"))
        #expect(screen.contains("case .mastered:"))
        #expect(screen.contains("private var savedEntries"))
        #expect(screen.contains("private var masteredEntries"))
        #expect(try source("Views/Screens/Main/Vocabulary/VocabularyListViews.swift")
            .contains("struct VocabularyMyWordsView"))
        // 저장은 기록으로 남고, 오늘 학습한 단어 목록이 그 상태를 그대로 읽는다.
        let service = try makeService()
        try service.setVocabularySaved(entryID: "e1", isSaved: true)
        #expect(try state(service, "e1").isSaved)
    }

    /// 오늘 학습을 끝내면 방금 한 단어를 다시 볼 수 있다. 목록의 진실은 오늘 배정된
    /// entryID 그 자체다 — 다시 세거나 추측하지 않는다.
    @Test func finishedDayOffersTodaysWordList() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("case todayLearned"))
        #expect(screen.contains("NavigationLink(value: VocabularyRoute.todayLearned)"))
        #expect(screen.contains("오늘 학습한 단어 보기"))
        #expect(screen.contains("entries: todayEntries"))
        #expect(screen.contains("showsProgress: true"))
        // 새 목록 화면을 만들지 않고 저장한 단어·익힌 단어와 같은 화면을 나눠 쓴다.
        #expect(screen.contains("VocabularyMyWordsView("))
    }

    /// 줄마다 영어 · 뜻 · 저장 여부 · 학습 상태 · 복습 횟수가 보인다.
    @Test func todaysWordRowsShowStatusAndReviewCount() throws {
        let list = code(try source("Views/Screens/Main/Vocabulary/VocabularyListViews.swift"))
        #expect(list.contains("Text(entry.term)"))
        #expect(list.contains("Text(entry.meaningKo)"))
        #expect(list.contains("state?.isSaved == true"))
        #expect(list.contains("Text(Self.progressText(state))"))
        // 복습을 한 적 없으면 "복습 0회"라고 적지 않는다.
        #expect(VocabularyEntryRow.progressText(nil) == "새 단어")
    }

    /// 추가 20개는 아직 열지 않았다. 홈의 CTA도 완료 화면과 같은 비활성 상태이고,
    /// 열릴 때의 값(데일리 토큰 1개)만 미리 밝힌다.
    @Test func theExtraTwentyStaysClosedAndPriced() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("오늘 \\(VocabularyDailySet.dailyTarget)개 더 학습하기"))
        #expect(screen.contains("isDisabled: true"))
        #expect(screen.contains("데일리 토큰 1개"))
        // 눌러도 부를 것이 없다 — 생성 경로가 이 화면에 아예 없다.
        #expect(!screen.contains("VocabularyGenerationViewModel"))
        #expect(!screen.contains("vocabulary/generate"))
        #expect(!screen.contains("VocabularyDailySetPlanner.assign(localDate: today, catalog: VocabularyCatalog.all, excluding: [])"))
    }

    /// 오늘의 주제 고르기는 남는다 — 이것이 "주제별 단어"와 다른 점이다.
    @Test func todayTopicPickerSurvivesTheHomeCleanup() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("case todayTopicPicker"))
        #expect(screen.contains("VocabularyTodayTopicPicker("))
    }

    /// 주제 고르기가 실제로 도는 목록은 `VocabularyCatalog.topics`이고, 그것은
    /// 기존 `VocabularyTaxonomy`(=`VocabularyTopic`) 전체와 **같은 순서·같은 원소**다.
    /// 축약된 주제 목록을 따로 만들지 않았고, 잘라내지도 않는다.
    @Test func topicPickerOffersEveryVocabularyTopic() throws {
        // 1) 화면이 도는 collection이 무엇인지.
        let screen = code(try source(screenPath))
        #expect(screen.contains("ForEach(VocabularyCatalog.topics)"))
        #expect(!screen.contains("VocabularyCatalog.topics.prefix"))
        #expect(!screen.contains("topics.prefix("))
        // 2) 그 collection의 실제 내용이 taxonomy 전체인지.
        #expect(VocabularyTopic.allCases.count == 16)
        #expect(VocabularyCatalog.topics == VocabularyTopic.allCases)
        // 3) 화면이 각 칸에 붙이는 개수도 16개 전부 계산된다(빈 주제가 없다).
        let counts = VocabularyTopic.allCases.reduce(into: [VocabularyTopic: Int]()) {
            $0[$1] = VocabularyCatalog.entries(topic: $1).count
        }
        #expect(counts.count == 16)
        #expect(counts.values.allSatisfy { $0 > 0 })
    }

    /// 홈에서 내렸다고 구현을 지우지 않았다. P14.2 생성 아키텍처와 토큰 계약은 그대로다.
    @Test func generationArchitectureStaysIntact() throws {
        let viewModel = try source("ViewModels/VocabularyGenerationViewModel.swift")
        #expect(viewModel.contains("tokenCost"))
        #expect(VocabularyGenerationViewModel.tokenCost == 1)
        #expect(try source("Services/API/APIClient.swift").contains("/v1/vocabulary/generate"))
        // 화면·라우트도 그대로 있다. P14.5.2에서 마지막 진입점(데일리 질문 CTA)이
        // 사라져 지금은 부르는 곳이 없지만, P14.6이 여기에 다시 붙는다.
        let sheet = code(try source("Views/Screens/Main/Vocabulary/VocabularyGenerationViews.swift"))
        #expect(sheet.contains("struct VocabularyGenerationSheet"))
        #expect(sheet.contains("VocabularyGenerationViewModel"))
    }

    /// AI 말하기 코치(P14.3)도 그대로 있다. 홈에 새 큰 CTA를 만들지도 않았다.
    @Test func speakingCoachStaysAsASecondaryTool() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("case speakingCoach(VocabularyEntry)"))
        #expect(screen.contains("VocabularySpeakingCoachView("))
        // 진입점은 예전 그대로 단어 상세 안에 있다 — 홈의 큰 CTA가 아니다.
        #expect(try source("Views/Screens/Main/Vocabulary/VocabularyListViews.swift")
            .contains("NavigationLink(value: VocabularyRoute.speakingCoach(entry))"))
        #expect(!code(try source(screenPath)).contains("말하기 코치"))
    }

    // MARK: 8. 토큰 경계

    /// 기본 오늘의 단어(주제 고르기 · 배정 · 카드 · 저장)는 값이 0이다.
    /// 토큰이 나가는 자리는 여전히 "AI 맞춤 단어 만들기" 한 곳뿐이다.
    @Test func theTodayVocabularyPathCostsNoDailyToken() throws {
        let screen = try source(screenPath)
        let picker = try #require(screen.range(of: "struct VocabularyTodayTopicPicker"))
        let pickerCode = code(String(screen[picker.lowerBound...]))
        for forbidden in ["tokenCost", "generate(", "reserve", "DailyToken", "URLSession", "AI"] {
            #expect(!pickerCode.contains(forbidden), "주제 고르기 화면이 \(forbidden)을(를) 건드린다")
        }
        let assignBody = code(String(screen[(screen.range(of: "private func assignToday")!.lowerBound)...]))
            .prefix(while: { $0 != "}" })
        #expect(!assignBody.contains("await"))
        #expect(!assignBody.contains("Task"))
    }
}
