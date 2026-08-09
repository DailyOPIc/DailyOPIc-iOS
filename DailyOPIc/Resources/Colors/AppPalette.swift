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
        // #262048 rather than #2E2656: `primary` is the foreground on this fill
        // in unselected chips, and the old value measured 4.27:1 in dark mode.
        dark: rgb(38, 32, 72)
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
    /// Foreground for content sitting on a `danger` fill. Mirrors
    /// `actionOnPrimary`: white on the dark red (#F87171) measures 2.77:1.
    static let actionOnDanger = dynamic(
        light: rgb(255, 255, 255),
        dark: rgb(17, 24, 39)
    )
    /// Foreground for content sitting on a `primaryMid` (disabled) fill.
    /// `primaryMid` runs the opposite way to `primary` — it is light in light
    /// mode and mid-tone in dark — so this token is the inverse of
    /// `actionOnPrimary`. White on the light fill (#9B87F5) measures 2.93:1.
    static let actionOnDisabled = dynamic(
        light: rgb(17, 24, 39),
        dark: rgb(255, 255, 255)
    )
    static let successSoft = dynamic(
        light: rgb(236, 253, 245),
        dark: rgb(24, 52, 43)
    )
    /// Destructive/error *fill* and icon tint.
    static let danger = dynamic(
        // #DC2626 rather than #EF4444, which measured 3.76:1 on white and was
        // too light for body-size error text.
        light: rgb(220, 38, 38),
        dark: rgb(248, 113, 113)
    )
    /// Destructive/error *text*. Split from `danger` because a fill colour and
    /// a body-text colour cannot share one value: #DC2626 passes on white
    /// (4.83:1) but only reaches 4.33:1 on `surface` (#F2F2F7), where most
    /// error text actually sits. Dark mode keeps `danger`, which already
    /// measures 6.15:1 there.
    static let dangerInk = dynamic(
        light: rgb(185, 28, 28),    // #B91C1C
        dark: rgb(248, 113, 113)    // #F87171
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
