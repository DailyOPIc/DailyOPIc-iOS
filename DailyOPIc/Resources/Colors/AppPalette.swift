import SwiftUI
import UIKit

/// Central color tokens. Every color adapts to light/dark mode via a dynamic
/// `UIColor` provider so the whole app stays legible in either appearance.
enum AppPalette {
    static let primary = dynamic(
        light: rgb(75, 36, 255),
        dark: rgb(150, 122, 255)
    )
    static let primarySoft = dynamic(
        light: rgb(237, 233, 255),
        dark: rgb(46, 38, 86)
    )
    static let primaryMid = dynamic(
        light: rgb(155, 135, 245),
        dark: rgb(120, 100, 210)
    )
    static let ink = dynamic(
        light: rgb(17, 24, 39),
        dark: rgb(240, 242, 248)
    )
    static let secondaryInk = dynamic(
        // #5B6472 rather than #6B7280: secondary text mostly sits on `surface`
        // (#F2F2F7 in light), where the old value measured 4.33:1 and missed AA.
        light: rgb(91, 100, 114),
        dark: rgb(160, 166, 178)
    )
    /// Foreground for content sitting on a `primary` fill. Dark mode uses dark
    /// ink, not white: white on the dark accent (#967AFF) measures 3.22:1.
    static let actionOnPrimary = dynamic(
        light: rgb(255, 255, 255),
        dark: rgb(17, 24, 39)
    )
    static let successSoft = dynamic(
        light: rgb(236, 253, 245),
        dark: rgb(24, 52, 43)
    )
    static let danger = dynamic(
        // #DC2626 rather than #EF4444, which measured 3.76:1 on white and was
        // too light for body-size error text.
        light: rgb(220, 38, 38),
        dark: rgb(248, 113, 113)
    )

    /// Base surface for cards; adapts to system background.
    static let surface = Color(.secondarySystemBackground)
    /// Elevated surface (dialogs, sheets).
    static let elevatedSurface = Color(.systemBackground)

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
