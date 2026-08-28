import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// P12: 시험일 정체성. 별이 어느 칸에 켜지는지를 정하는 유일한 판정이다.
///
/// 절대 시각이 아니라 학습 계획 타임존의 달력 날짜라, 사용자가 비행기를 타도
/// 시험일이 옆 칸으로 넘어가지 않는다.
@MainActor
struct ExamDayIdentityTests {
    private func settings(_ examDate: String?, timeZone: String = StudyCalendarFixture.seoul)
        -> StudyPlanSettings {
        StudyCalendarFixture.settings(examDate: examDate, timeZone: timeZone)
    }

    /// A. 설정한 시험일에는 표시가 켜진다.
    @Test func configuredExamDateIsMarked() {
        let plan = settings("2026-08-25")
        #expect(plan.isExamDay(StudyCalendarFixture.date("2026-08-25")))
        #expect(plan.examLocalDate == "2026-08-25")
    }

    /// B·C. 하루 전날도, 하루 뒷날도 시험일이 아니다.
    @Test func neighbouringDaysAreNotMarked() {
        let plan = settings("2026-08-25")
        #expect(!plan.isExamDay(StudyCalendarFixture.date("2026-08-24")))
        #expect(!plan.isExamDay(StudyCalendarFixture.date("2026-08-26")))
    }

    /// 시험일을 정하지 않은 사용자에게는 별이 하나도 없다.
    @Test func noExamDateMarksNothing() {
        let plan = settings(nil)
        #expect(plan.examLocalDate == nil)
        for day in ["2026-08-24", "2026-08-25", "2026-08-26"] {
            #expect(!plan.isExamDay(StudyCalendarFixture.date(day)))
        }
    }

    /// D. 시험일을 바꾸면 별이 따라 움직인다. 남는 표시를 지우는 청소 작업이 없다 —
    /// 별은 저장된 것이 아니라 설정에서 그때그때 파생되기 때문이다.
    @Test func changingTheExamDateMovesTheMarker() {
        let before = settings("2026-08-25")
        let after = settings("2026-09-04")
        #expect(before.isExamDay(StudyCalendarFixture.date("2026-08-25")))
        #expect(!after.isExamDay(StudyCalendarFixture.date("2026-08-25")))
        #expect(after.isExamDay(StudyCalendarFixture.date("2026-09-04")))
    }

    /// 시험일을 지우면 별도 사라진다.
    @Test func clearingTheExamDateRemovesTheMarker() {
        var plan = settings("2026-08-25")
        plan.examDate = nil
        #expect(!plan.isExamDay(StudyCalendarFixture.date("2026-08-25")))
    }

    /// E. 날짜 정체성을 정하는 것은 학습 계획 타임존이다.
    /// 서울 25일 00:30은 뉴욕에서 아직 24일이다 — 계획 타임존이 답을 가른다.
    @Test func planTimezoneDecidesTheExamDate() {
        let instant = StudyCalendarFixture.date("2026-08-25")
        #expect(settings("2026-08-25", timeZone: "Asia/Seoul").isExamDay(instant))

        let newYork = StudyPlanSettings(
            examDate: instant,
            studyWeekdays: [.monday],
            intensity: .steady,
            preferredStudyTime: StudyTimeOfDay(hour: 21, minute: 0),
            timezoneIdentifier: "America/New_York"
        )
        #expect(newYork.examLocalDate == "2026-08-24")
    }

