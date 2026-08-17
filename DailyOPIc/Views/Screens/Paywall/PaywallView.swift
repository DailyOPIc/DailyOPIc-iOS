import SwiftUI

/// 데일리오픽 프리미엄 구독 화면(V2).
///
/// 이전 버전은 네 개의 큰 카드를 늘어놓고 사용자가 직접 값을 비교하게 하는
/// 사양서였다. 이제는 (1) 데일리 토큰이 뭔지, (2) 플랜별로 몇 개인지,
/// (3) 어떤 플랜이 나에게 맞는지 한 번에 답하고, 선택한 유료 플랜 하나만
/// 자세히 보여준다. 전체 비교표는 접힌 보조 영역으로 내린다.
///
/// 가격은 항상 RevenueCat(StoreService)의 현지화 가격이며 앱에 상수로 두지 않는다.
struct PaywallView: View {
    /// 페이월을 연 지점. 분석 이벤트에만 쓰이고 화면 구성은 바꾸지 않는다.
    var source: PaywallSource = .settings

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPlan: PlanEntitlement = .plus
    @State private var purchasing: String?
    @State private var restoring = false
    @State private var managing = false
    @State private var showsComparison = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var store: StoreService { environment.store }
    private var currentPlan: PlanEntitlement { environment.currentPlan }

    /// 플랜별 실제 구매 상품(현지화 가격/구매 트리거 소스).
    private var packagesByPlan: [PlanEntitlement: StorePackage] {
        Dictionary(store.packages.map { ($0.plan, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var selectedCopy: PaywallPlanCopy { PaywallPlanCopy.copy(for: selectedPlan) }
    private var selectedPackage: StorePackage? { packagesByPlan[selectedPlan] }
    private var isPurchasing: Bool { purchasing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    header
                    dailyTokenExplainer
                    planSelector
                    selectedPlanDetail
                    freePlanRow
                    comparisonSection
                    footer
                }
                .padding(AppSpacing.md)
            }
            .background(AppPalette.surface.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { purchaseBar }
            .task {
                // 이미 유료면 그 플랜을 기본 선택으로 둔다(변경 대상이 명확해진다).
                if currentPlan.isPaid { selectedPlan = currentPlan }
                AppTelemetry.paywallViewed(source: source)
                await store.refreshCustomerInfo()
            }
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

    // MARK: - 헤더

    private var header: some View {
        VStack(spacing: AppSpacing.xs) {
            // 어디서 들어왔는지만 한 줄로 되짚는다. "당신에게 OO이 최적" 같은 추천은 하지 않는다.
            Text(
                source == .calendarLocked
                ? "학습 일정 자동화는 유료 플랜에 포함돼 있어요."
                : "내 학습량에 맞는 플랜을 선택하세요."
            )
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            currentPlanBadge
        }
        .frame(maxWidth: .infinity)
    }

    private var currentPlanBadge: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: currentPlan.isPaid ? "crown.fill" : "person")
            Text("현재 플랜 · \(currentPlan.displayName)")
                .font(AppTypography.footnote.weight(.semibold))
        }
        .foregroundStyle(AppPalette.primary)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppPalette.primarySoft, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: - 데일리 토큰 설명

    private var dailyTokenExplainer: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "bolt.fill")
                Text("데일리 토큰")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppPalette.primary)

            Text("토큰 1개로 새로운 Daily 문제 세트 1개를 시작할 수 있어요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.ink)
            Text("한 번 시작한 세트의 답변과 채점에는 추가 토큰이 들지 않아요. 모의고사는 토큰과 별개로 플랜별 횟수만큼 응시해요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppPalette.primarySoft)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 유료 플랜 선택

    private var planSelector: some View {
        // 접근성 글자 크기에서는 칩 3개를 가로로 두면 작은 iPhone 폭에서 한국어가
        // 깨진다. 그 구간에서만 세로로 쌓는다.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AppSpacing.sm))
            : AnyLayout(HStackLayout(spacing: AppSpacing.sm))
        return layout {
            ForEach(PaywallPlanCopy.paid) { copy in
                PaywallPlanChip(
                    copy: copy,
                    priceText: priceText(for: copy.plan),
                    isSelected: copy.plan == selectedPlan,
                    isCurrent: copy.plan == currentPlan
                ) {
                    guard selectedPlan != copy.plan else { return }
                    selectedPlan = copy.plan
                    AppTelemetry.paywallPlanSelected(plan: copy.plan, source: source)
                }
            }
        }
        .disabled(isPurchasing)
    }

    private var selectedPlanDetail: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPlan.displayName)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppPalette.ink)
                    Text(selectedCopy.tagline)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer(minLength: AppSpacing.sm)
                Text(priceText(for: selectedPlan))
                    .font(AppTypography.callout.weight(.bold))
                    .foregroundStyle(AppPalette.primary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(selectedCopy.benefits, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle.fill")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppPalette.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 무료 플랜(비교용, 구매 CTA 없음)

    private var freePlanRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("무료 플랜")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppPalette.ink)
                if !currentPlan.isPaid {
                    Text("현재 이용 중")
                        .font(AppTypography.caption)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(AppPalette.primarySoft, in: Capsule())
                        .foregroundStyle(AppPalette.primary)
                }
            }
            Text(PaywallPlanCopy.free.benefits.joined(separator: " · "))
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppPalette.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 모든 플랜 비교(보조)

