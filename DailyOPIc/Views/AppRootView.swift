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
