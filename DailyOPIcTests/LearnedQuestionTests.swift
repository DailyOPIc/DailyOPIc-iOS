import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

// MARK: 공용 픽스처

/// 재료는 가벼운 사본 `PlannerLearnedQuestionRecord`다(P11.1). 테스트는 실제 학습이
/// 남기는 것과 같은 순서로 — 분석 기록을 넣고, 앱이 쓰는 경로로 사본을 만든다.
@MainActor
private enum LearnedQuestionFixture {
    // 기본 인자에서도 쓰므로 액터 밖에서 읽을 수 있어야 한다.
    nonisolated static let seoul = TimeZone(identifier: "Asia/Seoul")!
    nonisolated static let newYork = TimeZone(identifier: "America/New_York")!

    static func makeContext() throws -> (PersistenceService, ModelContext) {
        // 앱이 실제로 여는 스키마 그대로 연다. 목록이 어긋나면 여기서 먼저 터진다.
        let container = try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let service = PersistenceService()
        service.configure(context: context)
        return (service, context)
    }

    static func question(
        _ prompt: String,
        number: Int = 1,
        section: ExamSection = .survey,
        style: QuestionStyle? = nil
    ) -> GeneratedQuestion {
        GeneratedQuestion(
            number: number,
            examSection: section,
            comboId: nil,
            topic: "travel",
            prompt: prompt,
            difficulty: .IM2,
            rubricFocus: [],
            questionStyle: style
        )
    }

    static var evaluation: PracticeEvaluation {
        PracticeEvaluation(
            predictedLevel: .IM2,
            confidence: .medium,
            scores: EvaluationScores(
                taskFulfillment: 3, grammar: 3, vocabulary: 3, discourse: 3, fluency: 3
            ),
            strengths: [],
            improvements: [],
            correctedAnswer: nil,
            targetGap: nil,
            sampleAnswer: nil,
            audioMetrics: AudioMetrics(
                durationSeconds: 60, speakingSeconds: 50,
                silenceRatio: 0.1, wordsPerMinute: 100, isEstimated: nil
            ),
            disclaimer: "",
            modelVersion: "test",
            promptVersion: "test",
            resultStatus: nil,
            rubrics: nil,
            warnings: nil,
            scoreScaleVersion: nil,
            answerQuality: nil
        )
    }

    /// 학습 계획 타임존 기준 "그날 몇 시 몇 분"의 실제 순간.
    static func instant(
        _ localDate: String, _ hour: Int, _ minute: Int, in timeZone: TimeZone = seoul
    ) throws -> Date {
        let calendar = LocalCalendarDate.calendar(timeZone: timeZone)
        let start = try #require(LocalCalendarDate.date(from: localDate, timeZone: timeZone))
        return try #require(
            calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: start)
        )
    }

    /// 분석 성공이 실제로 남기는 기록 한 줄 + 그 사본.
    /// 사본은 손으로 만들지 않고 앱과 같은 경로(`backfillLearnedQuestions`)로 만든다.
    @discardableResult
    static func learn(
        _ prompt: String,
        at date: Date,
        number: Int = 1,
        style: QuestionStyle? = nil,
        in context: ModelContext,
        via service: PersistenceService
    ) throws -> PracticeHistoryRecord {
        let record = try PracticeHistoryRecord(
            createdAt: date,
            targetLevel: .IM2,
            question: question(prompt, number: number, style: style),
            transcript: "spoken answer",
            evaluation: evaluation
        )
        context.insert(record)
        try context.save()
        try service.backfillLearnedQuestions()
        return record
    }

    /// 사본만 직접 넣는다(보관·삭제 테스트에서 원본과의 관계를 끊어 볼 때 쓴다).
    @discardableResult
    static func snapshot(
        _ prompt: String, at date: Date, id: UUID = UUID(), in context: ModelContext
    ) throws -> PlannerLearnedQuestionRecord {
        let record = PlannerLearnedQuestionRecord(
            sourcePracticeHistoryID: id, learnedAt: date, prompt: prompt, kindLabel: "설문 주제"
        )
        context.insert(record)
        try context.save()
        return record
    }
}

// MARK: §22. 무엇이 "학습한 문제"를 만드는가

/// 학습한 문제 기록은 **실제로 분석에 성공한 Daily 학습**에서만 나온다.
/// 세트를 받은 것, 문제를 연 것, 분석에 실패한 것, 일정을 적은 것은 아무것도 남기지 않는다.
@MainActor
struct LearnedQuestionSourceTests {
    fileprivate typealias Fixture = LearnedQuestionFixture

