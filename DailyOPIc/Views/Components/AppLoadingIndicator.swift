import SwiftUI

/// Branded loading indicator: three dots that bounce in sequence.
/// Falls back to a static row when Reduce Motion is on.
struct AppLoadingIndicator: View {
    var tint: Color = AppPalette.primary
    var dotSize: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animating ? 1 : 0.5)
                    .opacity(animating ? 1 : 0.4)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { if !reduceMotion { animating = true } }
        .accessibilityLabel("불러오는 중")
    }
}
