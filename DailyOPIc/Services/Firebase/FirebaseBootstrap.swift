import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum FirebaseBootstrap {
    static func configure() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.allApps?["__FIRAPP_DEFAULT"] == nil else {
            log("Firebase is already configured.")
            return
        }

        guard let options = FirebaseOptions.defaultOptions() else {
            log("GoogleService-Info.plist was not found in the app bundle. Firebase was not configured.")
            return
        }

        configureAppCheck()
        FirebaseApp.configure(options: options)

        log("Firebase configured. projectID=\(options.projectID ?? "unknown"), bundleID=\(Bundle.main.bundleIdentifier ?? "unknown")")
        verifyAppCheckToken()
        #else
        log("FirebaseCore is not linked. Firebase was not configured.")
        #endif
    }

    #if canImport(FirebaseAppCheck)
    private static func configureAppCheck() {
        #if targetEnvironment(simulator)
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        let provider = "Debug provider"
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        let provider = "App Attest"
        #endif

        log("App Check provider configured before FirebaseApp.configure(). build=\(buildConfiguration), target=\(runtimeTarget), provider=\(provider)")
        logAppAttestSupport()
    }

    private static func verifyAppCheckToken() {
        Task {
            do {
                let token = try await AppCheck.appCheck().token(forcingRefresh: shouldForceRefreshAppCheckToken)
                let ttlSeconds = max(0, Int(token.expirationDate.timeIntervalSinceNow))
                log("App Check token issued. tokenLength=\(token.token.count), expiresAt=\(iso8601.string(from: token.expirationDate)), ttlSeconds=\(ttlSeconds), forcingRefresh=\(shouldForceRefreshAppCheckToken)")
            } catch {
                log("App Check token request failed. error=\(error.localizedDescription)")
            }
        }
    }

    private static var shouldForceRefreshAppCheckToken: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func logAppAttestSupport() {
        #if canImport(DeviceCheck) && !targetEnvironment(simulator)
        if #available(iOS 14.0, *) {
            log("Device App Attest support=\(DCAppAttestService.shared.isSupported)")
        }
        #endif
    }
    #else
    private static func configureAppCheck() {
        log("FirebaseAppCheck is not linked. App Check provider was not configured.")
    }

    private static func verifyAppCheckToken() {}
    #endif

    private static var buildConfiguration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    private static var runtimeTarget: String {
        #if targetEnvironment(simulator)
        "Simulator"
        #else
        "Device"
        #endif
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func log(_ message: String) {
        print("[DailyOPIc][Firebase] \(message)")
    }
}
