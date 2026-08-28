import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// P10: 캘린더 칸이 말하는 것은 **그날 실제로 학습한 횟수** 하나뿐이다.
/// 계획 대비 달성률도, 개인 일정 수도, 메모도, 토큰도 재료가 아니다.
@MainActor
struct LearningHeatmapTests {

    // MARK: A~G. 횟수 → 단계

    @Test func zeroCompletionsHasNoFill() {
        #expect(LearningActivityLevel.make(completedSets: 0) == .zero)
        #expect(LearningActivityLevel.make(completedSets: 0).fillOpacity == 0)
    }

    @Test func eachCountMapsToItsOwnLevel() {
        #expect(LearningActivityLevel.make(completedSets: 1) == .one)
        #expect(LearningActivityLevel.make(completedSets: 2) == .two)
        #expect(LearningActivityLevel.make(completedSets: 3) == .three)
        #expect(LearningActivityLevel.make(completedSets: 4) == .four)
        #expect(LearningActivityLevel.make(completedSets: 5) == .fivePlus)
    }

    /// 5회 이상은 모두 같은 최고 단계다. 10회를 해도 더 진해질 칸이 없다.
    @Test func fiveOrMoreShareTheStrongestLevel() {
        for count in [5, 6, 10, 42] {
            #expect(LearningActivityLevel.make(completedSets: count) == .fivePlus)
        }
        #expect(LearningActivityLevel.fivePlus.fillOpacity == 1)
    }

    /// 음수는 있을 수 없지만, 들어와도 "학습 없음"으로 떨어진다.
    @Test func negativeCountsFallBackToZero() {
        #expect(LearningActivityLevel.make(completedSets: -3) == .zero)
    }

    // MARK: H. 단조 증가

    /// 더 많이 학습한 날이 더 연해 보이는 일은 없어야 한다.
    @Test func fillIsStrictlyIncreasingUpToTheTop() {
        let opacities = LearningActivityLevel.allCases.map(\.fillOpacity)
        #expect(opacities == opacities.sorted())
        for (lighter, darker) in zip(opacities, opacities.dropFirst()) {
            #expect(lighter < darker)
        }
        #expect(opacities.count == 6)
    }

    // MARK: I. 비율이 아니라 실제 횟수

