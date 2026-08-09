import SwiftUI

struct SplashView: View {
    @State private var pulse = false
    /// Wordmark sits above every text style, so it scales via UIFontMetrics
    /// rather than snapping down to .largeTitle.
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 40

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.white, AppPalette.primarySoft],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(AppPalette.primary)
                        .frame(width: 92, height: 92)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(pulse ? 1.04 : 0.96)
                Text("DailyOPIc")
                    .font(.system(size: wordmarkSize, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.primary)
                ProgressView()
                    .tint(AppPalette.primary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
