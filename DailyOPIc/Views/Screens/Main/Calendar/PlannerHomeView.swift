import SwiftUI
import SwiftData

/// 플래너 탭 안의 이동 경로. 탭이 이미 갖고 있는 NavigationStack을 그대로 쓴다.
enum PlannerRoute: Hashable {
    case fullCalendar
    /// 하루 상세. 값은 "yyyy-MM-dd"다 — Date로 실으면 기기 타임존이 바뀔 때 다른 날이 열린다.
    case dayDetail(String)
    case settings

    /// 하루 상세로 가는 유일한 경로 생성기. 주간 스트립과 전체 캘린더가 같은 함수를 써야
    /// 같은 날짜에서 같은 화면이 열린다(키를 각자 만들면 언젠가 하루가 어긋난다).
    static func dayDetail(for date: Date, timeZone: TimeZone) -> PlannerRoute {
        .dayDetail(LocalCalendarDate.text(from: date, timeZone: timeZone))
    }
}

/// 플래너 홈. 첫 화면에서 "오늘 뭘 해야 하지?"에 답하는 것이 이 화면의 전부다.
/// 월간 격자·설정·알림·잠긴 기능은 여기 두지 않고 각자의 화면으로 보낸다.
struct PlannerHomeView: View {
    let snapshot: StudyCalendarSnapshot
    let settings: StudyPlanSettings
    let targetLevel: OPIcLevel
    let planName: String
    let isShowingCachedSettings: Bool
    /// 데일리 탭으로 이동. 플래너는 학습 화면을 따로 갖지 않는다.
    let onStartDaily: () -> Void

    /// 주간 스트립의 작은 표시용. 전체 캘린더와 같은 날에 같은 표시가 뜨게 한다.
    @Query private var events: [PlannerEventRecord]
    @Query private var notes: [PlannerDayNoteRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if isShowingCachedSettings {
                    Text("오프라인이라 저장된 학습 계획을 보여주고 있어요.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                contextLine
                // 오늘의 팁은 학습 CTA보다 위에 있지만 주인공은 아니다. 앱에 담긴 고정
                // 문구라 네트워크·플랜·토큰과 아무 관계가 없다.
                OPIcTipCard(
                    tip: OPIcTipCatalog.tip(for: snapshot.today.date, timeZone: settings.timeZone)
                )
                todayCard
                weekCard
                plannerStateMessage
                fullCalendarLink
                Text(StudyPlanEstimator.disclaimer)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(AppSpacing.lg)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: PlannerRoute.settings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("플래너 설정")
            }
        }
    }

    private var plan: AdaptiveStudyPlan { snapshot.plan }

    // MARK: 헤더 문맥

    /// "목표 IH · 시험 D-24". 시험일이 없으면 목표만 말하고 지어내지 않는다.
    private var contextLine: some View {
        Text(contextText)
            .font(AppTypography.callout)
            .foregroundStyle(AppPalette.secondaryInk)
            .accessibilityLabel(contextText.replacingOccurrences(of: "·", with: ","))
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

    // MARK: 오늘

    /// 첫 화면의 주인공. 상태별로 할 말이 없으면 가짜 할 일을 만들지 않는다.
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("오늘의 학습")
                .font(AppTypography.sectionTitle)
            if plan.mode == .completed {
                Text("계획한 학습을 모두 완료했어요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                Label("권장 학습 계획 완료", systemImage: "checkmark.seal.fill")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.primary)
            } else if snapshot.today.state == .rest {
                Text("오늘은 쉬는 날이에요. 원하면 그냥 연습해도 좋아요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                // 권하지는 않되 길은 열어 둔다. 주 버튼으로 만들면 쉬는 날이 아니게 된다.
                Button("그래도 연습하기", action: onStartDaily)
                    .font(AppTypography.callout)
                    .minimumTouchTarget()
            } else {
                // 오늘 배정량은 압축 모드에서 달라진다. 고정된 기본 학습량이 아니다.
                Text("\(snapshot.today.completedSets) / \(snapshot.today.targetSets)세트")
                    .font(AppTypography.title)
                    .accessibilityLabel(
                        "오늘 \(snapshot.today.targetSets)세트 중 \(snapshot.today.completedSets)세트 완료"
                    )
                if plan.isCappedByPlan {
                    Text("오늘 권장 \(snapshot.today.targetSets)세트 · 현재 \(planName) 플랜 최대 \(plan.dailyCapacity)토큰")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                if snapshot.extraToday > 0 {
                    // 자동 재조정이 없는 플랜에는 "남은 일정에 반영했어요"라고 말하지 않는다.
                    Text(
                        plan.policy.canAutoReplan
                        ? "오늘 계획보다 \(snapshot.extraToday)세트 더 학습했어요. 남은 일정에 반영했어요."
                        : "오늘 계획보다 \(snapshot.extraToday)세트 더 학습했어요."
                    )
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                }
                if snapshot.today.state == .completed {
                    Label("오늘 학습 완료", systemImage: "checkmark.circle.fill")
                        .font(AppTypography.callout)
                        .foregroundStyle(AppPalette.primary)
                } else {
                    PrimaryButton(
                        title: snapshot.today.completedSets > 0 ? "학습 이어하기" : "학습 시작하기",
                        systemImage: "mic.fill",
                        action: onStartDaily
                    )
                }
            }
        }
        .cardStyle()
    }

    // MARK: 이번 주

    /// 주간 스트립과 주간 요약은 같은 7일을 말한다. 카드를 둘로 나누면 같은 이야기가
    /// 두 번 쌓이므로 한 칸에 담는다.
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            weekStrip
            weekSummary
        }
        .cardStyle()
    }

