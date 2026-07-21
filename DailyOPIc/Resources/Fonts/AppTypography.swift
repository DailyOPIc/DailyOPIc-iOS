import SwiftUI

enum AppTypography {
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let cardTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .rounded)
    static let callout = Font.system(size: 15, weight: .medium, design: .rounded)
    static let footnote = Font.system(size: 13, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .semibold, design: .rounded)
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
