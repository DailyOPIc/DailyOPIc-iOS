import Foundation

/// 취약 유형 분석 노출 수준.
enum WeaknessTier {
    case none
    case basic
    case advanced
}

extension PlanEntitlement {
    var weaknessTier: WeaknessTier {
        switch self {
        case .free, .basic: .none
        case .plus: .basic
        case .pro: .advanced
        }
    }
}

/// 로컬 학습 기록에서 계산한 스마트 인사이트(신규 AI 호출 없음).
struct StudyInsights {
    struct TrendPoint {
        let date: Date
        let level: OPIcLevel
        var ordinal: Int { OPIcLevel.allCases.firstIndex(of: level) ?? 0 }
    }

    struct DimensionAverage {
        let name: String
        let score: Int
    }

    struct WeeklyReport {
        let attempts: Int
        let averageLevel: OPIcLevel?
        let weakestDimension: String?
    }

    let trend: [TrendPoint]
    let dimensionAverages: [DimensionAverage]?
    let weeklyReport: WeeklyReport?

    /// 기록 입력(날짜/예상등급/영역 점수)에서 인사이트를 계산.
    static func build(from entries: [(date: Date, level: OPIcLevel, scores: EvaluationScores?)]) -> StudyInsights {
        let sorted = entries.sorted { $0.date < $1.date }
        let trend = sorted.map { TrendPoint(date: $0.date, level: $0.level) }

        // 영역별 평균(과제/문법/어휘/담화/유창성).
        let scored = entries.compactMap { $0.scores }
        var dimensionAverages: [DimensionAverage]? = nil
        if !scored.isEmpty {
            func avg(_ keyPath: (EvaluationScores) -> Int) -> Int {
                let total = scored.reduce(0) { $0 + keyPath($1) }
                return Int((Double(total) / Double(scored.count)).rounded())
            }
            dimensionAverages = [
                DimensionAverage(name: "과제 충족", score: avg(\.taskFulfillment)),
                DimensionAverage(name: "문법", score: avg(\.grammar)),
                DimensionAverage(name: "어휘", score: avg(\.vocabulary)),
                DimensionAverage(name: "담화 구성", score: avg(\.discourse)),
                DimensionAverage(name: "유창성", score: avg(\.fluency)),
            ]
        }

        // 최근 7일 주간 리포트.
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        let weekly = weekAgo.map { cutoff in entries.filter { $0.date >= cutoff } } ?? entries
        var weeklyReport: WeeklyReport? = nil
        if !weekly.isEmpty {
            let levels = weekly.map { Double(OPIcLevel.allCases.firstIndex(of: $0.level) ?? 0) }
            let avgOrdinal = Int((levels.reduce(0, +) / Double(levels.count)).rounded())
            let averageLevel = OPIcLevel.allCases.indices.contains(avgOrdinal)
                ? OPIcLevel.allCases[avgOrdinal] : nil
            let weekScores = weekly.compactMap { $0.scores }
            var weakest: String? = nil
            if !weekScores.isEmpty {
                let dims: [(String, (EvaluationScores) -> Int)] = [
                    ("과제 충족", \.taskFulfillment), ("문법", \.grammar), ("어휘", \.vocabulary),
                    ("담화 구성", \.discourse), ("유창성", \.fluency),
                ]
                weakest = dims.min { lhs, rhs in
                    let l = weekScores.reduce(0) { $0 + lhs.1($1) }
                    let r = weekScores.reduce(0) { $0 + rhs.1($1) }
                    return l < r
                }?.0
            }
            weeklyReport = WeeklyReport(
                attempts: weekly.count,
                averageLevel: averageLevel,
                weakestDimension: weakest
            )
        }

        return StudyInsights(
            trend: trend,
            dimensionAverages: dimensionAverages,
            weeklyReport: weeklyReport
        )
    }
}
