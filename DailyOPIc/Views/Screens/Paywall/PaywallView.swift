import SwiftUI

/// 데일리오픽 프리미엄 구독 화면.
/// 티어 카드 자체가 구매 버튼이며, 현재 플랜 표시 + 플랜 변경 + 복원 + 구독 관리를 제공한다.
/// 상품/가격은 RevenueCat(StoreService)에서 오며, 미설정 시 안내 문구만 노출한다.
struct PaywallView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var purchasing: String?
    @State private var restoring = false
    @State private var managing = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var store: StoreService { environment.store }
    private var currentPlan: PlanEntitlement { environment.currentPlan }

    /// 플랜별 실제 구매 상품(현지화 가격/구매 트리거 소스).
    private var packagesByPlan: [PlanEntitlement: StorePackage] {
        Dictionary(store.packages.map { ($0.plan, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    header
                    tierCards
                    Text("예상 등급 추이 · 취약 유형 분석 · 주간 리포트는 모든 플랜에서 무료로 제공돼요.")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color(AppPalette.secondaryInk))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    if store.packages.isEmpty {
                        unavailableNotice
                    }
                    footer
                }
                .padding(AppSpacing.md)
            }
            .background(AppPalette.surface.ignoresSafeArea())
            .task { await store.refreshCustomerInfo() }
            .navigationTitle("데일리오픽 프리미엄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .alert("알림", isPresented: .constant(errorMessage != nil)) {
                Button("확인") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("안내", isPresented: .constant(infoMessage != nil)) {
                Button("확인") { infoMessage = nil }
            } message: {
                Text(infoMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("데일리오픽 프리미엄")
                .font(AppTypography.title)
                .foregroundStyle(Color(AppPalette.ink))
                .multilineTextAlignment(.center)
            Text("광고 없이 매일 연습하고, AI가 약점까지 잡아줍니다.")
                .font(AppTypography.callout)
                .foregroundStyle(Color(AppPalette.secondaryInk))
                .multilineTextAlignment(.center)
            currentPlanBadge
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.sm)
    }

    private var currentPlanBadge: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: currentPlan.isPaid ? "crown.fill" : "person")
            Text("현재 플랜 · \(currentPlan.displayName)")
                .font(AppTypography.footnote.weight(.semibold))
        }
        .foregroundStyle(Color(AppPalette.primary))
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color(AppPalette.primarySoft))
        .clipShape(Capsule())
        .padding(.top, AppSpacing.xs)
    }

    private var tierCards: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(PaywallTier.all) { tier in
                let package = packagesByPlan[tier.plan]
                let isCurrent = tier.plan == currentPlan
                let purchasable = tier.plan != .free && !isCurrent && package != nil

                PaywallTierCard(
                    tier: tier,
                    isCurrent: isCurrent,
                    priceText: priceText(for: tier, package: package),
                    isPurchasing: purchasing != nil && purchasing == package?.id,
                    isPurchasable: purchasable
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .onTapGesture {
                    guard purchasable, let package else { return }
                    Task { await purchase(package) }
                }
                .opacity(purchasing != nil && purchasing != package?.id ? 0.5 : 1)
            }
        }
        .disabled(purchasing != nil)
    }

    private func priceText(for tier: PaywallTier, package: StorePackage?) -> String {
        if tier.plan == .free { return "무료" }
        // 하드코딩 금지 원칙: 현지화 가격 우선, 미로딩 시에만 임시 표기.
        return package?.localizedPrice ?? "불러오는 중…"
    }

    private var unavailableNotice: some View {
        Text("상품 정보를 불러오는 중입니다. 스토어 설정이 완료되면 카드를 눌러 바로 구독할 수 있어요.")
            .font(AppTypography.footnote)
            .foregroundStyle(Color(AppPalette.secondaryInk))
            .multilineTextAlignment(.center)
            .padding(AppSpacing.md)
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.sm) {
            if currentPlan.isPaid {
                Button {
                    Task { await manage() }
                } label: {
                    if managing { ProgressView() } else { Text("구독 관리 · 해지").font(AppTypography.callout) }
                }
                .minimumTouchTarget()
                .disabled(managing)
            }

            Button {
                Task { await restore() }
            } label: {
                if restoring {
                    ProgressView()
                } else {
                    Text("구매 복원")
                        .font(AppTypography.callout)
                }
            }
            .minimumTouchTarget()
            .disabled(restoring)

            HStack(spacing: AppSpacing.md) {
                if let privacy = AppConfiguration.privacyPolicyURL {
                    Button("개인정보 처리방침") { openURL(privacy) }
                        .minimumTouchTarget()
                }
                Button("이용약관(EULA)") { openURL(AppConfiguration.termsOfUseURL) }
                    .minimumTouchTarget()
            }
            .font(AppTypography.footnote)
            .foregroundStyle(Color(AppPalette.secondaryInk))
            Text("구독은 App Store 계정으로 청구되며 기간 종료 24시간 전까지 해지하지 않으면 자동 갱신됩니다. 설정 > Apple ID에서 언제든 관리할 수 있습니다.")
                .font(AppTypography.caption)
                .foregroundStyle(Color(AppPalette.secondaryInk))
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.sm)
    }

    private func purchase(_ package: StorePackage) async {
        purchasing = package.id
        defer { purchasing = nil }
        do {
            try await store.purchase(package)
            if currentPlan == package.plan {
                // 업그레이드/신규 구독은 즉시 적용 → 닫기.
                dismiss()
            } else {
                // 다운그레이드는 App Store 정책상 다음 결제일에 적용된다.
                infoMessage = "요금제 변경이 예약되었습니다. 현재 구독 기간이 끝나면 \(package.plan.displayName)(으)로 전환됩니다."
            }
        } catch StoreError.purchaseCancelled {
            // 사용자가 취소 — 조용히 무시.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            try await store.restore()
            if currentPlan.isPaid { dismiss() }
            else { errorMessage = "복원할 활성 구독이 없습니다." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func manage() async {
        managing = true
        defer { managing = false }
        do {
            try await store.manageSubscriptions()
            await environment.refreshCapabilities()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 페이월 티어 비교 카드용 정적 모델.
struct PaywallTier: Identifiable {
    let plan: PlanEntitlement
    let highlights: [String]
    /// 오픈 기념 할인 등 프로모션 배지(없으면 nil).
    let promoBadge: String?
    let promoNote: String?

    var id: String { plan.rawValue }

    static let all: [PaywallTier] = [
        PaywallTier(
            plan: .free,
            highlights: [
                "데일리 새 문제 세트 하루 1회 (+광고 보너스 1회)",
                "모의고사 최초 1회 체험",
                "결과: 예상 등급 + 강점",
                "학습 기록 최근 7일",
                "광고 있음",
            ],
            promoBadge: nil,
            promoNote: nil
        ),
        PaywallTier(
            plan: .basic,
            highlights: [
                "광고 완전 제거",
                "데일리 새 문제 세트 하루 3회",
                "모의고사 하루 1회",
                "결과: + 개선점 · 5차원 루브릭 분석",
                "학습 기록 최근 30일",
            ],
            promoBadge: "오픈 기념 할인",
            promoNote: "오픈 초기 특가 진행 중 — 지금 가장 저렴하게 시작하세요."
        ),
        PaywallTier(
            plan: .plus,
            highlights: [
                "데일리 새 문제 세트 하루 10회",
                "모의고사 하루 3회",
                "결과: + 교정답안 · 모범답안 · 목표 등급까지",
                "학습 기록 최근 30일",
            ],
            promoBadge: nil,
            promoNote: nil
        ),
        PaywallTier(
            plan: .pro,
            highlights: [
                "데일리 새 문제 세트 하루 20회",
                "모의고사 하루 5회",
                "결과: + 모의고사 항목별(문항별) 피드백",
                "학습 기록 전체",
            ],
            promoBadge: nil,
            promoNote: nil
        ),
    ]
}

private struct PaywallTierCard: View {
    let tier: PaywallTier
    let isCurrent: Bool
    let priceText: String
    let isPurchasing: Bool
    let isPurchasable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.plan.displayName)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(Color(AppPalette.ink))
                if let badge = tier.promoBadge {
                    Text(badge)
                        .font(AppTypography.caption)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color(AppPalette.primary))
                        .foregroundStyle(AppPalette.actionOnPrimary)
                        .clipShape(Capsule())
                }
                Spacer()
                if isPurchasing {
                    ProgressView()
                } else {
                    Text(tier.plan == .free ? "무료" : "\(priceText)\(tier.plan == .free ? "" : "/월")")
                        .font(AppTypography.callout.weight(.bold))
                        .foregroundStyle(Color(AppPalette.primary))
                }
            }
            if let note = tier.promoNote {
                Text(note)
                    .font(AppTypography.caption)
                    .foregroundStyle(Color(AppPalette.primary))
            }
            ForEach(tier.highlights, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill")
                    .font(AppTypography.footnote)
                    .foregroundStyle(Color(AppPalette.secondaryInk))
                    .labelStyle(.titleAndIcon)
            }
            statusLine
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AppPalette.elevatedSurface))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(
                    isCurrent ? Color(AppPalette.primary) : Color.clear,
                    lineWidth: 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    @ViewBuilder
    private var statusLine: some View {
        if isCurrent {
            Text("현재 이용 중")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(Color(AppPalette.primary))
        } else if isPurchasable {
            Text("탭하여 시작하기 →")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(Color(AppPalette.primary))
        }
    }
}