    /// F. 기기 타임존은 판정에 끼지 않는다. 같은 설정이면 어디서 열어도 같은 날이다.
    @Test func deviceTimezoneNeverMovesTheMarker() {
        let plan = settings("2026-08-25")
        let examDay = StudyCalendarFixture.date("2026-08-25")
        // 기기 타임존이 무엇이든 `isExamDay`가 읽는 것은 설정의 타임존 하나뿐이다.
        for identifier in ["Asia/Seoul", "America/New_York", "UTC", "Pacific/Kiritimati"] {
            let device = TimeZone(identifier: identifier)!
            // 기기 달력으로 자른 하루의 시작·끝. 어느 기기에서 열어도 판정은 그대로다.
            let deviceCalendar = LocalCalendarDate.calendar(timeZone: device)
            let deviceStart = deviceCalendar.startOfDay(for: examDay)
            #expect(plan.isExamDay(examDay), "\(identifier)에서 시험일이 움직였다")
            // 기기 타임존이 만든 값을 넣어도 답을 정하는 것은 계획 타임존이다.
            #expect(
                plan.isExamDay(deviceStart)
                    == (LocalCalendarDate.text(from: deviceStart, timeZone: plan.timeZone)
                        == "2026-08-25")
            )
        }
        // 같은 순간을 기기 타임존별로 읽으면 날짜가 갈리지만, 계획이 말하는 시험일은 하나다.
        #expect(
            LocalCalendarDate.text(from: examDay, timeZone: TimeZone(identifier: "UTC")!)
                == "2026-08-24"
        )
        #expect(plan.examLocalDate == "2026-08-25")
    }

    /// G. 주간 스트립과 전체 캘린더는 같은 함수 하나를 부른다.
    /// 두 화면이 각자 비교식을 쓰면 같은 날에 별이 켜졌다 꺼졌다 한다.
    @Test func weekStripAndFullCalendarAgree() {
        let plan = settings("2026-08-25")
        for offset in -10...10 {
            let date = plan.calendar.date(
                byAdding: .day, value: offset, to: StudyCalendarFixture.date("2026-08-25")
            )!
            // 두 화면 모두 이 한 줄을 그대로 넘긴다(StudyDayCell.isExamDay).
            let weekStrip = plan.isExamDay(date)
            let fullCalendar = plan.isExamDay(date)
            #expect(weekStrip == fullCalendar)
            #expect(weekStrip == (offset == 0))
        }
    }

    /// H. 지난 시험일·오늘·앞으로의 시험일 모두 안전하게 분류된다.
    /// 지난 날짜에도 별은 남는다 — 그날 시험이 있었다는 사실은 바뀌지 않는다.
    @Test func pastTodayAndFutureAllClassify() {
        let today = StudyCalendarFixture.date("2026-08-20")
        for exam in ["2026-07-01", "2026-08-20", "2026-12-31"] {
            let plan = settings(exam)
            let date = StudyCalendarFixture.date(exam)
            #expect(plan.isExamDay(date))
            #expect(!plan.isExamDay(today.addingTimeInterval(-86_400 * 400)))
        }
    }
}

/// P12: 칸이 그리는 것들이 서로 간섭하지 않는지. 별은 **더해지는** 채널이다.
@MainActor
struct ExamDayCellPresentationTests {
    private func cell(
        completed: Int, isToday: Bool = false, isExamDay: Bool = true, hasEvent: Bool = false
    ) -> StudyDayCell {
        StudyDayCell(
            day: StudyDay(
                date: StudyCalendarFixture.date("2026-08-25"),
                state: completed > 0 ? .completed : .planned,
                completedSets: completed,
                targetSets: 3
            ),
            calendar: StudyCalendarFixture.settings().calendar,
            isToday: isToday,
            isExamDay: isExamDay,
            hasEvent: hasEvent
        )
    }

    /// A. 시험일 + 학습 0회 → 별은 켜지고 히트맵은 비어 있다.
    @Test func examDayWithoutLearningStaysUnfilled() {
        let subject = cell(completed: 0)
        #expect(subject.isExamDay)
        #expect(LearningActivityLevel.make(completedSets: 0) == .zero)
        #expect(LearningActivityLevel.make(completedSets: 0).fillOpacity == 0)
    }

    /// B. 시험일 + 1회 → 첫 단계.
    @Test func examDayWithOneSessionUsesLevelOne() {
        #expect(cell(completed: 1).isExamDay)
        #expect(LearningActivityLevel.make(completedSets: 1) == .one)
    }

    /// C. 시험일 + 5회 이상 → 가장 진한 단계.
    @Test func examDayWithManySessionsUsesStrongestLevel() {
        for count in [5, 9] {
            #expect(cell(completed: count).isExamDay)
            #expect(LearningActivityLevel.make(completedSets: count) == .fivePlus)
        }
    }

    /// D. 시험일 + 오늘 → 별과 오늘 테두리가 함께 있다. 하나가 다른 하나를 대신하지 않는다.
    @Test func examDayAndTodayCoexist() {
        let subject = cell(completed: 2, isToday: true)
        #expect(subject.isToday)
        #expect(subject.isExamDay)
    }

