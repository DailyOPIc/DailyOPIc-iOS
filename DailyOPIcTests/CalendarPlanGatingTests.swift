import Foundation
import Testing
@testable import DailyOPIc

/// G4: 캘린더는 전 플랜이 쓰고, 유료가 사는 것은 **자동화 깊이**다.
/// 무료의 계산이 일부러 틀리지 않는다는 것까지 함께 지킨다.
struct CalendarPlanGatingTests {
    private let today = StudyCalendarFixture.date("2026-08-14")  // 금요일

    private func settings(examDate: String? = nil) -> StudyPlanSettings {
        StudyCalendarFixture.settings(examDate: examDate)
    }

    /// 목표 IH · 최근 IH → 권장 20세트(최근 등급을 모르면 44세트).
    /// 강도 꾸준히(2) · 토큰 2 → 하루 2세트.
    private func plan(
        policy: CalendarFeaturePolicy,
        settings: StudyPlanSettings? = nil,
        recentLevel: OPIcLevel? = .IH,
        dailyCapacity: Int = 2,
        completions: [String: Int] = [:]
    ) -> AdaptiveStudyPlan {
        AdaptiveStudyPlanner.plan(
            settings: settings ?? self.settings(),
            targetLevel: .IH,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            completions: StudyCalendarFixture.completions(completions),
            policy: policy,
            today: today
        )
    }

    private func snapshot(
        policy: CalendarFeaturePolicy,
        settings: StudyPlanSettings? = nil,
        historical: [String: Int] = [:],
        completions: [String: Int] = [:]
    ) -> StudyCalendarSnapshot {
        StudyCalendarSnapshot.make(
            settings: settings ?? self.settings(),
            targetLevel: .IH,
            recentLevel: .IH,
            dailyCapacity: 2,
            completions: StudyCalendarFixture.completions(completions),
            historicalTargets: historical,
            policy: policy,
            today: today
        )
    }

    // MARK: 무료도 캘린더를 제대로 쓴다

    @Test func freeCalendarTracksProgressStreakAndCompletionStates() {
        let snapshot = snapshot(
            policy: .free,
            historical: ["2026-08-12": 2, "2026-08-13": 2, "2026-08-14": 2],
            completions: ["2026-08-12": 2, "2026-08-13": 2, "2026-08-14": 2]
        )
        #expect(snapshot.today.state == .completed)
        #expect(snapshot.today.completedSets == 2)
        #expect(snapshot.streak == 3)
        #expect(snapshot.weekCompletedDays == 3)
    }

    @Test func freeCalendarStaysFullyAvailable() {
        // 무료도 캘린더 자체는 잠기지 않는다. 오늘 카드·주간·앞으로의 일정이 모두 있다.
        let snapshot = snapshot(policy: .free)
        #expect(snapshot.today.isScheduled)
        #expect(snapshot.weekDays.count == 7)
        #expect(!snapshot.plan.upcomingDays.isEmpty)
    }

    @Test func freeCalendarKeepsMissedDaysMissed() {
        // 놓친 날을 완료로 둔갑시키지 않는다.
        let snapshot = snapshot(
            policy: .free,
            historical: ["2026-08-12": 2, "2026-08-13": 2],
            completions: ["2026-08-12": 2]
        )
        let missed = snapshot.weekDays.first { $0.date == StudyCalendarFixture.date("2026-08-13") }
        #expect(missed?.state == .missed)
        #expect(missed?.completedSets == 0)
        #expect(snapshot.streak == 0)
    }

    @Test func freeRemainingWorkloadStaysTruthful() {
        // 완료한 만큼 남은 학습량이 줄어드는 것은 무료도 똑같다.
        let free = plan(policy: .free, recentLevel: nil, completions: ["2026-08-13": 6])
        #expect(free.totalRecommendedSets == 44)
        #expect(free.completedSets == 6)
        #expect(free.remainingSets == 38)
    }

    @Test func freeDailyTargetIsAFixedQuotaNotRedistributed() {
        // 남은 학습량이 1세트여도 무료의 하루 배정량은 정해진 2세트 그대로다.
        let done = ["2026-08-13": 43]
        let free = plan(policy: .free, recentLevel: nil, completions: done)
        let paid = plan(policy: .everything, recentLevel: nil, completions: done)
        #expect(free.remainingSets == 1)
        #expect(free.upcomingDays.map(\.targetSets) == [2])
        #expect(paid.upcomingDays.map(\.targetSets) == [1])
    }

    @Test func freeScheduleShortensWhenWorkIsDoneAhead() {
        // 자동 재조정이 없어도 끝낸 만큼 일정이 짧아진다(계산을 일부러 틀리지 않는다).
        let free = plan(policy: .free, recentLevel: nil, completions: ["2026-08-13": 34])
        #expect(free.remainingSets == 10)
        #expect(free.estimatedStudyDays == 5)
        #expect(free.estimatedCompletionDate == StudyCalendarFixture.date("2026-08-20"))
    }

