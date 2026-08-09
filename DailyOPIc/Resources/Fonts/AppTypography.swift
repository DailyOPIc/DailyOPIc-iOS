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

/// Consistent spacing scale (4pt base).
enum AppSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

/// Consistent corner-radius scale.
enum AppRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}
