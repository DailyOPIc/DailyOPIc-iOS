import SwiftUI
import SwiftData

/// 플래너 탭의 뿌리. 설정 전에는 온보딩, 설정 후에는 월간 캘린더(플래너 홈)다.
/// 학습 계획 설정과 학습 알림만 여기서 밀어낸다 — 캘린더는 밀어낼 곳이 없다(P14.5.2).
struct StudyCalendarScreen: View {
    let viewModel: StudyCalendarViewModel
    let preferences: AppPreferences
    /// 하루 시트의 개인 일정 저장소. 화면이 SwiftData를 직접 만지지 않게 서비스로 받는다.
    let persistence: PersistenceService

    @Query(sort: \StudySetCompletionRecord.completedAt, order: .reverse)
    private var completionRecords: [StudySetCompletionRecord]
    @Query(sort: \PracticeHistoryRecord.createdAt, order: .reverse)
    private var practiceRecords: [PracticeHistoryRecord]
    @Query private var dayPlanRecords: [StudyDayPlanRecord]
    /// 날짜별 활동의 재료 셋. 서로 다른 기록이라 각자 읽어서 한 번에 합친다(P14.5.2).
    @Query private var activityRecords: [StudyActivityDailyRecord]
    @Query private var learnedQuestionRecords: [PlannerLearnedQuestionRecord]
    @Query private var mockRecords: [MockHistoryRecord]

    /// 지금 열려 있는 하루. 주간 스트립과 전체 캘린더가 **같은** 이 값 하나를 바꾸고,
    /// 시트도 여기 한 곳에서만 뜬다 — 화면마다 시트를 달면 언젠가 두 개가 겹친다.
    @State private var selectedDate: PlannerSelectedDate?

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

    /// 최근 분석 결과의 예상 등급. 판정 규칙은 알림 예약과 공유한다.
    private var recentLevel: OPIcLevel? {
        StudyCalendarViewModel.recentLevel(from: practiceRecords.first)
    }

    /// 캘린더 칸이 읽을 "실제로 한 학습". 단어는 날짜별 기록에서, 데일리는 분석이
    /// 끝난 문제 하나하나에서, 모의고사는 채점까지 끝난 응시에서 온다 —
    /// 어느 것도 화면에서 다시 세거나 추정하지 않는다.
    private var activities: [String: PlannerDayActivity] {
        PlannerActivityCalendar.activities(
            vocabulary: activityRecords,
            dailyAnsweredAt: learnedQuestionRecords.map(\.learnedAt),
            mockCompletedAt: mockRecords.map(\.createdAt),
            timeZone: viewModel.settings?.timeZone ?? .current
        )
    }

    private var snapshot: StudyCalendarSnapshot? {
        viewModel.snapshot(
            completions: completions,
            recentLevel: recentLevel,
            historicalTargets: historicalTargets
        )
    }

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                loadingView
            case let .failed(message):
                failureView(message)
            case .loaded:
                if let snapshot {
                    PlannerHomeView(
                        snapshot: snapshot,
                        settings: viewModel.settings ?? .draft,
                        targetLevel: viewModel.targetLevel,
                        isShowingCachedSettings: viewModel.isShowingCachedSettings,
                        completions: completions,
                        activities: activities,
                        onSelectDate: { selectedDate = PlannerSelectedDate($0) }
                    )
                    // 오늘까지의 배정 학습량을 고정해 둔다. 내일 설정을 바꿔도 오늘의 기록은
                    // 그대로 남는다.
                    .onAppear {
                        viewModel.freezeSchedule(snapshot)
                        // 알림 예약은 플래너를 새로 그릴 때 맞춘다. 이걸 위해 새 API를 부르지 않는다.
                        Task { await viewModel.reconcileReminders() }
                    }
                } else {
                    StudyPlanSetupView(
                        viewModel: viewModel,
                        onFinished: {},
                        onChangeTargetLevel: { preferences.isPresentingLevelSelection = true }
                    )
                }
            }
        }
        .navigationTitle("플래너")
        // 플래너 뿌리에 붙인 시트 하나. 전체 캘린더로 밀고 들어간 상태에서도 같은 시트가 뜨고,
        // 내리면 사용자는 보던 달·보던 자리에 그대로 남는다.
        .sheet(item: $selectedDate) { selection in
            daySheet(selection.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(for: PlannerRoute.self) { route in
            switch route {
            case .settings:
                PlannerSettingsView(viewModel: viewModel) {
                    preferences.isPresentingLevelSelection = true
                }
            case .notifications:
                PlannerNotificationSettingsView(viewModel: viewModel)
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    /// 하루 시트. 학습 상태는 격자와 **같은** 계산에서 뽑는다(두 번째 계산 경로를 만들지 않는다).
    @ViewBuilder
    private func daySheet(_ localDate: String) -> some View {
        if let snapshot,
           let settings = viewModel.settings,
           let date = LocalCalendarDate.date(from: localDate, timeZone: settings.timeZone) {
            PlannerDaySheet(
                localDate: localDate,
                day: StudyCalendarEngine.day(
                    date: date,
                    today: snapshot.today.date,
                    settings: settings,
                    schedule: snapshot.schedule,
                    completions: completions
                ),
                isStudyWeekday: settings.isStudyDay(date),
                isToday: settings.calendar.startOfDay(for: date) == snapshot.today.date,
                isExamDay: settings.isExamDay(date),
                calendar: settings.calendar,
                persistence: persistence,
                reminders: viewModel.studyReminders,
                canUseEventReminder: viewModel.canUseEventReminder,
                onPlannerEventsChanged: {
                    // 일정이 바뀌면 예약도 바뀐다. 저장/삭제 자리에서 직접 예약하지 않고
                    // 언제나 같은 재조정 한 곳을 다시 돌린다.
                    Task { await viewModel.reconcileEventReminders() }
                }
            )
        }
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

    /// 플래너 요청이 실패해도 다른 탭은 그대로 쓸 수 있다. 여기서만 재시도를 보여준다.
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