    @Test func completingEverythingEndsThePlanOnEveryTier() {
        for policy in [CalendarFeaturePolicy.free, .fallback(for: .basic), .everything] {
            let plan = plan(policy: policy, recentLevel: nil, completions: ["2026-08-13": 44])
            #expect(plan.mode == .completed)
            #expect(plan.upcomingDays.isEmpty)
        }
    }

    // MARK: 자동 일정 재조정(베이직부터)

    @Test func autoReplanRedistributesRemainingWorkIntoFutureDays() {
        let basic = plan(
            policy: .fallback(for: .basic),
            recentLevel: nil,
            completions: ["2026-08-13": 39]
        )
        #expect(basic.upcomingDays.map(\.targetSets) == [2, 2, 1])
    }

    @Test func basicUnlocksAutoReplanOnly() {
        let basic = CalendarFeaturePolicy.fallback(for: .basic)
        #expect(basic.canAutoReplan)
        #expect(!basic.canUseRecentEvaluation)
        #expect(!basic.canBackplanToExam)
    }

    // MARK: 최근 평가 반영(플러스부터)

    @Test func evaluationAdaptivePlanningIsPlusOnly() {
        // 최근 등급을 반영하면 목표까지 0단계 → 20세트, 반영하지 않으면 2단계 가정 → 44세트.
        #expect(plan(policy: .everything).totalRecommendedSets == 20)
        #expect(plan(policy: .fallback(for: .basic)).totalRecommendedSets == 44)
        #expect(plan(policy: .free).totalRecommendedSets == 44)
    }

    @Test func lockedEvaluationFallbackIsDeterministic() {
        // 최근 기록이 있든 없든 잠긴 플랜의 권장 학습량은 같은 값이다.
        let withRecent = plan(policy: .free, recentLevel: .IH)
        let withoutRecent = plan(policy: .free, recentLevel: nil)
        #expect(withRecent.totalRecommendedSets == withoutRecent.totalRecommendedSets)
    }

    // MARK: 시험일 역산(플러스부터)

    @Test func examBackplanCompressesOnlyWhenUnlocked() {
        // 권장 44세트 · 하루 2세트 · 토큰 5(상한 4). 시험 전 학습일은 11일뿐이다.
        let settings = settings(examDate: "2026-08-29")
        func plan(_ policy: CalendarFeaturePolicy) -> AdaptiveStudyPlan {
            self.plan(policy: policy, settings: settings, recentLevel: nil, dailyCapacity: 5)
        }

        // 플러스: 시험 전 학습일에 남은 학습량을 다시 나눈다(상한 4를 넘지 않는다).
        let plus = plan(.everything)
        #expect(plus.mode == .compressed)
        #expect(plus.upcomingDays.map(\.targetSets) == Array(repeating: 4, count: 11))

        // 무료: 다시 나누지 않는다. 하루 배정량은 그대로 2세트다.
        let free = plan(.free)
        #expect(free.mode == .onTrack)
        #expect(Set(free.upcomingDays.map(\.targetSets)) == [2])
    }

    @Test func lockedExamBackplanNeverInflatesTheDailyTarget() {
        // 시험이 코앞이어도 잠긴 플랜의 하루 배정량은 평소값을 넘지 않는다.
        let settings = settings(examDate: "2026-08-21")
        let free = plan(policy: .free, settings: settings, recentLevel: nil, dailyCapacity: 5)
        #expect(free.upcomingDays.allSatisfy { $0.targetSets == free.baseDailyTarget })
    }

    @Test func insufficientTimeStaysAnHonestNumberNotAnUpsell() {
        // 상한까지 올려도 시험 전에 못 끝내는 상황. 가능한 최대치와 부족분을 그대로 말한다.
        let settings = settings(examDate: "2026-08-21")
        let plus = plan(policy: .everything, settings: settings, recentLevel: nil, dailyCapacity: 5)
        #expect(plus.mode == .insufficientTime)
        #expect(plus.maximumSetsPossibleBeforeExam == 20)
        #expect(plus.shortfallSets == 24)

        // 같은 상황의 무료는 압축하지 않지만 경고는 똑같이 참이다.
        let free = plan(policy: .free, settings: settings, recentLevel: nil, dailyCapacity: 5)
        #expect(free.mode == .onTrack)
        #expect(free.finishesAfterExam)
    }

