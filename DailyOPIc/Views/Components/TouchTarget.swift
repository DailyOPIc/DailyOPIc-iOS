import SwiftUI

extension View {
    /// Guarantees the 44×44pt minimum interactive area from DESIGN.md §30.1.
    ///
    /// The visual content keeps its natural size and stays centred — only the
    /// hit region grows, so a 28pt chip still looks like a 28pt chip. Apply it
    /// as the outermost modifier on the control, after any `buttonStyle`.
    func minimumTouchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}
