import SwiftUI
import SwiftData

/// 캘린더 탭. 설정 전에는 온보딩, 설정 후에는 대시보드.
struct StudyCalendarScreen: View {
    let viewModel: StudyCalendarViewModel
    let preferences: AppPreferences
    /// Daily 탭으로 이동. 캘린더는 학습 화면을 따로 갖지 않는다.
    let onStartDaily: () -> Void

    @Query(sort: \StudySetCompletionRecord.completedAt, order: .reverse)
    private var completionRecords: [StudySetCompletionRecord]
    @Query(sort: \PracticeHistoryRecord.createdAt, order: .reverse)
    private var practiceRecords: [PracticeHistoryRecord]
    @Query private var dayPlanRecords: [StudyDayPlanRecord]
    @State private var isEditingPlan = false
    /// 잠긴 기능을 **직접 눌렀을 때만** Paywall이 열린다. 캘린더 진입이나 일정 부족으로는 열지 않는다.
    @State private var paywallFeature: CalendarLockedFeature?

    /// 그날 배정됐던 학습량. 지난 날짜는 이 값으로만 판정하고 현재 설정으로 다시 계산하지 않는다.
    private var historicalTargets: [String: Int] {
        dayPlanRecords.reduce(into: [:]) { $0[$1.localDate] = $1.targetSets }
    }

    private var completions: [Date: Int] {
        StudyCalendarEngine.completionCounts(
            completedAt: completionRecords.map(\.completedAt),
            calendar: viewModel.settings?.calendar ?? .current
        )
    }

