import SwiftUI
import SwiftData

/// 플래너 탭 안의 이동 경로. 탭이 이미 갖고 있는 NavigationStack을 그대로 쓴다.
///
/// 날짜는 여기 없다(P10). 하루를 열 때는 화면을 밀어내지 않고 `PlannerDaySheet`를 띄운다 —
/// 날짜를 확인할 때마다 뒤로 가기를 눌러야 했던 것이 플래너에서 가장 지치는 동작이었다.
///
/// 전체 캘린더도 여기 없다(P14.5.2). 플래너 홈이 곧 월간 캘린더라서 밀어낼 곳이 없다 —
/// 미리보기와 진짜 캘린더가 따로 있으면 같은 달을 두 번 그리게 된다.
enum PlannerRoute: Hashable, CaseIterable {
    case settings
    /// 학습 알림(P14.5.2). 오른쪽 위 종이 여는 곳이다.
    case notifications
}

/// 플래너 홈 = 월간 캘린더(P14.5.2).
///
/// 이 탭이 답하는 질문은 하나다: **"나는 언제 무엇을 했고, 언제 무엇을 하기로 했는가."**
/// 그래서 화면의 대부분은 달력이고, 달력 위에는 연속 학습 한 줄, 아래에는 고른 날의
/// 짧은 요약만 둔다. 학습하러 가는 버튼은 없다 — 데일리는 데일리 탭이, 단어는 단어장
/// 탭이 각자 자기 일을 한다. 플래너를 다른 탭으로 보내는 바로가기 허브로 쓰지 않는다.
///
/// 칸에 찍히는 숫자는 전부 **실제로 한 학습**이다. 계획도 예정도 아니고, 화면에서
/// 추정하지도 않는다(`PlannerActivityCalendar`).
struct PlannerHomeView: View {
    let snapshot: StudyCalendarSnapshot
    let settings: StudyPlanSettings
    let targetLevel: OPIcLevel
    let isShowingCachedSettings: Bool
    /// 날짜별 학습 완료 수. 칸의 진하기(히트맵)는 예전 그대로 이 값에서 나온다.
    let completions: [Date: Int]
    /// 날짜별 실제 활동(단어 · 데일리 · 모의). 캘린더 밖에서 한 번만 모아서 받는다.
    let activities: [String: PlannerDayActivity]

    /// 하루 시트를 열어 달라고 알린다. 시트는 플래너 뿌리 한 곳에서만 띄운다.
    let onSelectDate: (String) -> Void

    /// 칸 안의 일정 막대. 기존 개인 일정 모델을 그대로 읽는다(새 일정 모델을 만들지 않는다).
    @Query private var events: [PlannerEventRecord]

    @State private var monthOffset = 0
    /// 캘린더 아래 요약에 쓰는 선택 날짜. 탭 한 번은 요약까지고, 자세히 보기는 시트다 —
    /// 날짜를 볼 때마다 시트가 튀어 오르면 달력을 훑을 수가 없다.
    @State private var selectedLocalDate: String?

