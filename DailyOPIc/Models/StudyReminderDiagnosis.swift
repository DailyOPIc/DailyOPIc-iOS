import Foundation
import UserNotifications

/// 유료 알림 기능을 쓸 수 있는가 — **세 가지** 상태다.
///
/// `unknown`을 따로 두는 이유가 P7의 핵심이다. 앱이 막 켜졌을 때는 RevenueCat도 서버
/// capabilities도 아직 대답하지 않았고, 그때 `currentPlan`은 기본값 `.free`를 말한다.
/// 이 "아직 모름"을 `ineligible`로 다루면 재조정이 강등으로 착각해 유료 사용자의
/// 예약을 전부 지우고 로컬 의도까지 꺼 버린다(= 알림이 영영 오지 않는다).
///
/// 일정의 `nil` vs `[]`과 같은 규칙이다: 모를 때는 아무것도 하지 않는다.
///
/// P9부터 이 판정이 붙는 곳은 **개인 일정 알림**이다. 학습 알림은 전 플랜 공통이라
/// 자격 자체가 없다(항상 `.eligible`).
enum ReminderEligibility: String, Sendable, Equatable {
    case eligible
    case ineligible
    case unknown

    /// 플랜을 확인하기 전에는 `.unknown`이다. "무료로 보인다"와 "무료다"는 다르다.
    static func resolve(isEntitlementResolved: Bool, isCapable: Bool) -> ReminderEligibility {
        guard isEntitlementResolved else { return .unknown }
        return isCapable ? .eligible : .ineligible
    }
}

/// 알림이 예약됐는지, 안 됐다면 왜인지. 로그·진단 화면에 그대로 쓰는 고정 값이라
/// 사용자 콘텐츠(문구·메모·일정 제목·답변·UID)를 절대 담지 않는다.
enum ReminderSkipReason: String, Sendable, Equatable, CaseIterable {
    /// 플랜을 아직 확인하지 못했다. 예약도 삭제도 하지 않는다.
    case entitlementUnknown = "entitlement_unknown"
    /// 유료 기능인데 무료 플랜이다. **개인 일정 알림에만** 붙는다(학습 알림은 전 플랜 공통).
    case featureLocked = "feature_locked"
    /// 일정을 아직 모른다(계획 미로딩·저장소 미준비). 기존 예약은 건드리지 않는다.
    case scheduleUnknown = "schedule_unknown"
    /// 사용자가 앱에서 알림을 꺼 뒀다.
    case userDisabled = "user_disabled"
    /// 아직 시스템 권한을 물어본 적이 없다.
    case permissionNotDetermined = "permission_not_determined"
    /// 시스템 권한이 없다(거부됨).
    case permissionDenied = "permission_denied"
    /// 오늘 이미 학습을 한 번이라도 마쳤다. 배정량을 다 채웠는지는 보지 않는다(P9).
    case alreadyLearnedToday = "already_learned_today"
    /// 시험 당일에는 일반 학습 알림을 보내지 않는다.
    case examDay = "exam_day"
    /// 오늘의 공부 시간이 이미 지났다.
    case preferredTimePassed = "preferred_time_passed"
    /// 예약 지평(30일) 밖이다.
    case outsideHorizon = "outside_horizon"
    /// 이 일정은 "알림 없음"이다(또는 알림을 켠 일정이 하나도 없다).
    case userSelectedNone = "user_selected_none"
    /// 시간 없는 일정에는 알림을 걸 수 없다.
    case eventHasNoTime = "event_has_no_time"
    /// 알릴 시각이 이미 지났다.
    case triggerTimePassed = "trigger_time_passed"
    /// 알림을 만들었다. 여기까지 왔다면 앱 쪽 판단은 정상이다.
    case requestGenerated = "request_generated"

    /// DEBUG 진단 화면에 한국어로 보여줄 설명.
    var displayText: String {
        switch self {
        case .entitlementUnknown: "플랜 확인 전 (예약·삭제 안 함)"
        case .featureLocked: "무료 플랜 (유료 기능)"
        case .scheduleUnknown: "일정 미로딩 (예약 유지)"
        case .userDisabled: "앱에서 알림 꺼 둠"
        case .permissionNotDetermined: "시스템 권한 미요청"
        case .permissionDenied: "시스템 권한 없음"
        case .alreadyLearnedToday: "오늘 이미 학습함"
        case .examDay: "시험 당일"
        case .preferredTimePassed: "공부 시간이 이미 지남"
        case .outsideHorizon: "예약 지평 밖"
        case .userSelectedNone: "알림 없음으로 둠"
        case .eventHasNoTime: "시간 없는 일정"
        case .triggerTimePassed: "알림 시각이 이미 지남"
        case .requestGenerated: "예약함"
        }
    }
}

/// 하루치(또는 일정 하나) 판단 결과. 예약을 만들었거나, 만들지 않은 이유가 있거나 둘 중 하나다.
enum ReminderOutcome: Equatable, Sendable {
    case scheduled(LocalNotificationRequest)
    case skipped(ReminderSkipReason)

    var request: LocalNotificationRequest? {
        if case let .scheduled(request) = self { return request }
        return nil
    }

    var reason: ReminderSkipReason {
        switch self {
        case .scheduled: .requestGenerated
        case let .skipped(reason): reason
        }
    }
}

