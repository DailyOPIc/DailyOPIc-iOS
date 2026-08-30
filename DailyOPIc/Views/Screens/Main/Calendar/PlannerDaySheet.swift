import SwiftUI
import SwiftData

/// 시트를 여닫는 값. 날짜 정체성은 "yyyy-MM-dd" 문자열 그대로다 —
/// Date로 실으면 기기 타임존이 바뀔 때 다른 날이 열린다.
struct PlannerSelectedDate: Identifiable, Hashable {
    let id: String

    init(_ localDate: String) { id = localDate }
}

/// 하루 시트의 칸 순서. 순서가 화면 안에 흩어져 있으면 나중에 칸을 하나 끼워 넣을 때
/// 어디에 넣어야 하는지 코드가 말해 주지 못한다. 여기 한 줄이 그 답이다.
enum PlannerDaySheetSection: Int, CaseIterable, Sendable {
    /// 시험일에만 나타난다(P12). 그날의 첫 번째 맥락은 학습 기록이 아니라 시험이라
    /// 학습 요약보다 **위**에 둔다.
    case examDay
    case study
    /// P10에서 비워 둔 자리. P11에서 실제 학습한 문제가 들어왔다.
    case learnedQuestions
    case personalEvents
}

/// 하루 시트. 주간 스트립에서든 전체 캘린더에서든 날짜를 누르면 이것이 올라온다.
///
/// 화면을 밀어내지 않는 것이 요점이다(P10). 확인하고 아래로 내리면 사용자는 보던 자리에
/// 그대로 남는다 — 뒤로 가기를 눌러 달력으로 돌아올 필요가 없다.
///
/// 두 가지를 구분한다.
/// - 학습 기록: DailyOPIc 학습으로만 생기는 사실. 여기서는 **읽기만** 한다.
/// - 개인 일정: 사용자가 만든 일정. 이 기기에만 저장한다.
struct PlannerDaySheet: View {
    /// 이 시트의 날짜 정체성. Date가 아니라 "yyyy-MM-dd"다(타임존이 바뀌어도 같은 날).
    let localDate: String
    /// 격자와 같은 계산에서 나온 그날의 학습 상태. 여기서 다시 계산하지 않는다.
    let day: StudyDay
    /// 그날 실제로 한 학습(단어 · 데일리 · 모의). 캘린더 칸의 배지와 **같은 값**이다 —
    /// 시트가 따로 세면 같은 날이 두 가지 숫자를 갖게 된다.
    let activity: PlannerDayActivity
    let isStudyWeekday: Bool
    let isToday: Bool
    /// 설정한 OPIc 시험일인지(P12). 캘린더 별과 **같은** 판정(`StudyPlanSettings.isExamDay`)에서 온다.
    let isExamDay: Bool
    /// 학습 계획 타임존의 달력. 기기 타임존으로 그리면 날짜·요일이 하루 어긋난다.
    let calendar: Calendar
    let persistence: PersistenceService
    /// 권한 상태를 읽고, 명시적 선택일 때만 권한을 묻기 위해 받는다.
    let reminders: StudyReminderService
    /// 개인 일정 알림은 유료다. 일정 자체는 전 플랜이 쓴다(P9).
    let canUseEventReminder: Bool
    /// 일정이 바뀌면 알림 재조정을 한 번 돌린다. 여기서 직접 예약하지 않는다.
    let onPlannerEventsChanged: () -> Void

    @Query private var events: [PlannerEventRecord]

    @State private var editingEvent: PlannerEventDraft?
    /// nil = 아직 읽기 전. 빈 배열("그날 문제 기록이 없다")과 구분해야
    /// 시트가 열리는 순간 "이전 학습 기록" 문구가 깜빡이지 않는다.
    @State private var learnedQuestions: [LearnedQuestion]?

