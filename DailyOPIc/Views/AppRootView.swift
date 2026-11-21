import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    let environment: AppEnvironment

    var body: some View {
        Group {
            switch environment.launchState {
            case .launching:
                SplashView()
            case let .failed(message):
                AuthRecoveryView(message: message) {
                    Task { await environment.initialize() }
                }
            case .ready:
                // 앱 화면은 웹앱이다(WebShellView). 온보딩 · 학습 · 결제 진입도 웹이 그린다.
                // ponytail: 이전 네이티브 화면(MainTabView · OnboardingView 등)은 출시 확인 뒤 지운다.
                WebShellView(environment: environment)
            }
        }
        .tint(AppPalette.primary)
        .task {
            environment.persistence.configure(context: modelContext)
            // 이 빌드를 처음 열 때 남아 있던 분석 기록(최대 50개)의 문제 문장을
            // 플래너 사본으로 옮긴다. 로컬 · 한 번이면 끝 · 다시 돌아도 결과가 같다.
            _ = try? environment.persistence.backfillLearnedQuestions()
            if case .launching = environment.launchState {
                await environment.initialize()
            }
        }
    }
}
