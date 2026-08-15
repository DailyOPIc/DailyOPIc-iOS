import SwiftUI
import SwiftData

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        return true
    }
}

@main
struct DailyOPIcApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()

    private let modelContainer: ModelContainer?
    private let persistenceStartupError: String?

    init() {
        let schema = Schema([
            PracticeHistoryRecord.self,
            MockHistoryRecord.self,
            MockDraftRecord.self,
            StudySetCompletionRecord.self,
            StudyDayPlanRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            persistenceStartupError = nil
        } catch {
            modelContainer = nil
            persistenceStartupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                AppRootView(environment: environment)
                    .modelContainer(modelContainer)
                    .onChange(of: scenePhase) { _, phase in
                        // 포그라운드 복귀 시 구독 상태(해지/갱신/만료)를 즉시 최신화.
                        if phase == .active {
                            Task { await environment.refreshEntitlements() }
                        }
                    }
            } else {
                StorageRecoveryView(message: persistenceStartupError ?? "알 수 없는 저장소 오류")
            }
        }
    }
}

private struct StorageRecoveryView: View {
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(AppPalette.danger)
            Text("학습 기록 저장소를 열지 못했어요")
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text("앱을 다시 실행해 주세요. 문제가 계속되면 앱 데이터를 삭제하기 전에 지원팀에 문의해 기록 복구 가능 여부를 확인해 주세요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
            #if DEBUG
            Text(message).font(.caption).foregroundStyle(.secondary)
            #endif
        }
        .padding(AppSpacing.lg)
    }
}
