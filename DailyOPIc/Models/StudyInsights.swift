import Foundation

/// 로컬 학습 기록에서 계산한 스마트 인사이트(신규 AI 호출 없음).
/// 전 플랜 무료라 플랜 게이트가 없다.
struct StudyInsights {
    struct TrendPoint {
        let date: Date
        let level: OPIcLevel
        var ordinal: Int { OPIcLevel.allCases.firstIndex(of: level) ?? 0 }
    }

    /// 영역별 요약. 숫자 점수를 밖으로 내보내지 않는다 — 원본이 밴드를 되돌린
    /// 이산값(20/40/60/80/95)이라 평균의 소수점에는 근거가 없다.
    struct DimensionSummary {
        let name: String
        let band: RubricBand
    }

    struct WeeklyReport {
        let attempts: Int
        let averageLevel: OPIcLevel?
        let weakestDimension: String?
    }

    let trend: [TrendPoint]
    /// 약한 영역부터 정렬. 무엇부터 손볼지가 이 카드의 유일한 쓸모다.
    let dimensions: [DimensionSummary]?
    let weeklyReport: WeeklyReport?

    /// 기록 입력(날짜/예상등급/영역 점수)에서 인사이트를 계산.
    static func build(from entries: [(date: Date, level: OPIcLevel, scores: EvaluationScores?)]) -> StudyInsights {
        let sorted = entries.sorted { $0.date < $1.date }
        let trend = sorted.map { TrendPoint(date: $0.date, level: $0.level) }

        // 영역별 요약(과제/문법/어휘/담화/유창성). 평균은 정렬·밴드 환산에만 쓰고
        // 밖으로는 밴드만 내보낸다.
        let scored = entries.compactMap { $0.scores }
        let dimensions = Self.summarize(scored)

        // 최근 7일 주간 리포트.
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        let weekly = weekAgo.map { cutoff in entries.filter { $0.date >= cutoff } } ?? entries
        var weeklyReport: WeeklyReport? = nil
        if !weekly.isEmpty {
            let levels = weekly.map { Double(OPIcLevel.allCases.firstIndex(of: $0.level) ?? 0) }
            let avgOrdinal = Int((levels.reduce(0, +) / Double(levels.count)).rounded())
            let averageLevel = OPIcLevel.allCases.indices.contains(avgOrdinal)
                ? OPIcLevel.allCases[avgOrdinal] : nil
            weeklyReport = WeeklyReport(
                attempts: weekly.count,
                averageLevel: averageLevel,
                // 가장 약한 영역 = 같은 정렬의 첫 항목.
                weakestDimension: Self.summarize(weekly.compactMap { $0.scores })?.first?.name
            )
        }

        return StudyInsights(
            trend: trend,
            dimensions: dimensions,
            weeklyReport: weeklyReport
        )
    }

    private static let dimensionKeys: [(name: String, score: (EvaluationScores) -> Int)] = [
        ("과제 충족", \.taskFulfillment), ("문법", \.grammar), ("어휘", \.vocabulary),
        ("담화 구성", \.discourse), ("유창성", \.fluency),
    ]

    /// 영역별 평균을 밴드로 환산하고 약한 순서로 정렬한다.
    private static func summarize(_ scores: [EvaluationScores]) -> [DimensionSummary]? {
        guard !scores.isEmpty else { return nil }
        return dimensionKeys
            .map { key in
                let total = scores.reduce(0) { $0 + key.score($1) }
                let average = Int((Double(total) / Double(scores.count)).rounded())
                return (name: key.name, average: average)
            }
            .sorted { $0.average < $1.average }
            .map { DimensionSummary(name: $0.name, band: .nearest(toScore: $0.average)) }
    }
}
