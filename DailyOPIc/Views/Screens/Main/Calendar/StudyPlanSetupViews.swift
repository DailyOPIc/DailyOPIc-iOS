import SwiftUI

/// 학습 계획 설정의 입력 요소들. 온보딩(단계형)과 수정(한 화면)이 같은 조각을 쓴다.
/// 목표 등급만 예외로 여기서 저장하지 않는다 — 기존 난이도 재선택 화면이 진실이다.
enum StudyPlanSetupSection {
    struct TargetLevel: View {
        let targetLevel: OPIcLevel
        let onChange: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("목표 등급이 어떻게 되세요?")
                    .font(AppTypography.cardTitle)
                Text(targetLevel.rawValue)
                    .font(AppTypography.title)
                    .foregroundStyle(AppPalette.primary)
                Text(targetLevel.description)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                Button("목표 등급 변경", action: onChange)
                    .font(AppTypography.callout)
                    .minimumTouchTarget()
                    .accessibilityHint("난이도 재선택 화면을 엽니다")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct ExamDate: View {
        @Binding var examDate: Date?
        let calendar: Calendar

        private var hasExamDate: Bool { examDate != nil }

        var body: some View {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("시험일이 정해졌나요?")
                    .font(AppTypography.cardTitle)
                HStack(spacing: AppSpacing.sm) {
                    choice(title: "시험일 선택", isSelected: hasExamDate) {
                        examDate = calendar.startOfDay(for: .now)
                    }
                    choice(title: "아직 정하지 않았어요", isSelected: !hasExamDate) {
                        examDate = nil
                    }
                }
                if hasExamDate {
                    DatePicker(
                        "시험일",
                        selection: Binding(
                            get: { examDate ?? calendar.startOfDay(for: .now) },
                            set: { examDate = calendar.startOfDay(for: $0) }
                        ),
                        in: calendar.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .font(AppTypography.body)
                }
                Text("시험일은 나중에 바꿀 수 있어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func choice(
            title: String,
            isSelected: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Text(title)
                    .font(AppTypography.callout)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(isSelected ? AppPalette.primary : AppPalette.surface)
                    .foregroundStyle(isSelected ? AppPalette.actionOnPrimary : AppPalette.ink)
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .minimumTouchTarget()
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    struct Weekdays: View {
        @Binding var weekdays: Set<StudyWeekday>

        var body: some View {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("언제 공부할 수 있나요?")
                    .font(AppTypography.cardTitle)
                // 작은 아이폰에서도 7칸이 잘리지 않도록 고정 크기 대신 균등 분할.
                // 순서만 일~토다. 저장되는 값은 ISO(월=1 … 일=7) 그대로다.
                HStack(spacing: AppSpacing.xs) {
                    ForEach(StudyWeekday.displayOrder) { weekday in
                        chip(weekday)
                    }
                }
                Text("선택하지 않은 요일은 휴식일로 표시돼요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func chip(_ weekday: StudyWeekday) -> some View {
            let isSelected = weekdays.contains(weekday)
            return Button {
                if isSelected {
                    // 최소 한 요일은 남긴다. 전부 끄면 계획이 성립하지 않는다.
                    if weekdays.count > 1 { weekdays.remove(weekday) }
                } else {
                    weekdays.insert(weekday)
                }
            } label: {
                Text(weekday.shortLabel)
                    .font(AppTypography.callout)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(isSelected ? AppPalette.primary : AppPalette.surface)
                    .foregroundStyle(isSelected ? AppPalette.actionOnPrimary : AppPalette.ink)
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(weekday.accessibilityLabel)
            .accessibilityValue(isSelected ? "선택됨" : "선택 안 함")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    struct Intensity: View {
        @Binding var intensity: StudyIntensity
        let dailyCapacity: Int
        let planName: String

        var body: some View {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("하루에 얼마나 공부하고 싶나요?")
                    .font(AppTypography.cardTitle)
                ForEach(StudyIntensity.allCases) { option in
                    row(option)
                }
                if intensity.desiredDailySets > dailyCapacity {
                    // 잠금이 아니라 설명이다. 여기서 페이월을 열지 않는다.
                    Text(
                        "현재 \(planName) 플랜은 하루 Daily 토큰이 \(dailyCapacity)개예요. "
                        + "오늘의 권장 학습량은 \(dailyCapacity)세트로 맞춰 드릴게요."
                    )
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func row(_ option: StudyIntensity) -> some View {
            let isSelected = option == intensity
            return Button {
                intensity = option
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? AppPalette.primary : AppPalette.secondaryInk)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(option.title).font(AppTypography.sectionTitle)
                        Text(option.summary)
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? AppPalette.primarySoft : AppPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundStyle(AppPalette.ink)
            .accessibilityLabel("\(option.title), \(option.summary)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    struct PreferredTime: View {
        @Binding var time: StudyTimeOfDay

        var body: some View {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("언제 공부할까요?")
                    .font(AppTypography.cardTitle)
                DatePicker(
                    "학습 시간",
                    selection: Binding(
                        get: { time.date() },
                        set: { time = StudyTimeOfDay(date: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .font(AppTypography.body)
                // 권한 요청도, 알림 예약도 하지 않는다. 시각만 저장한다.
                Text("알림 기능은 학습 계획 설정 이후 사용할 수 있어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 캘린더 온보딩. 5단계, 각 단계는 질문 하나.
struct StudyPlanSetupView: View {
    let viewModel: StudyCalendarViewModel
    let onFinished: () -> Void
    let onChangeTargetLevel: () -> Void

    @State private var draft = StudyPlanSettings.draft
    @State private var step = 0

    private static let stepCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    stepContent
                }
                .padding(.vertical, AppSpacing.sm)
            }
            if let message = viewModel.saveErrorMessage {
                Text(message)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.dangerInk)
            }
            footer
        }
        .padding(AppSpacing.lg)
        .navigationTitle("학습 계획 만들기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("\(step + 1) / \(Self.stepCount)")
                .font(AppTypography.caption)
                .foregroundStyle(AppPalette.secondaryInk)
            ProgressView(value: Double(step + 1), total: Double(Self.stepCount))
                .tint(AppPalette.primary)
                .accessibilityLabel("설정 진행률")
                .accessibilityValue("\(Self.stepCount)단계 중 \(step + 1)단계")
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            StudyPlanSetupSection.TargetLevel(
                targetLevel: viewModel.targetLevel,
                onChange: onChangeTargetLevel
            )
        case 1:
            StudyPlanSetupSection.ExamDate(
                examDate: $draft.examDate,
                calendar: draft.calendar
            )
        case 2:
            StudyPlanSetupSection.Weekdays(weekdays: $draft.studyWeekdays)
        case 3:
            StudyPlanSetupSection.Intensity(
                intensity: $draft.intensity,
                dailyCapacity: viewModel.dailyCapacity,
                planName: viewModel.plan.displayName
            )
        default:
            StudyPlanSetupSection.PreferredTime(time: $draft.preferredStudyTime)
        }
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.sm) {
            PrimaryButton(
                title: step == Self.stepCount - 1 ? "학습 계획 시작하기" : "다음",
                isLoading: viewModel.isSaving,
                isDisabled: draft.studyWeekdays.isEmpty
            ) {
                if step < Self.stepCount - 1 {
                    step += 1
                } else {
                    Task {
                        if await viewModel.save(draft) { onFinished() }
                    }
                }
            }
            if step > 0 {
                Button("이전") { step -= 1 }
                    .font(AppTypography.callout)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .minimumTouchTarget()
            }
        }
    }
}

/// 플래너 설정. 온보딩과 달리 한 화면에서 바로 고친다.
/// 목표 등급은 여기서도 기존 난이도 재선택 경로를 그대로 연다.
///
/// 플래너 홈에서 설정을 걷어낸 뒤 갈 곳이 여기다. 학습 알림(P1)과 잠긴 자동화 기능도
/// "오늘 뭘 할까"를 묻는 홈이 아니라 이 화면이 맡는다.
struct PlannerSettingsView: View {
    let viewModel: StudyCalendarViewModel
    let onChangeTargetLevel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StudyPlanSettings
    /// 잠긴 기능을 **직접 눌렀을 때만** Paywall이 열린다. 화면 진입으로는 열지 않는다.
    @State private var paywallFeature: CalendarLockedFeature?

    init(
        viewModel: StudyCalendarViewModel,
        onChangeTargetLevel: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onChangeTargetLevel = onChangeTargetLevel
        _draft = State(initialValue: viewModel.settings ?? .draft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                StudyPlanSetupSection.TargetLevel(
                    targetLevel: viewModel.targetLevel,
                    onChange: onChangeTargetLevel
                )
                StudyPlanSetupSection.ExamDate(
                    examDate: $draft.examDate,
                    calendar: draft.calendar
                )
                StudyPlanSetupSection.Weekdays(weekdays: $draft.studyWeekdays)
                StudyPlanSetupSection.Intensity(
                    intensity: $draft.intensity,
                    dailyCapacity: viewModel.dailyCapacity,
                    planName: viewModel.plan.displayName
                )
                StudyPlanSetupSection.PreferredTime(time: $draft.preferredStudyTime)
                // 알림 시각은 저장된 공부 시간이다. 아직 저장하지 않은 draft를 알림 문구로 쓰면
                // 실제로 예약된 시각과 다른 말을 하게 된다.
                StudyReminderCard(
                    service: viewModel.studyReminders,
                    studyTime: viewModel.settings?.preferredStudyTime ?? draft.preferredStudyTime,
                    onReconcile: { Task { await viewModel.reconcileStudyReminders() } }
                )
                lockedFeatureCard
                // 설정을 바꿔도 이미 완료한 학습 기록은 그대로다.
                Text("설정을 바꾸면 남은 학습량을 앞으로의 일정에 다시 나눠요. 지금까지의 학습 기록은 그대로 남아요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                if let message = viewModel.saveErrorMessage {
                    Text(message)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.dangerInk)
                }
                PrimaryButton(
                    title: "저장",
                    isLoading: viewModel.isSaving,
                    isDisabled: draft.studyWeekdays.isEmpty
                ) {
                    Task {
                        if await viewModel.save(draft) { dismiss() }
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("플래너 설정")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywallFeature) { _ in PaywallView(source: .calendarLocked) }
    }

    /// 잠긴 자동화 기능. 한 칸에 모아 두고, 여기를 **직접 누를 때만** Paywall이 열린다.
    @ViewBuilder
    private var lockedFeatureCard: some View {
        let lockedFeatures = viewModel.lockedFeatures
        if !lockedFeatures.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("학습 플랜 기능")
                    .font(AppTypography.sectionTitle)
                ForEach(lockedFeatures, id: \.rawValue) { feature in
                    Button {
                        AppTelemetry.calendarFeatureLockedTap(
                            feature: feature,
                            plan: viewModel.plan
                        )
                        paywallFeature = feature
                    } label: {
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
