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

    /// 설정 화면의 계정 상태. 익명이면 아직 로그인 전이다.
    struct AccountSummary: Sendable, Equatable {
        let isAnonymous: Bool
        let providerIDs: [String]
        let email: String?

        var hasApple: Bool { providerIDs.contains("apple.com") }
        var hasGoogle: Bool { providerIDs.contains("google.com") }
    }

    enum LinkOutcome: Sendable {
        /// 지금 계정(uid 그대로)에 로그인 수단이 붙었다. 기록·구독이 그대로 남는다.
        case linked
        /// 이 로그인 수단은 이미 다른 계정(예: 웹에서 먼저 가입)에 쓰이고 있다.
        /// 사용자가 동의하면 `switchToExistingAccount()`로 그 계정으로 옮긴다.
        case accountExists
    }

    /// 이미 쓰이는 로그인 수단을 사용자 확인까지 잠시 보관한다(Apple 자격은 재사용이 안 돼
    /// Firebase가 돌려준 갱신 자격을 쓴다).
    private var pendingCredential: AuthCredential?

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

    func accountSummary() -> AccountSummary? {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { return nil }
        let providers = user.providerData.map(\.providerID)
        return AccountSummary(
            isAnonymous: user.isAnonymous,
            providerIDs: providers,
            email: user.email ?? user.providerData.compactMap(\.email).first
        )
        #else
        return nil
        #endif
    }

    #if canImport(FirebaseAuth)
    func linkApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> LinkOutcome {
        try await link(OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName))
    }

    func linkGoogle(idToken: String, accessToken: String) async throws -> LinkOutcome {
        try await link(GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken))
    }

    /// 익명 계정에 로그인 수단을 붙인다. uid가 바뀌지 않으므로 서버 기록·RevenueCat 구독이 그대로다.
    private func link(_ credential: AuthCredential) async throws -> LinkOutcome {
        _ = try await firebaseUserID()
        guard let user = Auth.auth().currentUser else { throw AuthError.firebaseAuthUnavailable }
        do {
            _ = try await user.link(with: credential)
            pendingCredential = nil
            return .linked
        } catch let error as NSError where error.code == AuthErrorCode.providerAlreadyLinked.rawValue {
            return .linked
        } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue
            || error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
            pendingCredential = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
            return .accountExists
        }
    }

    /// 이미 있는 계정으로 옮긴다. 이 기기의 익명 계정(uid)은 버려지고 새 uid를 돌려준다.
    func switchToExistingAccount() async throws -> String {
        guard let credential = pendingCredential else { throw AuthError.firebaseAuthUnavailable }
        let result = try await Auth.auth().signIn(with: credential)
        pendingCredential = nil
        return result.user.uid
    }

    /// Sign in with Apple로 연결된 계정을 지울 때 Apple 토큰을 폐기한다(App Store 요구 사항).
    func revokeAppleToken(authorizationCode: String) async throws {
        try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
    }

    /// 계정 삭제 뒤 로그아웃. 다음 요청에서 새 익명 계정이 만들어진다.
    func signOutAfterDeletion() throws {
        pendingCredential = nil
        try Auth.auth().signOut()
    }
    #endif

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