    /// A. 분석에 성공한 Daily 학습만 기록을 만든다. 실제 저장 경로(`savePractice`)를 그대로 탄다.
    @Test func successfulDailyEvaluationCreatesOneEntry() throws {
        let (persistence, _) = try Fixture.makeContext()
        let now = Date.now
        try persistence.savePractice(
            targetLevel: .IM2,
            question: Fixture.question("집에서 보내는 휴일에 대해 말해주세요."),
            transcript: "spoken answer",
            evaluation: Fixture.evaluation
        )
        let today = LocalCalendarDate.text(from: now, timeZone: .current)
        let learned = try persistence.learnedQuestions(on: today, timeZone: .current)
        #expect(learned.count == 1)
        #expect(learned.first?.prompt == "집에서 보내는 휴일에 대해 말해주세요.")
    }

    /// B. 문제를 열어 보기만 한 것은 학습이 아니다. 저장 경로를 타지 않으면 남는 것도 없다.
    @Test func openingAQuestionWithoutCompletingLeavesNothing() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        // 세트를 받아 화면에 띄운 것까지는 아무 기록도 아니다.
        _ = Fixture.question("열어만 본 문제")
        try Fixture.learn("끝까지 끝낸 문제", at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        let learned = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(learned.map(\.prompt) == ["끝까지 끝낸 문제"])
    }

    /// C. 분석 실패는 기록을 만들지 않는다. 실패 경로는 `savePractice` 앞에서 던지고 끝난다.
    @Test func failedEvaluationLeavesNothing() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn("성공한 문제", at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        // 실패한 시도는 저장을 부르지 않는다 — 그래서 줄이 늘지 않는다.
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).count == 1)
    }

    /// D. 개인 일정은 학습이 아니다. 하루에 일정을 몇 개 적어도 문제 목록은 비어 있다.
    @Test func plannerEventsAreNotLearnedQuestions() throws {
        let (persistence, _) = try Fixture.makeContext()
        let day = "2026-08-19"
        try persistence.savePlannerEvent(localDate: day, title: "스터디 모임", timeMinutes: 19 * 60)
        try persistence.savePlannerEvent(localDate: day, title: "복습")
        #expect(try persistence.plannerEvents(on: day).count == 2)
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).isEmpty)
    }

    /// E. 모의고사는 이 목록에 들어오지 않는다. 저장소부터 따로다(`MockHistoryRecord`).
    @Test func mockExamIsNotIncluded() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        let at = try Fixture.instant(day, 20, 0)
        context.insert(
            try MockHistoryRecord(
                createdAt: at,
                targetLevel: .IM2,
                questionSet: QuestionSet(
                    setId: "mock-set",
                    setHash: "hash",
                    questions: [Fixture.question("모의고사 문항입니다.")],
                    modelVersion: "test",
                    generatedAt: at,
                    fallbackUsed: false
                ),
                answers: [],
                evaluation: MockEvaluation(
                    predictedLevel: .IM2,
                    confidence: .medium,
                    scores: EvaluationScores(
                        taskFulfillment: 3, grammar: 3, vocabulary: 3, discourse: 3, fluency: 3
                    ),
                    strengths: [], improvements: [], targetGap: "", overallFeedback: "",
                    perQuestion: [], disclaimer: "", modelVersion: "test", promptVersion: "test",
                    resultStatus: nil, rubrics: nil, warnings: nil,
                    scoreScaleVersion: nil, answerQuality: nil
                )
            )
        )
        try context.save()
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).isEmpty)
    }

    /// F. 화면에 뜨는 문장은 사용자가 실제로 본 그 문장이다.
    /// 주제·ID로 다시 만들지 않으므로 줄바꿈·따옴표·이모지까지 그대로 돌아와야 한다.
    @Test func promptIsTheExactTextTheUserSaw() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        let exact = "당신이 \"가장 좋아하는\" 카페를 묘사해 주세요.\n그곳에서 무엇을 하나요? ☕️"
        try Fixture.learn(exact, at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        let learned = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(learned.first?.prompt == exact)
    }

    /// 문제 분류는 문제 카드가 쓰는 것과 같은 라벨이다(내부 코드값을 노출하지 않는다).
    @Test func kindLabelMatchesTheQuestionCard() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn(
            "롤플레이 문제", at: try Fixture.instant(day, 19, 12), style: .roleplay, in: context, via: persistence
        )
        try Fixture.learn(
            "설문 문제", at: try Fixture.instant(day, 19, 30), number: 2, in: context, via: persistence
        )
        let learned = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(learned.map(\.kindLabel) == ["롤플레이", "설문 주제"])
    }
}

// MARK: §23. 날짜 묶기

/// 문제는 학습 계획 타임존 기준 그날 칸에만 들어가고, 날짜를 넘나들지 않는다.
@MainActor
struct LearnedQuestionDateTests {
    fileprivate typealias Fixture = LearnedQuestionFixture

    /// A. 한 문제는 자기 날짜에만 나타난다.
    @Test func questionAppearsOnItsOwnDate() throws {
        let (persistence, context) = try Fixture.makeContext()
        try Fixture.learn("여행 이야기", at: try Fixture.instant("2026-08-19", 19, 12), in: context, via: persistence)
        #expect(try persistence.learnedQuestions(on: "2026-08-19", timeZone: Fixture.seoul).count == 1)
        #expect(try persistence.learnedQuestions(on: "2026-08-18", timeZone: Fixture.seoul).isEmpty)
        #expect(try persistence.learnedQuestions(on: "2026-08-20", timeZone: Fixture.seoul).isEmpty)
    }

