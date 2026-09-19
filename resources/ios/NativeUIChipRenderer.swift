import SwiftUI

/// SwiftUI Chip — compact selectable tag. Capsule with optional leading icon.
///
/// Echo-prevention (plan K) on bool selected state. Theme-sourced colors —
/// primary for active, surfaceVariant + outline for inactive (Model 3).
///
/// `glass` Tailwind family swaps the capsule fill for Liquid Glass (iOS 26+
/// real `.glassEffect(...)`, fallback `.regularMaterial`). The chip is
/// registered in `NodeStyleModifier.glassHandledByRenderer` so the outer
/// wrapper doesn't double-paint a glass plate behind the rectangular frame.
///
/// Bit 1 (prominent) is ignored — `.glassEffect()` has no prominent variant.
/// Bit 2 (interactive) chains `.interactive(true)` for press-highlight.
struct NativeUIChipRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSelected: Bool = false
    @State private var lastSentValue: Bool = false
    @State private var initialized: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let serverValue = p.getBool("value")
        let label       = p.getString("label")
        let iconName    = p.getString("icon")
        let onChangeCb  = p.getCallbackId("on_change")
        let onPressCb   = p.getCallbackId("on_press") != 0 ? p.getCallbackId("on_press") : node.onPress
        let disabled    = p.getBool("disabled")
        let a11yLabel   = p.getString("a11y_label")
        let a11yHint    = p.getString("a11y_hint")

        let glassFlags = p.getInt("glass", default: 0)
        let glassEnabled     = (glassFlags & 1) != 0
        let glassInteractive = (glassFlags & 4) != 0
        let glassClear       = (glassFlags & 8) != 0
        let hasUserBg        = (node.style?.bgColor ?? 0) != 0

        let bg = isSelected ? theme.primary : theme.surfaceVariant
        let fg = isSelected ? theme.onPrimary : theme.onSurface
        let border = isSelected ? theme.primary : theme.outline

        Button(action: {
            guard !disabled else { return }
            if onPressCb != 0 {
                // Server-driven: the press handler owns selection. Toggling
                // locally would make the chip fight the state it is handed
                // back, so a filter chip would flicker off on its own tap.
                NativeElementBridge.sendPressEvent(onPressCb, nodeId: node.id)
            } else {
                let new = !isSelected
                isSelected = new
                lastSentValue = new
                if onChangeCb != 0 {
                    NativeElementBridge.sendToggleChangeEvent(onChangeCb, nodeId: node.id, value: new)
                }
            }
        }) {
            HStack(spacing: 6) {
                if !iconName.isEmpty {
                    Image(systemName: getIconForName(iconName))
                        .nuiScaledFont(size: 14)
                }
                Text(label).nuiScaledFont(size: theme.fontSm, weight: .medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(fg)
            .modifier(ChipBackgroundModifier(
                fillColor: bg,
                borderColor: border,
                glassEnabled: glassEnabled,
                glassInteractive: glassInteractive,
                glassClear: glassClear,
                hasUserBg: hasUserBg
            ))
            // Extend the hit area to a 44pt-tall band without inflating the
            // visual pill (the capsule background is painted above, so the
            // extra frame height stays transparent).
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .onAppear {
            if !initialized {
                isSelected = serverValue
                lastSentValue = serverValue
                initialized = true
            }
        }
        .onChange(of: serverValue) { _, new in
            if new != lastSentValue {
                isSelected = new
                lastSentValue = new
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .modifier(A11yLabelModifier(label: a11yLabel))
        .modifier(A11yHintModifier(hint: a11yHint))
    }
}

/// Picks between solid capsule fill and Liquid Glass for the chip background.
/// Border is always painted on top so the chip's selected/unselected state
/// remains visible against either surface treatment.
private struct ChipBackgroundModifier: ViewModifier {
    let fillColor: Color
    let borderColor: Color
    let glassEnabled: Bool
    let glassInteractive: Bool
    let glassClear: Bool
    /// True when the user supplied a `bg-*` class. Skip the state-driven
    /// capsule fill so NodeStyleModifier's user-bg paint isn't covered.
    let hasUserBg: Bool

    func body(content: Content) -> some View {
        let shape = Capsule()
        let bordered = AnyView(
            content.overlay(shape.stroke(borderColor, lineWidth: 1))
        )

        if glassEnabled, #available(iOS 26.0, *) {
            if glassClear {
                bordered.glassEffect(.clear.interactive(glassInteractive), in: shape)
            } else {
                bordered.glassEffect(.regular.interactive(glassInteractive), in: shape)
            }
        } else if glassEnabled {
            bordered.background(
                shape.fill(glassClear ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
            )
        } else if hasUserBg {
            // User bg wins — paint nothing here, NodeStyleModifier already
            // painted the user's color beneath us.
            bordered
        } else {
            bordered.background(shape.fill(fillColor))
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

private struct A11yHintModifier: ViewModifier {
    let hint: String
    func body(content: Content) -> some View {
        if hint.isEmpty { content }
        else { content.accessibilityHint(hint) }
    }
}
