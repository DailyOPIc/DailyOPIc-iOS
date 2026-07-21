import Foundation
import SwiftUI
import Combine

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

@MainActor
final class AdService: NSObject, ObservableObject {
    enum State: Equatable { case idle, loading, ready, presenting, verifying, failed(String) }
    enum AdError: LocalizedError {
        case unavailable
        case notEarned
        case privacyOptionsUnavailable
        case privacyOptionsNotRequired
        case busy

        var errorDescription: String? {
            switch self {
            case .unavailable: "리워드 광고를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요."
            case .notEarned: "광고를 끝까지 시청해야 계속할 수 있습니다."
            case .privacyOptionsUnavailable: "광고 개인정보 설정을 열 수 없습니다. 잠시 후 다시 시도해 주세요."
            case .privacyOptionsNotRequired: "광고 개인정보 설정 메뉴를 지금은 열 수 없습니다."
            case .busy: "다른 광고를 처리하고 있습니다. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    @Published private(set) var canRequestAds = false
    @Published private(set) var canShowPrivacyOptions = false
    @Published private(set) var privacyOptionsStatusText = "광고 개인정보 설정 상태를 확인 중입니다."
    @Published private(set) var state: State = .idle
    private var activeNonce: String?

    #if canImport(GoogleMobileAds)
    private var rewardedAd: RewardedAd?
    private var rewardedPresentationDelegate: RewardedAdPresentationDelegate?
    private var didStartMobileAds = false
    #endif

    func prepare() async {
        #if canImport(UserMessagingPlatform)
        let parameters = consentRequestParameters()
        print("[DailyOPIc][UMP] request consent info update")
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    print("[DailyOPIc][UMP] consent info update failed. error=\(error.localizedDescription)")
                } else {
                    print(
                        "[DailyOPIc][UMP] consent info updated. "
                        + "status=\(Self.describe(ConsentInformation.shared.consentStatus)) "
                        + "formStatus=\(Self.describe(ConsentInformation.shared.formStatus)) "
                        + "privacyOptions=\(Self.describe(ConsentInformation.shared.privacyOptionsRequirementStatus))"
                    )
                }
                continuation.resume()
            }
        }
        updatePrivacyOptionsStatus()
        do {
            let wasRequired = ConsentInformation.shared.consentStatus == .required
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
            print("[DailyOPIc][UMP] consent form checked. wasRequired=\(wasRequired)")
        } catch {
            print("[DailyOPIc][UMP] consent form failed. error=\(error.localizedDescription)")
        }
        canRequestAds = ConsentInformation.shared.canRequestAds
        updatePrivacyOptionsStatus()
        print("[DailyOPIc][UMP] canRequestAds=\(canRequestAds)")
        #else
        canRequestAds = true
        canShowPrivacyOptions = false
        privacyOptionsStatusText = "User Messaging Platform SDK가 포함되지 않았습니다."
        print("[DailyOPIc][UMP] UserMessagingPlatform unavailable. canRequestAds=true")
        #endif

        #if canImport(GoogleMobileAds)
        configureGADTestDevicesIfNeeded()
        guard canRequestAds else {
            print("[DailyOPIc][Ads] Mobile Ads start skipped because canRequestAds=false")
            return
        }
        guard !didStartMobileAds else {
            print("[DailyOPIc][Ads] Mobile Ads already started")
            return
        }
        didStartMobileAds = true
        await withCheckedContinuation { continuation in
            MobileAds.shared.start { _ in continuation.resume() }
        }
        print("[DailyOPIc][Ads] Mobile Ads started")
        #endif
    }