    /// B. 같은 날 여러 문제는 한 목록에 모인다.
    @Test func multipleQuestionsShareOneDay() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn("첫 문제", at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        try Fixture.learn("둘째 문제", at: try Fixture.instant(day, 19, 20), number: 2, in: context, via: persistence)
        try Fixture.learn("셋째 문제", at: try Fixture.instant(day, 19, 31), number: 3, in: context, via: persistence)
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).count == 3)
    }

    /// C. 다른 날의 문제는 섞이지 않는다.
    @Test func questionsOnDifferentDatesStaySeparated() throws {
        let (persistence, context) = try Fixture.makeContext()
        try Fixture.learn("수요일 문제", at: try Fixture.instant("2026-08-19", 19, 12), in: context, via: persistence)
        try Fixture.learn("목요일 문제", at: try Fixture.instant("2026-08-20", 9, 0), in: context, via: persistence)
        #expect(
            try persistence.learnedQuestions(on: "2026-08-19", timeZone: Fixture.seoul)
                .map(\.prompt) == ["수요일 문제"]
        )
        #expect(
            try persistence.learnedQuestions(on: "2026-08-20", timeZone: Fixture.seoul)
                .map(\.prompt) == ["목요일 문제"]
        )
    }

    /// D. 그날의 학습 흐름 순서 — 오래된 것이 먼저다. 넣은 순서와 무관하다.
    @Test func questionsAreOrderedOldestFirst() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn("셋째", at: try Fixture.instant(day, 19, 31), number: 3, in: context, via: persistence)
        try Fixture.learn("첫째", at: try Fixture.instant(day, 19, 12), number: 1, in: context, via: persistence)
        try Fixture.learn("둘째", at: try Fixture.instant(day, 19, 20), number: 2, in: context, via: persistence)
        let learned = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(learned.map(\.prompt) == ["첫째", "둘째", "셋째"])
        #expect(learned.map(\.timeText) == ["19:12", "19:20", "19:31"])
    }

    /// E. 같은 학습(같은 원본 기록)은 몇 번을 다시 옮겨도 한 줄이다.
    /// 판정 기준은 원본 기록 ID다 — 분·문장으로 추측하지 않는다(P11.1).
    @Test func sameSourceRecordCannotProduceTwoRows() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn("같은 문제", at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        try persistence.backfillLearnedQuestions()
        try persistence.backfillLearnedQuestions()
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).count == 1)
    }

    /// 같은 분에 같은 문제를 **두 번 성공**한 것은 진짜 두 번이다. 원본 기록이 둘이면 줄도 둘이다.
    /// P11의 (분 + 문장) 접기는 이 사실을 지웠기 때문에 P11.1에서 걷어냈다.
    @Test func samePromptInTheSameMinuteFromTwoRecordsStaysTwoRows() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        let at = try Fixture.instant(day, 19, 12)
        let first = try Fixture.learn("같은 문제", at: at, in: context, via: persistence)
        let second = try Fixture.learn("같은 문제", at: at, in: context, via: persistence)
        #expect(first.id != second.id)
        let learned = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(learned.count == 2)
        #expect(Set(learned.map(\.id)) == [first.id, second.id])
    }

    /// 진짜 다시 학습한 것(몇 분 뒤 같은 문제)은 접지 않는다. 두 번 한 것은 두 줄이다.
    @Test func genuineRelearningLaterStaysTwoRows() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn("같은 문제", at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        try Fixture.learn("같은 문제", at: try Fixture.instant(day, 20, 40), in: context, via: persistence)
        let learned = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(learned.count == 2)
        #expect(learned.map(\.timeText) == ["19:12", "20:40"])
    }

    /// F. 자정 경계. 23:59와 00:00은 다른 날이다.
    @Test func localMidnightSplitsTwoDays() throws {
        let (persistence, context) = try Fixture.makeContext()
        try Fixture.learn("어제 마지막", at: try Fixture.instant("2026-08-19", 23, 59), in: context, via: persistence)
        try Fixture.learn("오늘 첫", at: try Fixture.instant("2026-08-20", 0, 0), in: context, via: persistence)
        #expect(
            try persistence.learnedQuestions(on: "2026-08-19", timeZone: Fixture.seoul)
                .map(\.prompt) == ["어제 마지막"]
        )
        #expect(
            try persistence.learnedQuestions(on: "2026-08-20", timeZone: Fixture.seoul)
                .map(\.prompt) == ["오늘 첫"]
        )
    }

    /// G·H. 어느 날인지는 **넘겨받은 학습 계획 타임존**이 정한다.
    /// 같은 순간이라도 서울에서는 20일 아침, 뉴욕에서는 19일 저녁이다.
    /// 기기 타임존이나 UTC는 이 판정에 끼어들지 않는다 — 여행해도 계획 타임존이 그대로면
    /// 이미 저장된 학습이 다른 칸으로 옮겨 가지 않는다.
    @Test func plannerTimeZoneDecidesTheDateNotTheDevice() throws {
        let (persistence, context) = try Fixture.makeContext()
        // 서울 2026-08-20 07:00 = 뉴욕 2026-08-19 18:00 = UTC 2026-08-19 22:00
        let at = try Fixture.instant("2026-08-20", 7, 0, in: Fixture.seoul)
        try Fixture.learn("같은 순간의 학습", at: at, in: context, via: persistence)

        #expect(try persistence.learnedQuestions(on: "2026-08-20", timeZone: Fixture.seoul).count == 1)
        #expect(try persistence.learnedQuestions(on: "2026-08-19", timeZone: Fixture.seoul).isEmpty)
        #expect(try persistence.learnedQuestions(on: "2026-08-19", timeZone: Fixture.newYork).count == 1)
        #expect(try persistence.learnedQuestions(on: "2026-08-20", timeZone: Fixture.newYork).isEmpty)
    }

    /// 히트맵이 완료 기록을 세는 변환과 같은 규칙이라, 칸과 시트가 다른 날을 가리킬 수 없다.
    @Test func groupingMatchesTheHeatmapConversion() throws {
        let (persistence, context) = try Fixture.makeContext()
        let calendar = LocalCalendarDate.calendar(timeZone: Fixture.seoul)
        let at = try Fixture.instant("2026-08-20", 0, 30)
        try Fixture.learn("자정 직후 학습", at: at, in: context, via: persistence)
        try persistence.recordStudySetCompletion(setId: "set-1", at: at)

        let counts = StudyCalendarEngine.completionCounts(
            completedAt: try persistence.studySetCompletionDates(), calendar: calendar
        )
        let heatmapDay = try #require(counts.keys.first)
        #expect(LocalCalendarDate.text(from: heatmapDay, timeZone: Fixture.seoul) == "2026-08-20")
        #expect(try persistence.learnedQuestions(on: "2026-08-20", timeZone: Fixture.seoul).count == 1)
    }

    /// 하루치만 읽는다. 다른 날 기록이 아무리 많아도 그날 것만 돌아온다.
    @Test func onlyTheSelectedDateIsLoaded() throws {
        let (persistence, context) = try Fixture.makeContext()
        for day in 1...28 {
            let date = String(format: "2026-08-%02d", day)
            try Fixture.learn("문제 \(day)", at: try Fixture.instant(date, 19, 0), in: context, via: persistence)
        }
        let learned = try persistence.learnedQuestions(on: "2026-08-15", timeZone: Fixture.seoul)
        #expect(learned.map(\.prompt) == ["문제 15"])
    }
}

