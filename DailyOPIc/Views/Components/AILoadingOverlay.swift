import SwiftUI

struct AILoadingOverlay: View {
    let kind: AsyncOperationKind
    let blocksInteraction: Bool
    let canContinueInBackground: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail = "잠시만 기다려 주세요."

    var body: some View {
        ZStack {
            if blocksInteraction { Color.black.opacity(0.28).ignoresSafeArea() }
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(kind.title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                if canContinueInBackground {
                    Text("화면을 닫아도 서버 작업은 백그라운드에서 계속됩니다.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(28)
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(8))
            detail = "안전하게 처리 중이에요. 조금 더 걸릴 수 있습니다."
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
