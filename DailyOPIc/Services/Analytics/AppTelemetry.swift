import Foundation
import OSLog

enum AppTelemetry {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DailyOPIc",
        category: "operations"
    )

    static func operationStarted(kind: AsyncOperationKind, id: UUID) {
        logger.info("operation_started kind=\(kind.rawValue, privacy: .public) id=\(id.uuidString, privacy: .private(mask: .hash))")
    }

    static func operationCompleted(kind: AsyncOperationKind, id: UUID) {
        logger.info("operation_completed kind=\(kind.rawValue, privacy: .public) id=\(id.uuidString, privacy: .private(mask: .hash))")
    }

    static func operationFailed(kind: AsyncOperationKind, id: UUID, retryable: Bool) {
        logger.error("operation_failed kind=\(kind.rawValue, privacy: .public) id=\(id.uuidString, privacy: .private(mask: .hash)) retryable=\(retryable)")
    }

    static func onboarding(page: Int, state: AppPreferences.GuideState) {
        logger.info("onboarding page=\(page) state=\(state.rawValue, privacy: .public)")
    }
}
