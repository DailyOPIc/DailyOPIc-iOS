import SwiftUI

struct AILoadingOverlay: View {
    let kind: AsyncOperationKind
    let blocksInteraction: Bool
    let canContinueInBackground: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var takingLonger = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            if blocksInteraction { Color.black.opacity(0.28).ignoresSafeArea() }
            VStack(spacing: AppSpacing.md) {
                AppLoadingIndicator(dotSize: 12)
                    .padding(.bottom, AppSpacing.xs)
                Text(kind.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if takingLonger {
                    Text("조금만 더 기다려 주세요.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .transition(.opacity)
                }
                if canContinueInBackground {
                    Text("화면을 닫아도 계속 진행돼요.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
            }
            .padding(AppSpacing.xl)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .padding(AppSpacing.xl)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true } }
        }
        .task {
            try? await Task.sleep(for: .seconds(8))
            withAnimation(.easeInOut(duration: 0.25)) { takingLonger = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
