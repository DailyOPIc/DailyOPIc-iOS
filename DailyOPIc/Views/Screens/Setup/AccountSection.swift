import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// 설정의 "계정" 섹션: 익명 계정에 Apple · Google 로그인을 붙이고(uid 유지), 계정을 삭제한다.
/// 로그인하면 웹(같은 Firebase 프로젝트)과 같은 계정이 되어 기록·구독이 이어진다.
struct AccountSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @State private var summary: AuthenticationService.AccountSummary?
    @State private var nonce = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var confirmsSwitch = false
    @State private var confirmsDeletion = false
    @State private var reauthenticator = AppleReauthenticator()

    var body: some View {
        Group {
            Section {
                if let summary, !summary.isAnonymous {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Label(signedInTitle(summary), systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline)
                        if let email = summary.email {
                            Text(email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
                if summary?.hasApple != true {
                    SignInWithAppleButton(.continue) { request in
                        nonce = AppleNonce.make()
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = AppleNonce.sha256(nonce)
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .disabled(isWorking)
                }
                if summary?.hasGoogle != true {
                    Button {
                        Task { await linkGoogle() }
                    } label: {
                        Text("Google로 계속하기")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .disabled(isWorking)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("계정")
            } footer: {
                Text("로그인하면 기기를 바꾸거나 웹에서도 같은 계정으로 학습 기록과 이용권이 이어져요.")
            }

            Section {
                Button("계정 삭제", role: .destructive) {
                    confirmsDeletion = true
                }
                .disabled(isWorking)
            } footer: {
                Text("구독은 자동으로 해지되지 않아요. iPhone 설정 → Apple 계정 → 구독에서 해지해 주세요.")
            }
        }
        .task { await reload() }
        .alert("이미 가입된 계정이에요", isPresented: $confirmsSwitch) {
            Button("그 계정으로 전환") { Task { await switchAccount() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("전환하면 그 계정의 기록과 이용권으로 바뀌어요. 이 기기에서 쓰던 구독은 그 계정으로 자동으로 옮겨져요.")
        }
        .alert("계정을 삭제할까요?", isPresented: $confirmsDeletion) {
            Button("삭제", role: .destructive) { Task { await deleteAccount() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("학습 기록, 사용량, 계정 정보가 모두 지워지고 되돌릴 수 없어요.")
        }
    }

    private func signedInTitle(_ summary: AuthenticationService.AccountSummary) -> String {
        switch (summary.hasApple, summary.hasGoogle) {
        case (true, true): "Apple · Google로 로그인됨"
        case (true, false): "Apple로 로그인됨"
        case (false, true): "Google로 로그인됨"
        default: "로그인됨"
        }
    }

    private func reload() async {
        summary = await environment.authentication.accountSummary()
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled { message = "Apple 로그인에 실패했어요. 다시 시도해 주세요." }
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                message = "Apple 로그인 정보를 읽지 못했어요."
                return
            }
            await run {
                try await environment.authentication.linkApple(
                    idToken: idToken, rawNonce: nonce, fullName: credential.fullName
                )
            }
        }
    }

    private func linkGoogle() async {
        #if canImport(GoogleSignIn)
        do {
            let tokens = try await GoogleSignInFlow.signIn()
            await run {
                try await environment.authentication.linkGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
            }
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            return
        } catch {
            message = "Google 로그인에 실패했어요. 다시 시도해 주세요."
        }
        #endif
    }

    private func run(_ link: () async throws -> AuthenticationService.LinkOutcome) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await link() {
            case .linked:
                message = "로그인했어요. 기록과 이용권이 이 계정에 저장돼요."
                await reload()
            case .accountExists:
                confirmsSwitch = true
            }
        } catch {
            message = "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func switchAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await environment.authentication.switchToExistingAccount()
            await environment.accountDidChange(transferPurchases: true)
            message = "기존 계정으로 전환했어요."
            await reload()
        } catch {
            message = "계정을 전환하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            var code: String?
            if summary?.hasApple == true {
                // Apple 토큰 폐기에 필요한 authorizationCode를 받으려면 한 번 더 Apple 인증을 거친다.
                let credential = try await reauthenticator.authorize()
                code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            }
            try await environment.deleteAccount(appleAuthorizationCode: code)
            message = "계정을 삭제했어요."
            await reload()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            message = "계정을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

/// Sign in with Apple의 nonce. Apple에는 SHA256을 보내고 Firebase에는 원문을 넘긴다(재전송 공격 방지).
enum AppleNonce {
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// 버튼 없이 Apple 인증을 띄운다(계정 삭제 전 토큰 폐기용 authorizationCode 받기).
@MainActor
final class AppleReauthenticator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    func authorize() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                finish(.success(credential))
            } else {
                finish(.failure(ASAuthorizationError(.unknown)))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.activeKeyWindow ?? ASPresentationAnchor() }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

#if canImport(GoogleSignIn)
@MainActor
enum GoogleSignInFlow {
    enum FlowError: Error { case unavailable, missingToken }

    static func signIn() async throws -> (idToken: String, accessToken: String) {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let presenter = UIApplication.shared.topViewController else { throw FlowError.unavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw FlowError.missingToken }
        return (idToken, result.user.accessToken.tokenString)
    }
}
#endif

private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }

    /// 설정은 시트로 열리므로 가장 위에 떠 있는 화면에서 Google 로그인을 띄워야 한다.
    var topViewController: UIViewController? {
        var top = activeKeyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
