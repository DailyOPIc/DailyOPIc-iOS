import Foundation
import UserNotifications

/// 테스트가 실제 권한 창을 띄우지 않도록 시스템 센터를 이 좁은 창구로만 쓴다.
protocol UserNotificationCenterProtocol: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async
    func removePendingRequests(identifiers: [String])
}

struct SystemNotificationCenter: UserNotificationCenterProtocol {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async {
        do {
            try await center.add(request)
        } catch {
            // 예약 실패는 조용히 사라지면 안 된다(예: 대기 알림 상한 초과).
            // 식별자·문구는 남기지 않고 실패했다는 사실만 남긴다.
            StudyReminderDiagnostics.log("add failed")
        }
    }

    func removePendingRequests(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// 앱을 보고 있는 동안 도착한 알림을 어떻게 띄울지.
///
/// delegate를 붙이지 않으면 iOS는 포그라운드 알림을 **조용히 버린다**. 학습 알림은
/// 사용자가 정한 "공부할 시간"에 울리므로 앱을 켜 둔 채 그 시각을 맞는 경우가 흔하다.
enum StudyReminderPresentation {
    static func options(for identifier: String) -> UNNotificationPresentationOptions {
        // 우리 알림만 띄운다. 다른 출처의 알림은 지금까지의 동작(표시 안 함)을 그대로 둔다.
        StudyReminderPolicy.isStudyReminder(identifier) ? [.banner, .list, .sound] : []
    }
}

/// DEBUG 전용 진단. 실기기에서 "왜 안 왔는지"를 보려고 두는 것이라
/// 개수·상태 같은 고정 값만 남기고 UID·문구·날짜는 남기지 않는다.
enum StudyReminderDiagnostics {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[DailyOPIc][Reminder] \(message())")
        #endif
    }
}

extension UNAuthorizationStatus {
    /// 이 상태에서 알림을 예약할 수 있는가. provisional/ephemeral도 조용히 전달된다.
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// 로그용 고정 값. 자유 텍스트를 남기지 않는다.
    var telemetryValue: String {
        switch self {
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        case .denied: "denied"
        default: "not_determined"
        }
    }
}

/// 학습 알림 예약 담당. UNUserNotificationCenter를 만지는 곳은 여기 하나뿐이다.
///
/// 권한은 **사용자가 명시적으로 켤 때만** 요청한다. 앱 실행·캘린더 진입·구매·오류 어디서도
/// 자동으로 시스템 창을 띄우지 않는다.
///
/// 앱 안의 `studyRemindersEnabled`는 "이 기기에서 알림을 받고 싶다"는 **사용자 의도**이고,
/// 실제 발송 권한은 언제나 OS다. 그래서 거부 상태에서 설정으로 권한을 켜고 돌아오면
/// 별도 조작 없이 예약이 다시 살아난다.
@MainActor
@Observable
final class StudyReminderService {
    private let center: UserNotificationCenterProtocol
    private let preferences: AppPreferences

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init(preferences: AppPreferences, center: UserNotificationCenterProtocol = SystemNotificationCenter()) {
        self.preferences = preferences
        self.center = center
    }

    /// 사용자가 앱에서 알림을 켜 뒀는가(시스템 권한과 별개).
    var isEnabled: Bool { preferences.studyRemindersEnabled }
    /// 실제로 예약이 가능한 상태.
    var isActive: Bool { isEnabled && authorizationStatus.allowsScheduling }
    /// 앱에서는 켰지만 OS 권한이 막혀 있는 상태 → 설정으로 안내한다.
    var needsSystemPermission: Bool { isEnabled && !authorizationStatus.allowsScheduling }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.authorizationStatus()
    }

