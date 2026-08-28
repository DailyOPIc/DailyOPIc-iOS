import Foundation
import Testing
@testable import DailyOPIc

/// P13.1. 데일리 토큰 1개 = 사용자가 시작한 AI 작업 1회다. 세트를 **끝까지**(획득 + 분석)
/// 가져가려면 2개가 든다. 플래너는 살 수 없는 숙제를 내면 안 된다.
struct PlannerTokenEconomicsTests {
    /// 세트 획득 1 + AI 분석 1. 이 숫자가 바뀌면 아래 표 전체가 같이 움직여야 한다.
    @Test func oneCompletedSetCostsASetTokenAndAnAnalysisToken() {
        #expect(StudyPlanEstimatorConfig.minimumTokensPerCompletedDailySet == 2)
    }

    /// 남는 홀수 토큰은 세트를 하나 더 계획할 근거가 되지 못한다.
    @Test func tokenWalletConvertsToCompletableSets() {
        let expected: [Int: Int] = [0: 0, 1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 10: 5, 20: 10]
        for (tokens, sets) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(StudyPlanEstimator.completedSetCapacity(tokens: tokens) == sets, "\(tokens)")
        }
        // 방어적으로: 음수 지갑은 음수 세트가 되지 않는다.
        #expect(StudyPlanEstimator.completedSetCapacity(tokens: -4) == 0)
    }

    /// 실제 플랜 할당(`plans.py`)이 계획 가능한 세트 수로 어떻게 내려앉는가.
    /// 할당량 자체는 이 단계에서 바꾸지 않았다.
    @Test func everyPlanCapIsWhatItsTokensCanActuallyFinish() {
        let expected: [PlanEntitlement: (wallet: Int, sets: Int)] = [
            .free: (2, 1),   // 기본 1 + 리워드 광고 1
            .basic: (3, 1),  // 세트 1 + 분석 1, 토큰 1개 남음
            .plus: (10, 5),
            .pro: (20, 10),
        ]
        for plan in PlanEntitlement.allCases {
            let want = try? #require(expected[plan])
            #expect(StudyPlanEstimator.dailyTokenWallet(capabilities: nil, plan: plan) == want?.wallet, "\(plan)")
            #expect(StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: plan) == want?.sets, "\(plan)")
        }
    }

    /// 서버 capabilities가 진실이다. 구 서버(보너스 필드 없음)만 플랜 표로 폴백한다.
    @Test func serverQuotaBeatsThePlanTableAndOldServersFallBack() {
        let generous = StudyCalendarFixture.capabilities(plan: "plus", practiceDaily: 9, practiceAdBonus: 0)
        #expect(StudyPlanEstimator.dailyTokenWallet(capabilities: generous, plan: .plus) == 9)
        #expect(StudyPlanEstimator.dailyCapacity(capabilities: generous, plan: .plus) == 4)

        let oldServer = StudyCalendarFixture.capabilities(plan: "free", practiceDaily: nil, practiceAdBonus: nil)
        #expect(StudyPlanEstimator.dailyTokenWallet(capabilities: oldServer, plan: .free) == 2)
        #expect(StudyPlanEstimator.dailyCapacity(capabilities: oldServer, plan: .free) == 1)
    }

    /// §13. 무료의 두 번째 토큰은 **기존 리워드 광고**에서만 나온다. 플래너는 상한을
    /// 계산할 뿐이고, 광고를 자동으로 틀거나 토큰을 몰래 더 주지 않는다.
    @Test func freePlanNeedsTheRewardedAdToCompleteEvenOneSet() {
        let baseOnly = StudyCalendarFixture.capabilities(plan: "free", practiceDaily: 1, practiceAdBonus: 0)
        #expect(StudyPlanEstimator.dailyTokenWallet(capabilities: baseOnly, plan: .free) == 1)
        // 기본 토큰만으로는 세트를 받을 수는 있어도 분석까지 못 간다 → 계획은 0세트.
        #expect(StudyPlanEstimator.dailyCapacity(capabilities: baseOnly, plan: .free) == 0)

        let withBonus = StudyCalendarFixture.capabilities(plan: "free", practiceDaily: 1, practiceAdBonus: 1)
        #expect(StudyPlanEstimator.dailyTokenWallet(capabilities: withBonus, plan: .free) == 2)
        #expect(StudyPlanEstimator.dailyCapacity(capabilities: withBonus, plan: .free) == 1)
        // 보너스를 받아도 하루 한 사이클이 한계다. 두 세트는 4토큰이라 살 수 없다.
        #expect(StudyPlanEstimator.completedSetCapacity(tokens: 2 + 1) == 1)
    }
}

