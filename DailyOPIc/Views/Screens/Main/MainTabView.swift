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
    }
}
