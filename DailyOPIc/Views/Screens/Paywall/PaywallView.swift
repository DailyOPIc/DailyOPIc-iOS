import SwiftUI

/// 구독/시험대비 패스 결제 화면. 티어 비교 + 상품 구매 + 복원.
/// 상품 목록은 RevenueCat(StoreService)에서 오며, 미설정 시 티어 안내만 노출한다.
struct PaywallView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var purchasing: String?
    @State private var restoring = false
    @State private var errorMessage: String?

    private var store: StoreService { environment.store }
    private var currentPlan: PlanEntitlement { environment.currentPlan }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    header
                    tierCards
                    if !store.packages.isEmpty {
                        purchaseSection
                    } else {
                        unavailableNotice
                    }
                    restoreAndLegal
                }
                .padding(AppSpacing.md)
            }
            .background(AppPalette.surface.ignoresSafeArea())
            .navigationTitle("가성비 OPIc 구독")
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
        }
    }

    private var header: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("가성비 있게 오픽 공부하자")
                .font(AppTypography.title)
                .foregroundStyle(Color(AppPalette.ink))
                .multilineTextAlignment(.center)
            Text("광고 없이 매일 연습 + 즉시 AI 피드백.\n학원 한 강좌보다 저렴하게.")
                .font(AppTypography.callout)
                .foregroundStyle(Color(AppPalette.secondaryInk))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.sm)
    }

    private var tierCards: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(PaywallTier.all) { tier in
                PaywallTierCard(
                    tier: tier,
                    isCurrent: tier.plan == currentPlan
                )
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("구독 선택")
                .font(AppTypography.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color(AppPalette.ink))
            ForEach(store.packages) { package in
                Button {
                    Task { await purchase(package) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.plan.displayName)
                                .font(AppTypography.callout)
                            Text(package.isSubscription ? "월 구독" : "시험 대비 패스")
                                .font(AppTypography.footnote)
                                .foregroundStyle(Color(AppPalette.secondaryInk))
                        }
                        Spacer()
                        if purchasing == package.id {
                            ProgressView()
                        } else {
                            Text(package.localizedPrice)
                                .font(AppTypography.callout.weight(.bold))
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity)
                    .background(Color(AppPalette.primarySoft))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .disabled(purchasing != nil)
            }
        }
    }

    private var unavailableNotice: some View {
        Text("상품 정보를 불러오는 중입니다. 스토어 설정이 완료되면 여기에서 바로 구독할 수 있어요.")
            .font(AppTypography.footnote)
            .foregroundStyle(Color(AppPalette.secondaryInk))
            .multilineTextAlignment(.center)
            .padding(AppSpacing.md)
    }

    private var restoreAndLegal: some View {
        VStack(spacing: AppSpacing.sm) {
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
            .disabled(restoring)

            if let privacy = AppConfiguration.privacyPolicyURL {
                Button("개인정보 처리방침") { openURL(privacy) }
                    .font(AppTypography.footnote)
                    .foregroundStyle(Color(AppPalette.secondaryInk))
            }
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
            if currentPlan.isPaid { dismiss() }
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
            else { errorMessage = "복원할 구독을 찾지 못했습니다." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 페이월 티어 비교 카드용 정적 모델.
struct PaywallTier: Identifiable {
    let plan: PlanEntitlement
    let highlights: [String]

    var id: String { plan.rawValue }

    static let all: [PaywallTier] = [
        PaywallTier(
            plan: .free,
            highlights: ["데일리 1회 + 광고 보너스 1회", "모의고사 체험 1회", "예상 등급·요약", "광고 있음"]
        ),
        PaywallTier(
            plan: .basic,
            highlights: ["광고 제거", "데일리 하루 3회", "매일 모의고사(기본 분석)", "기록 30일"]
        ),
        PaywallTier(
            plan: .plus,
            highlights: ["데일리 하루 10회", "상세 분석(교정·모범답안)", "예상 등급 추이·취약 유형(기본)"]
        ),
        PaywallTier(
            plan: .pro,
            highlights: ["데일리 하루 20회", "집중 분석 + 취약점 복습 세트", "주간 리포트 · 고급 취약 분석", "기록 전체"]
        ),
    ]
}

private struct PaywallTierCard: View {
    let tier: PaywallTier
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.plan.displayName)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(Color(AppPalette.ink))
                if tier.plan == .basic {
                    Text("가성비")
                        .font(AppTypography.caption)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color(AppPalette.primary))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(tier.plan == .free ? "무료" : "₩\(tier.plan.monthlyPriceKRW.formatted())/월")
                    .font(AppTypography.callout.weight(.bold))
                    .foregroundStyle(Color(AppPalette.primaryMid))
            }
            ForEach(tier.highlights, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill")
                    .font(AppTypography.footnote)
                    .foregroundStyle(Color(AppPalette.secondaryInk))
                    .labelStyle(.titleAndIcon)
            }
            if isCurrent {
                Text("현재 이용 중")
                    .font(AppTypography.caption)
                    .foregroundStyle(Color(AppPalette.primary))
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AppPalette.elevatedSurface))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(
                    isCurrent ? Color(AppPalette.primary) : Color.clear,
                    lineWidth: 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}
