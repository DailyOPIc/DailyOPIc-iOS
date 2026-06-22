import SwiftUI

struct AuthRecoveryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("앱을 시작할 수 없어요", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
