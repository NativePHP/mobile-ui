import SwiftUI

/// SwiftUI Badge — capsule pill with count or short label.
///
/// Variant-dispatched colors from the theme (Model 3). No per-instance
/// color overrides.
///
/// `glass` Tailwind family swaps the capsule fill for Liquid Glass (iOS 26+
/// real `.glassEffect(...)`, fallback `.regularMaterial`). The badge is
/// registered in `NodeStyleModifier.glassHandledByRenderer` so the outer
/// wrapper doesn't double-paint a glass plate behind the rectangular frame.
///
/// Bit 1 (prominent) is ignored — `.glassEffect()` has no prominent variant.
/// Bit 2 (interactive) chains `.interactive(true)` for press-highlight.
struct NativeUIBadgeRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let count     = p.getInt("count")
        let label     = p.getString("label")
        let variant   = p.getString("variant", default: "destructive")
        let a11yLabel = p.getString("a11y_label")

        let glassFlags = p.getInt("glass", default: 0)
        let glassEnabled     = (glassFlags & 1) != 0
        let glassInteractive = (glassFlags & 4) != 0
        let glassClear       = (glassFlags & 8) != 0
        let hasUserBg        = (node.style?.bgColor ?? 0) != 0

        let text = !label.isEmpty
            ? label
            : (count > 99 ? "99+" : "\(count)")

        let (bg, fg): (Color, Color) = {
            switch variant {
            case "primary":     return (theme.primary,     theme.onPrimary)
            case "accent":      return (theme.accent,      theme.onAccent)
            case "success":     return (theme.success,     theme.onSuccess)
            default:            return (theme.destructive, theme.onDestructive) // "destructive"
            }
        }()

        Text(text)
            .nuiScaledFont(size: 12, weight: .bold)
            .foregroundColor(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .modifier(BadgeBackgroundModifier(
                fillColor: bg,
                glassEnabled: glassEnabled,
                glassInteractive: glassInteractive,
                glassClear: glassClear,
                hasUserBg: hasUserBg
            ))
            .modifier(A11yLabelModifier(label: a11yLabel))
    }
}

/// Picks between solid capsule fill and Liquid Glass for the badge background.
private struct BadgeBackgroundModifier: ViewModifier {
    let fillColor: Color
    let glassEnabled: Bool
    let glassInteractive: Bool
    let glassClear: Bool
    /// True when the user supplied a `bg-*` class. Skip the variant fill
    /// so NodeStyleModifier's user-bg paint isn't covered.
    let hasUserBg: Bool

    func body(content: Content) -> some View {
        let shape = Capsule()

        if glassEnabled, #available(iOS 26.0, *) {
            if glassClear {
                content.glassEffect(.clear.interactive(glassInteractive), in: shape)
            } else {
                content.glassEffect(.regular.interactive(glassInteractive), in: shape)
            }
        } else if glassEnabled {
            content.background(
                shape.fill(glassClear ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
            )
        } else if hasUserBg {
            content
        } else {
            content.background(shape.fill(fillColor))
        }
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
