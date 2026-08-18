#if DEBUG
import SwiftUI
import UserNotifications

/// 실기기에서 "왜 학습 알림이 안 오는지"를 앱 안에서 바로 보기 위한 DEBUG 전용 칸.
///
/// 파일 전체가 `#if DEBUG`라서 Release/TestFlight/App Store 빌드에는 존재하지 않는다.
/// 보여주는 값은 상태·개수·시각뿐이다 — UID·알림 문구·답변·메모·일정 제목은 넣지 않는다.
struct StudyReminderDiagnosticsSection: View {
    let viewModel: StudyCalendarViewModel

    @State private var diagnosis: StudyReminderDiagnosis?
    @State private var pending: PendingStudyReminders = .empty
    @State private var settingsAuthorization: String = "확인 전"
    @State private var selfTestResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("알림 진단 (DEBUG)")
                .font(AppTypography.sectionTitle)

            row("권한", diagnosis?.authorization.telemetryValue ?? settingsAuthorization)
            row("현재 플랜", viewModel.plan.rawValue)
            row("알림 사용 가능 여부", diagnosis?.eligibility.rawValue ?? "확인 전")
            row("앱 알림 설정", (diagnosis?.isEnabled ?? viewModel.studyReminders.isEnabled) ? "ON" : "OFF")
            row("선호 공부 시간", viewModel.settings?.preferredStudyTime.displayText ?? "미설정")
            row("오늘 학습 상태", todayText)
            row("오늘 예약 판단 이유", diagnosis?.reason.displayText ?? "확인 전")
            row("desired", diagnosis?.desiredCount.map(String.init) ?? "unknown")
            row("pending (실제 iOS)", "\(pending.count)")
            row("다음 발화", nextFireText)
            row("트리거 타임존", pending.nextTriggerTimeZone ?? "-")
            if let failure = viewModel.studyReminders.lastAddFailure {
                row("마지막 예약 실패", failure.displayText)
            }

            HStack(spacing: AppSpacing.md) {
                Button("새로고침") { Task { await refresh() } }
                Button("60초 테스트 알림 예약") { Task { await runSelfTest() } }
            }
            .font(AppTypography.callout)
            .minimumTouchTarget()

            if let selfTestResult {
                Text(selfTestResult)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .cardStyle()
        .task { await refresh() }
    }

    private var todayText: String {
        guard let diagnosis, let target = diagnosis.todayTargetSets else { return "배정 없음" }
        return "\(diagnosis.todayCompletedSets ?? 0) / \(target) 세트"
    }

    private var nextFireText: String {
        guard let date = pending.nextTriggerDate else { return "없음" }
        let day = pending.nextLocalDate.map { "\($0) " } ?? ""
        return day + date.formatted(date: .omitted, time: .standard)
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
        StudyReminderDiagnostics.log(
            (diagnosis?.logLine ?? "") + " pending=\(pending.count)"
        )
    }

    private func runSelfTest() async {
        let result = await viewModel.studyReminders.scheduleSelfTestNotification()
        selfTestResult = "60초 테스트: " + result.displayText
        // 테스트 알림은 학습 알림 네임스페이스 밖이라 pending 수에 잡히지 않는다.
        await refresh()
    }
}
#endif