    private var calendar: Calendar { settings.calendar }
    private var today: Date { snapshot.today.date }

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
            schedule: snapshot.schedule,
            completions: completions
        )
    }

    /// 1일 앞에 비워 둘 칸 수. 요일 머리글이 일~토이므로 같은 기준(일=0)으로 센다.
    private var leadingBlanks: Int {
        StudyWeekday.from(date: monthStart, calendar: calendar).displayColumn
    }

    /// 날짜별 일정 제목. 칸마다 전체 목록을 훑으면 한 달에 30번 도는 일이 된다.
    private var eventTitlesByDate: [String: [String]] {
        PlannerEventRecord.sorted(events).reduce(into: [:]) { result, event in
            result[event.localDate, default: []].append(event.title)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if isShowingCachedSettings {
                    Text("오프라인이라 저장된 학습 계획을 보여주고 있어요.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                streakHeader
                monthHeader
                monthGrid
                selectedDaySummary
                plannerStateMessage
            }
            .padding(AppSpacing.lg)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: PlannerRoute.notifications) {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("학습 알림")
            }
        }
    }

    private var plan: AdaptiveStudyPlan { snapshot.plan }

    // MARK: 머리

    /// 연속 학습 두 숫자 + 목표/시험 문맥 한 줄. 카드가 아니라 머리글이다 —
    /// 여기가 커지면 캘린더가 밀린다.
    private var streakHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.lg) {
            streakValue(
                title: "현재 연속 학습",
                value: snapshot.streak,
                emphasized: true
            )
            streakValue(
                title: "최고 연속 학습",
                value: snapshot.bestStreak,
                emphasized: false
            )
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text(contextText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .accessibilityLabel(contextText.replacingOccurrences(of: "·", with: ","))
                // 학습 계획(공부 요일·강도·시험일)으로 가는 길. 오른쪽 위 아이콘이 종이 된 뒤
                // 이 줄이 유일한 입구라 작아도 지우지 않는다.
                NavigationLink("학습 계획", value: PlannerRoute.settings)
                    .font(AppTypography.caption)
                    .minimumTouchTarget()
            }
        }
    }

    private func streakValue(title: String, value: Int, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            Text(emphasized ? "🔥 \(value)일" : "\(value)일")
                .font(AppTypography.sectionTitle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)일")
    }

    private var contextText: String {
        var parts = ["목표 \(targetLevel.rawValue)"]
        if let remaining = snapshot.examDaysRemaining {
            parts.append(examDDayText(remaining))
        }
        return parts.joined(separator: " · ")
    }

    private func examDDayText(_ remaining: Int) -> String {
        if remaining > 0 { return "시험 D-\(remaining)" }
        return remaining == 0 ? "시험 당일" : "시험일 지남"
    }

    // MARK: 캘린더

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
        let titles = eventTitlesByDate
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
                    // 같은 날을 다시 누르면 접는다. 요약이 캘린더를 계속 밀고 있지 않게 한다.
                    selectedLocalDate = selectedLocalDate == key ? nil : key
                } label: {
                    StudyDayCell(
                        day: day,
                        calendar: calendar,
                        isToday: day.date == startOfToday,
                        isExamDay: settings.isExamDay(day.date),
                        hasEvent: titles[key]?.isEmpty == false,
                        showsWeekday: false,
                        activity: activities[key] ?? .empty,
                        eventTitles: titles[key] ?? [],
                        isSelected: selectedLocalDate == key
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("하루 요약을 봅니다")
            }
        }
    }

    // MARK: 고른 하루

    /// 캘린더 **아래**의 짧은 요약. 그날 한 학습과 그날의 일정만 말하고,
    /// 더 자세한 것(문제 목록·일정 추가)은 예전부터 있던 하루 시트로 넘긴다.
    @ViewBuilder
    private var selectedDaySummary: some View {
        if let key = selectedLocalDate,
           let date = LocalCalendarDate.date(from: key, timeZone: settings.timeZone) {
            let activity = activities[key] ?? .empty
            let titles = eventTitlesByDate[key] ?? []
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(date.formatted(.dateTime.month().day().weekday()))
                    .font(AppTypography.sectionTitle)
                Text(PlannerActivityCalendar.accessibilityText(activity) ?? "학습 기록이 없어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                if !titles.isEmpty {
                    ForEach(titles.prefix(3), id: \.self) { title in
                        Label(title, systemImage: "calendar")
                            .font(AppTypography.footnote)
                            .lineLimit(1)
                    }
                }
                Button {
                    onSelectDate(key)
                } label: {
                    Label(titles.isEmpty ? "+ 일정 추가" : "자세히 보기", systemImage: "chevron.right")
                        .labelStyle(.titleOnly)
                        .font(AppTypography.callout)
                }
                .minimumTouchTarget()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    // MARK: 계획 상태 안내

    /// 부족한 상태를 감추지 않되 자책하게 만드는 표현은 쓰지 않는다.
    /// 카드가 아니라 한 줄이다 — 캘린더가 주인공인 화면에서 경고가 자리를 차지하지 않는다.
    @ViewBuilder
    private var plannerStateMessage: some View {
        switch plan.mode {
        case .compressed:
            noticeLine("시험일까지 남은 기간을 반영해 학습량을 조정했어요.", isWarning: false)
        case .insufficientTime:
            noticeLine("현재 설정으로는 시험 전 권장 학습량을 모두 완료하기 어려워요.", isWarning: true)
        case .onTrack where plan.finishesAfterExam:
            noticeLine("현재 일정대로면 시험 전에 권장 학습량을 모두 마치기 어려워요.", isWarning: true)
        case .onTrack, .completed:
            EmptyView()
        }
    }

    private func noticeLine(_ text: String, isWarning: Bool) -> some View {
        Text(text)
            .font(AppTypography.footnote)
            .foregroundStyle(isWarning ? AppPalette.dangerInk : AppPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 하루 한 칸. 월간 격자가 쓰는 유일한 칸이다.
///
/// 칸이 말하는 것은 **그날 실제로 한 일**이다: 학습 횟수(진하기), 무엇을 했는지(배지),
/// 그날의 일정(막대). 계획 대비 달성률은 여기서 말하지 않는다 — 하루 시트의 몫이다.
struct StudyDayCell: View {
    let day: StudyDay
    /// 학습 계획 타임존의 달력. 기기 타임존으로 그리면 요일·날짜가 하루 어긋날 수 있다.
    let calendar: Calendar
    var isToday = false
    /// 설정한 OPIc 시험일인지(P12). 학습량 채우기·오늘 테두리와 **별개 채널**이라
    /// 별이 켜져도 히트맵 진하기는 그대로다.
    var isExamDay = false
    /// 개인 일정이 있는지. 제목까지 보여줄 자리가 없을 때를 위한 최소 표시다.
    var hasEvent = false
    /// 월간 격자에는 요일 머리글이 따로 있다. 칸마다 또 쓰면 격자가 시끄러워진다.
    var showsWeekday = true
    /// 그날 실제로 한 학습(P14.5.2). 기본값이 비어 있어 예전 호출부는 그대로 동작한다.
    var activity: PlannerDayActivity = .empty
    /// 그날의 일정 제목. 칸이 좁으므로 최대 두 개만 그리고 나머지는 "+n"으로 접는다.
    var eventTitles: [String] = []
    var isSelected = false

    /// 오늘 테두리는 채우기와 겹치지 않게 한 겹 바깥에 그린다. 글자 크기를 키우면 같이 커진다.
    @ScaledMetric(relativeTo: .footnote) private var fillDiameter: CGFloat = 28

    private var level: LearningActivityLevel {
        LearningActivityLevel.make(completedSets: day.completedSets)
    }

    /// 데일리 핵심 학습을 끝낸 날. 배정이 없던 날(휴식일 자율 학습)도 학습은 학습이다.
    private var dailyCompleted: Bool {
        day.state == .completed || day.hasUnscheduledLearning
    }

    /// 데일리도 오늘의 단어도 다 한 날. 하나만 한 날과 눈으로 구분되어야 해서
    /// 배지가 아니라 칸 자체에 도장을 찍는다.
    private var isFullyComplete: Bool {
        dailyCompleted && activity.isVocabularyComplete
    }

    var body: some View {
        VStack(spacing: 2) {
            if showsWeekday {
                Text(StudyWeekday.from(date: day.date, calendar: calendar).shortLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            activityCircle
            badgeRow
            eventBars
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .top)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(isSelected ? AppPalette.primarySoft : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 날짜 숫자 + 학습량 채우기 + (오늘이면) 바깥 테두리.
    /// 오늘을 채우기로 표시하면 "오늘"과 "많이 학습함"을 구분할 수 없게 된다.
    private var activityCircle: some View {
        ZStack {
            Circle()
                .fill(AppPalette.primary.opacity(level.fillOpacity))
                .frame(width: fillDiameter, height: fillDiameter)
            Text("\(calendar.component(.day, from: day.date))")
                .font(AppTypography.footnote)
                .foregroundStyle(level.needsLightNumber ? Color.white : AppPalette.ink)
            if isToday {
                Circle()
                    .strokeBorder(AppPalette.primary, lineWidth: 2)
                    .frame(width: fillDiameter + 8, height: fillDiameter + 8)
            }
            if isExamDay { examStar }
            if isFullyComplete { completionSeal }
        }
        .frame(width: fillDiameter + 8, height: fillDiameter + 8)
    }

    /// 시험일 별. 칸을 덮지 않게 오른쪽 위 모서리에 작게 얹는다 —
    /// 숫자와 학습량이 먼저 읽히고 별은 그다음이다.
    /// 빨강은 실제 오류에만 쓴다. 시험이 있다는 사실은 오류가 아니다.
    private var examStar: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 9))
            .foregroundStyle(AppPalette.primary)
            .padding(1)
            // 진한 학습량 채우기 위에 겹쳐도 별이 묻히지 않게 카드와 같은 바탕을 깐다.
            .background(.background, in: Circle())
            .frame(
                width: fillDiameter + 8, height: fillDiameter + 8,
                alignment: .topTrailing
            )
            .accessibilityHidden(true)
    }

    /// 데일리 + 오늘의 단어를 둘 다 끝낸 날의 도장. 별과 겹치지 않게 왼쪽 아래에 둔다.
    private var completionSeal: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 9))
            .foregroundStyle(AppPalette.primary)
            .background(.background, in: Circle())
            .frame(
                width: fillDiameter + 8, height: fillDiameter + 8,
                alignment: .bottomLeading
            )
            .accessibilityHidden(true)
    }

    /// 무엇을 했는지. 아이콘 + 숫자 한 쌍씩, 실제로 한 것만 최대 세 개다.
    /// 자리는 비워 두어 칸 높이가 들쭉날쭉해지지 않게 한다.
    private var badgeRow: some View {
        HStack(spacing: 2) {
            ForEach(PlannerActivityCalendar.badges(activity), id: \.label) { badge in
                HStack(spacing: 1) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 7))
                    Text("\(badge.count)")
                        .font(.system(size: 8))
                }
                .foregroundStyle(AppPalette.primary)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    /// 그날의 일정. 제목 한 줄짜리 작은 막대 두 개까지 보여주고 나머지는 "+n"이다.
    private var eventBars: some View {
        VStack(spacing: 1) {
            ForEach(eventTitles.prefix(2), id: \.self) { title in
                Text(title)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.primarySoft, in: RoundedRectangle(cornerRadius: 2))
            }
            if eventTitles.count > 2 {
                Text("+\(eventTitles.count - 2)")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
            // 일정 제목을 그릴 자리가 아예 없을 때(예전 호출부)를 위한 최소 표시.
            if eventTitles.isEmpty && hasEvent {
                Circle()
                    .fill(AppPalette.secondaryInk)
                    .frame(width: 4, height: 4)
            }
        }
        .foregroundStyle(AppPalette.ink)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        StudyDayCell.accessibilityText(
            date: day.date.formatted(.dateTime.month().day()),
            weekday: StudyWeekday.from(date: day.date, calendar: calendar).accessibilityLabel,
            isToday: isToday,
            isExamDay: isExamDay,
            completedSets: day.completedSets,
            hasEvent: hasEvent || !eventTitles.isEmpty,
            activity: activity
        )
    }

    /// 오늘 여부도, 학습량도, 시험일도 모양·색으로만 알리면 안 된다. 한 문장으로 조립해 읽어 준다.
    /// 읽어 주는 것은 실제로 한 일이다 — 색 이름도 단계 번호도 말하지 않는다.
    /// 시험일은 "별표"가 아니라 "OPIc 시험일"로 읽는다. 별은 표현이고 의미가 아니다.
    /// (뷰를 그리지 않고도 확인할 수 있게 순수 함수로 둔다.)
    static func accessibilityText(
        date: String,
        weekday: String,
        isToday: Bool,
        isExamDay: Bool = false,
        completedSets: Int,
        hasEvent: Bool,
        activity: PlannerDayActivity = .empty
    ) -> String {
        let today = isToday ? "오늘, " : ""
        let exam = isExamDay ? "OPIc 시험일, " : ""
        let event = hasEvent ? ", 개인 일정 있음" : ""
        let learning = LearningActivityLevel.accessibilityText(completedSets: completedSets)
        // 배지는 아이콘이라 소리로는 읽히지 않는다. 한 일을 이름 그대로 덧붙인다.
        let detail = PlannerActivityCalendar.accessibilityText(activity).map { ", \($0)" } ?? ""
        return "\(date) \(weekday), \(today)\(exam)\(learning)\(detail)\(event)"
    }
}