    private var comparisonSection: some View {
        DisclosureGroup("모든 플랜 비교", isExpanded: $showsComparison) {
            VStack(spacing: AppSpacing.sm) {
                ForEach(PaywallComparisonRow.all) { row in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(row.title)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppPalette.secondaryInk)
                        // 4열 그리드는 작은 iPhone 폭 + 큰 글자에서 반드시 깨진다.
                        // 플랜별 값을 세로로 쌓아 한국어 줄바꿈에 안전하게 둔다.
                        ForEach(Array(zip(PaywallComparisonRow.planColumns, row.values)), id: \.0) { plan, value in
                            HStack(alignment: .firstTextBaseline) {
                                Text(plan.displayName)
                                    .font(AppTypography.footnote)
                                    .foregroundStyle(AppPalette.secondaryInk)
                                Spacer(minLength: AppSpacing.sm)
                                Text(value)
                                    .font(AppTypography.footnote.weight(.semibold))
                                    .foregroundStyle(AppPalette.ink)
                                    .multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(row.title) \(plan.displayName) \(value)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, AppSpacing.sm)
        }
        .font(AppTypography.callout)
        .tint(AppPalette.primary)
        .padding(AppSpacing.md)
        .background(AppPalette.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    // MARK: - 구매 CTA

    @ViewBuilder
    private var purchaseBar: some View {
        VStack(spacing: AppSpacing.xs) {
            if selectedPlan == currentPlan {
                Text("\(selectedPlan.displayName) 플랜을 이용 중이에요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else if let package = selectedPackage {
                PrimaryButton(
                    title: "\(selectedPlan.displayName) 시작하기",
                    isLoading: purchasing == package.id,
                    // 다른 카드 구매가 진행 중이면 중복 탭을 막는다.
                    isDisabled: isPurchasing
                ) {
                    Task { await purchase(package) }
                }
            } else {
                Text("상품 정보를 불러오는 중입니다. 잠시 후 다시 시도해 주세요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// 가격은 스토어의 현지화 문자열만 쓴다. 앱에 원화 상수를 두지 않는다.
    private func priceText(for plan: PlanEntitlement) -> String {
        guard let price = packagesByPlan[plan]?.localizedPrice else { return "불러오는 중…" }
        return "\(price)/월"
    }

    // MARK: - 하단 링크

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
            .foregroundStyle(AppPalette.secondaryInk)
            Text("구독은 App Store 계정으로 청구되며 기간 종료 24시간 전까지 해지하지 않으면 자동 갱신됩니다. 설정 > Apple ID에서 언제든 관리할 수 있습니다.")
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, AppSpacing.sm)
    }

    // MARK: - 구매 / 복원

    private func purchase(_ package: StorePackage) async {
        guard purchasing == nil else { return }
        purchasing = package.id
        defer { purchasing = nil }
        AppTelemetry.purchaseStarted(plan: package.plan, source: source)
        do {
            try await store.purchase(package)
            AppTelemetry.purchaseSucceeded(plan: package.plan, source: source)
            if currentPlan == package.plan {
                // 업그레이드/신규 구독은 즉시 적용 → 닫기.
                dismiss()
            } else {
                // 다운그레이드는 App Store 정책상 다음 결제일에 적용된다.
                infoMessage = "요금제 변경이 예약되었습니다. 현재 구독 기간이 끝나면 \(package.plan.displayName)(으)로 전환됩니다."
            }
        } catch StoreError.purchaseCancelled {
            // 사용자가 취소 — 조용히 무시.
            AppTelemetry.purchaseFailed(plan: package.plan, source: source, error: StoreError.purchaseCancelled)
        } catch {
            AppTelemetry.purchaseFailed(plan: package.plan, source: source, error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        AppTelemetry.restoreStarted()
        do {
            try await store.restore()
            if currentPlan.isPaid {
                AppTelemetry.restoreSucceeded(plan: currentPlan)
                dismiss()
            } else {
                AppTelemetry.restoreFailed(error: nil)
                errorMessage = "복원할 활성 구독이 없습니다."
            }
        } catch {
            AppTelemetry.restoreFailed(error: error)
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

/// 유료 플랜 셀렉터 칩. 선택 상태를 색만으로 나타내지 않는다(테두리 + 체크 기호).
private struct PaywallPlanChip: View {
    let copy: PaywallPlanCopy
    let priceText: String
    let isSelected: Bool
    let isCurrent: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(isSelected ? AppPalette.primary : AppPalette.secondaryInk)
                Text(copy.plan.displayName)
                    .font(AppTypography.callout.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(AppPalette.ink)
                Text(priceText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .minimumScaleFactor(0.8)
                if isCurrent {
                    Text("이용 중")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.primary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.xs)
            .background(isSelected ? AppPalette.primarySoft : AppPalette.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(isSelected ? AppPalette.primary : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(copy.plan.displayName), \(copy.tagline), \(priceText)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
