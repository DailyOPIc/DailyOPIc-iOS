import SwiftUI
import SwiftData

struct ProgressScreen: View {
    private enum Period: String, CaseIterable, Identifiable {
        case seven = "최근 7일"
        case thirty = "30일"
        case all = "전체"
        var id: Self { self }
    }
    let preferences: AppPreferences
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeHistoryRecord.createdAt, order: .reverse)
    private var practiceRecords: [PracticeHistoryRecord]
    @Query(sort: \MockHistoryRecord.createdAt, order: .reverse)
    private var mockRecords: [MockHistoryRecord]
    @State private var showsDeleteAll = false
    @State private var period: Period = .seven

    private var cutoff: Date? {
        switch period {
        case .seven: Calendar.current.date(byAdding: .day, value: -7, to: .now)
        case .thirty: Calendar.current.date(byAdding: .day, value: -30, to: .now)
        case .all: nil
        }
    }
    private var visiblePractice: [PracticeHistoryRecord] {
        guard let cutoff else { return practiceRecords }
        return practiceRecords.filter { $0.createdAt >= cutoff }
    }
    private var visibleMock: [MockHistoryRecord] {
        guard let cutoff else { return mockRecords }
        return mockRecords.filter { $0.createdAt >= cutoff }
    }
    private var corruptRecordCount: Int {
        visiblePractice.filter { $0.question == nil || $0.evaluation == nil }.count
            + visibleMock.filter { $0.questionSet == nil || $0.evaluation == nil }.count
    }

    private var latestLevel: OPIcLevel? {
        let practice = visiblePractice.first.map { ($0.createdAt, $0.predictedLevel) }
        let mock = visibleMock.first.map { ($0.createdAt, $0.predictedLevel) }
        return [practice, mock].compactMap { $0 }.max { $0.0 < $1.0 }?.1
    }

    private var distribution: [(OPIcLevel, Int)] {
        let levels = visiblePractice.map(\.predictedLevel) + visibleMock.map(\.predictedLevel)
        return OPIcLevel.allCases.compactMap { level in
            let count = levels.filter { $0 == level }.count
            return count > 0 ? (level, count) : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("통계").font(AppTypography.title)
                    Text("이 기기에 저장된 나의 연습 기록이에요.")
                        .font(AppTypography.callout)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                Picker("통계 기간", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                summary
                if corruptRecordCount > 0 {
                    ErrorBanner(message: "불러올 수 없는 기록 \(corruptRecordCount)개가 있어요.")
                }
                if !distribution.isEmpty { distributionView }
                HStack {
                    VStack(alignment: .leading) {
                        Text("최근 기록").font(.title2.bold())
                        Text("최대 50개 연습 기록")
                            .font(.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    Spacer()
                    if !practiceRecords.isEmpty || !mockRecords.isEmpty {
                        Button("전체 삭제", role: .destructive) { showsDeleteAll = true }
                            .buttonStyle(.bordered)
                    }
                }
                records
                BannerAdView().frame(height: 50)
            }
            .padding(20)
        }
        .confirmationDialog("모든 로컬 기록을 삭제할까요?", isPresented: $showsDeleteAll) {
            Button("전체 삭제", role: .destructive, action: deleteAll)
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            Text("요약")
                .font(.headline)
                .foregroundStyle(AppPalette.primary)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(AppPalette.elevatedSurface)
                .overlay { Capsule().stroke(AppPalette.primary.opacity(0.5)) }
                .offset(y: -22)
            HStack(spacing: 12) {
                summaryCell(title: "총 시도", value: "\(visiblePractice.count + visibleMock.count)회")
                summaryCell(title: "최근 등급", value: latestLevel?.rawValue ?? "-")
            }
            HStack(spacing: 12) {
                summaryCell(title: "연습", value: "\(visiblePractice.count)회")
                summaryCell(title: "모의고사", value: "\(visibleMock.count)회")
            }
        }
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.primary.opacity(0.35), lineWidth: 1.5)
        }
        .padding(.top, 16)
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryInk)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(value == latestLevel?.rawValue ? AppPalette.primary : AppPalette.ink)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .background(value == latestLevel?.rawValue ? AppPalette.primarySoft : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var distributionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("등급 분포").font(.headline)
            ForEach(distribution, id: \.0) { level, count in
                HStack {
                    Text(level.rawValue)
                        .font(.subheadline.bold())
                        .frame(width: 40, alignment: .leading)
                    ProgressView(value: Double(count), total: Double(max(1, visiblePractice.count + visibleMock.count)))
                        .tint(AppPalette.primary)
                    Text("\(count)회")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var records: some View {
        let rows = historyRows
        if rows.isEmpty {
            ContentUnavailableView(
                "아직 기록이 없어요",
                systemImage: "mic.badge.plus",
                description: Text("첫 답변을 녹음하면 결과가 여기에 저장됩니다.")
            )
            .frame(minHeight: 220)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(rows) { row in
                    switch row.kind {
                    case let .practice(record):
                        NavigationLink { PracticeHistoryDetailView(record: record) } label: {
                            HistoryRow(
                                title: record.question?.prompt ?? "연습 답변",
                                subtitle: record.transcript,
                                level: record.predictedLevel,
                                date: record.createdAt,
                                kind: "PRACTICE"
                            )
                        }
                    case let .mock(record):
                        NavigationLink { MockHistoryDetailView(record: record) } label: {
                            HistoryRow(
                                title: "15문항 모의고사",
                                subtitle: record.evaluation?.overallFeedback ?? "종합 평가",
                                level: record.predictedLevel,
                                date: record.createdAt,
                                kind: "MOCK EXAM"
                            )
                        }
                    }
                }
            }
        }
    }

    private var historyRows: [HistoryItem] {
        let practice = visiblePractice.map { HistoryItem(id: $0.id, date: $0.createdAt, kind: .practice($0)) }
        let mock = visibleMock.map { HistoryItem(id: $0.id, date: $0.createdAt, kind: .mock($0)) }
        return (practice + mock).sorted { $0.date > $1.date }
    }

    private func deleteAll() {
        try? modelContext.delete(model: PracticeHistoryRecord.self)
        try? modelContext.delete(model: MockHistoryRecord.self)
        try? modelContext.delete(model: MockDraftRecord.self)
        try? modelContext.save()
    }
}

private struct HistoryItem: Identifiable {
    enum Kind {
        case practice(PracticeHistoryRecord)
        case mock(MockHistoryRecord)
    }
    let id: UUID
    let date: Date
    let kind: Kind
}

private struct HistoryRow: View {
    let title: String
    let subtitle: String
    let level: OPIcLevel
    let date: Date
    let kind: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind)
                    .font(.caption.bold())
                    .foregroundStyle(AppPalette.secondaryInk)
                Spacer()
                Text(level.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppPalette.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(AppPalette.primarySoft)
                    .clipShape(Capsule())
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(AppPalette.ink)
                .lineLimit(2)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryInk)
                .lineLimit(2)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .cardStyle()
    }
}