    func showRewardedAd(userIdentifier: String, customData: String) async throws {
        guard state == .idle || {
            if case .failed = state { return true }
            return false
        }() else { throw AdError.busy }
        state = .loading
        activeNonce = customData
        defer {
            activeNonce = nil
            if case .failed = state { } else { state = .idle }
        }
        #if canImport(GoogleMobileAds)
        guard canRequestAds else {
            throw AdError.unavailable
        }
        guard let unitID = AppConfiguration.rewardedAdUnitID else {
            throw AdError.unavailable
        }

        print("[DailyOPIc][Ads] loading rewarded ad. unitID=\(unitID)")
        let ad: RewardedAd
        do {
            ad = try await RewardedAd.load(with: unitID, request: Request())
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
        guard activeNonce == customData else { throw CancellationError() }
        state = .ready
        let options = ServerSideVerificationOptions()
        options.userIdentifier = userIdentifier
        options.customRewardText = customData
        ad.serverSideVerificationOptions = options
        rewardedAd = ad
        let earned = await withCheckedContinuation { continuation in
            let delegate = RewardedAdPresentationDelegate { earned in
                continuation.resume(returning: earned)
            }
            rewardedPresentationDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            state = .presenting
            ad.present(from: nil) {
                delegate.markRewardEarned()
            }
        }
        rewardedPresentationDelegate = nil
        rewardedAd = nil
        guard earned else { throw AdError.notEarned }
        state = .verifying
        #else
        try await Task.sleep(for: .milliseconds(500))
        state = .verifying
        #endif
    }

    func presentPrivacyOptions() async throws {
        #if canImport(UserMessagingPlatform)
        updatePrivacyOptionsStatus()
        guard canShowPrivacyOptions else {
            print("[DailyOPIc][UMP] privacy options skipped. \(privacyOptionsStatusText)")
            throw AdError.privacyOptionsNotRequired
        }
        guard let viewController = UIApplication.shared.topViewController else {
            throw AdError.privacyOptionsUnavailable
        }
        try await ConsentForm.presentPrivacyOptionsForm(from: viewController)
        updatePrivacyOptionsStatus()
        print("[DailyOPIc][UMP] privacy options form presented")
        #else
        throw AdError.privacyOptionsUnavailable
        #endif
    }

    #if canImport(UserMessagingPlatform)
    private func consentRequestParameters() -> RequestParameters {
        let parameters = RequestParameters()

        #if DEBUG
        let identifiers = AppConfiguration.umpDebugTestDeviceIdentifiers
        if !identifiers.isEmpty {
            let settings = DebugSettings()
            settings.testDeviceIdentifiers = identifiers
            settings.geography = .EEA
            parameters.debugSettings = settings
            print("[DailyOPIc][UMP] debug test devices configured. count=\(identifiers.count) geography=EEA")
        } else {
            print("[DailyOPIc][UMP] debug test devices not configured")
        }
        #endif

        return parameters
    }

    private func updatePrivacyOptionsStatus() {
        let status = ConsentInformation.shared.privacyOptionsRequirementStatus
        switch status {
        case .required:
            canShowPrivacyOptions = true
            privacyOptionsStatusText = "광고 개인정보 설정을 열 수 있습니다."
        case .notRequired:
            canShowPrivacyOptions = false
            privacyOptionsStatusText = ""
        case .unknown:
            canShowPrivacyOptions = false
            privacyOptionsStatusText = "광고 개인정보 설정 상태를 확인 중입니다."
        @unknown default:
            canShowPrivacyOptions = false
            privacyOptionsStatusText = "광고 개인정보 설정 상태를 확인할 수 없습니다."
        }
        print(
            "[DailyOPIc][UMP] privacy options status="
            + "\(Self.describe(status)) canShow=\(canShowPrivacyOptions)"
        )
    }

    nonisolated private static func describe(_ status: ConsentStatus) -> String {
        switch status {
        case .unknown: "unknown"
        case .required: "required"
        case .notRequired: "notRequired"
        case .obtained: "obtained"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    nonisolated private static func describe(_ status: FormStatus) -> String {
        switch status {
        case .unknown: "unknown"
        case .available: "available"
        case .unavailable: "unavailable"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    nonisolated private static func describe(_ status: PrivacyOptionsRequirementStatus) -> String {
        switch status {
        case .unknown: "unknown"
        case .required: "required"
        case .notRequired: "notRequired"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }
    #endif

    #if canImport(GoogleMobileAds)
    private func configureGADTestDevicesIfNeeded() {
        #if DEBUG
        let identifiers = AppConfiguration.gadTestDeviceIdentifiers
        if identifiers.isEmpty {
            print("[DailyOPIc][Ads] GAD test devices not configured")
        } else {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = identifiers
            print("[DailyOPIc][Ads] GAD test devices configured. count=\(identifiers.count)")
        }
        #endif
    }
    #endif
}

#if canImport(GoogleMobileAds)
@MainActor
private final class RewardedAdPresentationDelegate: NSObject, FullScreenContentDelegate {
    private let completion: (Bool) -> Void
    private var didComplete = false
    private var didEarnReward = false

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func markRewardEarned() {
        didEarnReward = true
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        print("[DailyOPIc][Ads] rewarded ad failed to present. error=\(error.localizedDescription)")
        complete(earned: false)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        complete(earned: didEarnReward)
    }

    private func complete(earned: Bool) {
        guard !didComplete else { return }
        didComplete = true
        completion(earned)
    }
}
#endif

private extension UIApplication {
    var topViewController: UIViewController? {
        connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
    }
}
