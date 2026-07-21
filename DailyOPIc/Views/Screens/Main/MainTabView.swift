import SwiftUI

struct MainTabView: View {
    let environment: AppEnvironment
    @State private var practiceViewModel: PracticeViewModel
    @State private var mockViewModel: MockExamViewModel
    @State private var selectedTab = 0

    init(environment: AppEnvironment) {
        self.environment = environment
        _practiceViewModel = State(initialValue: PracticeViewModel(environment: environment))
        _mockViewModel = State(initialValue: MockExamViewModel(environment: environment))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PracticeScreen(viewModel: practiceViewModel, preferences: environment.preferences)
            }
            .tabItem { Label("데일리", systemImage: "mic.fill") }
            .tag(0)

            NavigationStack {
                MockExamScreen(viewModel: mockViewModel)
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
    }
}
