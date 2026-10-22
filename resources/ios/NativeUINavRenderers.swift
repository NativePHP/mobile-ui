import SwiftUI

// MARK: - Top Bar

struct NativeUITopBarRenderer: View {
    let node: NativeUINode

    @Environment(\.nativeSafeAreaTop) private var safeAreaTop: CGFloat

    var body: some View {
        let props = node.props
        let title = props.getString("title", default: "")
        let subtitle = props.getString("subtitle", default: "")
        let textColorArgb = props.getColor("text_color", default: 0)
        let textColor: Color = textColorArgb != 0 ? Color(argb: textColorArgb) : .primary
        let bgColorArgb = props.getColor("background_color", default: 0)
        let backgroundColor: Color = bgColorArgb != 0 ? Color(argb: bgColorArgb) : .clear
        let elevation = CGFloat(props.getFloat("elevation"))
        let showBack = props.getBool("show_navigation_icon")
        // Per-bar font (font_name prop) — nil falls through to the theme
        // default inside nuiScaledFont.
        let barFont = props.getString("font_name")

        HStack(spacing: 8) {
            // Leading: back button (system back, not a press callback —
            // the PHP runloop catches EventType.systemBack and pops the stack).
            if showBack {
                Button {
                    NativeElementBridge.sendSystemBackEvent()
                } label: {
                    Image(systemName: "chevron.backward")
                        .nuiScaledFont(size: 17, weight: .semibold)
                        .foregroundColor(textColor)
                        .frame(width: 32, height: 32, alignment: .leading)
                        .nuiMinTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .nuiScaledFont(size: 17, weight: .semibold, fontName: barFont.isEmpty ? nil : barFont)
                    .foregroundColor(textColor)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .nuiScaledFont(size: 12, fontName: barFont.isEmpty ? nil : barFont)
                        .foregroundColor(textColor.opacity(0.7))
                }
            }

            Spacer()

            ForEach(node.children.filter { $0.type == "top_bar_action" }) { action in
                let icon = action.props.getString("icon", default: "ellipsis")
                // Icon-only action buttons need a spoken name: prefer an
                // explicit a11y_label, then the action's label prop, then a
                // humanized icon name so VoiceOver never reads them unlabeled.
                let a11y = action.props.getString("a11y_label")
                let actionLabel = action.props.getString("label", default: "")
                let effectiveA11y = !a11y.isEmpty
                    ? a11y
                    : (!actionLabel.isEmpty
                        ? actionLabel
                        : (NativeIcon.customName(icon) ?? icon).replacingOccurrences(of: "_", with: " ")
                              .replacingOccurrences(of: "-", with: " "))
                Button {
                    if action.onPress != 0 {
                        NativeElementBridge.sendPressEvent(action.onPress, nodeId: action.id)
                    }
                } label: {
                    NativeIconView(icon, pointSize: 17, relativeTo: .body)
                        .nuiScaledFont(size: 17, weight: .semibold)
                        .foregroundColor(textColor)
                        .frame(width: 32, height: 32)
                        .nuiMinTapTarget()
                }
                .buttonStyle(.plain)
                .modifier(A11yLabelModifier(label: effectiveA11y))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8 + safeAreaTop)        // status-bar / notch inset
        .padding(.bottom, 8)
        .background(backgroundColor)
        // Elevation renders as a hairline at the bottom of the bar — a
        // SwiftUI `.shadow()` cast outside the bar's bounds gets covered
        // by the next sibling in the wrapper column (the screen content
        // typically has its own background). The hairline lives inside
        // the bar's bounds so it always paints, and matches the standard
        // iOS chrome separator look.
        .overlay(alignment: .bottom) {
            if elevation > 0 {
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(height: max(0.5, elevation / 4))
            }
        }
    }
}

// MARK: - Bottom Nav

struct NativeUIBottomNavRenderer: View {
    let node: NativeUINode

    @Environment(\.nativeSafeAreaBottom) private var safeAreaBottom: CGFloat

    var body: some View {
        let items = node.children.filter { $0.type == "bottom_nav_item" }

        // Bar-level props from the BottomNav element. `active_color` is set
        // by `TabBar::activeColor()` (hex string parsed via ColorParser).
        // `dark` is set by `TabBar::dark()` and shifts both the bar's
        // background and the inactive item color toward a dark theme.
        // `label_visibility` ("labeled" / "selected" / "unlabeled") controls
        // when each item's label text is shown.
        let activeArgb = node.props.getColor("active_color", default: 0)
        let activeColor: Color = activeArgb != 0 ? Color(argb: activeArgb) : .accentColor
        // Per-bar font (font_name prop) — nil falls through to the theme
        // default inside nuiScaledFont.
        let barFont = node.props.getString("font_name")
        let isDark = node.props.getBool("dark")
        // Explicit `textColor()` from the TabBar builder wins for inactive
        // items; falls back to the gray defaults picked by `dark()`.
        let textColorArgb = node.props.getColor("text_color", default: 0)
        let inactiveColor: Color = textColorArgb != 0
            ? Color(argb: textColorArgb)
            : (isDark ? Color(white: 0.7) : .gray)
        // Explicit `backgroundColor()` from the TabBar builder wins; falls
        // back to the `dark()` default (dark surface) or transparent.
        let bgArgb = node.props.getColor("background_color", default: 0)
        let barBackground: Color = bgArgb != 0
            ? Color(argb: bgArgb)
            : (isDark ? Color(white: 0.12) : Color.clear)
        let labelVisibility = node.props.getString("label_visibility", default: "labeled")

        // The bar's bg is provided by a Rectangle that explicitly ignores
        // the wrapper's bottom safe area, so it reaches the screen edge
        // (standard iOS chrome — bg through the home-indicator zone).
        // Inside, an explicit bottom padding equal to the home-indicator
        // inset pushes the icons up so they sit just above the indicator,
        // not flush against it. This also visually balances the bar so it
        // doesn't look like there's empty padding below the icons —
        // because the dark bg now extends to the screen edge under them.
        HStack {
            ForEach(items) { item in
                let label = item.props.getString("label", default: "")
                let icon = item.props.getString("icon", default: "circle")
                let active = item.props.getBool("active")
                let badge = item.props.getString("badge", default: "")
                let news = item.props.getBool("news")

                let showLabel: Bool = {
                    switch labelVisibility {
                    case "unlabeled": return false
                    case "selected":  return active
                    default:          return true                 // "labeled"
                    }
                }()

                Button {
                    if item.onPress != 0 {
                        NativeElementBridge.sendPressEvent(item.onPress, nodeId: item.id)
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            NativeIconView(icon, pointSize: 24, relativeTo: .body)
                                .nuiScaledFont(size: 24)
                            if !badge.isEmpty {
                                Text(badge)
                                    .nuiScaledFont(size: 10, weight: .bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 8, y: -6)
                            } else if news {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -2)
                            }
                        }
                        if showLabel && !label.isEmpty {
                            Text(label)
                                .nuiScaledFont(size: 11, fontName: barFont.isEmpty ? nil : barFont)
                        }
                    }
                    .foregroundColor(active ? activeColor : inactiveColor)
                    .frame(maxWidth: .infinity)
                }
                // Announce the item name even when label_visibility hides the
                // visible text, and expose the active state to VoiceOver.
                .modifier(A11yLabelModifier(label: label))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 8 + safeAreaBottom)   // home-indicator inset
        .background(barBackground)
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

// MARK: - Side Nav (stores node for drawer)

struct NativeUISideNavRenderer: View {
    let node: NativeUINode

    var body: some View {
        // Side nav content is rendered by the drawer scaffold, not inline
        EmptyView()
    }
}