// MARK: §24. 문제 내용이 남지 않은 날

/// 학습한 사실은 남아 있는데 문제 내용이 없을 수 있다(구버전 학습 · 보관 한도 초과 ·
/// 사용자가 기록 탭에서 전체 삭제). 그럴 때 문제를 지어내지 않고 그대로 말한다.
@MainActor
struct LearnedQuestionLegacyTests {
    fileprivate typealias Fixture = LearnedQuestionFixture

    private func sample(minute: Int = 12, prompt: String = "문제") -> LearnedQuestion {
        LearnedQuestion(
            id: UUID(),
            learnedAt: Date(timeIntervalSince1970: TimeInterval(minute) * 60),
            minuteOfDay: 19 * 60 + minute,
            prompt: prompt,
            kindLabel: "설문 주제"
        )
    }

    /// A. 학습은 했는데 문제 내용이 없다 → 설명 문구를 보여준다.
    @Test func learningWithoutDetailShowsTheExplanation() {
        #expect(
            LearnedQuestionSection.make(questions: [], completedSets: 2) == .unavailable
        )
    }

    /// B. 학습 자체가 없던 날에는 설명 문구가 뜨지 않는다.
    /// 미래 날짜·휴식일·아무것도 안 한 날이 전부 여기 해당한다(완료 수가 0이다).
    @Test func daysWithoutLearningStaySilent() {
        #expect(LearnedQuestionSection.make(questions: [], completedSets: 0) == .hidden)
    }

    /// C. 문제 내용이 있으면 평범하게 목록을 보여주고 설명 문구는 나오지 않는다.
    @Test func availableDetailShowsTheListOnly() {
        let section = LearnedQuestionSection.make(questions: [sample()], completedSets: 1)
        guard case let .questions(rows) = section else {
            Issue.record("목록이 나와야 한다")
            return
        }
        #expect(rows.count == 1)
        #expect(section != .unavailable)
    }

    /// 아직 읽기 전에는 아무것도 그리지 않는다. 시트가 열리는 순간 설명이 깜빡이면 안 된다.
    @Test func nothingIsShownBeforeTheQueryFinishes() {
        #expect(LearnedQuestionSection.make(questions: nil, completedSets: 3) == .hidden)
        #expect(LearnedQuestionSection.make(questions: nil, completedSets: 0) == .hidden)
    }

    /// D. 문제 내용이 없다고 해서 그날의 학습 횟수·상태가 달라지지 않는다.
    /// 히트맵과 요약은 완료 기록만 보고, 이 칸은 그 값을 읽기만 한다.
    @Test func missingDetailDoesNotChangeCountsOrHeatmap() throws {
        let day = StudyDay(
            date: try Fixture.instant("2026-08-19", 0, 0),
            state: .partial,
            completedSets: 2,
            targetSets: 3
        )
        #expect(LearnedQuestionSection.make(questions: [], completedSets: day.completedSets) == .unavailable)
        #expect(day.completedSets == 2)
        #expect(LearningActivityLevel.make(completedSets: day.completedSets) == .two)
        #expect(
            PlannerDayStudyStatus.make(day: day, isStudyWeekday: true)
                .summaryText(day: day, isToday: false) == "2 / 3세트 학습"
        )
    }

    /// 설명 문구는 원인을 특정하지 않는다. 구버전 학습만이 이유가 아니기 때문이다.
    @Test func explanationCopyIsHonestAndCalm() {
        #expect(LearnedQuestionSection.unavailableTitle == "이전 학습 기록")
        #expect(
            LearnedQuestionSection.unavailableDetail
                == "이 날의 학습 기록은 남아 있지만, 문제 내용은 저장돼 있지 않아요."
        )
        for banned in ["실패", "오류", "손실", "복구"] {
            #expect(!LearnedQuestionSection.unavailableDetail.contains(banned))
        }
    }
}

