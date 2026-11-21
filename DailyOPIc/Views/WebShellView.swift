import SwiftUI
import UIKit
import WebKit

/// 앱 화면 = 웹앱(WKWebView). 화면은 웹이 그리고, 앱은 웹이 할 수 없는 일만 맡는다.
/// - 로그인: 앱의 Firebase 계정(익명 → Google/Apple 연결)을 그대로 쓴다. 웹은 요청마다 `headers`로 토큰을 받는다.
/// - 결제: 요금제는 앱의 인앱결제 화면(`openPaywall`). 웹의 토스 결제 · 토큰 구매는 앱 안에서 보이지 않는다.
/// - 계정: 로그인 연결 · 계정 삭제(Apple 토큰 폐기 포함)는 앱의 계정 화면(`openAccount`).
/// 웹 쪽 짝은 DailyOPIc-FE src/lib/native.ts.
struct WebShellView: View {
    let environment: AppEnvironment
    @State private var model = WebShellModel()

    var body: some View {
        WebView(model: model)
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if let error = model.loadError {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundStyle(AppPalette.secondaryInk)
                        Text("화면을 불러오지 못했어요")
                            .font(AppTypography.title)
                        Text(error)
                            .font(AppTypography.body)
                            .foregroundStyle(AppPalette.secondaryInk)
                            .multilineTextAlignment(.center)
                        Button("다시 시도") { model.reload() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                }
            }
            .sheet(isPresented: $model.showsPaywall, onDismiss: { model.sheetClosed(environment: environment) }) {
                PaywallView(source: .settings)
                    .environment(environment)
            }
            .sheet(isPresented: $model.showsAccount, onDismiss: { model.sheetClosed(environment: environment) }) {
                NavigationStack {
                    Form { AccountSection() }
                        .navigationTitle("계정 · 로그인")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("닫기") { model.showsAccount = false }
                            }
                        }
                }
                .environment(environment)
            }
            .task { await model.start(environment: environment) }
    }
}

@MainActor
@Observable
final class WebShellModel: NSObject {
    var showsPaywall = false
    var showsAccount = false
    var loadError: String?

    @ObservationIgnored fileprivate var webView: WKWebView?
    @ObservationIgnored private var environment: AppEnvironment?
    @ObservationIgnored private var uid: String?
    /// 결제 · 계정 화면을 연 웹 요청. 화면이 닫히면 답한다(웹은 그때 플랜을 다시 읽는다).
    @ObservationIgnored private var pendingReply: ((Any?, String?) -> Void)?

    fileprivate func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "dailyopic")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = .white
        #if DEBUG
        if #available(iOS 16.4, *) { view.isInspectable = true }
        #endif
        webView = view
        return view
    }

    func start(environment: AppEnvironment) async {
        self.environment = environment
        await loadForCurrentUser()
    }

    func reload() {
        loadError = nil
        Task { await loadForCurrentUser() }
    }

    /// 지금 앱 계정(uid)을 웹에 알려 주고 웹앱을 연다. 계정이 바뀌면 다시 부른다.
    private func loadForCurrentUser() async {
        guard let environment, let webView else { return }
        guard let uid = try? await environment.authentication.currentUserID() else {
            loadError = "네트워크 연결을 확인해 주세요."
            return
        }
        self.uid = uid
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(source: Self.bootstrapScript(uid: uid, preferences: environment.preferences),
                         injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        webView.load(URLRequest(url: AppConfiguration.webAppURL))
    }

    /// 웹이 앱 안임을 알게 하고, 기존 앱 사용자는 단계 · 설문을 다시 고르지 않게 웹 설정으로 옮겨 준다(웹에 없을 때만).
    private static func bootstrapScript(uid: String, preferences: AppPreferences) -> String {
        var script = "window.DailyOPIcNative = { uid: \(jsonString(uid)) };"
        if let level = preferences.initialLevel?.rawValue,
           let survey = preferences.mockSurvey,
           survey.leisure.count + survey.hobbies.count + survey.sports.count + survey.travel.count >= 3,
           let data = try? JSONEncoder().encode(WebPrefs(initialLevel: level, survey: survey)),
           let json = String(data: data, encoding: .utf8) {
            let key = jsonString("dailyopic:prefs:\(uid)")
            script += "try { if (!localStorage.getItem(\(key))) localStorage.setItem(\(key), \(jsonString(json))); } catch (e) {}"
        }
        return script
    }

    private struct WebPrefs: Encodable {
        let initialLevel: Int
        let survey: BackgroundSurvey
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    func sheetClosed(environment: AppEnvironment) {
        let reply = pendingReply
        pendingReply = nil
        Task {
            await environment.refreshEntitlements()
            // 계정을 연결해 기존 계정으로 옮겼거나 삭제했으면 uid가 바뀐다 → 새 계정으로 다시 연다.
            if let current = try? await environment.authentication.currentUserID(), current != uid {
                await loadForCurrentUser()
            } else {
                reply?(true, nil)
            }
        }
    }
}

extension WebShellModel: WKScriptMessageHandlerWithReply {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String,
              let environment else {
            replyHandler(nil, "unknown message")
            return
        }
        switch action {
        case "headers":
            Task {
                do {
                    replyHandler(try await environment.authentication.webHeaders(), nil)
                } catch {
                    replyHandler(nil, error.localizedDescription)
                }
            }
        case "openPaywall", "openAccount":
            pendingReply?(false, nil)
            pendingReply = replyHandler
            if action == "openPaywall" { showsPaywall = true } else { showsAccount = true }
        default:
            replyHandler(nil, "unsupported action \(action)")
        }
    }
}

extension WebShellModel: WKNavigationDelegate, WKUIDelegate {
    /// 우리 웹앱 주소 밖(약관의 외부 링크, 메일 등)은 Safari · 기본 앱으로 연다.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.host == AppConfiguration.webAppURL.host || url.scheme == "about" { return .allow }
        if navigationAction.targetFrame?.isMainFrame == false { return .allow }
        await UIApplication.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadError = nil
    }

    /// 답변 녹음: 우리 웹앱이 마이크를 쓰는 건 허용한다(앱의 마이크 권한은 iOS가 따로 묻는다).
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        origin.host == AppConfiguration.webAppURL.host ? .grant : .deny
    }

    /// target=_blank 링크는 같은 화면에서 연다.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }
}

private struct WebView: UIViewRepresentable {
    let model: WebShellModel

    func makeUIView(context: Context) -> WKWebView { model.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
