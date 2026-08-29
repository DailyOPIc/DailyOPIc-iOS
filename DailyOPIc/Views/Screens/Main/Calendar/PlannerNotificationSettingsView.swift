import SwiftUI

/// 학습 알림(P14.5.2). 플래너 오른쪽 위 종이 여는 화면이다.
///
/// 여기서 정하는 것은 둘뿐이다: **켤지 말지**와 **몇 시에 받을지**.
/// 새 알림 서비스도, 서버도 만들지 않았다 — 기존 `StudyReminderService`와
/// 학습 계획의 `preferredStudyTime`을 그대로 읽고 쓴다. 스위치의 진실은 여전히
/// 서비스 한 곳(`preference`)이라 앱 설정 화면과 이 화면이 다른 답을 낼 수 없다.
///
/// 권한은 **사용자가 켰을 때만** 묻는다. 화면을 여는 것만으로는 시스템 창이 뜨지 않는다.
struct PlannerNotificationSettingsView: View {
    let viewModel: StudyCalendarViewModel

    @Environment(AppEnvironment.self) private var environment
    /// 시각은 학습 계획의 값이다. 저장을 눌러야 바뀌므로 초안으로 들고 있는다.
    @State private var time: StudyTimeOfDay
    @State private var isSaving = false

    init(viewModel: StudyCalendarViewModel) {
        self.viewModel = viewModel
        _time = State(initialValue: (viewModel.settings ?? .draft).preferredStudyTime)
    }

    private var reminderState: StudyReminderSettingsState {
        .make(
            preference: environment.studyReminders.preference,
            authorization: environment.studyReminders.authorizationStatus
        )
    }

    private var savedTime: StudyTimeOfDay {
        (viewModel.settings ?? .draft).preferredStudyTime
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Toggle(
                    "오늘 학습 알림",
                    isOn: Binding(
                        get: { reminderState.isOn },
                        set: { isOn in Task { await setStudyReminders(isOn) } }
                    )
                )
                .font(AppTypography.body)
                Text(reminderState.statusText)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)

                // 시간 피커는 켜져 있을 때만 나온다. 꺼 둔 알림의 시각을 고르게 하면
                // "정했는데 왜 안 와요?"가 된다.
                if reminderState.isOn {
                    Divider()
                    Text("오늘 학습 시간")
                        .font(AppTypography.cardTitle)
                    DatePicker(
                        "오늘 학습 시간",
                        selection: Binding(
                            get: { time.date() },
                            set: { time = StudyTimeOfDay(date: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    if time != savedTime {
                        // 저장하면 학습 계획이 갱신되고, 예약은 늘 같은 재조정 한 곳에서
                        // 다시 맞춰진다 — 여기서 개별 알림을 직접 지우거나 걸지 않는다.
                        PrimaryButton(title: "시간 저장", isLoading: isSaving) {
                            Task { await saveTime() }
                        }
                    }
                }
                if let message = viewModel.saveErrorMessage {
                    Text(message)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.dangerInk)
                }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("학습 알림")
        .navigationBarTitleDisplayMode(.inline)
        // 지금 권한 상태를 다시 물어 온다. 묻기만 할 뿐 요청하지 않는다.
        .task { await environment.studyReminders.refreshAuthorizationStatus() }
    }

    /// 켜는 것은 **사용자의 명시적 행동**이라 여기서만 시스템 권한을 물을 수 있다.
    /// 끄면 예약도 함께 사라진다(재조정이 빈 목록을 만든다).
    private func setStudyReminders(_ isOn: Bool) async {
        if isOn {
            await environment.studyReminders.enable()
        } else {
            await environment.studyReminders.disable()
        }
        await viewModel.reconcileReminders()
    }

    private func saveTime() async {
        guard var draft = viewModel.settings else { return }
        draft.preferredStudyTime = time
        isSaving = true
        _ = await viewModel.save(draft)
        isSaving = false
    }
}
