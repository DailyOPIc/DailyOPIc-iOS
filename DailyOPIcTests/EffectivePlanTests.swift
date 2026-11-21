import Testing
@testable import DailyOPIc

/// 앱 플랜 = App Store 구독과 서버 플랜(웹 이용권 포함) 중 높은 쪽.
struct EffectivePlanTests {
    @Test func webPassOnServerUnlocksPlanWithoutAppStoreSubscription() {
        #expect(AppEnvironment.effectivePlan(storePlan: .free, serverPlan: "plus") == .plus)
    }

    @Test func freshAppStorePurchaseWinsBeforeServerWebhookArrives() {
        #expect(AppEnvironment.effectivePlan(storePlan: .pro, serverPlan: "free") == .pro)
    }

    @Test func higherOfBothIsUsed() {
        #expect(AppEnvironment.effectivePlan(storePlan: .basic, serverPlan: "pro") == .pro)
        #expect(AppEnvironment.effectivePlan(storePlan: .plus, serverPlan: "basic") == .plus)
    }

    @Test func withoutRevenueCatServerPlanIsUsedAndUnknownIsFree() {
        #expect(AppEnvironment.effectivePlan(storePlan: nil, serverPlan: "basic") == .basic)
        #expect(AppEnvironment.effectivePlan(storePlan: nil, serverPlan: nil) == .free)
        #expect(AppEnvironment.effectivePlan(storePlan: nil, serverPlan: "unknown") == .free)
    }
}