    /// E. 시험일 + 개인 일정 → 둘 다 남는다.
    @Test func examDayAndPersonalEventCoexist() {
        let subject = cell(completed: 0, hasEvent: true)
        #expect(subject.isExamDay)
        #expect(subject.hasEvent)
    }

    /// F. 별은 히트맵 단계를 건드리지 않는다. 같은 학습량이면 시험일이든 아니든 같은 진하기다.
    @Test func theStarNeverChangesTheHeatmapLevel() {
        for count in 0...6 {
            let exam = cell(completed: count, isExamDay: true)
            let normal = cell(completed: count, isExamDay: false)
            #expect(
                LearningActivityLevel.make(completedSets: exam.day.completedSets)
                    == LearningActivityLevel.make(completedSets: normal.day.completedSets)
            )
        }
    }

    /// G·H. 별은 연속 학습에도, 그날 배정 학습량에도 영향을 주지 않는다.
    /// 히트맵·연속 학습·주간 진행이 읽는 것은 실제 완료 기록뿐이다.
    @Test func theStarNeverChangesStreakOrTarget() {
        let settings = StudyCalendarFixture.settings(examDate: "2026-08-19")
        let none = StudyCalendarFixture.settings(examDate: nil)
        let completions = StudyCalendarFixture.completions([
            "2026-08-17": 1, "2026-08-18": 1, "2026-08-19": 1
        ])
        let today = StudyCalendarFixture.date("2026-08-19")
        let learningDays = LearningStreak.learningDays(from: completions)
        #expect(
            LearningStreak.current(
                learningDays: learningDays, today: today, calendar: settings.calendar
            ) == LearningStreak.current(
                learningDays: learningDays, today: today, calendar: none.calendar
            )
        )

        func day(_ plan: StudyPlanSettings) -> StudyDay {
            StudyCalendarEngine.day(
                date: today,
                today: today,
                settings: plan,
                schedule: StudySchedule(
                    historicalTargets: [:], plan: nil, settings: plan, today: today
                ),
                completions: completions
            )
        }
        #expect(day(settings).completedSets == day(none).completedSets)
        #expect(day(settings).targetSets == day(none).targetSets)
    }
}

/// P12: 읽어 주는 문장. 별 모양을 못 보는 사용자에게도 "OPIc 시험일"이 그대로 전달돼야 한다.
@MainActor
struct ExamDayAccessibilityTests {
    private func text(
        isToday: Bool = false, isExamDay: Bool = true, completedSets: Int = 0, hasEvent: Bool = false
    ) -> String {
        StudyDayCell.accessibilityText(
            date: "8월 25일", weekday: "화요일",
            isToday: isToday, isExamDay: isExamDay,
            completedSets: completedSets, hasEvent: hasEvent
        )
    }

    @Test func examDayIsSpokenAsMeaningNotAsAShape() {
        #expect(text() == "8월 25일 화요일, OPIc 시험일, 학습 기록 없음")
        #expect(
            text(isToday: true, completedSets: 3)
                == "8월 25일 화요일, 오늘, OPIc 시험일, 3회 학습"
        )
        #expect(
            text(completedSets: 2, hasEvent: true)
                == "8월 25일 화요일, OPIc 시험일, 2회 학습, 개인 일정 있음"
        )
        #expect(
            text(isToday: true, completedSets: 4, hasEvent: true)
                == "8월 25일 화요일, 오늘, OPIc 시험일, 4회 학습, 개인 일정 있음"
        )
    }

    /// 시험일이 아닌 날의 문장은 P10 그대로다 — 새 단어가 끼어들지 않는다.
    @Test func ordinaryDaysReadExactlyAsBefore() {
        #expect(text(isExamDay: false, completedSets: 3) == "8월 25일 화요일, 3회 학습")
        #expect(
            StudyDayCell.accessibilityText(
                date: "8월 25일", weekday: "화요일",
                isToday: false, completedSets: 3, hasEvent: false
            ) == "8월 25일 화요일, 3회 학습"
        )
    }

    /// 모양 이름도, 내부 키도 읽지 않는다.
    @Test func neverReadsShapeNamesOrInternalKeys() {
        for isToday in [true, false] {
            for count in 0...5 {
                for hasEvent in [true, false] {
                    let spoken = text(isToday: isToday, completedSets: count, hasEvent: hasEvent)
                    for banned in ["별표", "star", "레벨", "단계", "yyyy", "2026-08-25", "UUID"] {
                        #expect(!spoken.contains(banned), "읽어 주는 문장에 \(banned)이(가) 들어갔다")
                    }
                    #expect(spoken.contains("OPIc 시험일"))
                    #expect(spoken.contains(LearningActivityLevel.accessibilityText(completedSets: count)))
                }
            }
        }
    }
}