    @Test func proCalendarPlanningIsIdenticalToPlus() {
        // G4에서 프로 전용 일정 기능을 만들지 않았다. 계획 결과가 같아야 한다.
        let settings = settings(examDate: "2026-08-29")
        func plan(_ entitlement: PlanEntitlement) -> AdaptiveStudyPlan {
            self.plan(policy: .fallback(for: entitlement), settings: settings, dailyCapacity: 5)
        }
        #expect(plan(.pro).totalRecommendedSets == plan(.plus).totalRecommendedSets)
        #expect(plan(.pro).upcomingDays.map(\.targetSets) == plan(.plus).upcomingDays.map(\.targetSets))
        #expect(plan(.pro).mode == plan(.plus).mode)
    }

    @Test func lockedExamBackplanStillWarnsAndKeepsDDay() {
        let settings = settings(examDate: "2026-08-29")
        let free = plan(policy: .free, settings: settings)
        #expect(free.examDate == StudyCalendarFixture.date("2026-08-29"))
        #expect(free.finishesAfterExam)
        #expect(snapshot(policy: .free, settings: settings).examDaysRemaining == 15)
    }

    @Test func exambackplanDoesNotWarnWhenThePlanFitsBeforeTheExam() {
        let settings = settings(examDate: "2026-12-31")
        #expect(!plan(policy: .free, settings: settings).finishesAfterExam)
        #expect(!plan(policy: .everything, settings: settings).finishesAfterExam)
    }

    // MARK: 권한 해석(폴백은 한 곳에만)

    private func capabilities(
        plan: String?,
        autoReplan: Bool? = nil,
        evaluationAdaptive: Bool? = nil,
        examBackplan: Bool? = nil,
        studyReminder: Bool? = nil
    ) -> Capabilities {
        Capabilities(
            minimumSupportedAppVersion: "1.0.0",
            questionGenerationV2: true,
            mockSessionV2: true,
            evaluationRubricV2: true,
            practiceRefresh: true,
            guideSchemaVersion: 1,
            plan: plan,
            quotaPolicy: Capabilities.QuotaPolicy(
                dailyAnalysisFree: 1,
                dailyRefreshRewards: 1,
                mockSessionsPerDay: 1,
                mockRewardGates: 3,
                practiceDaily: 1,
                practiceAdBonus: 1,
                historyDays: 7,
                analysisDepth: "summary",
                reviewSet: false,
                adsEnabled: true,
                calendarAutoReplan: autoReplan,
                calendarEvaluationAdaptive: evaluationAdaptive,
                calendarExamBackplan: examBackplan,
                calendarStudyReminder: studyReminder
            )
        )
    }

    @Test func fallbackTableMatchesTheBackendPolicyMatrix() {
        #expect(CalendarFeaturePolicy.fallback(for: .free) == .free)
        #expect(CalendarFeaturePolicy.fallback(for: .plus) == .everything)
        #expect(CalendarFeaturePolicy.fallback(for: .pro) == .everything)
        #expect(CalendarFeaturePolicy.fallback(for: .pro) == .fallback(for: .plus))
    }

