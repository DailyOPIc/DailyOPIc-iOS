import SwiftUI
import SwiftData

/// 하루 상세. 전체 캘린더에서 날짜를 누르면 여기로 온다.
///
/// 세 가지를 확실히 구분한다.
/// - 학습 기록: DailyOPIc 학습으로만 생기는 사실. 여기서는 **읽기만** 한다.
/// - 개인 일정: 사용자가 만든 일정. 이 기기에만 저장한다.
/// - 메모: 날짜당 하나인 자유 메모. 이 기기에만 저장한다.
struct PlannerDayDetailView: View {
    /// 이 화면의 날짜 정체성. Date가 아니라 "yyyy-MM-dd"다(타임존이 바뀌어도 같은 날).
    let localDate: String
    /// 격자와 같은 계산에서 나온 그날의 학습 상태. 여기서 다시 계산하지 않는다.
    let day: StudyDay
    let isStudyWeekday: Bool
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
    @Query private var notes: [PlannerDayNoteRecord]

    @State private var editingEvent: PlannerEventDraft?
    /// nil이면 아직 저장된 메모를 읽기 전이다. 읽기 전에 빈 문자열로 덮어써서 지우면 안 된다.
    @State private var memoText: String?
    /// 메모 입력 중인지. 키보드를 내릴 방법이 이 화면에 하나는 있어야 한다.
    @FocusState private var isEditingMemo: Bool

    init(
        localDate: String,
        day: StudyDay,
        isStudyWeekday: Bool,
        calendar: Calendar,
        persistence: PersistenceService,
        reminders: StudyReminderService,
        canUseEventReminder: Bool,
        onPlannerEventsChanged: @escaping () -> Void
    ) {
        self.localDate = localDate
        self.day = day
        self.isStudyWeekday = isStudyWeekday
        self.calendar = calendar
        self.persistence = persistence
        self.reminders = reminders
        self.canUseEventReminder = canUseEventReminder
        self.onPlannerEventsChanged = onPlannerEventsChanged
        _events = Query(filter: #Predicate<PlannerEventRecord> { $0.localDate == localDate })
        _notes = Query(filter: #Predicate<PlannerDayNoteRecord> { $0.localDate == localDate })
    }

    private var sortedEvents: [PlannerEventRecord] { PlannerEventRecord.sorted(events) }
    private var storedMemo: String { notes.first?.text ?? "" }
    private var isMemoDirty: Bool {
        guard let memoText else { return false }
        return memoText.trimmingCharacters(in: .whitespacesAndNewlines) != storedMemo
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                studySection
                eventSection
                memoSection
            }
            .padding(AppSpacing.lg)
        }
        // 메모를 쓰다 보면 키보드가 화면을 덮는다. 스크롤로도, 완료 버튼으로도 내릴 수 있게 둔다.
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { isEditingMemo = false }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task { if memoText == nil { memoText = storedMemo } }
        // 뒤로 나갈 때 한 번 저장한다. 타이핑 한 글자마다 저장하지 않는다.
        .onDisappear { saveMemoIfNeeded() }
        .sheet(item: $editingEvent) { draft in
            PlannerEventEditor(
                draft: draft,
                reminders: reminders,
                canUseEventReminder: canUseEventReminder,
                onSave: { saved in
                    try? persistence.savePlannerEvent(
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

    // MARK: 학습 기록 (읽기 전용)

    private var status: PlannerDayStudyStatus {
        PlannerDayStudyStatus.make(day: day, isStudyWeekday: isStudyWeekday)
    }

    private var studySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("학습 기록")
                .font(AppTypography.sectionTitle)
            if let setsText {
                Text(setsText)
                    .font(AppTypography.title)
                    .accessibilityLabel(setsAccessibilityText ?? setsText)
            }
            Label(status.title, systemImage: status.symbolName)
                .font(AppTypography.callout)
                .foregroundStyle(statusTint)
            // 손으로 체크할 수 없다는 사실을 한 줄로 밝힌다.
            Text("학습 기록은 실제 Daily 학습으로만 기록돼요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 배정이 없던 날에 가짜 목표를 만들어 붙이지 않는다("1 / 0세트"도, "1 / 1세트 완료"도 아니다).
    /// 휴식일에 그냥 학습한 날은 한 일만 있는 그대로 말한다.
    private var setsText: String? {
        day.setsSummaryText.map { "Daily \($0)" }
    }

    private var setsAccessibilityText: String? {
        guard day.targetSets > 0 else { return nil }
        return "Daily \(day.targetSets)세트 중 \(day.completedSets)세트 완료"
    }

    private var statusTint: Color {
        switch status {
        case .completed: AppPalette.primary
        case .partial: AppPalette.primaryMid
        case .missed, .scheduled, .rest, .unplanned: AppPalette.secondaryInk
        }
    }

    // MARK: 개인 일정

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("개인 일정")
                .font(AppTypography.sectionTitle)
            if sortedEvents.isEmpty {
                Text("아직 등록한 일정이 없어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            } else {
                ForEach(sortedEvents) { event in
                    eventRow(event)
                }
            }
            Button("일정 추가", systemImage: "plus") {
                editingEvent = PlannerEventDraft(isNew: true)
            }
            .font(AppTypography.callout)
            .minimumTouchTarget()
            .accessibilityLabel("일정 추가")
            .accessibilityHint("\(titleText)에 개인 일정을 추가합니다")
            Text("일정과 메모는 이 기기에 저장돼요.")
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

    // MARK: 메모

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("메모")
                .font(AppTypography.sectionTitle)
            TextEditor(
                text: Binding(
                    get: { memoText ?? storedMemo },
                    set: { memoText = $0 }
                )
            )
            .frame(minHeight: 120)
            .font(AppTypography.body)
            .focused($isEditingMemo)
            .scrollContentBackground(.hidden)
            .padding(AppSpacing.sm)
            .background(AppPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .accessibilityLabel("메모")
            if isMemoDirty {
                // 저장 시점을 사용자가 알 수 있게 버튼을 둔다(뒤로 나가도 한 번 더 저장한다).
                Button("메모 저장") { saveMemoIfNeeded() }
                    .font(AppTypography.callout)
                    .minimumTouchTarget()
            } else if !storedMemo.isEmpty {
                // 버튼이 사라진 것만으로는 저장됐는지 알 수 없다. 상태를 한 줄로 말해 준다.
                Label("저장됨", systemImage: "checkmark.circle")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 공백만 남았으면 메모를 지운다(= 메모 없음). 저장은 명시적 버튼과 화면 이탈에서만 한다.
    private func saveMemoIfNeeded() {
        guard let memoText, isMemoDirty else { return }
        try? persistence.savePlannerNote(localDate: localDate, text: memoText)
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