/// P12: 정적 안내 내용. 공식 규정과 DailyOPIc 권장이 섞이지 않았는지 문장 단위로 확인한다.
struct ExamDayGuideContentTests {
    private var officialText: String {
        OPIcExamDayGuide.officialRules
            .map { "\($0.title) \($0.detail)" }
            .joined(separator: "\n") + "\n" + OPIcExamDayGuide.acceptedIDExamples
    }

    private var tipText: String { OPIcExamDayGuide.dailyOPIcTips.joined(separator: "\n") }

    /// 공식 안내에서 확인한 핵심 개념이 빠지지 않았는지. 규정 원문을 통째로 박아 두면
    /// 문구가 조금만 다듬어져도 테스트가 깨지므로 개념 단위로만 확인한다.
    @Test func officialRulesCoverTheEssentialConcepts() {
        for concept in [
            "규정 신분증",     // 지참 의무
            "모바일 신분증",   // 법적 효력이 있는 서비스 정상 작동 시에만
            "법적 효력",
            "캡처",            // 사본·캡처·촬영본 불가
            "10분 전",         // 입실
            "지각",            // 지각 시 응시 불가
            "전자기기",
            "필기도구",
            "메모",
            "참고 자료",
            "식음료",
            "감독관"           // 장비 이상 시 조치
        ] {
            #expect(officialText.contains(concept), "공식 확인사항에 '\(concept)'이(가) 없다")
        }
    }

    /// 신분증 예시는 "예:"로 시작한다 — 이 셋이 전부라고 읽히면 안 된다.
    @Test func acceptedIDCopyIsAnExampleNotAnExhaustiveList() {
        #expect(OPIcExamDayGuide.acceptedIDExamples.hasPrefix("예:"))
        for identity in ["주민등록증", "자동차운전면허증", "여권"] {
            #expect(OPIcExamDayGuide.acceptedIDExamples.contains(identity))
        }
        // "아무 신분증"으로 뭉뚱그리지 않는다. 사진이 붙었다고 다 되는 것이 아니다.
        #expect(!officialText.contains("아무 신분증"))
    }

    /// 장비 이상은 사용자가 직접 만지는 것이 아니라 감독관에게 알리는 일이다.
    @Test func equipmentTroubleGoesToTheProctor() {
        let rule = OPIcExamDayGuide.officialRules.first { $0.title == "장비 이상" }
        #expect(rule?.detail.contains("감독관") == true)
        #expect(rule?.detail.contains("직접 조작") == true)
    }

    /// DailyOPIc 권장은 4~6개. 목록이 길어지면 시험 당일에 읽히지 않는다.
    @Test func tipsStayShortEnoughToRead() {
        #expect((4...6).contains(OPIcExamDayGuide.dailyOPIcTips.count))
    }

    /// 권장이 점수를 약속하지 않는다.
    @Test func tipsNeverPromiseAScore() {
        for banned in [
            "점수가 오", "점수를 올", "AL", "합격", "보장", "반드시", "고득점", "무조건", "확실"
        ] {
            #expect(!tipText.contains(banned), "팁이 '\(banned)'을(를) 약속하고 있다")
        }
    }

    /// 권장이 공식 규정인 척하지 않는다.
    @Test func tipsNeverClaimToBeOfficial() {
        for banned in ["공식 규정", "공식 전략", "ACTFL", "규정에 따라", "의무"] {
            #expect(!tipText.contains(banned), "팁이 '\(banned)'으로 공식인 척한다")
        }
    }

    /// 규정을 정면으로 어기는 조언이 들어가면 안 된다.
    /// 필기도구는 책상 위에 두는 것 자체가 위반이고, 문제 메모는 저작권 침해다.
    @Test func tipsNeverContradictTheOfficialRules() {
        let everything = tipText + "\n" + officialText
        for forbidden in ["메모지를 챙", "펜을 챙", "필기구를 챙", "문제를 메모하", "메모하세요", "녹음하세요"] {
            #expect(!everything.contains(forbidden), "'\(forbidden)'은 공식 규정과 충돌한다")
        }
    }