/// P13.1의 불변식: 생성되는 모든 미래 학습일에 대해 `0 <= targetSets <= 토큰이 감당하는 세트 수`.
/// 어떤 유료 자동화(시험 역산·재조정·평가 반영)도 이 상한을 뚫지 못한다.
struct PlannerTokenCapInvariantTests {
    private let today = StudyCalendarFixture.date("2026-08-10") // 월요일

    private func settings(
        intensity: StudyIntensity,
        examDate: String? = nil,
        weekdays: Set<StudyWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    ) -> StudyPlanSettings {
        StudyCalendarFixture.settings(weekdays: weekdays, intensity: intensity, examDate: examDate)
    }

    /// 하나의 계획이 상한을 넘는 날을 하루도 만들지 않는지 본다.
    private func expectWithinCap(_ plan: AdaptiveStudyPlan, cap: Int, _ label: String) {
        #expect(plan.baseDailyTarget <= cap, "\(label)")
        #expect(plan.adaptiveDailyCeiling <= cap, "\(label)")
        for day in plan.upcomingDays {
            // 0세트짜리 "계획된 날"은 아예 만들지 않는다(휴식일과 구분되지 않는다).
            #expect(day.targetSets >= 1, "\(label) @\(day.date)")
            #expect(day.targetSets <= cap, "\(label) @\(day.date)")
        }
    }