    /// 최근 분석 결과의 예상 등급. 오래된 기록은 현재 실력으로 보지 않는다.
    private var recentLevel: OPIcLevel? {
        guard let latest = practiceRecords.first else { return nil }
        let age = Calendar.current.dateComponents(
            [.day],
            from: latest.createdAt,
            to: .now
        ).day ?? 0
        guard age <= StudyPlanEstimatorConfig.recentLevelMaxAgeDays else { return nil }
        return latest.predictedLevel
    }

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                loadingView
            case let .failed(message):
                failureView(message)
            case .loaded:
                if let snapshot = viewModel.snapshot(
                    completions: completions,
                    recentLevel: recentLevel,
                    historicalTargets: historicalTargets
                ) {
                    StudyCalendarDashboard(
                        snapshot: snapshot,
                        settings: viewModel.settings ?? .draft,
                        targetLevel: viewModel.targetLevel,
                        planName: viewModel.plan.displayName,
                        isShowingCachedSettings: viewModel.isShowingCachedSettings,
                        completions: completions,
                        lockedFeatures: viewModel.lockedFeatures,
                        onStartDaily: onStartDaily,
                        onEditPlan: { isEditingPlan = true },
                        onLockedFeature: { feature in
                            AppTelemetry.calendarFeatureLockedTap(
                                feature: feature,
                                plan: viewModel.plan
                            )
                            paywallFeature = feature
                        }
                    )
                    // 오늘까지의 배정 학습량을 고정해 둔다. 내일 설정을 바꿔도 오늘의 기록은
                    // 그대로 남는다.
                    .onAppear { viewModel.freezeSchedule(snapshot) }
                } else {
                    StudyPlanSetupView(
                        viewModel: viewModel,
                        onFinished: {},
                        onChangeTargetLevel: { preferences.isPresentingLevelSelection = true }
                    )
                }
            }
        }
        .navigationTitle("캘린더")
        .task { await viewModel.loadIfNeeded() }
        .sheet(isPresented: $isEditingPlan) {
            StudyPlanEditView(viewModel: viewModel) {
                isEditingPlan = false
                preferences.isPresentingLevelSelection = true
            }
        }
        .sheet(item: $paywallFeature) { _ in PaywallView(source: .calendarLocked) }
    }

    private var loadingView: some View {
        VStack(spacing: AppSpacing.md) {
            AppLoadingIndicator()
            Text("학습 계획을 불러오고 있어요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 캘린더 요청이 실패해도 다른 탭은 그대로 쓸 수 있다. 여기서만 재시도를 보여준다.
    private func failureView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(AppPalette.secondaryInk)
            Text("학습 계획을 불러오지 못했어요")
                .font(AppTypography.sectionTitle)
            Text(message)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
            Button("다시 시도") { Task { await viewModel.load() } }
                .font(AppTypography.callout)
                .minimumTouchTarget()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StudyCalendarDashboard: View {
    let snapshot: StudyCalendarSnapshot
    let settings: StudyPlanSettings
    let targetLevel: OPIcLevel
    let planName: String
    let isShowingCachedSettings: Bool
    let completions: [Date: Int]
    /// 아직 잠긴 자동화 기능. 비어 있으면 잠금 영역 자체를 그리지 않는다.
    var lockedFeatures: [CalendarLockedFeature] = []
    let onStartDaily: () -> Void
    let onEditPlan: () -> Void
    var onLockedFeature: (CalendarLockedFeature) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if isShowingCachedSettings {
                    Text("오프라인이라 저장된 학습 계획을 보여주고 있어요.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                goalCard
                weekStrip
                todayCard
                weekSummaryCard
                lockedFeatureCard
                StudyMonthView(
                    settings: settings,
                    schedule: snapshot.schedule,
                    completions: completions
                )
            }
            .padding(AppSpacing.lg)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("학습 설정 수정", systemImage: "slider.horizontal.3", action: onEditPlan)
                    .accessibilityLabel("학습 설정 수정")
            }
        }
    }

    // MARK: 목표 요약

    private var plan: AdaptiveStudyPlan { snapshot.plan }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("\(targetLevel.rawValue) 학습 플랜")
                .font(AppTypography.cardTitle)
            if plan.mode == .completed {
                Text("권장 학습 계획을 완료했어요.")
                    .font(AppTypography.body)
            } else {
                Text("남은 권장 학습 \(plan.remainingSets)세트")
                    .font(AppTypography.body)
                if let completion = plan.estimatedCompletionDate {
                    Text("\(completion.formatted(.dateTime.month().day())) 완료 예상 · 약 \(plan.estimatedStudyDays)일")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            if let remaining = snapshot.examDaysRemaining {
                // 시험일과 권장 계획 완료일은 다른 값이다. 나란히 두되 섞지 않는다.
                Text(examDDayText(remaining))
                    .font(AppTypography.caption)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppPalette.primarySoft)
                    .clipShape(Capsule())
            }
            plannerStateMessage
            Text(StudyPlanEstimator.disclaimer)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .cardStyle()
    }

    /// 계획 상태 안내. 부족한 상태를 감추지 않되 자책하게 만드는 표현은 쓰지 않는다.
    @ViewBuilder
    private var plannerStateMessage: some View {
        switch plan.mode {
        case .compressed:
            Text("시험일까지 남은 기간을 반영해 학습량을 조정했어요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        case .insufficientTime:
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("현재 설정으로는 시험 전 권장 학습량을 모두 완료하기 어려워요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.dangerInk)
                if let possible = plan.maximumSetsPossibleBeforeExam {
                    Text("남은 권장 학습 \(plan.remainingSets)세트 · 현재 일정에서 시험 전 최대 \(possible)세트 가능")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                // G3가 제안하는 행동은 설정 수정뿐이다. 플랜 업그레이드를 권하지 않는다(G4).
                Button("학습 설정 수정", action: onEditPlan)
                    .font(AppTypography.callout)
                    .minimumTouchTarget()
            }
        case .onTrack where plan.finishesAfterExam:
            // 시험일 역산이 잠겨 있어도 위험은 그대로 알린다. 대신 여기서 결제를 권하지 않는다.
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("현재 일정대로면 시험 전에 권장 학습량을 모두 마치기 어려워요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.dangerInk)
                Button("학습 설정 수정", action: onEditPlan)
                    .font(AppTypography.callout)
                    .minimumTouchTarget()
            }
        case .onTrack, .completed:
            EmptyView()
        }
    }

    private func examDDayText(_ remaining: Int) -> String {
        if remaining > 0 { return "시험 D-\(remaining)" }
        return remaining == 0 ? "시험 당일" : "시험일 지남"
    }

    // MARK: 주간 스트립

    private var weekStrip: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(snapshot.weekDays) { day in
                StudyDayCell(
                    day: day,
                    calendar: settings.calendar,
                    isToday: day.date == snapshot.today.date
                )
            }
        }
    }

    // MARK: 오늘

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("오늘의 학습")
                .font(AppTypography.sectionTitle)
            if plan.mode == .completed {
                Text("권장 학습 계획을 완료했어요. 원하면 계속 연습해도 좋아요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else if snapshot.today.state == .rest {
                Text("오늘은 휴식일이에요. 원하면 그냥 연습해도 좋아요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                // 오늘 배정량은 압축 모드에서 달라진다. 고정된 기본 학습량이 아니다.
                Text("Daily 연습 \(snapshot.today.completedSets) / \(snapshot.today.targetSets) 완료")
                    .font(AppTypography.body)
                if plan.isCappedByPlan {
                    Text("오늘 권장 \(snapshot.today.targetSets)세트 · 현재 \(planName) 플랜 최대 \(plan.dailyCapacity)토큰")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            if snapshot.extraToday > 0 {
                // 자동 재조정이 없는 플랜에는 "남은 일정에 반영했어요"라고 말하지 않는다.
                // 추가 학습이 남은 학습량을 줄이는 것은 두 플랜 모두 사실이다.
                Text(
                    plan.policy.canAutoReplan
                    ? "오늘 계획보다 \(snapshot.extraToday)세트 더 학습했어요. 남은 일정에 반영했어요."
                    : "오늘 계획보다 \(snapshot.extraToday)세트 더 학습했어요."
                )
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            if plan.mode == .completed {
                Label("권장 학습 계획 완료", systemImage: "checkmark.seal.fill")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.primary)
            } else if snapshot.today.state == .completed {
                Label("오늘 계획 완료", systemImage: "checkmark.circle.fill")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.primary)
            } else {
                PrimaryButton(title: "Daily 연습 시작", systemImage: "mic.fill", action: onStartDaily)
            }
        }
        .cardStyle()
    }

    // MARK: 주간 요약

    private var weekSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("이번 주")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                Text("\(snapshot.weekCompletedDays) / \(snapshot.weekScheduledDays)일 완료")
                    .font(AppTypography.sectionTitle)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text("연속 학습")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                Text("🔥 \(snapshot.streak)일")
                    .font(AppTypography.sectionTitle)
                    .accessibilityLabel("연속 학습 \(snapshot.streak)일")
            }
        }
        .cardStyle()
    }

    // MARK: 잠긴 자동화 기능

    /// 한 칸에 모아 둔다. 월간 보기와 오늘 할 일을 잠금 배지로 어지럽히지 않는다.
    /// 여기를 **직접 누를 때만** Paywall이 열린다.
    @ViewBuilder
    private var lockedFeatureCard: some View {
        if !lockedFeatures.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("학습 플랜 기능")
                    .font(AppTypography.sectionTitle)
                ForEach(lockedFeatures, id: \.rawValue) { feature in
                    Button { onLockedFeature(feature) } label: {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Image(systemName: "lock.fill")
                                .font(AppTypography.callout)
                                .foregroundStyle(AppPalette.secondaryInk)
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(feature.title)
                                    .font(AppTypography.callout)
                                Text(feature.detail)
                                    .font(AppTypography.footnote)
                                    .foregroundStyle(AppPalette.secondaryInk)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Text(feature.requirementText)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppPalette.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .minimumTouchTarget()
                    .accessibilityLabel(feature.accessibilityLabel)
                    .accessibilityHint(feature.detail)
                }
            }
            .cardStyle()
        }
    }
}

