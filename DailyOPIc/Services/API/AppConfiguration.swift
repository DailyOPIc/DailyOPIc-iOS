import Foundation

enum AppConfiguration {
    nonisolated static var apiBaseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "DAILYOPIC_API_BASE_URL") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return URL(string: "http://127.0.0.1:8000")!
    }

    nonisolated static var rewardedAdUnitID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GADRewardedAdUnitID") as? String
        return value?.isEmpty == false ? value : nil
    }
}
