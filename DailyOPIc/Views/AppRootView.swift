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
                // 루트 분기는 인증/부팅 상태와 "온보딩을 마쳤는가"만 표현한다.
                // 도움말·난이도 재선택 같은 일시적인 화면은 MainTabView 위에
                // 덮어서 띄운다(DESIGN_DECISIONS.md T1). 루트를 갈아끼우면
                // 학습 화면이 통째로 사라져 탭 선택·스크롤 위치가 초기화된다.
                if environment.preferences.hasCompletedOnboarding {
                    MainTabView(environment: environment)
                } else {
                    OnboardingView(environment: environment)
                }
            }
        }
        .tint(AppPalette.primary)
        .task {
            environment.persistence.configure(context: modelContext)
            if case .launching = environment.launchState {
                await environment.initialize()
            }
        }
    }
}
