import SwiftUI

/// 통계 탭의 스마트 인사이트 묶음.
/// 예상 등급 추이 / 취약 유형 분석 / 주간 리포트 — 모두 로컬 기록으로 계산(신규 AI 없음)하고
/// 전 플랜 무료다. 그래서 플랜도 잠금도 받지 않는다.
struct StudyInsightsSection: View {
    let insights: StudyInsights

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
        InsightCard(title: "예상 등급 추이") {
            if insights.trend.count < 2 {
                Text("기록이 2개 이상 쌓이면 추이가 표시돼요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                GradeTrendChart(points: insights.trend)
                    .frame(height: 120)
            }
        }
    }

    // MARK: 취약 유형 분석

    @ViewBuilder
    private var weaknessCard: some View {
        // 5영역을 약한 순으로. 점수가 아니라 밴드로 말한다.
        InsightCard(title: "취약 유형 분석") {
            if let dimensions = insights.dimensions, !dimensions.isEmpty {
                ForEach(dimensions, id: \.name) { item in
                    DimensionRow(name: item.name, band: item.band)
                }
            } else {
                Text("연습 기록이 쌓이면 영역별 분석이 표시돼요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    // MARK: 주간 리포트

    @ViewBuilder
    private var weeklyReportCard: some View {
        InsightCard(title: "주간 리포트") {
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title).font(AppTypography.cardTitle).foregroundStyle(AppPalette.ink)
            content
        }
        .cardStyle()
    }
}

/// 영역별 수준. 서버 밴드는 5단계뿐이라 5칸 표시 + 문구로 말한다.
/// 예전의 0~100 막대는 밴드를 되돌린 값(20/40/60/80/95)의 평균이라
/// "63점" 같은 정밀도가 근거 없이 만들어지고 있었다.
private struct DimensionRow: View {
    let name: String
    let band: RubricBand

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .frame(width: 72, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<RubricBand.ordered.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= band.step ? AppPalette.primary : Color(.tertiarySystemFill))
                        .frame(height: 8)
                }
            }
            // 색만으로 구분하지 않도록 기호+문구를 함께 둔다.
            Label(band.label, systemImage: band.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryInk)
                // 글씨가 커지면 막대가 줄고 문구는 남는다.
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(band.label)")
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
