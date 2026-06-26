import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore
#endif
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

actor AuthenticationService {
    enum AuthError: LocalizedError {
        case unavailable
        case appCheckUnavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "익명 인증을 준비할 수 없습니다. 네트워크와 Firebase 설정을 확인해 주세요."
            case .appCheckUnavailable:
                "Firebase App Check 토큰을 발급받지 못했습니다. 실제 기기의 App Attest entitlement와 Firebase Console 설정을 확인해 주세요."
            }
        }
    }

    func prepareForLaunch() async throws {
        #if canImport(FirebaseAuth) && canImport(FirebaseCore)
        if FirebaseApp.app() != nil {
            let user = try await firebaseUser()
            _ = try await idToken(for: user)
            return
        }
        #endif
        _ = debugInstallationID
    }

    func headers() async throws -> [String: String] {
        #if canImport(FirebaseAuth) && canImport(FirebaseCore)
        if FirebaseApp.app() != nil {
            let user = try await firebaseUser()
            let idToken = try await idToken(for: user)
            var headers = ["Authorization": "Bearer \(idToken)"]
            #if canImport(FirebaseAppCheck)
            do {
                headers["X-Firebase-AppCheck"] = try await appCheckToken()
            } catch {
                print("[DailyOPIc][Firebase] App Check header token failed. error=\(error.localizedDescription)")
                throw AuthError.appCheckUnavailable
            }
            #endif
            return headers
        }
        #endif
        return ["X-Debug-User-ID": debugInstallationID]
    }

    private var debugInstallationID: String {
        let key = "dailyopic_debug_installation_id"
        if let value = UserDefaults.standard.string(forKey: key) {
            return value
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    #if canImport(FirebaseAuth)
    private func firebaseUser() async throws -> User {
        if let user = Auth.auth().currentUser { return user }
        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: error ?? AuthError.unavailable)
                }
            }
        }
    }

    private func idToken(for user: User) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(false) { token, error in
                if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: error ?? AuthError.unavailable)
                }
            }
        }
    }
    #endif

    #if canImport(FirebaseAppCheck)
    private func appCheckToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppCheck.appCheck().token(forcingRefresh: false) { result, error in
                if let result {
                    continuation.resume(returning: result.token)
                } else {
                    continuation.resume(throwing: error ?? AuthError.unavailable)
                }
            }
        }
    }
    #endif
}