/// "왜 오늘 알림이 없지?"에 한 줄로 답하기 위한 값.
///
/// 실기기에서 플래너 전체를 눈으로 따라가지 않고도 원인을 좁히려고 만든다.
/// 담는 것은 개수·상태·시각뿐이고 알림 문구·메모·일정 제목·UID는 담지 않는다.
///
/// 학습 알림과 개인 일정 알림이 **각각** 하나씩 만든다. 둘을 한 값으로 합치면
/// 어느 쪽이 실패했는지가 사라진다.
struct ReminderDiagnosis: Equatable, Sendable {
    let reason: ReminderSkipReason
    let eligibility: ReminderEligibility
    /// 앱 안의 "알림 받기" 의도(시스템 권한과 별개).
    let isEnabled: Bool
    let authorization: UNAuthorizationStatus
    /// 지금 예약돼 있어야 할 알림 수. `nil`은 일정을 아직 모른다는 뜻이다.
    let desiredCount: Int?
    /// 오늘 실제로 마친 학습 세트 수(학습 알림 진단에만 쓴다).
    let todayCompletedSets: Int?

    var isScheduledToday: Bool { reason == .requestGenerated }

    /// 로그 한 줄. 고정 값만 이어 붙인다.
    var logLine: String {
        "reason=\(reason.rawValue) eligibility=\(eligibility.rawValue) "
        + "enabled=\(isEnabled) status=\(authorization.telemetryValue) "
        + "desired=\(desiredCount.map(String.init) ?? "unknown")"
    }

    /// 재조정이 실제로 밟는 순서 그대로 판정한다. 순서를 바꾸면 진단이
    /// "코드가 한 일"이 아니라 "사람이 보기 좋은 이유"를 말하게 되어 쓸모가 없어진다.
    static func make(
        eligibility: ReminderEligibility,
        isEnabled: Bool,
        authorization: UNAuthorizationStatus,
        desired: [LocalNotificationRequest]?,
        todayOutcome: ReminderOutcome?,
        todayCompletedSets: Int? = nil
    ) -> ReminderDiagnosis {
        func result(_ reason: ReminderSkipReason) -> ReminderDiagnosis {
            ReminderDiagnosis(
                reason: reason,
                eligibility: eligibility,
                isEnabled: isEnabled,
                authorization: authorization,
                desiredCount: desired?.count,
                todayCompletedSets: todayCompletedSets
            )
        }
        switch eligibility {
        case .unknown: return result(.entitlementUnknown)
        case .ineligible: return result(.featureLocked)
        case .eligible: break
        }
        guard desired != nil else { return result(.scheduleUnknown) }
        guard isEnabled else { return result(.userDisabled) }
        guard authorization.allowsScheduling else {
            return result(
                authorization == .denied ? .permissionDenied : .permissionNotDetermined
            )
        }
        return result(todayOutcome?.reason ?? .scheduleUnknown)
    }
}

/// 실제로 iOS에 남아 있는 우리 알림. 앱이 **원한** 목록이 아니라 OS가 **받아들인** 것이다.
/// 둘은 갈라질 수 있고(예약 실패·다른 재조정이 지움), 갈라진 순간이 곧 버그다.
struct PendingReminders: Equatable, Sendable {
    let count: Int
    /// 가장 먼저 울릴 예약의 식별자 꼬리표. 학습 알림은 "yyyy-MM-dd"다.
    let nextLocalDate: String?
    /// 트리거가 계산한 다음 발화 시각. `nil`이면 iOS는 그 알림을 영원히 울리지 않는다.
    let nextTriggerDate: Date?
    /// 트리거에 붙은 타임존 식별자. 기기 타임존과 다르면 시각이 밀린다.
    let nextTriggerTimeZone: String?

    static let empty = PendingReminders(
        count: 0,
        nextLocalDate: nil,
        nextTriggerDate: nil,
        nextTriggerTimeZone: nil
    )

    /// 대기 중인 `UNNotificationRequest`에서 만든다. 문구는 읽지 않는다.
    /// 네임스페이스를 받는 이유: 학습 알림과 일정 알림을 **각각** 세야 한다.
    init(
        requests: [UNNotificationRequest],
        identifierPrefix: String = StudyReminderPolicy.identifierPrefix
    ) {
        let triggers = requests.compactMap { request -> (String, UNCalendarNotificationTrigger, Date)? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fire = trigger.nextTriggerDate() else { return nil }
            return (request.identifier, trigger, fire)
        }
        let next = triggers.min { $0.2 < $1.2 }
        count = requests.count
        nextLocalDate = next?.0.replacingOccurrences(of: identifierPrefix, with: "")
        nextTriggerDate = next?.2
        nextTriggerTimeZone = next?.1.dateComponents.timeZone?.identifier
    }

    init(count: Int, nextLocalDate: String?, nextTriggerDate: Date?, nextTriggerTimeZone: String?) {
        self.count = count
        self.nextLocalDate = nextLocalDate
        self.nextTriggerDate = nextTriggerDate
        self.nextTriggerTimeZone = nextTriggerTimeZone
    }
}

/// 예약 실패 사유. `UNUserNotificationCenter.add`가 던진 오류를 **버리지 않기** 위한 값이다.
/// 도메인·코드만 남기고 문구·식별자는 남기지 않는다.
struct NotificationAddFailure: Equatable, Sendable {
    let domain: String
    let code: Int

    var displayText: String { "\(domain) #\(code)" }
}
