import SwiftUI
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        // delegate가 없으면 iOS는 앱이 떠 있는 동안 도착한 로컬 알림을 그냥 버린다.
        // 학습 알림은 사용자가 정한 공부 시간에 울리므로 앱을 켜 둔 채 맞는 일이 흔하다.
        // 알림을 새로 요청하지는 않는다(권한 요청은 여전히 캘린더의 명시적 CTA에서만).
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            StudyReminderPresentation.options(for: notification.request.identifier)
        )
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
                            // 날짜가 바뀌었거나 설정에서 알림 권한을 바꿨을 수 있다.
                            // 엔타이틀먼트보다 먼저 재조정하면 하루 학습량을 무료 기준으로
                            // 잘못 잡은 알림을 30일치 다시 써 버린다. 순서를 고정한다.
                            Task {
                                await environment.refreshEntitlements()
                                await environment.studyCalendarViewModel.reconcileStudyReminders()
                            }
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
