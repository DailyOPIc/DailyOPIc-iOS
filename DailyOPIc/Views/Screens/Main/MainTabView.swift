import SwiftUI

/// 탭 바의 목적지. 순서·라벨·아이콘이 여기 한 곳에만 있어서 화면과 테스트가 같은
/// 목록을 읽는다. 태그는 `rawValue`이므로 순서를 바꾸면 태그도 함께 움직인다 —
/// 선택 상태를 숫자 리터럴로 들고 있는 곳을 만들지 않는다.
enum MainTab: Int, CaseIterable, Identifiable, Hashable {
    case daily
    case mock
    case planner
    case vocabulary
    case progress

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .daily: "데일리"
        case .mock: "모의고사"
        case .planner: "플래너"
        case .vocabulary: "단어장"
        case .progress: "통계"
        }
    }

    var systemImage: String {
        switch self {
        case .daily: "mic.fill"
        case .mock: "list.number"
        case .planner: "calendar"
        case .vocabulary: "book.closed.fill"
        case .progress: "chart.bar.fill"
        }
    }
}

struct MainTabView: View {
    let environment: AppEnvironment
    @State private var selectedTab: MainTab = .daily

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PracticeScreen(
                    viewModel: environment.practiceViewModel,
                    preferences: environment.preferences
                )
            }
            .tabItem { Label(MainTab.daily.title, systemImage: MainTab.daily.systemImage) }
            .tag(MainTab.daily)

            NavigationStack {
                MockExamScreen(viewModel: environment.mockViewModel)
            }
            .tabItem { Label(MainTab.mock.title, systemImage: MainTab.mock.systemImage) }
            .tag(MainTab.mock)

            NavigationStack {
                StudyCalendarScreen(
                    viewModel: environment.studyCalendarViewModel,
                    preferences: environment.preferences,
                    persistence: environment.persistence,
                    // 플래너는 학습 화면을 따로 만들지 않고 기존 데일리 탭으로 보낸다.
                    onStartDaily: { selectedTab = .daily }
                )
            }
            .tabItem { Label(MainTab.planner.title, systemImage: MainTab.planner.systemImage) }
            .tag(MainTab.planner)

            NavigationStack {
                VocabularyScreen(
                    preferences: environment.preferences,
                    persistence: environment.persistence
                )
            }
            .tabItem { Label(MainTab.vocabulary.title, systemImage: MainTab.vocabulary.systemImage) }
            .tag(MainTab.vocabulary)

            NavigationStack {
                ProgressScreen(preferences: environment.preferences, persistence: environment.persistence)
            }
            .tabItem { Label(MainTab.progress.title, systemImage: MainTab.progress.systemImage) }
            .tag(MainTab.progress)
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
