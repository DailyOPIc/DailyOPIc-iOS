import Foundation

enum AppConfiguration {
    enum ConfigurationError: LocalizedError {
        case invalidProductionAPI
        case missingProductionAdUnit
        case sampleAdUnitInRelease

        var errorDescription: String? {
            switch self {
            case .invalidProductionAPI: "프로덕션 API 주소가 올바르게 설정되지 않았습니다."
            case .missingProductionAdUnit: "프로덕션 광고 unit ID가 설정되지 않았습니다."
            case .sampleAdUnitInRelease: "Release 빌드에 Google sample 광고 unit ID를 사용할 수 없습니다."
            }
        }
    }
    nonisolated static var apiBaseURL: URL {
        resolvedAPIBaseURL.url
    }

    nonisolated static var apiBaseURLSource: String {
        resolvedAPIBaseURL.source
    }

    nonisolated static var rewardedAdUnitID: String? {
        configuredString(Bundle.main.object(forInfoDictionaryKey: "GADRewardedAdUnitID") as? String)
    }

    nonisolated static var bannerAdUnitID: String? {
        configuredString(Bundle.main.object(forInfoDictionaryKey: "GADBannerAdUnitID") as? String)
    }

    nonisolated static var privacyPolicyURL: URL? {
        configuredURL(Bundle.main.object(forInfoDictionaryKey: "DAILYOPIC_PRIVACY_POLICY_URL") as? String)
    }

    nonisolated static func validateForLaunch() throws {
        #if !DEBUG
        let url = apiBaseURL
        guard url.scheme == "https",
              let host = url.host,
              !host.contains("REPLACE_WITH") else {
            throw ConfigurationError.invalidProductionAPI
        }
        guard let rewardedAdUnitID, let bannerAdUnitID else {
            throw ConfigurationError.missingProductionAdUnit
        }
        let samplePrefix = "ca-app-pub-3940256099942544/"
        guard !rewardedAdUnitID.hasPrefix(samplePrefix),
              !bannerAdUnitID.hasPrefix(samplePrefix) else {
            throw ConfigurationError.sampleAdUnitInRelease
        }
        #endif
    }

    #if DEBUG
    nonisolated static var gadTestDeviceIdentifiers: [String] {
        let environment = configuredList(ProcessInfo.processInfo.environment["GAD_TEST_DEVICE_IDS"])
        if !environment.isEmpty { return environment }
        return configuredList(Bundle.main.object(forInfoDictionaryKey: "GADTestDeviceIdentifiers") as? String)
    }

    nonisolated static var umpDebugTestDeviceIdentifiers: [String] {
        configuredList(ProcessInfo.processInfo.environment["UMP_DEBUG_TEST_DEVICE_IDS"])
    }
    #endif

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
        guard let value = configuredString(value),
              !value.contains("$("),
              let url = URL(string: value),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func configuredString(_ value: String?) -> String? {
        guard let value = cleaned(value), !value.contains("$(") else {
            return nil
        }
        return value
    }

    #if DEBUG
    private static func configuredList(_ value: String?) -> [String] {
        guard let value = configuredString(value) else {
            return []
        }
        return value
            .split { character in
                character == "," || character == ";" || character.isWhitespace || character.isNewline
            }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
    #endif

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