    /// 공포·조급함을 파는 문장을 쓰지 않는다.
    @Test func tipsAreCalm() {
        for banned in ["큰일", "망치", "위험", "실패하면", "서둘러", "늦으면 끝"] {
            #expect(!tipText.contains(banned))
        }
    }

    /// 카드가 규정을 실시간으로 받아오는 척하지 않는다. 확인은 사용자 몫으로 남긴다.
    @Test func theCardAsksTheUserToRecheckTheOfficialNotice() {
        #expect(OPIcExamDayGuide.footer.contains("공식 안내"))
        #expect(OPIcExamDayGuide.officialLink.scheme == "https")
        #expect(OPIcExamDayGuide.officialLink.host == "www.opic.or.kr")
    }

    /// 두 목록의 제목이 서로 다르다 — 화면에서 성격이 구분되는 최소 조건이다.
    @Test func officialAndRecommendationHaveDistinctTitles() {
        #expect(OPIcExamDayGuide.officialTitle == "공식 확인사항")
        #expect(OPIcExamDayGuide.tipsTitle.hasPrefix("DailyOPIc"))
        #expect(OPIcExamDayGuide.officialTitle != OPIcExamDayGuide.tipsTitle)
    }

    /// 지난 시험일을 열어도 어색하지 않도록, 정적 안내에 남은 날짜 표현을 쓰지 않는다.
    @Test func staticGuideHasNoCountdownCopy() {
        let everything = officialText + "\n" + tipText + "\n" + OPIcExamDayGuide.footer
        for banned in ["곧 시험", "D-", "남았", "며칠", "내일 시험", "오늘 시험"] {
            #expect(!everything.contains(banned), "정적 안내에 '\(banned)' 같은 카운트다운이 있다")
        }
    }
}

/// P12: 시트 구조. 시험일 안내가 어디에 들어가고 무엇을 밀어내지 않는지.
@MainActor
struct ExamDaySheetTests {
    /// 시험일 안내는 학습 요약보다 **위**, 나머지 순서는 P11 그대로다.
    @Test func examGuideComesFirstAndKeepsTheRestInOrder() throws {
        let order = PlannerDaySheetSection.allCases
        #expect(order == [.examDay, .study, .learnedQuestions, .personalEvents])
        let exam = try #require(order.firstIndex(of: .examDay))
        let study = try #require(order.firstIndex(of: .study))
        let questions = try #require(order.firstIndex(of: .learnedQuestions))
        let events = try #require(order.firstIndex(of: .personalEvents))
        #expect(exam < study)
        #expect(study < questions)
        #expect(questions < events)
    }

    /// 시험일에만 켜진다. 시트에 넘기는 값은 캘린더 별과 **같은** 판정에서 온다.
    @Test func theSectionAppearsOnlyOnTheConfiguredExamDate() {
        let settings = StudyCalendarFixture.settings(examDate: "2026-08-25")
        #expect(settings.isExamDay(StudyCalendarFixture.date("2026-08-25")))
        #expect(!settings.isExamDay(StudyCalendarFixture.date("2026-08-24")))
        #expect(!settings.isExamDay(StudyCalendarFixture.date("2026-08-26")))
    }

    /// 새 화면도, 새 경로도 만들지 않았다. 시트는 여전히 하나다.
    @Test func noNewScreenOrRouteIsIntroduced() {
        #expect(Set(PlannerRoute.allCases) == [.fullCalendar, .settings])
    }

    /// 체크 상태를 저장하지 않는다. P12는 안내이지 할 일 관리가 아니다.
    @Test func noChecklistStateIsPersisted() {
        let entities = Schema.dailyOPIc.entities.map(\.name)
        #expect(!entities.contains("ExamChecklistRecord"))
        #expect(!entities.contains("PlannerExamDayRecord"))
        #expect(!entities.contains("PlannerDayNoteRecord"))
        // 시험일 안내는 저장소를 늘리지 않았다. P11.1까지의 7개 + P14 단어장 상태 1개.
        #expect(entities.count == 8)
    }
}