// MARK: §25·§26. 시트 배치와 접근성

/// 시트 안에서의 자리와 읽히는 문장. 화면을 그리지 않고 순수 값으로만 확인한다.
@MainActor
struct LearnedQuestionPresentationTests {
    private func sample(
        minute: Int, prompt: String, at seconds: TimeInterval? = nil
    ) -> LearnedQuestion {
        LearnedQuestion(
            id: UUID(),
            learnedAt: Date(timeIntervalSince1970: seconds ?? TimeInterval(minute) * 60),
            minuteOfDay: minute,
            prompt: prompt,
            kindLabel: "설문 주제"
        )
    }

    /// 학습한 문제 칸은 학습 요약과 개인 일정 **사이**에 있다.
    @Test func questionSectionSitsBetweenStudyAndEvents() throws {
        #expect(
            PlannerDaySheetSection.allCases
                == [.examDay, .study, .learnedQuestions, .personalEvents]
        )
        let order = PlannerDaySheetSection.allCases
        let study = try #require(order.firstIndex(of: .study))
        let questions = try #require(order.firstIndex(of: .learnedQuestions))
        let events = try #require(order.firstIndex(of: .personalEvents))
        #expect(study < questions)
        #expect(questions < events)
    }

    /// 화면을 밀어내는 경로는 P10에서 없앤 그대로다. 문제 목록도 새 화면을 만들지 않는다.
    @Test func noPushRouteIsReintroduced() {
        #expect(Set(PlannerRoute.allCases) == [.settings, .notifications])
        #expect(PlannerRoute.allCases.count == 2)
    }

    /// 메모는 돌아오지 않았다. 칸은 P12에서 시험일 안내 하나만 늘었고 자유 입력 칸은 없다.
    @Test func noMemoSectionReturns() {
        #expect(PlannerDaySheetSection.allCases.count == 4)
        #expect(
            Schema.dailyOPIc.entities.map(\.name).contains("PlannerDayNoteRecord") == false
        )
    }

    /// 시각 표기는 로케일이 아니라 학습 계획 타임존 기준의 벽시계 그대로다.
    @Test func timeTextIsZeroPaddedWallClock() {
        #expect(sample(minute: 19 * 60 + 12, prompt: "문제").timeText == "19:12")
        #expect(sample(minute: 9 * 60 + 5, prompt: "문제").timeText == "09:05")
        #expect(sample(minute: 0, prompt: "문제").timeText == "00:00")
        #expect(sample(minute: 23 * 60 + 59, prompt: "문제").timeText == "23:59")
    }

    /// VoiceOver는 시각을 자연스럽게 읽고 내부 ID는 읽지 않는다.
    @Test func voiceOverReadsTimeThenQuestion() {
        let row = sample(minute: 19 * 60 + 12, prompt: "집에서 보내는 휴일에 대해 말해주세요.")
        #expect(row.accessibilityText == "19시 12분, 집에서 보내는 휴일에 대해 말해주세요.")
        #expect(!row.accessibilityText.contains(row.id.uuidString))
        for banned in ["setId", "questionId", "UUID", "번호"] {
            #expect(!row.accessibilityText.contains(banned))
        }
    }

    /// 칸 제목은 하나뿐이다.
    @Test func sectionTitleIsFixed() {
        #expect(LearnedQuestionSection.title == "학습한 문제")
    }

    /// 많은 문제도 잘라내지 않는다. 목록은 세로로 늘어나고 시트가 스크롤한다.
    @Test func manyQuestionsAreAllKept() {
        let rows = (0..<30).map { sample(minute: 8 * 60 + $0, prompt: "문제 \($0)") }
        let timeline = LearnedQuestion.timeline(rows)
        #expect(timeline.count == 30)
        #expect(timeline.first?.prompt == "문제 0")
        #expect(timeline.last?.prompt == "문제 29")
    }

    /// 정렬은 사전순이 아니라 시간순이다.
    @Test func orderingIsChronologicalNotAlphabetical() {
        let rows = [
            sample(minute: 20 * 60, prompt: "가장 먼저 오는 글자"),
            sample(minute: 9 * 60, prompt: "하늘에 대해 말해주세요")
        ]
        #expect(LearnedQuestion.timeline(rows).map(\.prompt) == ["하늘에 대해 말해주세요", "가장 먼저 오는 글자"])
    }

    /// 같은 시각이면 순서를 ID로 고정한다 — 다시 그릴 때마다 줄이 뒤바뀌지 않는다.
    @Test func identicalTimestampsKeepAStableOrder() {
        let rows = [
            sample(minute: 19 * 60, prompt: "A", at: 100),
            sample(minute: 19 * 60, prompt: "B", at: 100)
        ]
        #expect(LearnedQuestion.timeline(rows) == LearnedQuestion.timeline(rows.reversed()))
    }
}

