import Foundation
import Security

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

actor AuthenticationService {
    enum AuthError: LocalizedError {
        case appCheckUnavailable
        case firebaseAuthUnavailable
        case installationIDUnavailable

        var errorDescription: String? {
            switch self {
            case .appCheckUnavailable:
                "Firebase App Check 토큰을 발급받지 못했습니다. 실제 기기의 App Attest entitlement와 Firebase Console 설정을 확인해 주세요."
            case .firebaseAuthUnavailable:
                "안전한 사용자 인증을 준비하지 못했습니다. 네트워크 연결을 확인하고 다시 시도해 주세요."
            case .installationIDUnavailable:
                "기기 식별자를 준비할 수 없습니다. Keychain 접근 상태를 확인해 주세요."
            }
        }
    }

    private let keychainService = "com.mark.opicmobile.dailyopic"
    private let installationIDAccount = "installation_id"

    func prepareForLaunch() async throws {
        _ = try installationID()
        _ = try await firebaseUserID()
        _ = try await appCheckToken()
    }

    /// RevenueCat 등에서 서버와 동일한 사용자 식별자(Firebase uid)로 로그인하기 위한 접근자.
    func currentUserID() async throws -> String {
        try await firebaseUserID()
    }

    func headers(forceRefreshAuthToken: Bool = false) async throws -> [String: String] {
        var values = [
            "X-DailyOPIc-User-ID": try installationID(),
            "X-Firebase-AppCheck": try await appCheckToken(),
            "Authorization": "Bearer \(try await firebaseIDToken(forceRefresh: forceRefreshAuthToken))"
        ]
        values["X-App-Version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        values["X-DailyOPIc-Capabilities"] = "operations-v1,mock-session-v2,evaluation-rubric-v2,onboarding-v2"
        return values
    }

    private func firebaseUserID() async throws -> String {
        #if canImport(FirebaseAuth) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { throw AuthError.firebaseAuthUnavailable }
        if let current = Auth.auth().currentUser { return current.uid }
        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let user = result?.user {
                    continuation.resume(returning: user.uid)
                } else {
                    continuation.resume(throwing: error ?? AuthError.firebaseAuthUnavailable)
                }
            }
        }
        #else
        throw AuthError.firebaseAuthUnavailable
        #endif
    }

    private func firebaseIDToken(forceRefresh: Bool) async throws -> String {
        #if canImport(FirebaseAuth)
        _ = try await firebaseUserID()
        guard let user = Auth.auth().currentUser else { throw AuthError.firebaseAuthUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: error ?? AuthError.firebaseAuthUnavailable)
                }
            }
        }
        #else
        throw AuthError.firebaseAuthUnavailable
        #endif
    }

    private func installationID() throws -> String {
        if let existing = try readInstallationID() {
            return existing
        }
        let value = UUID().uuidString
        try saveInstallationID(value)
        return value
    }

    private func readInstallationID() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: installationIDAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              UUID(uuidString: value) != nil else {
            throw AuthError.installationIDUnavailable
        }
        return value
    }

    private func saveInstallationID(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: installationIDAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw AuthError.installationIDUnavailable
        }
    }

    private func appCheckToken() async throws -> String {
        #if canImport(FirebaseAppCheck) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else {
            throw AuthError.appCheckUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            AppCheck.appCheck().token(forcingRefresh: false) { result, error in
                if let result {
                    continuation.resume(returning: result.token)
                } else {
                    continuation.resume(throwing: error ?? AuthError.appCheckUnavailable)
                }
            }
        }
        #else
        throw AuthError.appCheckUnavailable
        #endif
    }
}