/// 하루 한 칸. 색만으로 상태를 구분하지 않도록 기호를 함께 그린다.
struct StudyDayCell: View {
    let day: StudyDay
    /// 학습 계획 타임존의 달력. 기기 타임존으로 그리면 요일·날짜가 하루 어긋날 수 있다.
    let calendar: Calendar
    var isToday = false

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(StudyWeekday.from(date: day.date, calendar: calendar).shortLabel)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            Image(systemName: day.state.symbolName)
                .font(.system(size: 16))
                .foregroundStyle(tint)
            Text("\(calendar.component(.day, from: day.date))")
                .font(AppTypography.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm)
        .background(isToday ? AppPalette.primarySoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(day.date.formatted(.dateTime.month().day())) "
            + "\(StudyWeekday.from(date: day.date, calendar: calendar).accessibilityLabel), "
            + day.state.title
            + (day.isScheduled ? ", \(day.completedSets) / \(day.targetSets) 세트" : "")
        )
    }

    private var tint: Color {
        switch day.state {
        case .completed: AppPalette.primary
        case .partial: AppPalette.primaryMid
        case .missed: AppPalette.danger
        case .planned, .rest: AppPalette.secondaryInk
        }
    }
}

/// 월간 보기. 오늘 할 일보다 아래에 두는 보조 화면이라 기본 SwiftUI 격자로 충분하다.
struct StudyMonthView: View {
    let settings: StudyPlanSettings
    let schedule: StudySchedule
    let completions: [Date: Int]

    @State private var monthOffset = 0

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

    /// 1일 앞에 비워 둘 칸 수(월요일 시작).
    private var leadingBlanks: Int {
        StudyWeekday.from(date: monthStart, calendar: calendar).rawValue - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xs), count: 7), spacing: AppSpacing.sm) {
                ForEach(StudyWeekday.allCases) { weekday in
                    Text(weekday.shortLabel)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(days) { day in
                    StudyDayCell(
                        day: day,
                        calendar: calendar,
                        isToday: calendar.isDateInToday(day.date)
                    )
                }
            }
            legend
        }
        .cardStyle()
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