// MARK: §15. 보관 — 풍부한 기록과 가벼운 사본은 다른 창을 쓴다

/// 분석 기록은 최근 50개, 문제 사본은 366일. 이 비대칭이 P11.1의 전부다.
@MainActor
struct LearnedQuestionRetentionTests {
    fileprivate typealias Fixture = LearnedQuestionFixture

    private func saveOne(_ prompt: String, _ persistence: PersistenceService) throws {
        try persistence.savePractice(
            targetLevel: .IM2,
            question: Fixture.question(prompt),
            transcript: "spoken answer",
            evaluation: Fixture.evaluation
        )
    }

    private func richCount(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<PracticeHistoryRecord>()).count
    }

    private func snapshots(_ context: ModelContext) throws -> [PlannerLearnedQuestionRecord] {
        try context.fetch(FetchDescriptor<PlannerLearnedQuestionRecord>())
    }

    /// A. 분석 기록의 50개 정책은 그대로다. P11.1이 이걸 늘리지 않는다.
    @Test func practiceHistoryStaysCappedAtFifty() throws {
        let (persistence, context) = try Fixture.makeContext()
        for index in 0..<60 { try saveOne("문제 \(index)", persistence) }
        #expect(try richCount(context) == 50)
    }

    /// B. 50개 창 밖으로 밀려난 학습도 **문제 문장은 남는다**. P11.1이 존재하는 이유다.
    @Test func snapshotsSurviveAfterTheRichRecordIsTrimmed() throws {
        let (persistence, context) = try Fixture.makeContext()
        for index in 0..<60 { try saveOne("문제 \(index)", persistence) }
        #expect(try richCount(context) == 50)
        #expect(try snapshots(context).count == 60)
        // 가장 오래된 학습은 분석 기록이 사라졌는데도 문제 문장이 남아 있다.
        let survivor = try #require(try snapshots(context).first { $0.prompt == "문제 0" })
        let sourceId = survivor.sourcePracticeHistoryID
        let rich = try context.fetch(
            FetchDescriptor<PracticeHistoryRecord>(predicate: #Predicate { $0.id == sourceId })
        )
        #expect(rich.isEmpty)
        let today = LocalCalendarDate.text(from: .now, timeZone: .current)
        #expect(try persistence.learnedQuestions(on: today, timeZone: .current).count == 60)
    }

    /// C·D·E. 창은 완료 기록과 같은 366일이고, 그 밖은 지워진다. 무한히 쌓이지 않는다.
    @Test func snapshotsFollowTheThreeHundredSixtySixDayWindow() throws {
        let (persistence, context) = try Fixture.makeContext()
        let calendar = Calendar.current
        let inside = try #require(calendar.date(byAdding: .day, value: -300, to: .now))
        let outside = try #require(calendar.date(byAdding: .day, value: -400, to: .now))
        try Fixture.snapshot("300일 전 문제", at: inside, in: context)
        try Fixture.snapshot("400일 전 문제", at: outside, in: context)

        try persistence.backfillLearnedQuestions()   // 정리는 기존 저장 수명주기 안에서 돈다

        #expect(try snapshots(context).map(\.prompt) == ["300일 전 문제"])
    }

    /// F. 사본에는 전사도 평가도 없다. 스키마에 적힌 것이 전부다.
    @Test func snapshotStoresNothingSensitive() throws {
        let entity = try #require(
            Schema.dailyOPIc.entities.first { $0.name == "PlannerLearnedQuestionRecord" }
        )
        let properties = Set(entity.properties.map(\.name))
        #expect(properties == ["sourcePracticeHistoryID", "learnedAt", "prompt", "kindLabel"])
        for banned in [
            "transcript", "evaluationData", "answersData", "audio",
            "predictedLevelRaw", "targetLevelRaw", "uid", "token", "receipt"
        ] {
            #expect(!properties.contains(banned))
        }
    }

    /// 스키마 그대로 열리고 사본이 왕복한다(P11.1은 추가만 하는 변경이다).
    @Test func snapshotRoundTripsThroughTheRealSchema() throws {
        let (_, context) = try Fixture.makeContext()
        let at = try Fixture.instant("2026-08-19", 19, 12)
        let id = UUID()
        try Fixture.snapshot("왕복 문제", at: at, id: id, in: context)
        let stored = try #require(try snapshots(context).first)
        #expect(stored.sourcePracticeHistoryID == id)
        #expect(stored.learnedAt == at)
        #expect(stored.prompt == "왕복 문제")
        #expect(stored.kindLabel == "설문 주제")
    }
}