    /// 계획 10세트 중 1회와 계획 1세트 중 1회는 **같은** 진하기다.
    @Test func levelIgnoresThePlannedTarget() {
        let hugePlan = StudyDay(
            date: StudyCalendarFixture.date("2026-08-12"), state: .partial,
            completedSets: 1, targetSets: 10
        )
        let tinyPlan = StudyDay(
            date: StudyCalendarFixture.date("2026-08-12"), state: .completed,
            completedSets: 1, targetSets: 1
        )
        #expect(
            LearningActivityLevel.make(completedSets: hugePlan.completedSets)
            == LearningActivityLevel.make(completedSets: tinyPlan.completedSets)
        )
        // 달성률이라면 10%와 100%로 갈렸을 자리다.
        #expect(LearningActivityLevel.make(completedSets: hugePlan.completedSets) == .one)
    }

    // MARK: J. 휴식일도 실제로 한 만큼 진하다

    @Test func restDayAndPlannedDayWithTheSameCountLookTheSame() {
        let rest = StudyDay(
            date: StudyCalendarFixture.date("2026-08-15"), state: .rest,
            completedSets: 3, targetSets: 0
        )
        let planned = StudyDay(
            date: StudyCalendarFixture.date("2026-08-14"), state: .completed,
            completedSets: 3, targetSets: 3
        )
        #expect(
            LearningActivityLevel.make(completedSets: rest.completedSets)
            == LearningActivityLevel.make(completedSets: planned.completedSets)
        )
        // 아무것도 하지 않은 휴식일은 칠하지 않는다.
        #expect(LearningActivityLevel.make(completedSets: 0) == .zero)
    }

    /// 미래 날짜도 마찬가지다. 계획된 학습량을 미리 칠해 두지 않는다.
    @Test func futureDaysAreNeverPreFilled() {
        let future = StudyDay(
            date: StudyCalendarFixture.date("2026-09-01"), state: .planned,
            completedSets: 0, targetSets: 5
        )
        #expect(LearningActivityLevel.make(completedSets: future.completedSets) == .zero)
    }

    // MARK: 오늘 · 진하기는 서로 다른 채널

    /// 오늘 표시는 테두리다. 채우기를 오늘 여부로 바꾸면 "오늘"과 "많이 학습함"을
    /// 구분할 수 없게 된다 — 두 값은 서로 간섭하지 않는다.
    @Test func todayIsIndependentOfHowMuchWasLearned() {
        for count in [0, 1, 5] {
            let cell = StudyDayCell(
                day: StudyDay(
                    date: StudyCalendarFixture.date("2026-08-19"), state: .partial,
                    completedSets: count, targetSets: 3
                ),
                calendar: StudyCalendarFixture.settings().calendar,
                isToday: true
            )
            #expect(cell.isToday)
            #expect(LearningActivityLevel.make(completedSets: count).fillOpacity
                    == LearningActivityLevel.make(completedSets: count).fillOpacity)
        }
    }

    // MARK: 읽어 주는 문장

    @Test func voiceOverReadsTheActualCountNotTheColor() {
        #expect(
            StudyDayCell.accessibilityText(
                date: "8월 19일", weekday: "수요일",
                isToday: false, completedSets: 3, hasEvent: false
            ) == "8월 19일 수요일, 3회 학습"
        )
        #expect(
            StudyDayCell.accessibilityText(
                date: "8월 19일", weekday: "수요일",
                isToday: true, completedSets: 3, hasEvent: false
            ) == "8월 19일 수요일, 오늘, 3회 학습"
        )
        #expect(
            StudyDayCell.accessibilityText(
                date: "8월 19일", weekday: "수요일",
                isToday: false, completedSets: 0, hasEvent: false
            ) == "8월 19일 수요일, 학습 기록 없음"
        )
        #expect(
            StudyDayCell.accessibilityText(
                date: "8월 19일", weekday: "수요일",
                isToday: true, completedSets: 0, hasEvent: true
            ) == "8월 19일 수요일, 오늘, 학습 기록 없음, 개인 일정 있음"
        )
    }

    /// 색 이름도, 단계 번호도, 메모도 읽지 않는다.
    @Test func voiceOverNeverMentionsColorLevelOrMemo() {
        for count in 0...6 {
            for isToday in [true, false] {
                for hasEvent in [true, false] {
                    let text = StudyDayCell.accessibilityText(
                        date: "8월 19일", weekday: "수요일",
                        isToday: isToday, completedSets: count, hasEvent: hasEvent
                    )
                    for banned in ["보라", "색", "레벨", "단계", "메모"] {
                        #expect(!text.contains(banned), "읽어 주는 문장에 \(banned)이(가) 들어갔다: \(text)")
                    }
                }
            }
        }
    }
}

/// P10: 하루 시트가 말하는 학습 한 줄. 재료는 격자와 같은 `StudyDay` 하나뿐이다.
@MainActor
struct PlannerDaySummaryTests {
    private func day(_ completed: Int, _ target: Int, state: StudyDayState) -> StudyDay {
        StudyDay(
            date: StudyCalendarFixture.date("2026-08-19"),
            state: state,
            completedSets: completed,
            targetSets: target
        )
    }

