import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// 단어장 복습 엔진(P14.1). 간격 일정 · 상태 전이 · 오늘 진행도 · 세션 큐를
/// 고정된 날짜로만 검증한다. `Date.now`에 기대는 테스트는 없다.
@MainActor
struct VocabularyReviewTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    /// 그 로컬 날짜의 오전 9시. 자정 경계에 걸리지 않는 평범한 학습 시각.
    private func moment(_ localDate: String, _ timeZone: TimeZone, hour: Int = 9) throws -> Date {
        let day = try #require(LocalCalendarDate.date(from: localDate, timeZone: timeZone))
        let calendar = LocalCalendarDate.calendar(timeZone: timeZone)
        return try #require(calendar.date(byAdding: .hour, value: hour, to: day))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeService(_ container: ModelContainer) -> PersistenceService {
        let service = PersistenceService()
        service.configure(context: ModelContext(container))
        return service
    }

    private func state(
        _ service: PersistenceService,
        _ entryID: String = "cafe-crowded"
    ) throws -> VocabularyStateRecord {
        try #require(try service.vocabularyStates().first { $0.entryID == entryID })
    }

    // MARK: 간격 일정

    @Test func firstSuccessSchedulesTomorrow() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: true, consecutiveSuccessCount: 0, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .reviewing)
        #expect(outcome.consecutiveSuccessCount == 1)
        #expect(outcome.nextReviewLocalDate == "2026-08-29")
    }

    @Test func secondSuccessSchedulesThreeDays() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: true, consecutiveSuccessCount: 1, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .reviewing)
        #expect(outcome.nextReviewLocalDate == "2026-08-31")
    }

    @Test func thirdSuccessSchedulesSevenDays() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: true, consecutiveSuccessCount: 2, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .reviewing)
        #expect(outcome.nextReviewLocalDate == "2026-09-04")
    }

    @Test func fourthSuccessSchedulesFourteenDays() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: true, consecutiveSuccessCount: 3, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .reviewing)
        #expect(outcome.nextReviewLocalDate == "2026-09-11")
    }

    @Test func fifthSuccessMastersWithThirtyDayMaintenance() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: true, consecutiveSuccessCount: 4, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .mastered)
        #expect(outcome.consecutiveSuccessCount == 5)
        #expect(outcome.nextReviewLocalDate == "2026-09-27")
    }

    /// 익힘 뒤의 유지 복습은 계속 30일이다.
    @Test func masteredMaintenanceStaysMasteredAndRepeatsMonthly() {
        for streak in 5...9 {
            let outcome = VocabularyReviewPolicy.apply(
                knewIt: true, consecutiveSuccessCount: streak, today: "2026-08-28", timeZone: seoul
            )
            #expect(outcome.status == .mastered)
            #expect(outcome.nextReviewLocalDate == "2026-09-27")
        }
    }

    @Test func wrongAnswerResetsStreakAndSchedulesTomorrow() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: false, consecutiveSuccessCount: 4, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .learning)
        #expect(outcome.consecutiveSuccessCount == 0)
        #expect(outcome.nextReviewLocalDate == "2026-08-29")
    }

    @Test func masteredItemLeavesMasteredWhenForgotten() {
        let outcome = VocabularyReviewPolicy.apply(
            knewIt: false, consecutiveSuccessCount: 7, today: "2026-08-28", timeZone: seoul
        )
        #expect(outcome.status == .learning)
        #expect(outcome.consecutiveSuccessCount == 0)
    }

    // MARK: 날짜 계산

    /// 달력 하루 단위다. 월·연 경계에서도 어긋나지 않는다.
    @Test func schedulingCrossesMonthAndYearBoundaries() {
        #expect(
            VocabularyReviewPolicy.localDate("2026-12-30", addingDays: 3, timeZone: seoul)
                == "2027-01-02"
        )
        #expect(
            VocabularyReviewPolicy.localDate("2026-02-27", addingDays: 1, timeZone: seoul)
                == "2026-02-28"
        )
    }

    /// 서머타임이 있는 지역에서도 "하루 뒤"는 다음 날짜다(86400초 산술이면 어긋난다).
    @Test func daylightSavingDayStillAdvancesByOneCalendarDay() {
        #expect(
            VocabularyReviewPolicy.localDate("2026-03-07", addingDays: 1, timeZone: newYork)
                == "2026-03-08"
        )
        #expect(
            VocabularyReviewPolicy.localDate("2026-03-08", addingDays: 1, timeZone: newYork)
                == "2026-03-09"
        )
    }

    /// 같은 순간이라도 하루 경계는 계획 타임존이 정한다.
    @Test func localDayDependsOnThePlanTimeZone() throws {
        let instant = try moment("2026-08-28", seoul, hour: 8)
        #expect(LocalCalendarDate.text(from: instant, timeZone: seoul) == "2026-08-28")
        #expect(LocalCalendarDate.text(from: instant, timeZone: newYork) == "2026-08-27")
    }

    // MARK: 저장된 상태 전이

    @Test func newPlusKnownBecomesReviewing() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-28", seoul)
        )
        let record = try state(service)
        #expect(record.status == .reviewing)
        #expect(record.consecutiveSuccessCount == 1)
        #expect(record.failureCount == 0)
        #expect(record.nextReviewLocalDate == "2026-08-29")
        #expect(record.lastStudiedLocalDate == "2026-08-28")
    }

    @Test func newPlusForgottenBecomesLearning() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-08-28", seoul)
        )
        let record = try state(service)
        #expect(record.status == .learning)
        #expect(record.consecutiveSuccessCount == 0)
        #expect(record.failureCount == 1)
        #expect(record.nextReviewLocalDate == "2026-08-29")
    }

    /// `consecutiveSuccessCount`는 누적 성공이 아니라 **연속** 성공이다.
    @Test func wrongAnswerResetsTheStoredStreakButKeepsFailureHistory() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-28", seoul)
        )
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-29", seoul)
        )
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-09-01", seoul)
        )
        let record = try state(service)
        #expect(record.consecutiveSuccessCount == 0)
        #expect(record.failureCount == 1)
        #expect(record.status == .learning)
        #expect(record.nextReviewLocalDate == "2026-09-02")

        // 다시 맞히면 1회부터 새로 쌓인다.
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-09-02", seoul)
        )
        let again = try state(service)
        #expect(again.consecutiveSuccessCount == 1)
        #expect(again.status == .reviewing)
        #expect(again.nextReviewLocalDate == "2026-09-03")
    }

    /// 다섯 번 연속으로 맞히면 익힘이 되고, 유지 복습이 30일 뒤로 잡힌다.
    @Test func fiveScheduledSuccessesReachMastered() throws {
        let service = makeService(try makeContainer())
        let days = ["2026-08-28", "2026-08-29", "2026-09-01", "2026-09-08", "2026-09-22"]
        for day in days {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true,
                timeZone: seoul, now: try moment(day, seoul)
            )
        }
        let record = try state(service)
        #expect(record.status == .mastered)
        #expect(record.consecutiveSuccessCount == 5)
        #expect(record.nextReviewLocalDate == "2026-10-22")
        #expect(!record.isDueForReview(on: "2026-09-22"))
        #expect(record.isDueForReview(on: "2026-10-22"))
    }

    @Test func masteredForgottenReturnsToLearningTomorrow() throws {
        let service = makeService(try makeContainer())
        for day in ["2026-08-28", "2026-08-29", "2026-09-01", "2026-09-08", "2026-09-22"] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true,
                timeZone: seoul, now: try moment(day, seoul)
            )
        }
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-10-22", seoul)
        )
        let record = try state(service)
        #expect(record.status == .learning)
        #expect(record.consecutiveSuccessCount == 0)
        #expect(record.nextReviewLocalDate == "2026-10-23")
        #expect(record.isDueForReview(on: "2026-10-23"))
    }

    // MARK: 오늘 복습 목록

    @Test func dueListTakesTodayAndOverdueOnly() throws {
        let service = makeService(try makeContainer())
        // 어제 틀린 항목 → 오늘 예정.
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-08-27", seoul)
        )
        // 오늘 맞힌 항목 → 내일 예정.
        try service.recordVocabularyAnswer(
            entryID: "cafe-favorite-place", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-28", seoul)
        )
        let states = try service.vocabularyStates()
        let due = VocabularyDailyProgress.dueIDs(states: states, today: "2026-08-28")
        #expect(due == ["cafe-crowded"])
    }

    @Test func overdueItemStaysDue() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-08-01", seoul)
        )
        let states = try service.vocabularyStates()
        #expect(VocabularyDailyProgress.dueIDs(states: states, today: "2026-08-28") == ["cafe-crowded"])
    }

    /// 아직 배우지 않은 단어는 복습 목록에 들어오지 않는다. 저장만 한 단어도 마찬가지다.
    @Test func neverStudiedVocabularyIsNotDue() throws {
        let service = makeService(try makeContainer())
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: true)
        let states = try service.vocabularyStates()
        #expect(VocabularyDailyProgress.dueIDs(states: states, today: "2026-08-28").isEmpty)
        #expect(states.first?.status == .new)
    }

    /// 복습을 마치면 그날의 목록에서 빠진다.
    @Test func completedReviewLeavesTodaysDueList() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-08-27", seoul)
        )
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-28", seoul)
        )
        let states = try service.vocabularyStates()
        #expect(VocabularyDailyProgress.dueIDs(states: states, today: "2026-08-28").isEmpty)
        #expect(VocabularyDailyProgress.dueIDs(states: states, today: "2026-08-29") == ["cafe-crowded"])
    }

    // MARK: 오늘의 새 단어 후보

    /// 한 번이라도 배운 단어는 새 단어 후보에서 빠진다 — 복습 시스템의 몫이다.
    @Test func studiedVocabularyIsExcludedFromNewCandidates() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-08-27", seoul)
        )
        try service.recordVocabularyAnswer(
            entryID: "cafe-favorite-place", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-27", seoul)
        )
        try service.setVocabularySaved(entryID: "friends-spend-time-with", isSaved: true)

        let studied = VocabularyDailyProgress.studiedIDs(states: try service.vocabularyStates())
        #expect(studied == ["cafe-crowded", "cafe-favorite-place"])

        let set = VocabularyDailySetPlanner.assign(
            localDate: "2026-08-28",
            catalog: VocabularyCatalog.all,
            excluding: studied
        )
        #expect(!set.entryIDs.contains("cafe-crowded"))
        #expect(!set.entryIDs.contains("cafe-favorite-place"))
        // 저장만 한 단어는 아직 새 단어다.
        #expect(!studied.contains("friends-spend-time-with"))
    }

    /// 후보가 바닥나면 있는 만큼만 준다. 배운 단어를 새 단어인 척 되돌리지 않는다.
    @Test func exhaustedPoolReturnsFewerThanTheDailyTarget() {
        let catalog = Array(VocabularyCatalog.all.prefix(12))
        let studied = Set(catalog.prefix(9).map(\.id))
        let set = VocabularyDailySetPlanner.assign(
            localDate: "2026-08-28",
            catalog: catalog,
            excluding: studied
        )
        #expect(set.entryIDs.count == 3)
        #expect(Set(set.entryIDs).isDisjoint(with: studied))
    }

    /// 배정은 같은 로컬 날짜 동안 그대로다. 학습을 시작한 뒤 후보가 줄어도 바뀌지 않는다.
    @Test func todaysAssignmentIsStableEvenAfterStudyingSomeOfIt() {
        let first = VocabularyDailySetPlanner.assign(
            localDate: "2026-08-28", catalog: VocabularyCatalog.all
        )
        #expect(first.covers("2026-08-28"))
        #expect(!first.covers("2026-08-29"))
        // 화면은 covers가 참이면 다시 계산하지 않는다. 같은 인자로 다시 계산해도 결과가 같다.
        let again = VocabularyDailySetPlanner.assign(
            localDate: "2026-08-28", catalog: VocabularyCatalog.all
        )
        #expect(first == again)
    }

    /// 후보가 하나도 없어도 그날의 답은 "이미 정했다"이다 — 화면이 매번 다시 계산하지 않는다.
    @Test func emptyAssignmentStillCoversToday() {
        let set = VocabularyDailySetPlanner.assign(localDate: "2026-08-28", catalog: [])
        #expect(set.entryIDs.isEmpty)
        #expect(set.covers("2026-08-28"))
    }

    // MARK: 오늘 진행도

    @Test func bothAnswersCountOnceTowardTodaysGoal() throws {
        let service = makeService(try makeContainer())
        let assigned = Array(VocabularyCatalog.all.prefix(10).map(\.id))
        let now = try moment("2026-08-28", seoul)
        try service.recordVocabularyAnswer(entryID: assigned[0], knewIt: true, timeZone: seoul, now: now)
        try service.recordVocabularyAnswer(entryID: assigned[1], knewIt: true, timeZone: seoul, now: now)
        try service.recordVocabularyAnswer(entryID: assigned[2], knewIt: false, timeZone: seoul, now: now)

        let states = Dictionary(
            try service.vocabularyStates().map { ($0.entryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(
            VocabularyDailyProgress.attemptedCount(
                assigned: assigned, states: states, today: "2026-08-28"
            ) == 3
        )
        #expect(
            VocabularyDailyProgress.remainingIDs(
                assigned: assigned, states: states, today: "2026-08-28"
            ).count == 7
        )
    }

    /// 같은 세션에서 다시 답해도 진행도는 오르지 않는다.
    @Test func sameSessionRetryDoesNotDoubleCountProgress() throws {
        let service = makeService(try makeContainer())
        let assigned = Array(VocabularyCatalog.all.prefix(10).map(\.id))
        let now = try moment("2026-08-28", seoul)
        try service.recordVocabularyAnswer(entryID: assigned[0], knewIt: false, timeZone: seoul, now: now)
        try service.recordVocabularyAnswer(entryID: assigned[0], knewIt: false, timeZone: seoul, now: now)

        let states = Dictionary(
            try service.vocabularyStates().map { ($0.entryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(
            VocabularyDailyProgress.attemptedCount(
                assigned: assigned, states: states, today: "2026-08-28"
            ) == 1
        )
    }

    /// 4 / 10에서 나갔다가 앱을 다시 켜도 남은 6개부터 이어진다.
    @Test func partialSessionSurvivesRestartAndContinues() throws {
        let container = try makeContainer()
        let assigned = Array(VocabularyCatalog.all.prefix(10).map(\.id))
        let now = try moment("2026-08-28", seoul)
        let service = makeService(container)
        for id in assigned.prefix(4) {
            try service.recordVocabularyAnswer(entryID: id, knewIt: true, timeZone: seoul, now: now)
        }

        // 앱 재시작 = 같은 저장소를 새 서비스로 다시 연다.
        let reopened = makeService(container)
        let states = Dictionary(
            try reopened.vocabularyStates().map { ($0.entryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let remaining = VocabularyDailyProgress.remainingIDs(
            assigned: assigned, states: states, today: "2026-08-28"
        )
        #expect(remaining == Array(assigned.dropFirst(4)))
        #expect(
            VocabularyDailyProgress.attemptedCount(
                assigned: assigned, states: states, today: "2026-08-28"
            ) == 4
        )
    }

    /// 어제 답한 것은 오늘 진행도에 들어가지 않는다.
    @Test func yesterdaysAnswersDoNotCountTowardToday() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-27", seoul)
        )
        let states = Dictionary(
            try service.vocabularyStates().map { ($0.entryID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(
            VocabularyDailyProgress.attemptedCount(
                assigned: ["cafe-crowded"], states: states, today: "2026-08-28"
            ) == 0
        )
    }

    // MARK: 세션 큐

    private func entries(_ count: Int) -> [VocabularyEntry] {
        Array(VocabularyCatalog.all.prefix(count))
    }

    @Test func correctAnswersWalkTheQueueOnce() {
        var session = VocabularyStudySession(entries: entries(3))
        var seen: [String] = []
        while let current = session.current {
            seen.append(current.id)
            session.answer(knewIt: true)
        }
        #expect(seen == entries(3).map(\.id))
        #expect(session.isFinished)
        #expect(session.attemptedCount == 3)
        #expect(session.knownCount == 3)
        #expect(session.forgottenCount == 0)
    }

    /// 틀린 항목은 세션 안에서 한 번 더 나온다. 바로 다음 카드로 나오지는 않는다.
    @Test func forgottenItemComesBackOnceLaterInTheSession() {
        let items = entries(5)
        var session = VocabularyStudySession(entries: items)
        session.answer(knewIt: true)   // A
        session.answer(knewIt: false)  // B → 뒤로
        #expect(session.current?.id == items[2].id)
        #expect(session.pending.map(\.id) == [items[2].id, items[3].id, items[4].id, items[1].id])
    }

    /// 두 번째 오답은 다시 넣지 않는다 — 무한 반복이 생기지 않는다.
    @Test func secondFailureDoesNotRequeueAgain() {
        let items = entries(3)
        var session = VocabularyStudySession(entries: items)
        session.answer(knewIt: false)  // A → 뒤로
        session.answer(knewIt: true)   // B
        session.answer(knewIt: true)   // C
        #expect(session.current?.id == items[0].id)
        session.answer(knewIt: false)  // A 두 번째 오답
        #expect(session.isFinished)
        #expect(session.attemptedCount == 3)
    }

    /// 오답이 반복돼도 세션은 반드시 끝난다.
    @Test func sessionAlwaysTerminatesUnderRepeatedFailures() {
        var session = VocabularyStudySession(entries: entries(5))
        var answered = 0
        while session.current != nil, answered < 100 {
            session.answer(knewIt: false)
            answered += 1
        }
        #expect(session.isFinished)
        // 5개 + 각 1회 재시도 = 최대 10번.
        #expect(answered == 10)
        #expect(session.attemptedCount == 5)
        #expect(session.forgottenCount == 5)
    }

    /// 틀렸다가 다시 맞혀도 "다시 볼 표현"으로 센다 — 실제로 내일 다시 나오기 때문이다.
    @Test func retriedItemCountsAsForgottenInTheSummary() {
        var session = VocabularyStudySession(entries: entries(2))
        session.answer(knewIt: false)
        session.answer(knewIt: true)
        session.answer(knewIt: true)
        #expect(session.isFinished)
        #expect(session.attemptedCount == 2)
        #expect(session.knownCount == 1)
        #expect(session.forgottenCount == 1)
    }

    @Test func emptySessionIsFinishedImmediately() {
        var session = VocabularyStudySession(entries: [])
        session.answer(knewIt: true)
        #expect(session.isFinished)
        #expect(session.attemptedCount == 0)
    }

    // MARK: 저장 · 익힌 단어

    /// 저장은 학습 상태와 독립이다. 상태가 바뀌어도 저장 표시는 그대로다.
    @Test func savedFlagSurvivesStateTransitions() throws {
        let service = makeService(try makeContainer())
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: true)
        for day in ["2026-08-28", "2026-08-29", "2026-09-01", "2026-09-08", "2026-09-22"] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true,
                timeZone: seoul, now: try moment(day, seoul)
            )
        }
        let record = try state(service)
        #expect(record.isSaved)
        #expect(record.status == .mastered)
    }

    /// 저장을 풀어도 학습 기록은 지워지지 않는다.
    @Test func unsavingKeepsReviewHistory() throws {
        let service = makeService(try makeContainer())
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true,
            timeZone: seoul, now: try moment("2026-08-28", seoul)
        )
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: true)
        try service.setVocabularySaved(entryID: "cafe-crowded", isSaved: false)
        let record = try state(service)
        #expect(!record.isSaved)
        #expect(record.status == .reviewing)
        #expect(record.consecutiveSuccessCount == 1)
        #expect(record.nextReviewLocalDate == "2026-08-29")
    }

    /// 익힘은 자동 저장이 아니다.
    @Test func masteringDoesNotSaveTheWord() throws {
        let service = makeService(try makeContainer())
        for day in ["2026-08-28", "2026-08-29", "2026-09-01", "2026-09-08", "2026-09-22"] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true,
                timeZone: seoul, now: try moment(day, seoul)
            )
        }
        #expect(try state(service).isSaved == false)
    }

    /// 익힌 단어 목록은 status == mastered 그대로다.
    @Test func masteredListReflectsStatusExactly() throws {
        let service = makeService(try makeContainer())
        for day in ["2026-08-28", "2026-08-29", "2026-09-01", "2026-09-08", "2026-09-22"] {
            try service.recordVocabularyAnswer(
                entryID: "cafe-crowded", knewIt: true,
                timeZone: seoul, now: try moment(day, seoul)
            )
        }
        try service.recordVocabularyAnswer(
            entryID: "cafe-favorite-place", knewIt: true,
            timeZone: seoul, now: try moment("2026-09-22", seoul)
        )
        let mastered = try service.vocabularyStates()
            .filter { $0.status == .mastered }
            .map(\.entryID)
        #expect(mastered == ["cafe-crowded"])

        // 잊으면 목록에서 빠진다.
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: false,
            timeZone: seoul, now: try moment("2026-10-22", seoul)
        )
        #expect(try service.vocabularyStates().filter { $0.status == .mastered }.isEmpty)
    }
}
