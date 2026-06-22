import SwiftUI
import SwiftData

#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if canImport(FirebaseCore)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return true
        }
        #if canImport(FirebaseAppCheck)
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        #endif
        FirebaseApp.configure()
        #endif
        return true
    }
}

@main
struct DailyOPIcApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            PracticeHistoryRecord.self,
            MockHistoryRecord.self,
            MockDraftRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData 저장소를 열 수 없습니다: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView(environment: environment)
        }
        .modelContainer(modelContainer)
    }
}
