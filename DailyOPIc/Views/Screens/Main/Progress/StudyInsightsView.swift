import SwiftUI

/// 통계 탭의 플랜별 스마트 인사이트 묶음.
/// 예상 등급 추이 / 취약 유형 분석 / 주간 리포트 — 모두 로컬 기록으로 계산(신규 AI 없음).
/// 플랜 미충족 항목은 잠금 카드로 표시하고 탭하면 페이월을 연다.
struct StudyInsightsSection: View {
    let plan: PlanEntitlement
    let insights: StudyInsights
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            gradeTrendCard
            weaknessCard
            weeklyReportCard
        }
    }

    // MARK: 예상 등급 추이

    @ViewBuilder
    private var gradeTrendCard: some View {
        let limited = plan == .free
        let points = limited ? Array(insights.trend.suffix(3)) : insights.trend
        InsightCard(title: "예상 등급 추이", locked: false) {
            if points.count < 2 {
                Text("기록이 2개 이상 쌓이면 추이가 표시돼요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                GradeTrendChart(points: points)
                    .frame(height: 120)
                if limited {
                    Text("무료 플랜은 최근 3개만 표시돼요. 전체 추이는 유료 플랜에서.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
        }
    }

    // MARK: 취약 유형 분석

    @ViewBuilder
    private var weaknessCard: some View {
        // 매트릭스: free/basic 없음, plus 기본(최상위 1), pro 고급(전체).
        let tier = plan.weaknessTier
        InsightCard(
            title: "취약 유형 분석",
            locked: tier == .none,
            onUpgrade: onUpgrade
        ) {
            if let averages = insights.dimensionAverages, !averages.isEmpty {
                switch tier {
                case .none:
                    Text("내 답변에서 가장 약한 영역을 짚어드려요. (플러스 이상)")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                case .basic:
                    if let weakest = averages.min(by: { $0.score < $1.score }) {
                        Text("가장 보완이 필요한 영역")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                        DimensionBar(name: weakest.name, score: weakest.score, highlight: true)
                    }
                case .advanced:
                    ForEach(averages.sorted { $0.score < $1.score }, id: \.name) { item in
                        DimensionBar(name: item.name, score: item.score, highlight: false)
                    }
                    if plan == .pro {
                        Text("가장 약한 영역 위주로 '복습 세트'를 만들면 효율이 올라가요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
            } else {
                Text("연습 기록이 쌓이면 영역별 분석이 표시돼요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    // MARK: 주간 리포트(Pro)

    @ViewBuilder
    private var weeklyReportCard: some View {
        InsightCard(
            title: "주간 리포트",
            locked: plan != .pro,
            onUpgrade: onUpgrade
        ) {
            if plan == .pro {
                if let report = insights.weeklyReport {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        reportRow("이번 주 응시", "\(report.attempts)회")
                        reportRow("평균 예상 등급", report.averageLevel?.rawValue ?? "-")
                        if let weakest = report.weakestDimension {
                            reportRow("집중 보완 영역", weakest)
                        }
                    }
                } else {
                    Text("이번 주 기록이 없어요.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            } else {
                Text("매주 학습 요약을 리포트로 받아보세요. (프로)")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    private func reportRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(AppTypography.footnote).foregroundStyle(AppPalette.secondaryInk)
            Spacer()
            Text(value).font(AppTypography.callout.weight(.semibold)).foregroundStyle(AppPalette.ink)
        }
    }
}

// MARK: - 카드 셸

private struct InsightCard<Content: View>: View {
    let title: String
    var locked: Bool = false
    var onUpgrade: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(title).font(AppTypography.cardTitle).foregroundStyle(AppPalette.ink)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
                if locked {
                    Button("업그레이드") { onUpgrade?() }
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.primary)
                }
            }
            content
        }
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture { if locked { onUpgrade?() } }
    }
}

private struct DimensionBar: View {
    let name: String
    let score: Int
    let highlight: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .frame(width: 72, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(highlight ? AppPalette.danger : AppPalette.primary)
                        .frame(width: max(8, proxy.size.width * CGFloat(Double(score) / 100.0)))
                }
            }
            .frame(height: 10)
            Text("\(score)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryInk)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

private struct GradeTrendChart: View {
    let points: [StudyInsights.TrendPoint]

    var body: some View {
        GeometryReader { proxy in
            let maxOrdinal = Double(OPIcLevel.allCases.count - 1)
            let stepX = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : 0
            let coords = points.enumerated().map { index, point in
                CGPoint(
                    x: CGFloat(index) * stepX,
                    y: proxy.size.height * (1 - CGFloat(Double(point.ordinal) / maxOrdinal))
                )
            }
            ZStack {
                Path { path in
                    guard let first = coords.first else { return }
                    path.move(to: first)
                    for point in coords.dropFirst() { path.addLine(to: point) }
                }
                .stroke(AppPalette.primary, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(Array(coords.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(AppPalette.primary)
                        .frame(width: 7, height: 7)
                        .position(point)
                }
                if let last = points.last, let lastCoord = coords.last {
                    Text(last.level.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.primary)
                        .position(x: max(14, lastCoord.x - 10), y: max(10, lastCoord.y - 12))
                }
            }
        }
    }
}