    /// 일요일부터 시작하는 7칸. 두 번째 월간 캘린더가 되지 않도록 상태 기호만 얹고,
    /// 누르면 전체 캘린더와 **같은** 하루 상세로 간다.
    private var weekStrip: some View {
        let eventDates = Set(events.map(\.localDate))
        let noteDates = Set(notes.map(\.localDate))
        return HStack(spacing: AppSpacing.xs) {
            ForEach(snapshot.weekDays) { day in
                let key = LocalCalendarDate.text(from: day.date, timeZone: settings.timeZone)
                NavigationLink(value: PlannerRoute.dayDetail(for: day.date, timeZone: settings.timeZone)) {
                    StudyDayCell(
                        day: day,
                        calendar: settings.calendar,
                        isToday: day.date == snapshot.today.date,
                        hasEvent: eventDates.contains(key),
                        hasNote: noteDates.contains(key)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("하루 상세를 봅니다")
            }
        }
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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
            if plan.mode != .completed {
                Text(remainingText)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .cardStyle()
    }

    private var remainingText: String {
        let remaining = "남은 권장 학습 \(plan.remainingSets)세트"
        guard let completion = plan.estimatedCompletionDate else { return remaining }
        return remaining
            + " · \(completion.formatted(.dateTime.month().day())) 완료 예상"
    }

    // MARK: 계획 상태 안내

    /// 부족한 상태를 감추지 않되 자책하게 만드는 표현은 쓰지 않는다.
    /// 여기서 권하는 행동은 설정 수정뿐이다. 플랜 업그레이드를 권하지 않는다(G4).
    @ViewBuilder
    private var plannerStateMessage: some View {
        switch plan.mode {
        case .compressed:
            Text("시험일까지 남은 기간을 반영해 학습량을 조정했어요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        case .insufficientTime:
            warningCard {
                Text("현재 설정으로는 시험 전 권장 학습량을 모두 완료하기 어려워요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.dangerInk)
                if let possible = plan.maximumSetsPossibleBeforeExam {
                    Text("남은 권장 학습 \(plan.remainingSets)세트 · 현재 일정에서 시험 전 최대 \(possible)세트 가능")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
        case .onTrack where plan.finishesAfterExam:
            // 시험일 역산이 잠겨 있어도 위험은 그대로 알린다. 대신 여기서 결제를 권하지 않는다.
            warningCard {
                Text("현재 일정대로면 시험 전에 권장 학습량을 모두 마치기 어려워요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.dangerInk)
            }
        case .onTrack, .completed:
            EmptyView()
        }
    }

    private func warningCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            content()
            NavigationLink("학습 설정 수정", value: PlannerRoute.settings)
                .font(AppTypography.callout)
                .minimumTouchTarget()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 전체 캘린더

    private var fullCalendarLink: some View {
        NavigationLink(value: PlannerRoute.fullCalendar) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "calendar")
                    .foregroundStyle(AppPalette.primary)
                Text("전체 캘린더 보기")
                    .font(AppTypography.callout)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .cardStyle()
        .accessibilityHint("월간 학습 계획을 봅니다")
    }
}

/// 하루 한 칸. 색만으로 상태를 구분하지 않도록 기호를 함께 그린다.
struct StudyDayCell: View {
    let day: StudyDay
    /// 학습 계획 타임존의 달력. 기기 타임존으로 그리면 요일·날짜가 하루 어긋날 수 있다.
    let calendar: Calendar
    var isToday = false
    /// 개인 일정·메모가 있는지. 학습 상태와 다른 기호로, 훨씬 작게 그린다.
    var hasEvent = false
    var hasNote = false

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
            entryIndicators
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm)
        .background(isToday ? AppPalette.primarySoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 개인 일정·메모 표시. 학습 상태 기호(16pt)와 겹쳐 보이지 않게 아주 작게 둔다.
    /// 색이 아니라 모양이 다르고, 읽어 주는 문장에도 따로 들어간다.
    @ViewBuilder
    private var entryIndicators: some View {
        if hasEvent || hasNote {
            HStack(spacing: 2) {
                if hasEvent {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                }
                if hasNote {
                    Image(systemName: "text.alignleft").font(.system(size: 7))
                }
            }
            .foregroundStyle(AppPalette.secondaryInk)
            .accessibilityHidden(true)
        }
    }

    /// 오늘 여부는 배경색으로만 알리면 안 된다. 한 문장으로 조립해 읽어 준다.
    private var accessibilityText: String {
        let weekday = StudyWeekday.from(date: day.date, calendar: calendar).accessibilityLabel
        let date = day.date.formatted(.dateTime.month().day())
        let today = isToday ? "오늘, " : ""
        let sets = day.isScheduled ? ", \(day.completedSets) / \(day.targetSets) 세트" : ""
        let entries = [hasEvent ? "개인 일정 있음" : nil, hasNote ? "메모 있음" : nil]
            .compactMap { $0 }
            .map { ", \($0)" }
            .joined()
        return "\(date) \(weekday), \(today)\(day.state.title)\(sets)\(entries)"
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