    @Test func oldBackendWithoutCalendarFieldsFallsBackToThePlan() {
        let policy = CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "plus"),
            plan: .plus
        )
        #expect(policy == .everything)
    }

    @Test func missingCapabilitiesFallBackToThePlan() {
        #expect(CalendarFeaturePolicy.resolve(capabilities: nil, plan: .basic).canAutoReplan)
        #expect(!CalendarFeaturePolicy.resolve(capabilities: nil, plan: .free).canAutoReplan)
    }

    @Test func serverCapabilitiesWinWhenTheyDescribeTheSamePlan() {
        // 서버가 진실이다. 같은 플랜을 말하고 있으면 서버 값을 그대로 쓴다.
        let policy = CalendarFeaturePolicy.resolve(
            capabilities: capabilities(
                plan: "basic",
                autoReplan: true,
                evaluationAdaptive: false,
                examBackplan: false
            ),
            plan: .basic
        )
        #expect(policy == .fallback(for: .basic))
    }

    @Test func staleServerSnapshotDoesNotLockOutAJustUpgradedUser() {
        // 방금 결제해 로컬 엔타이틀먼트가 앞서 간 상태. 낡은 free 스냅샷으로 잠그지 않는다.
        let policy = CalendarFeaturePolicy.resolve(
            capabilities: capabilities(plan: "free", autoReplan: false),
            plan: .plus
        )
        #expect(policy == .everything)
    }

    // MARK: 잠금 UI 계약

    @Test func lockedFeatureListShrinksAsThePlanGrows() {
        // 설정 화면의 "학습 플랜 기능" 칸은 자동화 3종만 모은다(학습 알림은 자기 카드에서 잠긴다).
        func locked(_ plan: PlanEntitlement) -> [CalendarLockedFeature] {
            let policy = CalendarFeaturePolicy.fallback(for: plan)
            return CalendarLockedFeature.automationCases.filter { $0.isLocked(under: policy) }
        }
        #expect(locked(.free) == [.autoReplan, .evaluationAdaptive, .examBackplan])
        #expect(locked(.basic) == [.evaluationAdaptive, .examBackplan])
        #expect(locked(.plus).isEmpty)
        #expect(locked(.pro).isEmpty)
    }

    @Test func lockedFeatureMetadataIsAFixedSchema() {
        #expect(CalendarLockedFeature.allCases.map(\.rawValue)
            == ["auto_replan", "evaluation_adaptive", "exam_backplan", "study_reminder"])
        #expect(CalendarLockedFeature.automationCases.map(\.rawValue)
            == ["auto_replan", "evaluation_adaptive", "exam_backplan"])
        #expect(CalendarLockedFeature.autoReplan.requiredPlan == .basic)
        #expect(CalendarLockedFeature.evaluationAdaptive.requiredPlan == .plus)
        #expect(CalendarLockedFeature.examBackplan.requiredPlan == .plus)
        #expect(CalendarLockedFeature.studyReminder.requiredPlan == .basic)
    }

    @Test func lockedFeatureAccessibilityLabelDoesNotRelyOnTheLockIcon() {
        #expect(CalendarLockedFeature.autoReplan.accessibilityLabel
            == "자동 일정 재조정, 잠김, 베이직부터 이용 가능")
        #expect(CalendarLockedFeature.examBackplan.accessibilityLabel
            == "시험일까지 역산한 일정, 잠김, 플러스부터 이용 가능")
    }

    @Test func noWeaknessPlannerIsOfferedAnywhere() {
        for feature in CalendarLockedFeature.allCases {
            #expect(!feature.title.contains("취약"))
            #expect(!feature.detail.contains("취약"))
        }
    }

    // MARK: 플랜 변경과 과거 기록

    @Test func planChangeDoesNotRewriteFrozenHistory() {
        // 어제 무료로 "완료 1 / 1"이던 날은 업그레이드해도 그대로다.
        let frozen = ["2026-08-13": 1]
        let before = snapshot(policy: .free, historical: frozen, completions: ["2026-08-13": 1])
        let after = snapshot(policy: .everything, historical: frozen, completions: ["2026-08-13": 1])
        func yesterday(_ snapshot: StudyCalendarSnapshot) -> StudyDay? {
            snapshot.weekDays.first { $0.date == StudyCalendarFixture.date("2026-08-13") }
        }
        #expect(yesterday(before)?.targetSets == 1)
        #expect(yesterday(after)?.targetSets == 1)
        #expect(yesterday(after)?.state == .completed)
    }

    @Test func historicalBackfillIsIdenticalOnEveryPlan() {
        // 되살리는 과거 배정량은 기본 학습량만 쓴다 → 자동화 권한과 무관하다.
        let free = snapshot(policy: .free).targetsToFreeze(settings: settings(), today: today)
        let plus = snapshot(policy: .everything).targetsToFreeze(settings: settings(), today: today)
        #expect(free.filter { $0.key < "2026-08-14" } == plus.filter { $0.key < "2026-08-14" })
    }

    @Test func upgradeKeepsSettingsAndCompletionsAndOnlyUnlocksAutomation() {
        let frozen = ["2026-08-13": 2]
        let completions = ["2026-08-13": 39]
        let free = snapshot(policy: .free, historical: frozen, completions: completions)
        let basic = snapshot(policy: .fallback(for: .basic), historical: frozen, completions: completions)

        // 완료 기록·설정 기반 일정 시작점은 그대로.
        #expect(free.plan.completedSets == basic.plan.completedSets)
        #expect(free.today.completedSets == basic.today.completedSets)
        #expect(free.plan.remainingSets == basic.plan.remainingSets)
        // 달라지는 것은 앞으로의 배정량 재분배뿐이다.
        #expect(free.plan.upcomingDays.map(\.targetSets) == [2, 2, 2])
        #expect(basic.plan.upcomingDays.map(\.targetSets) == [2, 2, 1])
    }

    @Test func downgradeKeepsHistoryAndOnlyChangesFuturePlanning() {
        let frozen = ["2026-08-12": 2, "2026-08-13": 2]
        let completions = ["2026-08-12": 2, "2026-08-13": 2]
        let plus = snapshot(policy: .everything, historical: frozen, completions: completions)
        let free = snapshot(policy: .free, historical: frozen, completions: completions)

        // 과거·연속 학습·완료 기록은 그대로.
        #expect(plus.streak == free.streak)
        #expect(plus.weekCompletedDays == free.weekCompletedDays)
        // 앞으로의 계획만 달라진다(평가 반영이 꺼져 권장 학습량이 보수적으로 바뀐다).
        #expect(plus.plan.totalRecommendedSets == 20)
        #expect(free.plan.totalRecommendedSets == 44)
    }
}
