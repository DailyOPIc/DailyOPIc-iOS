import SwiftUI

struct MainTabView: View {
    let environment: AppEnvironment
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PracticeScreen(
                    viewModel: environment.practiceViewModel,
                    preferences: environment.preferences
                )
            }
            .tabItem { Label("데일리", systemImage: "mic.fill") }
            .tag(0)

            NavigationStack {
                MockExamScreen(viewModel: environment.mockViewModel)
            }
            .tabItem { Label("모의고사", systemImage: "list.number") }
            .tag(1)

            NavigationStack {
                ProgressScreen(preferences: environment.preferences)
            }
            .tabItem { Label("통계", systemImage: "chart.bar.fill") }
            .tag(2)
        }
        .environmentObject(environment.ads)
        .environment(environment)
        // 도움말과 난이도 재선택은 학습 탭을 걷어내지 않고 그 위에 덮는다.
        // 두 플래그는 동시에 켜지지 않는다: 설정 시트는 한 번에 한 경로만
        // 요청하고(PracticeScreen.applyPendingSetupRoute), 재선택 화면 안의
        // 도움말은 OnboardingView 내부 단계로 처리된다.
        .fullScreenCover(isPresented: isPresentingGuide) {
            OPIcGuideView(preferences: environment.preferences) { skipped in
                environment.preferences.finishGuide(skipped: skipped)
            }
        }
        .fullScreenCover(isPresented: isPresentingLevelSelection) {
            OnboardingView(environment: environment)
        }
    }

    private var isPresentingGuide: Binding<Bool> {
        Binding(
            get: { environment.preferences.isPresentingGuide },
            set: { environment.preferences.isPresentingGuide = $0 }
        )
    }

    private var isPresentingLevelSelection: Binding<Bool> {
        Binding(
            get: { environment.preferences.isPresentingLevelSelection },
            set: { environment.preferences.isPresentingLevelSelection = $0 }
        )
    }
}