// MARK: §16. 쓰기와 백필

/// 사본은 **분석 성공과 같은 저장**에서만 생기고, 이미 남아 있던 기록은 한 번 옮겨 온다.
@MainActor
struct LearnedQuestionBackfillTests {
    fileprivate typealias Fixture = LearnedQuestionFixture

    private func snapshots(_ context: ModelContext) throws -> [PlannerLearnedQuestionRecord] {
        try context.fetch(FetchDescriptor<PlannerLearnedQuestionRecord>())
    }

    /// A·E. 분석 성공 한 번 = 사본 한 줄, 문장은 사용자가 본 그대로.
    @Test func successfulEvaluationWritesTheSnapshotInTheSameSave() throws {
        let (persistence, context) = try Fixture.makeContext()
        let exact = "집에서 보내는 휴일에 대해 말해주세요.\n무엇을 하나요? ☕️"
        try persistence.savePractice(
            targetLevel: .IM2,
            question: Fixture.question(exact, style: .roleplay),
            transcript: "spoken answer",
            evaluation: Fixture.evaluation
        )
        #expect(try snapshots(context).count == 1)
        let stored = try #require(try snapshots(context).first)
        #expect(stored.prompt == exact)
        #expect(stored.kindLabel == "롤플레이")
        // 원본 기록과 같은 ID로 묶인다.
        let rich = try #require(try persistence.latestPracticeRecord())
        #expect(stored.sourcePracticeHistoryID == rich.id)
    }

    /// B. 분석에 실패하면 저장 경로 자체를 타지 않는다 — 사본도 없다.
    @Test func failedEvaluationWritesNoSnapshot() throws {
        let (_, context) = try Fixture.makeContext()
        // 실패는 `savePractice` 앞에서 끝난다. 아무것도 부르지 않은 상태가 곧 그 상태다.
        #expect(try snapshots(context).isEmpty)
    }

    /// C. 문제를 열어만 본 것도 사본을 만들지 않는다.
    @Test func openingAQuestionWritesNoSnapshot() throws {
        let (persistence, context) = try Fixture.makeContext()
        _ = Fixture.question("열어만 본 문제")
        try persistence.backfillLearnedQuestions()
        #expect(try snapshots(context).isEmpty)
    }

    /// D. 모의고사는 사본을 만들지 않는다. 저장 경로가 다르다.
    @Test func mockExamWritesNoSnapshot() throws {
        let (persistence, context) = try Fixture.makeContext()
        try persistence.saveMock(
            targetLevel: .IM2,
            questionSet: QuestionSet(
                setId: "mock-set",
                setHash: "hash",
                questions: [Fixture.question("모의고사 문항입니다.")],
                modelVersion: "test",
                generatedAt: .now,
                fallbackUsed: false
            ),
            answers: [],
            evaluation: MockEvaluation(
                predictedLevel: .IM2,
                confidence: .medium,
                scores: EvaluationScores(
                    taskFulfillment: 3, grammar: 3, vocabulary: 3, discourse: 3, fluency: 3
                ),
                strengths: [], improvements: [], targetGap: "", overallFeedback: "",
                perQuestion: [], disclaimer: "", modelVersion: "test", promptVersion: "test",
                resultStatus: nil, rubrics: nil, warnings: nil,
                scoreScaleVersion: nil, answerQuality: nil
            )
        )
        try persistence.backfillLearnedQuestions()
        #expect(try snapshots(context).isEmpty)
    }

