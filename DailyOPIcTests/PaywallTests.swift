import Foundation
import Testing
@testable import DailyOPIc

/// 페이월 V2의 표시 계약. UI 스냅샷이 아니라 "무엇을 약속하는가"를 지킨다.
struct PaywallTests {
    @Test func paidSelectorOffersExactlyBasicPlusPro() {
        #expect(PaywallPlanCopy.paid.map(\.plan) == [.basic, .plus, .pro])
    }

    @Test func everyPlanCopyResolvesAndFreeIsTheFallback() {
        for plan in PlanEntitlement.allCases where plan != .free {
            #expect(PaywallPlanCopy.copy(for: plan).plan == plan)
        }
        #expect(PaywallPlanCopy.copy(for: .free).plan == .free)
    }

    /// 데일리 토큰 수는 백엔드 `plans.py`의 `practice_daily`가 진실이다.
    /// 한쪽만 바뀌면 페이월이 지키지 못할 약속을 하게 된다.
    @Test func dailyTokenCountsMatchServerPracticeDailyLimits() {
        let expected: [PlanEntitlement: String] = [.basic: "3", .plus: "10", .pro: "20"]
        for copy in PaywallPlanCopy.paid {
            let tokenLine = copy.benefits.first { $0.contains("데일리 토큰") }
            #expect(tokenLine == "매일 데일리 토큰 \(expected[copy.plan]!)개")
        }
        #expect(PaywallPlanCopy.free.benefits.first?.hasPrefix("매일 데일리 토큰 1개") == true)
    }

    /// 서버가 강제하지 않거나 앱에서 도달할 수 없는 혜택은 광고하지 않는다.
    /// - 기록 보관 기간: 서버에 기록 조회 API가 없고 로컬 저장은 전 플랜 동일하다.
    /// - 취약점 복습 세트 / 취약점 기반 일정: 앱에 진입 화면이 없거나(전자) 구현 자체가 없다(후자).
    /// 캘린더·일정 문구는 G4에서 실제 동작이 생겼으므로 더 이상 금지어가 아니다.
    @Test func copyNeverPromisesUnenforcedBenefits() {
        let forbidden = ["기록 보관", "복습"]
        let allCopy = (PaywallPlanCopy.paid + [PaywallPlanCopy.free])
            .flatMap { [$0.tagline] + $0.benefits }
            + PaywallComparisonRow.all.flatMap { [$0.title] + $0.values }
        for line in allCopy {
            for word in forbidden {
                #expect(!line.contains(word), "\(line) 이 아직 제공하지 않는 '\(word)'를 약속한다")
            }
        }
    }

    /// 캘린더 문구는 각 플랜이 **실제로 켜는** 자동화만 말한다.
    @Test func calendarCopyMatchesEachPlanCapabilities() {
        func lines(_ copy: PaywallPlanCopy) -> String { copy.benefits.joined(separator: "\n") }

        // 무료: 캘린더를 쓴다고만 말하고 자동화를 약속하지 않는다.
        let free = lines(.free)
        #expect(free.contains("학습 캘린더"))
        #expect(!free.contains("자동"))
        #expect(!free.contains("역산"))

        // 베이직: 자동 재조정 하나만.
        let basic = lines(PaywallPlanCopy.copy(for: .basic))
        #expect(basic.contains("자동 일정 재조정"))
        #expect(!basic.contains("역산"))
        #expect(!basic.contains("최근 평가"))

        // 플러스: 평가 반영 + 시험일 역산.
        let plus = lines(PaywallPlanCopy.copy(for: .plus))
        #expect(plus.contains("최근 평가를 반영한 학습 계획"))
        #expect(plus.contains("시험일까지 역산한 일정 조정"))

        // 프로: 플러스와 같은 일정 기능이라고만 말한다. 프로 전용 일정 기능은 없다.
        let pro = lines(PaywallPlanCopy.copy(for: .pro))
        #expect(pro.contains("플러스의 학습 일정 기능 그대로"))
    }

    /// 구현이 없는 취약점 기반 일정은 어떤 플랜 문구에도 나오지 않는다.
    @Test func copyNeverClaimsWeaknessBasedScheduling() {
        let allCopy = (PaywallPlanCopy.paid + [PaywallPlanCopy.free])
            .flatMap { [$0.tagline] + $0.benefits }
            + PaywallComparisonRow.all.flatMap { [$0.title] + $0.values }
        for line in allCopy {
            #expect(!line.contains("취약"), "\(line) 이 구현 없는 취약점 기반 일정을 약속한다")
        }
    }

    /// 실제 프로모션이 없으면 한정 특가·긴박함 문구도 없어야 한다.
    @Test func copyContainsNoFakePromotionOrUrgency() {
        let banned = ["할인", "특가", "지금", "한정", "무료 체험", "이벤트"]
        let allCopy = (PaywallPlanCopy.paid + [PaywallPlanCopy.free])
            .flatMap { [$0.tagline] + $0.benefits }
        for line in allCopy {
            for word in banned {
                #expect(!line.contains(word), "\(line) 에 근거 없는 마케팅 문구 '\(word)'가 있다")
            }
        }
    }

    @Test func comparisonRowsCoverEveryPlanColumn() {
        #expect(PaywallComparisonRow.planColumns == [.free, .basic, .plus, .pro])
        for row in PaywallComparisonRow.all {
            #expect(row.values.count == PaywallComparisonRow.planColumns.count)
        }
    }

    /// 로그 스키마. 값이 바뀌면 이전 이벤트와 이어지지 않는다.
    @Test func paywallSourceRawValuesAreTheLogSchema() {
        #expect(PaywallSource.settings.rawValue == "settings")
        #expect(PaywallSource.tokenExhausted.rawValue == "token_exhausted")
        #expect(PaywallSource.resultLocked.rawValue == "result_locked")
        #expect(PaywallSource.mockLimit.rawValue == "mock_limit")
        #expect(PaywallSource.calendarLocked.rawValue == "calendar_locked")
    }

    @Test func purchaseErrorsMapToFixedCategories() {
        #expect(PurchaseErrorCategory(StoreError.purchaseCancelled) == .cancelled)
        #expect(PurchaseErrorCategory(StoreError.notConfigured) == .notConfigured)
        #expect(PurchaseErrorCategory(StoreError.unknown("SKErrorDomain 2")) == .unknown)
        #expect(PurchaseErrorCategory(URLError(.notConnectedToInternet)) == .unknown)
    }
}
