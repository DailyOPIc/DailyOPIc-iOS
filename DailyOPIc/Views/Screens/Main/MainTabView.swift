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
            .tabItem { Label("Practice", systemImage: "mic.fill") }
            .tag(0)

            NavigationStack {
                MockExamScreen(viewModel: mockViewModel)
            }
            .tabItem { Label("Mock", systemImage: "list.number") }
            .tag(1)

            NavigationStack {
                ProgressScreen(preferences: environment.preferences)
            }
            .tabItem { Label("Progress", systemImage: "checkmark.circle.fill") }
            .tag(2)
        }
        .environmentObject(environment.ads)
    }
}
