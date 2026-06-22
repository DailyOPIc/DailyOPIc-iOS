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
    enum AdError: LocalizedError {
        case unavailable
        case notEarned

        var errorDescription: String? {
            switch self {
            case .unavailable: "리워드 광고를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요."
            case .notEarned: "광고를 끝까지 시청해야 평가를 계속할 수 있습니다."
            }
        }
    }

    @Published private(set) var canRequestAds = false

    #if canImport(GoogleMobileAds)
    private var rewardedAd: RewardedAd?
    #endif

    func prepare() async {
        #if canImport(UserMessagingPlatform)
        let parameters = RequestParameters()
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { _ in
                continuation.resume()
            }
        }
        try? await ConsentForm.loadAndPresentIfRequired(from: nil)
        canRequestAds = ConsentInformation.shared.canRequestAds
        #else
        canRequestAds = true
        #endif

        #if canImport(GoogleMobileAds)
        guard canRequestAds else { return }
        await withCheckedContinuation { continuation in
            MobileAds.shared.start { _ in continuation.resume() }
        }
        #endif
    }

    func showRewardedAd(userIdentifier: String, customData: String) async throws {
        #if canImport(GoogleMobileAds)
        guard canRequestAds else { throw AdError.unavailable }
        let unitID: String
        #if DEBUG
        unitID = "ca-app-pub-3940256099942544/1712485313"
        #else
        guard let configured = AppConfiguration.rewardedAdUnitID else {
            throw AdError.unavailable
        }
        unitID = configured
        #endif

        let ad = try await RewardedAd.load(with: unitID, request: Request())
        let options = ServerSideVerificationOptions()
        options.userIdentifier = userIdentifier
        options.customRewardText = customData
        ad.serverSideVerificationOptions = options
        rewardedAd = ad
        let earned = await withCheckedContinuation { continuation in
            ad.present(from: nil) {
                continuation.resume(returning: true)
            }
        }
        rewardedAd = nil
        guard earned else { throw AdError.notEarned }
        #else
        try await Task.sleep(for: .milliseconds(500))
        #endif
    }

    func presentPrivacyOptions() async {
        #if canImport(UserMessagingPlatform)
        try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
        #endif
    }
}
