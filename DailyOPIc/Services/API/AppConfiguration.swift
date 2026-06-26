import Foundation

enum AppConfiguration {
    nonisolated static var apiBaseURL: URL {
        resolvedAPIBaseURL.url
    }

    nonisolated static var apiBaseURLSource: String {
        resolvedAPIBaseURL.source
    }

    nonisolated static var rewardedAdUnitID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GADRewardedAdUnitID") as? String
        return value?.isEmpty == false ? value : nil
    }

    private static var resolvedAPIBaseURL: (url: URL, source: String) {
        if let url = configuredURL(ProcessInfo.processInfo.environment["DAILYOPIC_API_BASE_URL"]) {
            return (url, "Scheme environment DAILYOPIC_API_BASE_URL")
        }

        #if DEBUG
        if let url = debugServerURLFromEnvironment() {
            return (url, "Scheme environment DAILYOPIC_DEBUG_SERVER_HOST")
        }
        #endif

        if let value = Bundle.main.object(forInfoDictionaryKey: "DAILYOPIC_API_BASE_URL") as? String,
           let url = configuredURL(value) {
            return (url, "Info.plist DAILYOPIC_API_BASE_URL")
        }

        #if DEBUG
        return (URL(string: "http://172.20.10.2:8000")!, "Debug fallback")
        #else
        return (URL(string: "https://REPLACE_WITH_CLOUD_RUN_URL")!, "Release fallback")
        #endif
    }

    private static func debugServerURLFromEnvironment() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let host = cleaned(environment["DAILYOPIC_DEBUG_SERVER_HOST"]) else {
            return nil
        }
        let port = cleaned(environment["DAILYOPIC_DEBUG_SERVER_PORT"]) ?? "8000"
        return configuredURL("http://\(host):\(port)")
    }

    private static func configuredURL(_ value: String?) -> URL? {
        guard let value = cleaned(value),
              !value.contains("$("),
              let url = URL(string: value),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
