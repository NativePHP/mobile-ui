import SwiftUI

struct NativeUIIconRenderer: View {
    let node: NativeUINode

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = node.props
        let name = p.getString("name")
        let size = CGFloat(p.getFloat("size", default: 24))
        // default light color to 0 (unset) so an icon without an
        // explicit color class inherits SwiftUI `.primary`, which auto-flips
        // with the nativephp-color-scheme override. Original vendor default
        // of 0xFF000000 (pure black) rendered invisible on dark surfaces.
        let lightArgb = p.getColor("color", default: 0)
        let darkArgb  = p.getColor("dark_color", default: 0)
        let a11yLabel = p.getString("a11y_label")

        // Mirrors ViewClickHandlers' detection: an icon is interactive when
        // any of the click callbacks it wires are present.
        let interactive = node.onPress != 0
            || node.onLongPress != 0
            || p.getInt("on_double_tap") != 0

        // When dark mode is active and a `dark-color` was supplied, use it;
        // otherwise fall through to the regular `color`. Same shape as
        // NodeStyleModifier's bg / border dark resolution so authoring stays
        // consistent across element types.
        let effectiveArgb: Int = (colorScheme == .dark && darkArgb != 0)
            ? darkArgb
            : lightArgb

        Image(systemName: getIconForName(name))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(effectiveArgb == 0 ? .primary : Color(argb: effectiveArgb))
            // Extend clickable icons to a 44pt hit target BEFORE the click
            // handlers attach, so the tap gesture covers the enlarged shape.
            .modifier(IconTapTargetModifier(interactive: interactive))
            .applyClickHandlers(node: node)
            .modifier(IconA11yModifier(label: a11yLabel, interactive: interactive))
    }
}

/// 44pt minimum hit target — only for icons that actually respond to taps.
/// Decorative icons keep their intrinsic frame so layouts aren't inflated.
private struct IconTapTargetModifier: ViewModifier {
    let interactive: Bool
    func body(content: Content) -> some View {
        if interactive { content.nuiMinTapTarget() }
        else { content }
    }
}

/// Icons with an `a11y_label` announce it; unlabeled decorative icons are
/// hidden from VoiceOver. Interactive icons always stay visible and carry
/// the button trait (falling back to a bare button when unlabeled rather
/// than disappearing from the accessibility tree).
private struct IconA11yModifier: ViewModifier {
    let label: String
    let interactive: Bool

    func body(content: Content) -> some View {
        if interactive {
            if label.isEmpty {
                content.accessibilityAddTraits(.isButton)
            } else {
                content
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.isButton)
            }
        } else if label.isEmpty {
            content.accessibilityHidden(true)
        } else {
            content.accessibilityLabel(label)
        }
    }
}
