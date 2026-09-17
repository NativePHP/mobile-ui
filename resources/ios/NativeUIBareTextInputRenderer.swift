import SwiftUI

/// Chromeless text input — `NativeUITextInputCore` only, with optional
/// horizontal padding so it can sit cleanly inside a wrapper that
/// supplies the visible chrome (glass pill, card, etc.).
///
/// Composition (vs. outlined / filled variants):
///
///   `[ TextInputCore ]`     ← that's the entire view
///
/// No outline. No fill. No label. No supporting text. No icons. The
/// caller wraps this in whatever container they want and applies the
/// pill / capsule / rounded-rect chrome via class. Reuses all of
/// `NativeUITextInputCore`'s state/echo/sync machinery — variant
/// differences are purely visual.
struct NativeUIBareTextInputRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props

        let disabled  = p.getBool("disabled")
        let readOnly  = p.getBool("read_only")
        let isError   = p.getBool("is_error")
        let size      = p.getString("size", default: "md")
        let a11yLabel = p.getString("a11y_label")
        let a11yHint  = p.getString("a11y_hint")

        let textSize: CGFloat = {
            switch size {
            case "sm": return theme.fontSm
            case "lg": return theme.fontLg
            default:   return theme.fontMd
            }
        }()

        // Per-instance color override — bare variant only (Model 3 stays
        // for outlined / filled). `dark_color` is the dark-mode companion
        // auto-derived by the collector from a `dark:text-*` class.
        let darkOverrideArgb = colorScheme == .dark ? p.getColor("dark_color", default: 0) : 0
        let lightOverrideArgb = p.getColor("color", default: 0)
        let hasOverride = darkOverrideArgb != 0 || lightOverrideArgb != 0
        let baseTextColor: Color = {
            if darkOverrideArgb != 0 { return Color(argb: darkOverrideArgb) }
            if lightOverrideArgb != 0 { return Color(argb: lightOverrideArgb) }
            return theme.onSurface
        }()

        let resolvedTint: Color = {
            if isError { return theme.destructive }
            if hasOverride { return baseTextColor }
            return theme.primary
        }()

        // Placeholder color override — independent of `color`/`dark_color`.
        // No `placeholder-*` Tailwind class exists to drive a dark
        // companion the way `dark:text-*` does for `color`, so
        // `dark_placeholder_color` is set directly from a sibling
        // `dark-placeholder-color` attribute (mirrors `Icon`'s `dark-color`).
        let darkPlaceholderArgb = colorScheme == .dark ? p.getColor("dark_placeholder_color", default: 0) : 0
        let lightPlaceholderArgb = p.getColor("placeholder_color", default: 0)
        let placeholderOverride: Color? = {
            if darkPlaceholderArgb != 0 { return Color(argb: darkPlaceholderArgb) }
            if lightPlaceholderArgb != 0 { return Color(argb: lightPlaceholderArgb) }
            return nil
        }()

        NativeUITextInputCore(
            node: node,
            textSize: textSize,
            contentColor: disabled ? baseTextColor.opacity(0.6) : baseTextColor,
            tintColor: resolvedTint,
            placeholderColor: placeholderOverride
        )
        .opacity(disabled ? 0.6 : 1.0)
        .allowsHitTesting(!disabled && !readOnly)
        .modifier(A11yLabelModifier(label: a11yLabel))
        .modifier(A11yHintModifier(hint: a11yHint))
    }
}

// MARK: - Accessibility modifiers (conditional)

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}

private struct A11yHintModifier: ViewModifier {
    let hint: String
    func body(content: Content) -> some View {
        if hint.isEmpty { content }
        else { content.accessibilityHint(hint) }
    }
}
