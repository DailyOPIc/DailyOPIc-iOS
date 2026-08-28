#if DEBUG
import SwiftUI
import UserNotifications

/// 실기기에서 "왜 학습 알림이 안 오는지"를 앱 안에서 바로 보기 위한 DEBUG 전용 칸.
///
/// 파일 전체가 `#if DEBUG`라서 Release/TestFlight/App Store 빌드에는 존재하지 않는다.
/// 보여주는 값은 상태·개수·시각뿐이다 — UID·알림 문구·답변·메모·일정 제목은 넣지 않는다.
struct StudyReminderDiagnosticsSection: View {
    let viewModel: StudyCalendarViewModel

    @State private var diagnosis: ReminderDiagnosis?
    @State private var pending: PendingReminders = .empty
    @State private var eventDiagnosis: ReminderDiagnosis?
    @State private var eventPending: PendingReminders = .empty
    @State private var settingsAuthorization: String = "확인 전"
    @State private var selfTestResult: String?
    @State private var eventSelfTestResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("알림 진단 (DEBUG)")
                .font(AppTypography.sectionTitle)

            row("권한", diagnosis?.authorization.telemetryValue ?? settingsAuthorization)
            row("현재 플랜", viewModel.plan.rawValue)
            row("선호 공부 시간", viewModel.settings?.preferredStudyTime.displayText ?? "미설정")

            // 두 네임스페이스를 **따로** 센다. 합치면 어느 쪽이 실패했는지 사라진다.
            Text("학습 알림 (전 플랜)")
                .font(AppTypography.callout)
            row("앱 알림 설정", (diagnosis?.isEnabled ?? viewModel.studyReminders.isEnabled) ? "ON" : "OFF")
            row("의도(3상태)", viewModel.studyReminders.preference.rawValue)
            row("오늘 학습 상태", todayText)
            row("오늘 예약 판단 이유", diagnosis?.reason.displayText ?? "확인 전")
            row("desired", diagnosis?.desiredCount.map(String.init) ?? "unknown")
            row("pending (실제 iOS)", "\(pending.count)")
            row("다음 발화", nextFireText(pending))
            row("트리거 타임존", pending.nextTriggerTimeZone ?? "-")
            if let failure = viewModel.studyReminders.lastAddFailure {
                row("마지막 예약 실패", failure.displayText)
            }

            Text("개인 일정 알림 (베이직+)")
                .font(AppTypography.callout)
            row("일정 알림 자격", eventDiagnosis?.eligibility.rawValue ?? "확인 전")
            row("판단 이유", eventDiagnosis?.reason.displayText ?? "확인 전")
            row("desired", eventDiagnosis?.desiredCount.map(String.init) ?? "unknown")
            row("pending (실제 iOS)", "\(eventPending.count)")
            row("다음 발화", nextFireText(eventPending))
            if let failure = viewModel.studyReminders.lastEventAddFailure {
                row("마지막 예약 실패", failure.displayText)
            }

            HStack(spacing: AppSpacing.md) {
                Button("새로고침") { Task { await refresh() } }
                Button("60초 테스트 알림 예약") { Task { await runSelfTest() } }
            }
            .font(AppTypography.callout)
            .minimumTouchTarget()
            Button("60초 일정 알림 테스트") { Task { await runEventSelfTest() } }
                .font(AppTypography.callout)
                .minimumTouchTarget()

            if let eventSelfTestResult {
                Text(eventSelfTestResult)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            if let selfTestResult {
                Text(selfTestResult)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .cardStyle()
        .task { await refresh() }
    }

    /// 배정량이 아니라 **실제 완료 수**를 본다. 알림 취소 기준이 그것이기 때문이다(P9).
    private var todayText: String {
        guard let completed = diagnosis?.todayCompletedSets else { return "확인 전" }
        return completed > 0 ? "\(completed)세트 완료" : "아직 안 함"
    }

    /// 꼬리표는 학습 알림이면 날짜, 일정 알림이면 일정 id다. 일정 제목은 어디에도 없다.
    private func nextFireText(_ snapshot: PendingReminders) -> String {
        guard let date = snapshot.nextTriggerDate else { return "없음" }
        let tag = snapshot.nextLocalDate.map { "\($0.prefix(10)) " } ?? ""
        return tag + date.formatted(date: .omitted, time: .standard)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(AppPalette.secondaryInk)
            Spacer(minLength: AppSpacing.sm)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(AppTypography.footnote)
        .accessibilityElement(children: .combine)
    }

    /// 진단은 읽기만 한다. 여기서 재조정하거나 권한을 요청하지 않는다.
    private func refresh() async {
        await viewModel.studyReminders.refreshAuthorizationStatus()
        settingsAuthorization = viewModel.studyReminders.authorizationStatus.telemetryValue
        diagnosis = viewModel.studyReminderDiagnosis()
        pending = await viewModel.studyReminders.pendingSnapshot()
        eventDiagnosis = viewModel.eventReminderDiagnosis()
        eventPending = await viewModel.studyReminders.pendingEventSnapshot()
        StudyReminderDiagnostics.log(
            "study " + (diagnosis?.logLine ?? "") + " pending=\(pending.count) | "
            + "event " + (eventDiagnosis?.logLine ?? "") + " pending=\(eventPending.count)"
        )
    }

    /// 실제 일정·알림 설정·학습 알림을 건드리지 않는다. 다른 네임스페이스를 쓴다.
    private func runEventSelfTest() async {
        let result = await viewModel.studyReminders.scheduleEventSelfTestNotification()
        eventSelfTestResult = "60초 일정 테스트: " + result.displayText
        await refresh()
    }

    private func runSelfTest() async {
        let result = await viewModel.studyReminders.scheduleSelfTestNotification()
        selfTestResult = "60초 테스트: " + result.displayText
        // 테스트 알림은 학습 알림 네임스페이스 밖이라 pending 수에 잡히지 않는다.
        await refresh()
    }
}
#endif
