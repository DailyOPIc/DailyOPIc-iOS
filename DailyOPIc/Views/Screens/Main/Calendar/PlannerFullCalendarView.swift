import SwiftUI
import SwiftData

/// 전체 캘린더. 플래너 홈에서 밀어낸 월간 격자가 사는 곳이다.
/// 날짜를 누르면 홈의 주간 스트립과 **같은** 하루 시트가 열린다 — 여기서도 화면을 밀어내지 않는다.
struct PlannerFullCalendarView: View {
    let settings: StudyPlanSettings
    let schedule: StudySchedule
    let completions: [Date: Int]
    /// 학습 계획 타임존 기준의 오늘. 기기 시계로 다시 구하면 여행 중에 다른 칸이 오늘이 된다.
    let today: Date

    /// 날짜를 누르면 알려만 준다. 시트는 플래너 뿌리 한 곳에서만 띄운다.
    let onSelectDate: (String) -> Void

    /// 개인 일정이 있는 날에만 작은 표시를 얹는다. 격자를 시끄럽게 만들지 않는다.
    @Query private var events: [PlannerEventRecord]

    @State private var monthOffset = 0

    private var calendar: Calendar { settings.calendar }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: today)
        let firstOfThisMonth = calendar.date(from: components) ?? today
        return calendar.date(byAdding: .month, value: monthOffset, to: firstOfThisMonth)
            ?? firstOfThisMonth
    }

    private var days: [StudyDay] {
        StudyCalendarEngine.days(
            from: monthStart,
            count: calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30,
            today: today,
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
        // 날짜 칸마다 다시 만들면 한 달에 30번 도는 일이다. 격자를 그리기 전에 한 번만 만든다.
        let eventDates = Set(events.map(\.localDate))
        let startOfToday = calendar.startOfDay(for: today)
        return LazyVGrid(
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
                Button {
                    onSelectDate(key)
                } label: {
                    StudyDayCell(
                        day: day,
                        calendar: calendar,
                        isToday: day.date == startOfToday,
                        hasEvent: eventDates.contains(key),
                        showsWeekday: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("하루 정보를 봅니다")
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

    /// 여섯 줄짜리 범례 대신 한 줄. 칸이 말하는 것이 하나뿐이라 설명도 하나면 된다.
    private var legend: some View {
        Text("학습 횟수가 많을수록 날짜가 진하게 표시돼요.")
            .font(AppTypography.caption)
            .foregroundStyle(AppPalette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
