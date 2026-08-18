import Foundation
import UserNotifications

/// 학습 알림을 쓸 수 있는 플랜인가 — **세 가지** 상태다.
///
/// `unknown`을 따로 두는 이유가 P7의 핵심이다. 앱이 막 켜졌을 때는 RevenueCat도 서버
/// capabilities도 아직 대답하지 않았고, 그때 `currentPlan`은 기본값 `.free`를 말한다.
/// 이 "아직 모름"을 `ineligible`로 다루면 재조정이 강등으로 착각해 유료 사용자의
/// 예약을 전부 지우고 로컬 의도까지 꺼 버린다(= 알림이 영영 오지 않는다).
///
/// 일정의 `nil` vs `[]`과 같은 규칙이다: 모를 때는 아무것도 하지 않는다.
enum StudyReminderEligibility: String, Sendable, Equatable {
    case eligible
    case ineligible
    case unknown

    /// 플랜을 확인하기 전에는 `.unknown`이다. "무료로 보인다"와 "무료다"는 다르다.
    static func resolve(
        isEntitlementResolved: Bool,
        canUseStudyReminder: Bool
    ) -> StudyReminderEligibility {
        guard isEntitlementResolved else { return .unknown }
        return canUseStudyReminder ? .eligible : .ineligible
    }
}

/// 오늘 알림이 예약됐는지, 안 됐다면 왜인지. 로그·진단 화면에 그대로 쓰는 고정 값이라
/// 사용자 콘텐츠(문구·메모·답변·UID)를 절대 담지 않는다.
enum StudyReminderSkipReason: String, Sendable, Equatable, CaseIterable {
    /// 플랜을 아직 확인하지 못했다. 예약도 삭제도 하지 않는다.
    case eligibilityUnknown = "eligibility_unknown"
    /// 무료 플랜(또는 강등). 유료 기능이라 예약하지 않는다.
    case featureLocked = "feature_locked"
    /// 일정을 아직 모른다(계획 미로딩·저장소 미준비). 기존 예약은 건드리지 않는다.
    case scheduleUnknown = "schedule_unknown"
    /// 사용자가 앱에서 알림을 꺼 뒀다.
    case userDisabled = "user_disabled"
    /// 아직 시스템 권한을 물어본 적이 없다.
    case permissionNotDetermined = "permission_not_determined"
    /// 시스템 권한이 없다(거부됨).
    case permissionDenied = "permission_denied"
    /// 오늘은 휴식일이다.
    case restDay = "rest_day"
    /// 오늘 배정량을 이미 다 했다(또는 권장 학습량을 모두 마쳤다).
    case targetComplete = "target_complete"
    /// 오늘은 계획에 학습량이 배정되지 않았다.
    case noTarget = "no_target"
    /// 시험 당일에는 학습 숙제 알림을 보내지 않는다.
    case examDay = "exam_day"
    /// 오늘의 공부 시간이 이미 지났다.
    case preferredTimePassed = "preferred_time_passed"
    /// 예약 지평(30일) 밖이다.
    case outsideHorizon = "outside_horizon"
    /// 알림을 만들었다. 여기까지 왔다면 앱 쪽 판단은 정상이다.
    case requestGenerated = "request_generated"

    /// DEBUG 진단 화면에 한국어로 보여줄 설명.
    var displayText: String {
        switch self {
        case .eligibilityUnknown: "플랜 확인 전 (예약·삭제 안 함)"
        case .featureLocked: "무료 플랜 (유료 기능)"
        case .scheduleUnknown: "일정 미로딩 (예약 유지)"
        case .userDisabled: "앱에서 알림 꺼 둠"
        case .permissionNotDetermined: "시스템 권한 미요청"
        case .permissionDenied: "시스템 권한 없음"
        case .restDay: "오늘은 휴식일"
        case .targetComplete: "오늘 배정량 완료"
        case .noTarget: "오늘 배정량 없음"
        case .examDay: "시험 당일"
        case .preferredTimePassed: "공부 시간이 이미 지남"
        case .outsideHorizon: "예약 지평 밖"
        case .requestGenerated: "예약함"
        }
    }
}

/// 하루치 판단 결과. 예약을 만들었거나, 만들지 않은 이유가 있거나 둘 중 하나다.
enum StudyReminderOutcome: Equatable, Sendable {
    case scheduled(StudyReminderRequest)
    case skipped(StudyReminderSkipReason)

    var request: StudyReminderRequest? {
        if case let .scheduled(request) = self { return request }
        return nil
    }

    var reason: StudyReminderSkipReason {
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
struct StudyReminderDiagnosis: Equatable, Sendable {
    let reason: StudyReminderSkipReason
    let eligibility: StudyReminderEligibility
    /// 앱 안의 "알림 받기" 의도(시스템 권한과 별개).
    let isEnabled: Bool
    let authorization: UNAuthorizationStatus
    /// 지금 예약돼 있어야 할 알림 수. `nil`은 일정을 아직 모른다는 뜻이다.
    let desiredCount: Int?
    let todayTargetSets: Int?
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
        eligibility: StudyReminderEligibility,
        isEnabled: Bool,
        authorization: UNAuthorizationStatus,
        desired: [StudyReminderRequest]?,
        todayOutcome: StudyReminderOutcome?,
        todayTargetSets: Int? = nil,
        todayCompletedSets: Int? = nil
    ) -> StudyReminderDiagnosis {
        func result(_ reason: StudyReminderSkipReason) -> StudyReminderDiagnosis {
            StudyReminderDiagnosis(
                reason: reason,
                eligibility: eligibility,
                isEnabled: isEnabled,
                authorization: authorization,
                desiredCount: desired?.count,
                todayTargetSets: todayTargetSets,
                todayCompletedSets: todayCompletedSets
            )
        }
        switch eligibility {
        case .unknown: return result(.eligibilityUnknown)
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
struct PendingStudyReminders: Equatable, Sendable {
    let count: Int
    /// 가장 먼저 울릴 예약의 식별자 날짜 부분("yyyy-MM-dd").
    let nextLocalDate: String?
    /// 트리거가 계산한 다음 발화 시각. `nil`이면 iOS는 그 알림을 영원히 울리지 않는다.
    let nextTriggerDate: Date?
    /// 트리거에 붙은 타임존 식별자. 기기 타임존과 다르면 시각이 밀린다.
    let nextTriggerTimeZone: String?

    static let empty = PendingStudyReminders(
        count: 0,
        nextLocalDate: nil,
        nextTriggerDate: nil,
        nextTriggerTimeZone: nil
    )

    /// 대기 중인 `UNNotificationRequest`에서 만든다. 문구는 읽지 않는다.
    init(requests: [UNNotificationRequest]) {
        let triggers = requests.compactMap { request -> (String, UNCalendarNotificationTrigger, Date)? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fire = trigger.nextTriggerDate() else { return nil }
            return (request.identifier, trigger, fire)
        }
        let next = triggers.min { $0.2 < $1.2 }
        count = requests.count
        nextLocalDate = next?.0.replacingOccurrences(
            of: StudyReminderPolicy.identifierPrefix,
            with: ""
        )
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
struct StudyReminderAddFailure: Equatable, Sendable {
    let domain: String
    let code: Int

    var displayText: String { "\(domain) #\(code)" }
}