    /// F. 이 빌드를 처음 열 때 남아 있던 분석 기록의 문제 문장을 옮겨 온다.
    @Test func backfillCopiesSurvivingRichHistory() throws {
        let (persistence, context) = try Fixture.makeContext()
        for index in 0..<3 {
            let record = try PracticeHistoryRecord(
                createdAt: try Fixture.instant("2026-08-19", 19, index),
                targetLevel: .IM2,
                question: Fixture.question("이전 빌드 문제 \(index)", number: index + 1),
                transcript: "spoken answer",
                evaluation: Fixture.evaluation
            )
            context.insert(record)
        }
        try context.save()

        #expect(try persistence.backfillLearnedQuestions() == 3)
        #expect(
            try persistence.learnedQuestions(on: "2026-08-19", timeZone: Fixture.seoul)
                .map(\.prompt) == ["이전 빌드 문제 0", "이전 빌드 문제 1", "이전 빌드 문제 2"]
        )
    }

    /// G·I. 다시 돌려도 결과가 같다. 원본 ID가 유니크라 두 줄이 되지 않는다.
    @Test func backfillIsIdempotent() throws {
        let (persistence, context) = try Fixture.makeContext()
        try Fixture.learn("문제", at: try Fixture.instant("2026-08-19", 19, 12), in: context, via: persistence)
        #expect(try persistence.backfillLearnedQuestions() == 0)
        #expect(try persistence.backfillLearnedQuestions() == 0)
        #expect(try snapshots(context).count == 1)
    }

    /// H. 같은 문장을 같은 분에 두 번 성공한 것은 원본이 둘이므로 사본도 둘이다.
    @Test func twoDistinctRecordsInTheSameMinuteKeepTwoSnapshots() throws {
        let (persistence, context) = try Fixture.makeContext()
        let at = try Fixture.instant("2026-08-19", 19, 12)
        try Fixture.learn("같은 문제", at: at, in: context, via: persistence)
        try Fixture.learn("같은 문제", at: at, in: context, via: persistence)
        #expect(try snapshots(context).count == 2)
    }

    /// 백필은 남아 있는 기록만 옮긴다. 없는 과거를 만들어 내지 않는다.
    @Test func backfillNeverInventsMissingHistory() throws {
        let (persistence, context) = try Fixture.makeContext()
        // 완료 기록만 있고 분석 기록이 없는 날 = 문제 문장이 사라진 과거.
        try persistence.recordStudySetCompletion(
            setId: "old-set", at: try Fixture.instant("2026-08-01", 19, 0)
        )
        #expect(try persistence.backfillLearnedQuestions() == 0)
        #expect(try snapshots(context).isEmpty)
        #expect(try persistence.learnedQuestions(on: "2026-08-01", timeZone: Fixture.seoul).isEmpty)
    }
}

// MARK: §17. 기록 삭제

/// 사용자가 기록을 지우면 문제 문장도 함께 사라진다. 플래너에 몰래 남는 사본은 없다.
@MainActor
struct LearnedQuestionDeletionTests {
    fileprivate typealias Fixture = LearnedQuestionFixture

    /// A·D. 전체 삭제 → 사본도 사라지고, 어디에도 문제 문장이 남지 않는다.
    @Test func deletingHistoryAlsoDeletesTheQuestionSnapshots() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        try Fixture.learn("지워질 문제", at: try Fixture.instant(day, 19, 12), in: context, via: persistence)
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).count == 1)

        try persistence.deleteAllHistory()

        #expect(try context.fetch(FetchDescriptor<PlannerLearnedQuestionRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PracticeHistoryRecord>()).isEmpty)
        #expect(try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul).isEmpty)
    }

    /// B·C. 달력의 학습량은 기존 정책대로 남고, 그날 시트는 정직한 안내로 돌아간다.
    @Test func aggregateLearningHistorySurvivesAndTheSheetFallsBack() throws {
        let (persistence, context) = try Fixture.makeContext()
        let day = "2026-08-19"
        let at = try Fixture.instant(day, 19, 12)
        try Fixture.learn("지워질 문제", at: at, in: context, via: persistence)
        try persistence.recordStudySetCompletion(setId: "set-1", at: at)

        try persistence.deleteAllHistory()

        // 완료 기록(= 히트맵·연속 학습의 재료)은 그대로다.
        #expect(try persistence.studySetCompletionDates().count == 1)
        let questions = try persistence.learnedQuestions(on: day, timeZone: Fixture.seoul)
        #expect(questions.isEmpty)
        #expect(
            LearnedQuestionSection.make(questions: questions, completedSets: 1) == .unavailable
        )
    }

    /// 삭제는 모의고사 기록과 작성 중이던 초안까지 기존과 똑같이 지운다(범위를 줄이지 않았다).
    @Test func deletionStillClearsMockHistoryAndDraft() throws {
        let (persistence, context) = try Fixture.makeContext()
        try persistence.saveDraft(
            targetLevel: .IM2,
            questionSet: QuestionSet(
                setId: "draft-set", setHash: "hash",
                questions: [Fixture.question("초안 문항")],
                modelVersion: "test", generatedAt: .now, fallbackUsed: false
            ),
            answers: []
        )
        try persistence.deleteAllHistory()
        #expect(try context.fetch(FetchDescriptor<MockHistoryRecord>()).isEmpty)
        #expect(try persistence.latestDraft() == nil)
    }
}