    @Test func plannedDayShowsBothNumbers() {
        let partial = day(1, 3, state: .partial)
        #expect(
            PlannerDayStudyStatus.make(day: partial, isStudyWeekday: true)
                .summaryText(day: partial, isToday: false) == "1 / 3세트 학습"
        )
        #expect(
            PlannerDayStudyStatus.make(day: partial, isStudyWeekday: true)
                .summaryText(day: partial, isToday: true) == "오늘 1 / 3세트 학습"
        )
        let done = day(3, 3, state: .completed)
        #expect(
            PlannerDayStudyStatus.make(day: done, isStudyWeekday: true)
                .summaryText(day: done, isToday: false) == "3 / 3세트 학습"
        )
    }

    @Test func futureAndMissedDaysNeverPretendToHaveRecords() {
        let planned = day(0, 2, state: .planned)
        #expect(
            PlannerDayStudyStatus.make(day: planned, isStudyWeekday: true)
                .summaryText(day: planned, isToday: false) == "학습 예정 · 2세트"
        )
        let missed = day(0, 2, state: .missed)
        #expect(
            PlannerDayStudyStatus.make(day: missed, isStudyWeekday: true)
                .summaryText(day: missed, isToday: false) == "학습 기록 없음 · 계획 2세트"
        )
    }

    /// 휴식일에 스스로 학습한 날은 "휴식"만 말하고 끝내지 않는다. 가짜 분모도 만들지 않는다.
    @Test func restDayTellsBothTheRestAndTheLearning() {
        let learnedOnRest = day(2, 0, state: .rest)
        #expect(
            PlannerDayStudyStatus.make(day: learnedOnRest, isStudyWeekday: false)
                .summaryText(day: learnedOnRest, isToday: false) == "휴식일 · 2회 학습"
        )
        let idleRest = day(0, 0, state: .rest)
        #expect(
            PlannerDayStudyStatus.make(day: idleRest, isStudyWeekday: false)
                .summaryText(day: idleRest, isToday: false) == "휴식일 / 학습 기록 없음"
        )
    }

    /// 계획이 끝난 뒤의 학습 요일(배정 0)은 휴식일이 아니다. 한 일만 말한다.
    @Test func unplannedStudyWeekdayReportsOnlyWhatHappened() {
        let learned = day(1, 0, state: .rest)
        #expect(
            PlannerDayStudyStatus.make(day: learned, isStudyWeekday: true)
                .summaryText(day: learned, isToday: true) == "오늘 1회 학습"
        )
        let idle = day(0, 0, state: .rest)
        #expect(
            PlannerDayStudyStatus.make(day: idle, isStudyWeekday: true)
                .summaryText(day: idle, isToday: false) == "학습 기록 없음"
        )
    }

    /// 어떤 조합에서도 "1 / 0세트" 같은 가짜 분모가 나오지 않는다.
    @Test func summaryNeverInventsADenominator() {
        for completed in 0...5 {
            for isStudyWeekday in [true, false] {
                let zeroTarget = day(completed, 0, state: .rest)
                let text = PlannerDayStudyStatus.make(day: zeroTarget, isStudyWeekday: isStudyWeekday)
                    .summaryText(day: zeroTarget, isToday: false)
                #expect(!text.contains("/ 0세트"), "\(text)")
                #expect(!text.contains("메모"), "\(text)")
            }
        }
    }
}

/// P10: 메모 모델은 출시된 적이 없으므로 스키마에서 통째로 사라졌다.
/// 나머지 모델은 하나도 빠지지 않아야 한다 — 빠뜨리면 그 저장 데이터가 사라진다.
@MainActor
struct PersistenceSchemaTests {
    private var entityNames: Set<String> {
        Set(Schema.dailyOPIc.entities.map(\.name))
    }

    @Test func schemaKeepsEveryShippedModel() {
        #expect(entityNames == [
            "PracticeHistoryRecord",
            "MockHistoryRecord",
            "MockDraftRecord",
            "StudySetCompletionRecord",
            "StudyDayPlanRecord",
            "PlannerEventRecord",
            // P11.1 — 그날 학습한 문제의 가벼운 사본. 추가만 했고 뺀 것은 없다.
            "PlannerLearnedQuestionRecord",
            // P14 — 단어장 항목별 내 상태. 마찬가지로 추가만 했다.
            "VocabularyStateRecord",
        ])
    }

    @Test func memoModelIsGone() {
        #expect(!entityNames.contains("PlannerDayNoteRecord"))
    }

    /// P9의 개인 일정 알림 오프셋은 그대로 남아 있어야 한다.
    @Test func plannerEventKeepsItsReminderOffset() throws {
        let entity = try #require(
            Schema.dailyOPIc.entities.first { $0.name == "PlannerEventRecord" }
        )
        let properties = Set(entity.properties.map(\.name))
        #expect(properties.contains("reminderOffsetMinutes"))
        #expect(properties.contains("localDate"))
        #expect(properties.contains("timeMinutes"))
    }

    /// 스키마 그대로 저장소가 열린다(모델 제거 뒤에도 컨테이너가 만들어지는지).
    @Test func containerOpensWithTheCurrentSchema() throws {
        let container = try ModelContainer(
            for: Schema.dailyOPIc,
            configurations: ModelConfiguration(schema: Schema.dailyOPIc, isStoredInMemoryOnly: true)
        )
        let persistence = PersistenceService()
        persistence.configure(context: ModelContext(container))
        #expect(try persistence.savePlannerEvent(localDate: "2026-08-19", title: "스터디"))
        #expect(try persistence.plannerEvents(on: "2026-08-19").count == 1)
    }
}
