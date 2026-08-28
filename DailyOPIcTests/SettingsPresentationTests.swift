import Foundation
import Testing
import UserNotifications
@testable import DailyOPIc

/// P9: 메인 설정 화면의 "알림"·"구독" 칸이 말하는 것.
///
/// 화면을 띄우지 않고 값으로 검증한다 — 스크린샷은 문구가 바뀌면 같이 썩는다.
@MainActor
struct SettingsPresentationTests {

    // MARK: 구독 칸

    /// A. 현재 플랜을 그대로 적는다.
    @Test func planTextNamesTheCurrentPlan() {
        let texts = PlanEntitlement.allCases.map {
            SubscriptionSettingsState.make(plan: $0, isEntitlementResolved: true).planText
        }
        #expect(texts == ["현재 플랜 무료", "현재 플랜 베이직", "현재 플랜 플러스", "현재 플랜 프로"])
    }

    /// B·C. 무료는 업그레이드, 베이직·플러스는 상위 플랜 보기 — 둘 다 기존 Paywall로 간다.
    @Test func upgradeCtaOpensThePaywall() {
        let free = SubscriptionSettingsState.make(plan: .free, isEntitlementResolved: true)
        #expect(free.actionTitle == "프리미엄으로 업그레이드")
        #expect(free.action == .paywall)

        for plan in [PlanEntitlement.basic, .plus] {
            let state = SubscriptionSettingsState.make(plan: plan, isEntitlementResolved: true)
            #expect(state.actionTitle == "더 높은 플랜 보기", "\(plan)")
            #expect(state.action == .paywall, "\(plan)")
        }
    }

    /// D·E. 최상위 플랜에게 업그레이드를 권하지 않는다. 대신 구독 관리로 간다.
    @Test func proIsOfferedManageSubscriptionInsteadOfAnUpgrade() {
        let pro = SubscriptionSettingsState.make(plan: .pro, isEntitlementResolved: true)
        #expect(pro.actionTitle == "구독 관리")
        #expect(pro.action == .manage)
        #expect(pro.actionTitle?.contains("업그레이드") == false)
    }

    /// F. 화면을 여는 것만으로는 Paywall이 뜨지 않는다 — 누를 것이 있을 뿐이다.
    @Test func openingSettingsNeverPresentsThePaywallByItself() {
        // 열림 여부는 `.paywall` 동작을 **눌렀을 때** 결정된다. 상태 자체는 아무것도 열지 않는다.
        for plan in PlanEntitlement.allCases {
            let state = SubscriptionSettingsState.make(plan: plan, isEntitlementResolved: true)
            #expect(state.action != .none)
        }
        #expect(PaywallSource.settings.rawValue == "settings")
    }

    /// G. 아직 확인되지 않은 엔타이틀먼트를 "무료"라고 적지 않는다(P7).
    @Test func unresolvedEntitlementIsNeverLabelledFree() {
        let state = SubscriptionSettingsState.make(plan: .free, isEntitlementResolved: false)
        #expect(state.planText == "구독 정보를 확인하는 중이에요")
        #expect(!state.planText.contains("무료"))
        #expect(state.actionTitle == nil)
        #expect(state.action == .none)
        #expect(!state.isResolved)
        // 결제한 사용자가 잠깐 "무료"를 보는 일도 없다.
        #expect(SubscriptionSettingsState.make(plan: .pro, isEntitlementResolved: false)
            == state)
    }

    /// 가격은 스토어에서만 온다. 설정 화면 문구에 금액을 적지 않는다.
    @Test func noHardcodedPriceAppearsInSettingsCopy() {
        let copy = PlanEntitlement.allCases.flatMap {
            [
                SubscriptionSettingsState.make(plan: $0, isEntitlementResolved: true).planText,
                SubscriptionSettingsState.make(plan: $0, isEntitlementResolved: true).actionTitle ?? "",
            ]
        }.joined()
        for token in ["원", "₩", "월 ", "/월"] {
            #expect(!copy.contains(token), "\(token)")
        }
    }

    // MARK: 알림 칸

    /// H. 스위치는 전 플랜에 있다. 플랜은 이 값에 아예 들어오지 않는다.
    @Test func reminderToggleIsAvailableOnEveryPlan() {
        let state = StudyReminderSettingsState.make(
            preference: .unspecified,
            authorization: .authorized
        )
        #expect(state.isOn)
        #expect(state.statusText == "매일 정한 시간에 알려드려요")
        // 잠금·업그레이드 유도 문구가 남아 있지 않다(P4 정책 폐기).
        for preference in StudyReminderPreference.allCases {
            for authorization in [
                UNAuthorizationStatus.notDetermined, .denied, .authorized, .provisional,
            ] {
                let text = StudyReminderSettingsState
                    .make(preference: preference, authorization: authorization).statusText
                for banned in ["베이직", "플러스", "프로", "업그레이드", "잠"] {
                    #expect(!text.contains(banned), "\(preference)/\(authorization): \(banned)")
                }
            }
        }
    }

    /// 상태 문구 세 가지가 제품 진실 그대로다.
    @Test func statusTextMatchesEachState() {
        #expect(StudyReminderSettingsState
            .make(preference: .enabled, authorization: .authorized).statusText
            == "매일 정한 시간에 알려드려요")
        #expect(StudyReminderSettingsState
            .make(preference: .disabled, authorization: .authorized).statusText
            == "학습 알림이 꺼져 있어요")
        #expect(StudyReminderSettingsState
            .make(preference: .enabled, authorization: .denied).statusText
            == "iPhone 설정에서 알림을 허용해 주세요")
        // 거부 상태에서 스위치를 다시 눌러도 권한 창은 뜨지 않는다.
        #expect(!StudyReminderSettingsState
            .make(preference: .enabled, authorization: .denied).requestsPermissionOnEnable)
    }

    /// I. 설정 스위치와 예약 서비스가 **같은 저장소 한 곳**을 본다(두 번째 설정이 없다).
    @Test func settingsToggleAndSchedulerShareOnePreference() async {
        let harness = ReminderServiceHarness()
        defer { harness.tearDown() }
        // 플래너 쪽에서 서비스를 새로 만들어도 같은 저장소를 읽는다.
        let plannerSide = StudyReminderService(
            preferences: harness.preferences,
            center: harness.center
        )

        await harness.service.disable()

        #expect(!plannerSide.isEnabled)
        #expect(plannerSide.preference == .disabled)
        #expect(StudyReminderService(
            preferences: harness.reloadedPreferences(),
            center: harness.center
        ).preference == .disabled)
    }
}
