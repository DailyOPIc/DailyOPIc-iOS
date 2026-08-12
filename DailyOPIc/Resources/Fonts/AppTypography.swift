import SwiftUI

/// Typography scale built on iOS text styles so every token scales with
/// Dynamic Type. Each style's default size matches the fixed size it replaces,
/// so the visual hierarchy is unchanged at the default content size:
/// title 28, cardTitle 22, sectionTitle 17, body 16, callout 15,
/// footnote 13, caption 12.
enum AppTypography {
    static let title = Font.system(.title, design: .rounded).weight(.bold)
    static let cardTitle = Font.system(.title2, design: .rounded).weight(.bold)
    /// `.headline` is already semibold, so no weight override is needed.
    static let sectionTitle = Font.system(.headline, design: .rounded)
    static let body = Font.system(.callout, design: .rounded)
    static let callout = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let footnote = Font.system(.footnote, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
}

/// Spacing scale on a strict 4pt grid (DESIGN.md §6.4). The previous values
/// (6/10/16/22/28) were off-grid at three of five steps.
enum AppSpacing {
    /// Icon-to-label gaps and inline elements.
    static let xs: CGFloat = 4
    /// Tightly grouped elements; also the minimum gap between touch targets.
    static let sm: CGFloat = 8
    /// Default element spacing and card interior padding.
    static let md: CGFloat = 16
    /// Section spacing and screen side margins.
    static let lg: CGFloat = 24
    /// Major block separation.
    static let xl: CGFloat = 32
}

/// Corner-radius scale named by role rather than size (DESIGN.md §6.5), so a
/// call site has to state what it is rather than pick a magnitude.
/// Every corner uses `style: .continuous`.
enum AppRadius {
    /// Buttons, chips, inputs.
    static let control: CGFloat = 12
    /// Cards and section containers.
    static let card: CGFloat = 16
    /// Bottom sheets, dialogs, large overlays.
    static let sheet: CGFloat = 24
}
