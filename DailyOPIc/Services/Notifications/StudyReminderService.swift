import Foundation
import UserNotifications

/// 테스트가 실제 권한 창을 띄우지 않도록 시스템 센터를 이 좁은 창구로만 쓴다.
protocol UserNotificationCenterProtocol: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    /// 실패를 돌려준다. 예약이 조용히 사라지면 "원한 목록"만 보고 성공했다고 착각하게 된다.
    @discardableResult
    func add(_ request: UNNotificationRequest) async -> NotificationAddFailure?
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

    @discardableResult
    func add(_ request: UNNotificationRequest) async -> NotificationAddFailure? {
        do {
            try await center.add(request)
            return nil
        } catch {
            // 예약 실패는 조용히 사라지면 안 된다(예: 대기 알림 상한 초과).
            // 식별자·문구는 남기지 않고 도메인·코드만 남긴다.
            let error = error as NSError
            return NotificationAddFailure(domain: error.domain, code: error.code)
        }
    }

    func removePendingRequests(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// 앱을 보고 있는 동안 도착한 알림을 어떻게 띄울지.
///
/// delegate를 붙이지 않으면 iOS는 포그라운드 알림을 **조용히 버린다**. 학습 알림은
/// 사용자가 정한 "공부할 시간"에 울리므로 앱을 켜 둔 채 그 시각을 맞는 경우가 흔하고,
/// 개인 일정 알림은 시작 직전이라 더 그렇다.
enum StudyReminderPresentation {
    static func options(for identifier: String) -> UNNotificationPresentationOptions {
        // 우리 알림만 띄운다. 다른 출처의 알림은 지금까지의 동작(표시 안 함)을 그대로 둔다.
        if StudyReminderPolicy.isStudyReminder(identifier)
            || PlannerEventReminderPolicy.isEventReminder(identifier) {
            return [.banner, .list, .sound]
        }
        #if DEBUG
        // 60초 테스트 알림도 포그라운드에서 보여야 "전달 자체는 되는가"를 판별할 수 있다.
        if StudyReminderSelfTest.isSelfTest(identifier)
            || PlannerEventSelfTest.isSelfTest(identifier) {
            return [.banner, .list, .sound]
        }
        #endif
        return []
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

/// 로컬 알림 예약 담당. UNUserNotificationCenter를 만지는 곳은 여기 하나뿐이다.
/// 학습 알림과 개인 일정 알림 **두 네임스페이스**를 각각, 그러나 같은 재조정 루틴으로 맞춘다.
///
/// 권한은 **사용자가 명시적으로 켤 때만** 요청한다. 앱 실행·캘린더 진입·구매·오류 어디서도
/// 자동으로 시스템 창을 띄우지 않는다.
///
/// 앱 안의 의도(`studyReminderPreference`)와 OS 권한은 별개다. 그래서 거부 상태에서
/// 설정으로 권한을 켜고 돌아오면 별도 조작 없이 예약이 다시 살아난다.
@MainActor
@Observable
final class StudyReminderService {
    private let center: UserNotificationCenterProtocol
    private let preferences: AppPreferences

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// 마지막 재조정이 학습 알림을 건너뛴 이유. DEBUG 진단 화면이 읽는다.
    private(set) var lastSkipReason: ReminderSkipReason?
    /// 마지막 학습 알림 `add` 실패. iOS가 예약을 거절하면 여기에만 흔적이 남는다.
    private(set) var lastAddFailure: NotificationAddFailure?
    /// 개인 일정 알림 쪽 값. 학습 알림과 **합치지 않는다** — 합치면 어느 쪽이 실패했는지 사라진다.
    private(set) var lastEventSkipReason: ReminderSkipReason?
    private(set) var lastEventAddFailure: NotificationAddFailure?

    init(preferences: AppPreferences, center: UserNotificationCenterProtocol = SystemNotificationCenter()) {
        self.preferences = preferences
        self.center = center
    }

    /// 저장된 3상태 의도. `unspecified`는 "사용자가 아직 고른 적 없음"이다.
    var preference: StudyReminderPreference { preferences.studyReminderPreference }

    /// 학습 알림을 받고 싶어 하는가(시스템 권한과 별개).
    /// 명시적으로 끈 적이 없으면 **켜진 것으로 본다**(P9 기본 ON).
    var isEnabled: Bool { preference.isEffectivelyOn }
    /// 실제로 예약이 가능한 상태.
    var isActive: Bool { isEnabled && authorizationStatus.allowsScheduling }
    /// 앱에서는 켰지만 OS 권한이 막혀 있는 상태 → 설정으로 안내한다.
    var needsSystemPermission: Bool { isEnabled && authorizationStatus == .denied }

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
        preferences.studyReminderPreference = .enabled
        AppTelemetry.studyReminderPermissionResult(status)
        return status
    }

    /// 개인 일정 알림을 켜려는 **명시적 선택**에서만 부른다.
    /// 학습 알림 의도(`studyReminderPreference`)는 건드리지 않는다 — 다른 기능이다.
    /// 이미 물어본 뒤라면(거부 포함) 다시 묻지 않는다. iOS도 두 번째 창은 띄워 주지 않는다.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        var status = await center.authorizationStatus()
        if status == .notDetermined {
            _ = await center.requestAuthorization()
            status = await center.authorizationStatus()
        }
        authorizationStatus = status
        return status
    }

    /// 앱 안에서 끄기. 시스템 권한은 건드리지 않고 우리 알림만 걷어낸다.
    /// 여기서 남긴 `disabled`는 **영구적**이다 — 어떤 자동 경로도 이 선택을 덮어쓰지 않는다.
    func disable() async {
        preferences.studyReminderPreference = .disabled
        await cancelAll()
        AppTelemetry.studyReminderDisabled()
    }

    /// 학습 알림 재조정. **플랜을 보지 않는다** — 전 플랜 공통 기능이다(P9).
    ///
    /// `nil`은 "지금은 일정을 모른다"(계획 미로딩·저장소 미준비)이고 `[]`는 "예약할 것이 없다"이다.
    /// 둘을 같은 값으로 다루면 앱이 켜지는 순간의 재조정이 — 계획을 읽기도 전에 —
    /// 앞으로의 멀쩡한 예약을 전부 지운다. 모를 때는 권한 상태만 최신화하고 손대지 않는다.
    func reconcile(_ desired: [LocalNotificationRequest]?) async {
        await refreshAuthorizationStatus()
        let result = await reconcile(
            desired: desired,
            prefix: StudyReminderPolicy.identifierPrefix,
            isEnabled: isEnabled,
            eligibility: .eligible,
            label: "study"
        )
        lastSkipReason = result.reason
        lastAddFailure = result.failure
    }

    /// 개인 일정 알림 재조정. 여기가 P9의 유료 경계다.
    ///
    /// 자격을 **아직 모를 때**는 아무것도 하지 않는다(P7). 앱이 막 켜진 순간에는
    /// RevenueCat도 서버도 대답하기 전이라 플랜이 기본값 무료로 보이는데, 그것을 강등으로
    /// 착각하면 유료 사용자의 예약을 전부 지워 버린다.
    func reconcileEventReminders(
        _ desired: [LocalNotificationRequest]?,
        eligibility: ReminderEligibility
    ) async {
        await refreshAuthorizationStatus()
        let result = await reconcile(
            desired: desired,
            prefix: PlannerEventReminderPolicy.identifierPrefix,
            isEnabled: true, // 일정 알림의 on/off는 일정마다 고른 "미리 알림"이 곧 의도다.
            eligibility: eligibility,
            emptyReason: .userSelectedNone,
            label: "event"
        )
        lastEventSkipReason = result.reason
        lastEventAddFailure = result.failure
    }

    /// 두 네임스페이스가 **같은** 차분 루틴을 쓴다. 예약을 저장·수정·삭제·실행 시점마다
    /// 흩어 놓으면 어느 경로가 예약을 지웠는지 영원히 알 수 없다.
    /// 같은 입력으로 여러 번 돌려도 결과가 같다.
    private func reconcile(
        desired: [LocalNotificationRequest]?,
        prefix: String,
        isEnabled: Bool,
        eligibility: ReminderEligibility,
        emptyReason: ReminderSkipReason? = nil,
        label: String
    ) async -> (reason: ReminderSkipReason?, failure: NotificationAddFailure?) {
        switch eligibility {
        case .unknown:
            // 모를 때는 예약도 삭제도 하지 않는다. 다음 재조정이 알고 나서 정리한다.
            return (skip(.entitlementUnknown, label: label), nil)
        case .ineligible:
            // 자격 상실은 일정을 알기 전에 처리한다. 일정을 모른다고 미루면
            // 강등된 사용자가 유료 시절 예약된 알림을 계속 받는다.
            // 사용자가 고른 알림 설정 자체는 지우지 않는다 — 다시 결제하면 그대로 살아난다.
            await cancel(prefix: prefix)
            return (skip(.featureLocked, label: label), nil)
        case .eligible:
            break
        }
        guard let desired else {
            return (skip(.scheduleUnknown, label: label), nil)
        }
        guard isEnabled else {
            await cancel(prefix: prefix)
            return (skip(.userDisabled, label: label), nil)
        }
        guard authorizationStatus.allowsScheduling else {
            await cancel(prefix: prefix)
            return (skip(permissionSkipReason, label: label), nil)
        }
        let pending = await requests(prefix: prefix)
        let desiredByIdentifier = Dictionary(
            desired.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // 사라진 것 + 내용/시각이 바뀐 것을 걷어낸다. 다른 네임스페이스는 손대지 않는다.
        let stale = pending.filter { !(desiredByIdentifier[$0.identifier]?.matches($0) ?? false) }
        if !stale.isEmpty {
            center.removePendingRequests(identifiers: stale.map(\.identifier))
        }
        let kept = Set(pending.map(\.identifier)).subtracting(stale.map(\.identifier))
        var added = 0
        var failed = 0
        var failure: NotificationAddFailure?
        for request in desired where !kept.contains(request.identifier) {
            if let error = await center.add(request.notificationRequest) {
                failed += 1
                failure = error
            } else {
                added += 1
            }
        }
        StudyReminderDiagnostics.log(
            "reconciled=\(label) status=\(authorizationStatus.telemetryValue) "
            + "desired=\(desired.count) kept=\(kept.count) added=\(added) "
            + "removed=\(stale.count) failed=\(failed)"
            + (failure.map { " error=\($0.displayText)" } ?? "")
        )
        return (desired.isEmpty ? emptyReason : nil, failure)
    }

    private var permissionSkipReason: ReminderSkipReason {
        authorizationStatus == .denied ? .permissionDenied : .permissionNotDetermined
    }

    @discardableResult
    private func skip(_ reason: ReminderSkipReason, label: String) -> ReminderSkipReason {
        StudyReminderDiagnostics.log("skipped=\(label) reason=\(reason.rawValue)")
        return reason
    }

    /// 학습 알림만 제거한다. 전체 삭제(removeAllPending…)는 쓰지 않는다 —
    /// 그러면 개인 일정 알림과 DEBUG 테스트 알림까지 같이 날아간다.
    func cancelAll() async {
        await cancel(prefix: StudyReminderPolicy.identifierPrefix)
    }

    private func cancel(prefix: String) async {
        let identifiers = await requests(prefix: prefix).map(\.identifier)
        guard !identifiers.isEmpty else { return }
        center.removePendingRequests(identifiers: identifiers)
    }

    private func requests(prefix: String) async -> [UNNotificationRequest] {
        await center.pendingRequests().filter { $0.identifier.hasPrefix(prefix) }
    }

    /// iOS에 **실제로** 남아 있는 우리 알림. 앱이 원한 목록과 다를 수 있고,
    /// 다르다는 사실 자체가 진단의 핵심이라 desired로 대신하지 않는다.
    func pendingSnapshot() async -> PendingReminders {
        PendingReminders(
            requests: await requests(prefix: StudyReminderPolicy.identifierPrefix),
            identifierPrefix: StudyReminderPolicy.identifierPrefix
        )
    }

    /// 개인 일정 알림 쪽 실제 대기 목록. 꼬리표는 일정 id라 제목이 새어 나가지 않는다.
    func pendingEventSnapshot() async -> PendingReminders {
        PendingReminders(
            requests: await requests(prefix: PlannerEventReminderPolicy.identifierPrefix),
            identifierPrefix: PlannerEventReminderPolicy.identifierPrefix
        )
    }

    #if DEBUG
    /// DEBUG 진단용 60초 테스트 알림. 학습 알림 설정·예약을 건드리지 않는다.
    func scheduleSelfTestNotification() async -> StudyReminderSelfTest.Result {
        await StudyReminderSelfTest.schedule(center: center)
    }

    /// DEBUG 진단용 60초 **일정** 알림 테스트. 실제 일정·알림 설정·학습 알림을 건드리지 않는다.
    func scheduleEventSelfTestNotification() async -> StudyReminderSelfTest.Result {
        await StudyReminderSelfTest.schedule(
            center: center,
            request: PlannerEventSelfTest.request()
        )
    }
    #endif
}

#if DEBUG
/// 실기기에서 "OS 전달 경로 자체가 되는가"만 떼어 보기 위한 DEBUG 전용 테스트 알림.
///
/// 이 알림이 오는데 학습 알림이 안 오면 문제는 플래너 예약 판단에 있고,
/// 이것마저 오지 않으면 권한·기기 표시 설정을 봐야 한다.
///
/// 학습 알림과 **다른 네임스페이스**를 쓴다. 학습 알림 정리(`cancelAll`)가 이것을 지우지
/// 않고, 이것이 학습 알림 예약·설정·토큰·StudyPlan에 아무 영향을 주지 않게 하려는 것이다.
enum StudyReminderSelfTest {
    static let identifierPrefix = "dailyopic.debug.notification-test."
    static let delay: TimeInterval = 60

    static func isSelfTest(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    /// 60초 뒤 한 번. 반복하지 않는다.
    static func request(id: UUID = UUID()) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "DailyOPIc 알림 테스트"
        content.body = "60초 테스트 알림이 도착했어요."
        content.sound = .default
        return UNNotificationRequest(
            identifier: identifierPrefix + id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
    }

    enum Result: Equatable {
        case scheduled(Date)
        case unauthorized(String)
        case failed(String)

        var displayText: String {
            switch self {
            case let .scheduled(fireDate):
                "예약됨 · \(fireDate.formatted(date: .omitted, time: .standard))"
            case let .unauthorized(status): "권한 없음 (\(status))"
            case let .failed(error): "실패 · \(error)"
            }
        }
    }

    /// 권한이 있을 때만 예약한다. 여기서 권한 창을 새로 띄우지 않는다.
    static func schedule(
        center: UserNotificationCenterProtocol,
        request: UNNotificationRequest = Self.request(),
        now: Date = .now
    ) async -> Result {
        let status = await center.authorizationStatus()
        guard status.allowsScheduling else { return .unauthorized(status.telemetryValue) }
        if let failure = await center.add(request) { return .failed(failure.displayText) }
        return .scheduled(now.addingTimeInterval(delay))
    }
}

/// 개인 일정 알림 전달 경로만 떼어 보기 위한 DEBUG 전용 테스트 알림.
///
/// 실제 `PlannerEventRecord`도, 일정마다 고른 미리 알림도, 학습 알림도 건드리지 않는다.
/// 그래서 **또 다른** 네임스페이스를 쓴다 — 일정 알림 재조정이 이것을 지우면
/// "테스트 알림이 오나?"를 확인하는 동안 테스트 알림이 사라진다.
enum PlannerEventSelfTest {
    static let identifierPrefix = "dailyopic.debug.event-notification-test."

    static func isSelfTest(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func request(id: UUID = UUID()) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = PlannerEventReminderPolicy.title
        content.body = "60초 일정 알림 테스트가 도착했어요."
        content.sound = .default
        return UNNotificationRequest(
            identifier: identifierPrefix + id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: StudyReminderSelfTest.delay,
                repeats: false
            )
        )
    }
}
#endif

extension LocalNotificationRequest {
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
