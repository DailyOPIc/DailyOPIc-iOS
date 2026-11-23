import Combine
import SwiftUI
import UIKit
import WebKit

/// 앱 화면 = 웹앱(WKWebView). 화면은 웹이 그리고, 앱은 웹이 할 수 없는 일만 맡는다.
/// - 로그인: 앱의 Firebase 계정(익명 → Google/Apple 연결)을 그대로 쓴다. 웹은 요청마다 `headers`로 토큰을 받는다.
/// - 결제: 요금제는 앱의 인앱결제 화면(`openPaywall`). 웹의 토스 결제 · 토큰 구매는 앱 안에서 보이지 않는다.
/// - 계정: 로그인 연결 · 계정 삭제(Apple 토큰 폐기 포함)는 앱의 계정 화면(`openAccount`).
/// - 녹음 · 전사: 앱의 음성 인식(`speechStart` / `speechStop`). 웹 음성 인식을 쓰면 WebKit이 실행마다 마이크 허용을 따로 묻는다.
/// 웹 쪽 짝은 DailyOPIc-FE src/lib/native.ts.
struct WebShellView: View {
    let environment: AppEnvironment
    @State private var model = WebShellModel()

    var body: some View {
        // 웹 화면은 하나로 둔다. 배너 유무(플랜 · 서버 정책이 실행 중에 정해진다)에 따라 웹 화면을
        // if/else로 나누면 SwiftUI가 웹 화면을 새로 만들어, 아무것도 불러오지 않은 흰 화면이 된다.
        VStack(spacing: 0) {
            WebView(model: model)
                .ignoresSafeArea(edges: environment.showsAds ? [] : .bottom)
            if environment.showsAds {
                // 무료 플랜: 웹 화면 아래(하단 탭 밑)에 배너. 유료는 서버 정책으로 숨는다.
                BannerAdView()
                    .frame(height: 50)
                    .environmentObject(environment.ads)
                    .environment(environment)
            }
        }
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
            // 웹앱은 늘 밝은 테마다. 기기가 다크 모드여도 상태바 뒤가 검게 비지 않고 글자도 어둡게.
            .background(Color.white.ignoresSafeArea())
            .preferredColorScheme(.light)
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
    /// 처음 녹음할 때 만든다(오디오 세션 · 인터럽션 옵저버를 미리 잡지 않게).
    @ObservationIgnored private var speech: SpeechRecognitionService?
    @ObservationIgnored private var speechText: AnyCancellable?

    /// 웹 화면은 한 번만 만든다. SwiftUI가 뷰를 다시 만들어도 같은 웹 화면(불러온 페이지 그대로)을 돌려준다.
    fileprivate func makeWebView() -> WKWebView {
        if let webView { return webView }
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
        // .task가 화면(makeUIView)보다 먼저 돌 수 있다. 웹 화면이 아직 없으면 여기서 만든다.
        guard let environment else { return }
        let webView = makeWebView()
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
        var script = "window.DailyOPIcNative = { uid: \(jsonString(uid)), speech: true };"
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

    private static func adErrorMessage(_ error: Error) -> String {
        if let api = error as? APIClientError, api.isRewardQuotaExhausted {
            return "오늘 광고로 받을 수 있는 토큰을 모두 받았어요. 내일 다시 받을 수 있어요."
        }
        if let ad = error as? AdService.AdError, case .notEarned = ad { return "광고를 끝까지 보면 토큰을 받을 수 있어요." }
        if let ad = error as? AdService.AdError { return ad.localizedDescription }
        return "광고를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    /// 인식 중인 문장을 웹에 실시간으로 넘긴다(웹은 `dailyopic:speech` 이벤트로 받는다).
    private func speechService() -> SpeechRecognitionService {
        if let speech { return speech }
        let service = SpeechRecognitionService()
        speechText = service.$transcript
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] text in
                let js = "window.dispatchEvent(new CustomEvent('dailyopic:speech', { detail: \(Self.jsonString(text)) }))"
                self?.webView?.evaluateJavaScript(js)
            }
        speech = service
        return service
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
        case "watchAd":
            // 보상형 광고 → 서버가 AdMob 검증 후 오늘 쓸 보너스 토큰 1개를 준다(기존 앱 흐름 그대로).
            Task {
                do {
                    let intent = try await environment.api.createRewardIntent(purpose: .practiceCredits, requestID: UUID())
                    try await environment.ads.showRewardedAd(userIdentifier: intent.userIdentifier, customData: intent.customData)
                    _ = try await environment.api.waitForReward(nonce: intent.nonce)
                    replyHandler(true, nil)
                } catch {
                    replyHandler(nil, Self.adErrorMessage(error))
                }
            }
        case "speechStart":
            let speech = speechService()
            Task {
                do {
                    try await speech.start()
                    replyHandler(true, nil)
                } catch {
                    replyHandler(nil, error.localizedDescription)
                }
            }
        case "speechStop":
            // 답: { transcript, audio(base64 m4a) }. 아무 말도 인식되지 않았으면 빈 전사 · 오디오 없음.
            guard let speech, speech.isListening else {
                replyHandler(["transcript": ""], nil)
                return
            }
            Task {
                do {
                    let result = try await speech.stop()
                    defer { try? FileManager.default.removeItem(at: result.audioURL) }
                    let audio = try Data(contentsOf: result.audioURL).base64EncodedString()
                    replyHandler(["transcript": result.transcript, "audio": audio], nil)
                } catch SpeechRecognitionService.SpeechError.noSpeech {
                    replyHandler(["transcript": ""], nil)
                } catch {
                    speech.cancel()
                    replyHandler(nil, error.localizedDescription)
                }
            }
        case "speechCancel":
            speech?.cancel()
            replyHandler(true, nil)
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

    /// 웹의 window.alert / window.confirm. WKWebView는 이걸 직접 그려 줘야 하고,
    /// 안 그리면 confirm()이 곧바로 false가 돼 "새 세트 받기" 같은 확인이 조용히 취소된다.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in done.resume() })
            Self.present(alert) { done.resume() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in done.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in done.resume(returning: true) })
            Self.present(alert) { done.resume(returning: false) }
        }
    }

    /// 맨 위 화면에 띄운다. 띄울 곳이 없으면 `fallback`으로 바로 답한다.
    private static func present(_ controller: UIViewController, fallback: () -> Void) {
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return fallback() }
        top.present(controller, animated: true)
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