    /// 플랜 × 강도 × 시험일 시나리오 전부. 시험일 없음 / 여유 / 촉박 / 이미 지남.
    @Test func noPlanEverSchedulesMoreSetsThanTokensCanFinish() {
        let exams: [String?] = [nil, "2026-12-31", "2026-08-14", "2026-08-09"]
        for entitlement in PlanEntitlement.allCases {
            let cap = StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: entitlement)
            for intensity in StudyIntensity.allCases {
                for exam in exams {
                    let plan = AdaptiveStudyPlanner.plan(
                        settings: settings(intensity: intensity, examDate: exam),
                        targetLevel: .AL,
                        recentLevel: .NM,
                        dailyCapacity: cap,
                        completions: [:],
                        policy: .fallback(for: entitlement),
                        today: today
                    )
                    expectWithinCap(plan, cap: cap, "\(entitlement)/\(intensity)/\(exam ?? "없음")")
                }
            }
        }
    }

    /// 시험 역산(압축·부족)은 플러스부터 열린다. 열려도 상한은 그대로다.
    @Test func examBackplanCannotBuyItsWayPastTheTokenCap() {
        let cap = StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: .plus) // 5
        let compressed = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .light, examDate: "2026-10-19"),
            targetLevel: .AL,
            recentLevel: .NM,
            dailyCapacity: cap,
            completions: [:],
            policy: .everything,
            today: today
        )
        #expect(compressed.mode == .compressed)
        expectWithinCap(compressed, cap: cap, "compressed")

        // 상한까지 채워도 모자란 경우: 부족분을 숨기려고 상한을 넘기지 않는다.
        let short = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .light, examDate: "2026-08-21"),
            targetLevel: .AL,
            recentLevel: .NM,
            dailyCapacity: cap,
            completions: [:],
            policy: .everything,
            today: today
        )
        #expect(short.mode == .insufficientTime)
        #expect((short.shortfallSets ?? 0) > 0)
        expectWithinCap(short, cap: cap, "insufficientTime")
    }

    /// 자동 재조정(놓친 학습 되분배)도 상한 안에서만 움직인다.
    @Test func autoReplanAfterMissedDaysStaysWithinTheTokenCap() {
        let cap = StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: .basic) // 1
        let replanned = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .focused, examDate: "2026-09-30"),
            targetLevel: .AL,
            recentLevel: nil,
            dailyCapacity: cap,
            completions: [:],
            policy: .fallback(for: .basic),
            today: StudyCalendarFixture.date("2026-08-24")
        )
        expectWithinCap(replanned, cap: cap, "autoReplan")
    }

    /// 최근 평가 반영으로 권장 총량이 커져도 하루 배정량은 상한을 넘지 않는다.
    @Test func evaluationAdaptivePlanStaysWithinTheTokenCap() {
        let cap = StudyPlanEstimator.dailyCapacity(capabilities: nil, plan: .pro) // 10
        for recent in [OPIcLevel.NM, .IM2, .AL] {
            let plan = AdaptiveStudyPlanner.plan(
                settings: settings(intensity: .focused, examDate: "2026-09-07"),
                targetLevel: .AL,
                recentLevel: recent,
                dailyCapacity: cap,
                completions: [:],
                policy: .everything,
                today: today
            )
            expectWithinCap(plan, cap: cap, "recent \(recent)")
        }
    }

    /// 토큰이 한 세트도 완주시키지 못하면(무료 + 광고 미시청) 숙제를 만들지 않는다.
    /// 그렇다고 스스로 하는 학습을 막지도 않는다 — 계획이 없을 뿐이다.
    @Test func zeroCapacityProducesNoPlannedDays() {
        let plan = AdaptiveStudyPlanner.plan(
            settings: settings(intensity: .focused),
            targetLevel: .AL,
            recentLevel: nil,
            dailyCapacity: 0,
            completions: [:],
            policy: .free,
            today: today
        )
        #expect(plan.upcomingDays.isEmpty)
        #expect(plan.baseDailyTarget == 0)
        #expect(plan.estimatedCompletionDate == nil)
    }

    /// 휴식일은 토큰이 남아돌아도 휴식일이다.
    @Test func restDaysStayAtZeroEvenWithTokensToSpare() {
        let weekdaysOnly = settings(intensity: .light, weekdays: [.monday])
        let plan = AdaptiveStudyPlanner.plan(
            settings: weekdaysOnly,
            targetLevel: .AL,
            recentLevel: nil,
            dailyCapacity: 10,
            completions: [:],
            policy: .everything,
            today: today
        )
        let schedule = StudySchedule(
            historicalTargets: [:],
            plan: plan,
            settings: weekdaysOnly,
            today: today
        )
        #expect(schedule.targetSets(for: today) == 1)
        for offset in 1...4 { // 화~금
            let restDay = StudyCalendarFixture.date("2026-08-1\(offset)")
            #expect(plan.plan(for: restDay) == nil)
            #expect(schedule.targetSets(for: restDay) == 0)
        }
    }

    /// P8.1의 고정 기록은 불변이다. 상한이 내려갔다고 지난 날의 진실을 고쳐 쓰지 않는다.
    @Test func frozenHistoricalTargetsAreNotRewrittenByTheNewCap() {
        let plannerSettings = settings(intensity: .light)
        let todayLater = StudyCalendarFixture.date("2026-08-17")
        let plan = AdaptiveStudyPlanner.plan(
            settings: plannerSettings,
            targetLevel: .AL,
            recentLevel: nil,
            dailyCapacity: 1,
            completions: [:],
            policy: .everything,
            today: todayLater
        )
        let schedule = StudySchedule(
            historicalTargets: ["2026-08-10": 7, "2026-08-11": 0],
            plan: plan,
            settings: plannerSettings,
            today: todayLater
        )
        // 7세트는 지금 상한(1)을 한참 넘지만 그날의 기록이므로 그대로 남는다.
        #expect(schedule.targetSets(for: StudyCalendarFixture.date("2026-08-10")) == 7)
        #expect(schedule.targetSets(for: StudyCalendarFixture.date("2026-08-11")) == 0)
        // 오늘·미래만 새 상한을 따른다.
        #expect(schedule.targetSets(for: todayLater) <= 1)
    }
}
