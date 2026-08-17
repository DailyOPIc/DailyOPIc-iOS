import SwiftUI
import SwiftData

/// 전체 캘린더. 플래너 홈에서 밀어낸 월간 격자가 사는 곳이다.
/// 날짜를 누르면 하루 상세(`PlannerDayDetailView`)로 간다.
struct PlannerFullCalendarView: View {
    let settings: StudyPlanSettings
    let schedule: StudySchedule
    let completions: [Date: Int]

    /// 개인 일정·메모가 있는 날에만 작은 표시를 얹는다. 격자를 시끄럽게 만들지 않는다.
    @Query private var events: [PlannerEventRecord]
    @Query private var notes: [PlannerDayNoteRecord]

    @State private var monthOffset = 0

    private var eventDates: Set<String> { Set(events.map(\.localDate)) }
    private var noteDates: Set<String> { Set(notes.map(\.localDate)) }

    private var calendar: Calendar { settings.calendar }

    private var monthStart: Date {
        let today = calendar.startOfDay(for: .now)
        let components = calendar.dateComponents([.year, .month], from: today)
        let firstOfThisMonth = calendar.date(from: components) ?? today
        return calendar.date(byAdding: .month, value: monthOffset, to: firstOfThisMonth)
            ?? firstOfThisMonth
    }

    private var days: [StudyDay] {
        StudyCalendarEngine.days(
            from: monthStart,
            count: calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30,
            today: .now,
            settings: settings,
            schedule: schedule,
            completions: completions
        )
    }

    /// 1일 앞에 비워 둘 칸 수. 요일 머리글이 일~토이므로 같은 기준(일=0)으로 센다.
    private var leadingBlanks: Int {
        StudyWeekday.from(date: monthStart, calendar: calendar).displayColumn
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                monthHeader
                monthGrid
                monthSummary
                legend
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("전체 캘린더")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthHeader: some View {
        HStack {
            Text(monthStart.formatted(.dateTime.year().month()))
                .font(AppTypography.sectionTitle)
            Spacer(minLength: 0)
            Button("이전 달", systemImage: "chevron.left") { monthOffset -= 1 }
                .labelStyle(.iconOnly)
                .minimumTouchTarget()
            Button("다음 달", systemImage: "chevron.right") { monthOffset += 1 }
                .labelStyle(.iconOnly)
                .minimumTouchTarget()
        }
    }

    private var monthGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xs), count: 7),
            spacing: AppSpacing.sm
        ) {
            // 머리글은 일~토. 각 칸이 스스로 요일을 읽어 주므로 머리글은 VoiceOver에서 숨긴다.
            ForEach(StudyWeekday.displayOrder) { weekday in
                Text(weekday.shortLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .accessibilityHidden(true)
            }
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 1)
            }
            ForEach(days) { day in
                let key = LocalCalendarDate.text(from: day.date, timeZone: settings.timeZone)
                NavigationLink(value: PlannerRoute.dayDetail(key)) {
                    StudyDayCell(
                        day: day,
                        calendar: calendar,
                        isToday: calendar.isDateInToday(day.date),
                        hasEvent: eventDates.contains(key),
                        hasNote: noteDates.contains(key)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("하루 상세를 봅니다")
            }
        }
    }

    /// 이 달의 요약 한 줄. 홈의 주간 요약과 겹치지 않게 달 단위 숫자만 말한다.
    private var monthSummary: some View {
        let summary = StudyCalendarEngine.weekSummary(days: days)
        return Text("이번 달 학습일 \(summary.completed) / \(summary.scheduled)일 완료")
            .font(AppTypography.footnote)
            .foregroundStyle(AppPalette.secondaryInk)
    }

    private var legend: some View {
        // 색약 사용자를 위해 기호와 문구를 함께 설명한다.
        HStack(spacing: AppSpacing.md) {
            ForEach(StudyDayState.allCases, id: \.rawValue) { state in
                Label(state.title, systemImage: state.symbolName)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