    init(
        localDate: String,
        day: StudyDay,
        activity: PlannerDayActivity,
        isStudyWeekday: Bool,
        isToday: Bool,
        isExamDay: Bool,
        calendar: Calendar,
        persistence: PersistenceService,
        reminders: StudyReminderService,
        canUseEventReminder: Bool,
        onPlannerEventsChanged: @escaping () -> Void
    ) {
        self.localDate = localDate
        self.day = day
        self.activity = activity
        self.isStudyWeekday = isStudyWeekday
        self.isToday = isToday
        self.isExamDay = isExamDay
        self.calendar = calendar
        self.persistence = persistence
        self.reminders = reminders
        self.canUseEventReminder = canUseEventReminder
        self.onPlannerEventsChanged = onPlannerEventsChanged
        _events = Query(filter: #Predicate<PlannerEventRecord> { $0.localDate == localDate })
    }

    private var sortedEvents: [PlannerEventRecord] { PlannerEventRecord.sorted(events) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(titleText)
                    .font(AppTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                ForEach(PlannerDaySheetSection.allCases, id: \.rawValue) { section in
                    view(for: section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.lg)
        }
        // 문제 목록은 시트가 열릴 때 하루치만 읽는다. 캘린더 칸은 이 조회를 하지 않는다.
        .task(id: localDate) {
            learnedQuestions = (
                try? persistence.learnedQuestions(on: localDate, timeZone: calendar.timeZone)
            ) ?? []
        }
        // 편집기는 시트 위의 시트다. 닫으면 이 시트로 돌아오고, 달력은 그대로 뒤에 남아 있다.
        .sheet(item: $editingEvent) { draft in
            PlannerEventEditor(
                draft: draft,
                reminders: reminders,
                canUseEventReminder: canUseEventReminder,
                onSave: { saved in
                    _ = try? persistence.savePlannerEvent(
                        id: saved.isNew ? nil : saved.id,
                        localDate: localDate,
                        title: saved.title,
                        timeMinutes: saved.timeMinutes,
                        reminderOffsetMinutes: saved.reminderOffsetMinutes
                    )
                    onPlannerEventsChanged()
                },
                onDelete: draft.isNew ? nil : {
                    try? persistence.deletePlannerEvent(id: draft.id)
                    onPlannerEventsChanged()
                }
            )
        }
    }

    /// "8월 20일 목요일". 로케일 포매터를 쓰지 않는 이유는 기기 타임존이 학습 계획
    /// 타임존과 다를 때 날짜가 하루 밀려 보이기 때문이다.
    private var titleText: String {
        let parts = calendar.dateComponents([.month, .day], from: day.date)
        let weekday = StudyWeekday.from(date: day.date, calendar: calendar).accessibilityLabel
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(weekday)"
    }

    @ViewBuilder
    private func view(for section: PlannerDaySheetSection) -> some View {
        switch section {
        case .examDay: examDaySection
        case .study: studySection
        case .learnedQuestions: learnedQuestionSection
        case .personalEvents: eventSection
        }
    }

    // MARK: OPIc 시험일 (P12 · 정적 안내)

    /// 설정한 시험일에만 나타난다. 담는 것은 정적 안내뿐이라 저장도 네트워크도 없다.
    ///
    /// 지난 시험일에도 같은 내용이 그대로 뜬다 — 그래서 "곧 시험이에요" 같은
    /// 남은 날짜 표현을 쓰지 않는다. D-day는 플래너 홈이 이미 말한다.
    @ViewBuilder
    private var examDaySection: some View {
        if isExamDay {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Label(OPIcExamDayGuide.sectionTitle, systemImage: "star.fill")
                    .font(AppTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                officialRuleGroup
                tipGroup
                Text(OPIcExamDayGuide.footer)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                // 사용자가 직접 누를 때만 열린다. 체크리스트 자체는 이 링크 없이도 다 읽힌다.
                Link(OPIcExamDayGuide.officialLinkTitle, destination: OPIcExamDayGuide.officialLink)
                    .font(AppTypography.callout)
                    .minimumTouchTarget()
                    .accessibilityHint("사파리에서 OPIc 공식 안내를 엽니다")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    /// 공식 규정. DailyOPIc 권장과 섞이지 않도록 제목을 따로 달고 체크 기호로만 쓴다.
    private var officialRuleGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(OPIcExamDayGuide.officialTitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            ForEach(OPIcExamDayGuide.officialRules) { rule in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: rule.symbol)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.primary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(rule.title)
                            .font(AppTypography.body)
                        Text(rule.detail)
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            // 신분증 표를 다 펼치면 정작 볼 것이 안 보인다. 접어 두고 필요할 때만 편다.
            DisclosureGroup(OPIcExamDayGuide.acceptedIDTitle) {
                Text(OPIcExamDayGuide.acceptedIDExamples)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(AppTypography.footnote)
        }
    }

    /// DailyOPIc 권장. 공식 규정처럼 보이면 안 되므로 제목·기호·문장을 모두 다르게 둔다.
    private var tipGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(OPIcExamDayGuide.tipsTitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            ForEach(OPIcExamDayGuide.dailyOPIcTips, id: \.self) { tip in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text("•")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .accessibilityHidden(true)
                    Text(tip)
                        .font(AppTypography.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 학습 기록 (읽기 전용)

    private var status: PlannerDayStudyStatus {
        PlannerDayStudyStatus.make(day: day, isStudyWeekday: isStudyWeekday)
    }

    private var studySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("오늘의 학습")
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            Text(status.summaryText(day: day, isToday: isToday))
                .font(AppTypography.body)
            activityBadges
            if activity.isVocabularyComplete, day.state == .completed {
                Label("오늘의 학습 완료", systemImage: "checkmark.circle.fill")
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.primary)
            }
            // 손으로 체크할 수 없다는 사실을 한 줄로 밝힌다.
            Text("학습 기록은 실제 Daily 학습으로만 기록돼요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 칸에 찍힌 것과 같은 배지를 같은 값으로 그린다(`PlannerActivityCalendar`).
    @ViewBuilder
    private var activityBadges: some View {
        let badges = PlannerActivityCalendar.badges(activity)
        if !badges.isEmpty {
            HStack(spacing: AppSpacing.md) {
                ForEach(badges, id: \.label) { badge in
                    Label("\(badge.label) \(badge.count)", systemImage: badge.symbol)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(PlannerActivityCalendar.accessibilityText(activity) ?? "")
        }
    }

    // MARK: 학습한 문제 (P11 · 읽기 전용)

    /// 그날 실제로 학습한 문제. 여기서 다시 채점하거나 답변을 보여주지 않는다 —
    /// "그날 어떤 문제를 학습했는지"에만 답한다. 결과 화면은 기록 탭에 이미 있다.
    @ViewBuilder
    private var learnedQuestionSection: some View {
        switch LearnedQuestionSection.make(
            questions: learnedQuestions,
            completedSets: day.completedSets
        ) {
        case .hidden:
            EmptyView()
        case let .questions(questions):
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(LearnedQuestionSection.title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                ForEach(questions) { question in
                    learnedQuestionRow(question)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        case .unavailable:
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(LearnedQuestionSection.unavailableTitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                // 남아 있지 않은 문제를 지어내지 않는다. 없다는 사실만 말한다.
                Text(LearnedQuestionSection.unavailableDetail)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    /// 시각 + 문제. 누를 것이 없는 읽기 전용 줄이라 버튼으로 만들지 않는다.
    /// 문제가 길어도 무슨 문제였는지 알 수 있어야 해서 네 줄까지 편다.
    private func learnedQuestionRow(_ question: LearnedQuestion) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text(question.timeText)
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(question.prompt)
                    .font(AppTypography.body)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(question.kindLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question.accessibilityText)
    }

    // MARK: 개인 일정

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("개인 일정")
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            if sortedEvents.isEmpty {
                Text("아직 등록한 일정이 없어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                ForEach(sortedEvents) { event in
                    eventRow(event)
                }
            }
            Button("개인 일정 추가", systemImage: "plus") {
                editingEvent = PlannerEventDraft(isNew: true)
            }
            .font(AppTypography.callout)
            .minimumTouchTarget()
            .accessibilityLabel("개인 일정 추가")
            .accessibilityHint("\(titleText)에 개인 일정을 추가합니다")
            Text("개인 일정은 이 기기에 저장돼요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func eventRow(_ event: PlannerEventRecord) -> some View {
        Button {
            editingEvent = PlannerEventDraft(event: event)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                // 시간 없는 일정에 가짜 시각을 그리지 않는다.
                Text(event.time?.displayText ?? "시간 없음")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(event.title)
                        .font(AppTypography.body)
                        .multilineTextAlignment(.leading)
                    if let offset = event.reminderOffsetMinutes {
                        Label(
                            PlannerEventReminderPolicy.optionTitle(offset),
                            systemImage: "bell"
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            event.time.map { "\($0.displayText), \(event.title)" } ?? "시간 없음, \(event.title)"
        )
        .accessibilityHint("일정을 수정하거나 삭제합니다")
    }
}

/// 일정 편집 중인 값. 화면이 사라져도 레코드를 직접 붙들지 않도록 값으로 복사해 둔다.
struct PlannerEventDraft: Identifiable {
    let id: UUID
    let isNew: Bool
    var title: String
    var timeMinutes: Int?
    /// nil = 알림 없음. 새 일정의 기본값이다 — 시간을 넣었다고 알림이 저절로 켜지지 않는다.
    var reminderOffsetMinutes: Int?

    init(isNew: Bool) {
        id = UUID()
        self.isNew = isNew
        title = ""
        timeMinutes = nil
        reminderOffsetMinutes = nil
    }

    init(event: PlannerEventRecord) {
        id = event.id
        isNew = false
        title = event.title
        timeMinutes = event.timeMinutes
        reminderOffsetMinutes = event.reminderOffsetMinutes
    }
}

/// 일정 추가·수정 시트. 제목·(선택) 시간·(유료) 미리 알림을 받는다.
/// 반복·색상·장소·사용자 지정 간격은 V1에 없다.
struct PlannerEventEditor: View {
    @State private var draft: PlannerEventDraft
    let reminders: StudyReminderService
    let canUseEventReminder: Bool
    let onSave: (PlannerEventDraft) -> Void
    /// 새 일정에는 삭제가 없다.
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// 잠긴 알림 줄을 **직접 눌렀을 때만** 열린다.
    @State private var isPresentingPaywall = false

    init(
        draft: PlannerEventDraft,
        reminders: StudyReminderService,
        canUseEventReminder: Bool,
        onSave: @escaping (PlannerEventDraft) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: draft)
        self.reminders = reminders
        self.canUseEventReminder = canUseEventReminder
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var trimmedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTime: Bool { draft.timeMinutes != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("제목") {
                    TextField("예: 카페에서 OPIc 공부", text: $draft.title)
                        .submitLabel(.done)
                        .accessibilityLabel("일정 제목")
                }
                Section("시간") {
                    Toggle(
                        "시간 지정",
                        isOn: Binding(
                            get: { hasTime },
                            set: { draft.timeMinutes = $0 ? 9 * 60 : nil }
                        )
                    )
                    if let minutes = draft.timeMinutes {
                        DatePicker(
                            "시간",
                            selection: Binding(
                                get: { StudyTimeOfDay(hour: minutes / 60, minute: minutes % 60).date() },
                                set: {
                                    let time = StudyTimeOfDay(date: $0)
                                    draft.timeMinutes = time.hour * 60 + time.minute
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                    } else {
                        Text("시간 없음으로 저장돼요.")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                Section("알림") {
                    reminderRows
                }
                if let onDelete {
                    Section {
                        Button("일정 삭제", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .accessibilityLabel("일정 삭제, \(trimmedTitle)")
                    }
                }
            }
            .navigationTitle(draft.isNew ? "일정 추가" : "일정 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 빈 제목은 저장할 수 없다. 알림창 대신 버튼을 비활성으로 둔다.
                    Button("저장") {
                        draft.title = trimmedTitle
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .sheet(isPresented: $isPresentingPaywall) {
                PaywallView(source: .calendarLocked)
            }
            .task { await reminders.refreshAuthorizationStatus() }
        }
    }

    /// 알림 칸. 잠긴 사용자에게도 기능을 숨기지 않고 잠긴 채로 보여준다.
    @ViewBuilder
    private var reminderRows: some View {
        if !canUseEventReminder {
            lockedReminderRow
        } else if !hasTime {
            // 시간이 없으면 알릴 시각도 없다. 없는 선택지를 만들어 두지 않는다.
            Text("시간을 정하면 알림을 걸 수 있어요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        } else {
            Picker(
                "일정 알림",
                selection: Binding(
                    get: { draft.reminderOffsetMinutes },
                    set: { select($0) }
                )
            ) {
                Text(PlannerEventReminderPolicy.optionTitle(nil)).tag(Int?.none)
                ForEach(PlannerEventReminderPolicy.allowedOffsets, id: \.self) { minutes in
                    Text(PlannerEventReminderPolicy.optionTitle(minutes)).tag(Int?.some(minutes))
                }
            }
            if draft.reminderOffsetMinutes != nil,
               reminders.authorizationStatus == .denied {
                Text("iPhone 설정에서 알림을 허용해 주세요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
    }

    /// 알림을 켜는 것은 명시적 선택이다. 그때만 시스템 권한 창이 뜰 수 있고,
    /// 이미 거부한 뒤라면 다시 묻지 않는다.
    private func select(_ minutes: Int?) {
        draft.reminderOffsetMinutes = minutes
        guard minutes != nil else { return }
        Task { await reminders.requestAuthorizationIfNeeded() }
    }

    private var lockedReminderRow: some View {
        Button {
            isPresentingPaywall = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AppPalette.secondaryInk)
                Text("일정 알림")
                Spacer(minLength: 0)
                Text("베이직부터 이용 가능")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .accessibilityLabel(CalendarLockedFeature.eventReminder.accessibilityLabel)
        .accessibilityHint(CalendarLockedFeature.eventReminder.detail)
    }
}