    /// 명시적 CTA에서만 호출한다.
    /// 아직 물어본 적 없을 때만 시스템 권한 창을 띄우고, 거부 상태에서는 다시 묻지 않는다.
    @discardableResult
    func enable() async -> UNAuthorizationStatus {
        AppTelemetry.studyReminderEnableTapped()
        var status = await center.authorizationStatus()
        if status == .notDetermined {
            _ = await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        authorizationStatus = status
        preferences.studyRemindersEnabled = true
        AppTelemetry.studyReminderPermissionResult(status)
        return status
    }

    /// 앱 안에서 끄기. 시스템 권한은 건드리지 않고 우리 알림만 걷어낸다.
    func disable() async {
        preferences.studyRemindersEnabled = false
        await cancelAll()
        AppTelemetry.studyReminderDisabled()
    }

    /// 대기 중인 알림을 원하는 목록과 같게 만든다. 같은 입력으로 여러 번 돌려도 결과가 같다.
    ///
    /// `nil`은 "지금은 일정을 모른다"(계획 미로딩·저장소 미준비)이고 `[]`는 "예약할 것이 없다"이다.
    /// 둘을 같은 값으로 다루면 앱이 켜지는 순간의 재조정이 — 계획을 읽기도 전에 —
    /// 앞으로의 멀쩡한 예약을 전부 지운다. 모를 때는 권한 상태만 최신화하고 손대지 않는다.
    ///
    /// `isEligible`은 유료 자격(`CalendarFeaturePolicy.canUseStudyReminder`)이다. 자격 판단은
    /// 이 인자 하나로만 들어온다 — 서비스가 플랜을 직접 보지 않는다.
    /// 기본값 `true`는 자격과 무관한 P1 경로(테스트 포함)를 그대로 두기 위한 것이고,
    /// 앱에서 부르는 곳은 `StudyCalendarViewModel.reconcileStudyReminders()` 하나뿐이다.
    func reconcile(_ desired: [StudyReminderRequest]?, isEligible: Bool = true) async {
        await refreshAuthorizationStatus()
        // 자격 상실은 일정을 알기 전에 처리한다. 일정을 모른다고 미루면
        // 강등된 사용자가 유료 시절 예약된 알림을 계속 받는다.
        guard isEligible else {
            await revokeForIneligibility()
            return
        }
        guard let desired else {
            StudyReminderDiagnostics.log("skipped reason=schedule_unknown")
            return
        }
        guard isActive else {
            StudyReminderDiagnostics.log(
                "skipped reason=inactive enabled=\(isEnabled) status=\(authorizationStatus.telemetryValue)"
            )
            await cancelAll()
            return
        }
        let pending = await studyReminderRequests()
        let desiredByIdentifier = Dictionary(
            desired.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // 사라진 날짜 + 내용/시각이 바뀐 날짜를 걷어낸다.
        let stale = pending.filter { !(desiredByIdentifier[$0.identifier]?.matches($0) ?? false) }
        if !stale.isEmpty {
            center.removePendingRequests(identifiers: stale.map(\.identifier))
        }
        let kept = Set(pending.map(\.identifier)).subtracting(stale.map(\.identifier))
        var added = 0
        for request in desired where !kept.contains(request.identifier) {
            await center.add(request.notificationRequest)
            added += 1
        }
        StudyReminderDiagnostics.log(
            "reconciled status=\(authorizationStatus.telemetryValue) "
            + "desired=\(desired.count) kept=\(kept.count) added=\(added) removed=\(stale.count)"
        )
    }

    /// 유료 자격을 잃었을 때(강등). 우리 알림만 걷어내고 로컬 "켜 둠" 의도를 끈다.
    ///
    /// - 시스템 권한은 건드리지 않는다. 알림 허용은 사용자가 OS에 준 것이고 우리가 뺏을 것이 아니다.
    /// - 권한을 다시 요청하지도 않는다.
    /// - 의도(`studyRemindersEnabled`)를 끄는 것은 일부러다. 나중에 다시 업그레이드해도
    ///   알림이 저절로 켜지지 않고, 사용자가 직접 켜야 한다.
    /// - 여러 번 불러도 결과가 같다(두 번째부터는 지울 것도 끌 것도 없다).
    private func revokeForIneligibility() async {
        let hadIntent = preferences.studyRemindersEnabled
        preferences.studyRemindersEnabled = false
        await cancelAll()
        if hadIntent {
            StudyReminderDiagnostics.log("revoked reason=plan_ineligible")
        }
    }

    /// 우리 네임스페이스의 알림만 제거한다. 전체 삭제(removeAllPending…)는 쓰지 않는다.
    func cancelAll() async {
        let identifiers = await studyReminderRequests().map(\.identifier)
        guard !identifiers.isEmpty else { return }
        center.removePendingRequests(identifiers: identifiers)
    }

    private func studyReminderRequests() async -> [UNNotificationRequest] {
        await center.pendingRequests().filter { StudyReminderPolicy.isStudyReminder($0.identifier) }
    }
}

extension StudyReminderRequest {
    var notificationRequest: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        )
    }

    /// 이미 예약된 알림이 지금 원하는 것과 같은가(문구·시각까지).
    func matches(_ request: UNNotificationRequest) -> Bool {
        guard request.identifier == identifier,
              request.content.title == title,
              request.content.body == body,
              let trigger = request.trigger as? UNCalendarNotificationTrigger
        else { return false }
        return trigger.dateComponents == dateComponents
    }
}
