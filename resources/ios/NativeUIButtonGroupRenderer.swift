import SwiftUI

/// SwiftUI segmented selector. Each option renders as a pressable pill in a
/// horizontal bar; the active one gets a theme.primary fill + onPrimary text.
///
/// Echo-prevention on selected-index (plan K). Theme-sourced colors — no
/// per-instance `color` override (Model 3).
struct NativeUIButtonGroupRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedIndex: Int = 0
    @State private var lastSentValue: Int = 0
    @State private var initialized: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let options     = p.getStringList("options")
        let serverValue = p.getInt("value")
        let onChangeCb  = p.getCallbackId("on_change")
        let disabled    = p.getBool("disabled")
        let a11yLabel   = p.getString("a11y_label")

        guard !options.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    let isSelected = index == selectedIndex
                    let isFirst = index == 0
                    let isLast  = index == options.count - 1

                    Button(action: {
                        selectedIndex = index
                        lastSentValue = index
                        if onChangeCb != 0 {
                            NativeElementBridge.sendTabChangeEvent(onChangeCb, nodeId: node.id, index: index)
                        }
                    }) {
                        Text(label)
                            .nuiScaledFont(size: theme.fontSm, weight: .medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(isSelected ? theme.onPrimary : theme.onSurface)
                            .background(isSelected ? theme.primary : Color.clear)
                            // A plain-style button only hit-tests drawn content, so an
                            // unselected segment's clear background would leave just the
                            // label tappable. Make the whole segment the tap target.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius:     isFirst ? theme.radiusMd : 0,
                            bottomLeadingRadius:  isFirst ? theme.radiusMd : 0,
                            bottomTrailingRadius: isLast  ? theme.radiusMd : 0,
                            topTrailingRadius:    isLast  ? theme.radiusMd : 0
                        )
                    )
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

                    if !isLast {
                        Rectangle().fill(theme.outline).frame(width: 1, height: 36)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusMd)
                    .stroke(theme.outline, lineWidth: 1)
            )
            .opacity(disabled ? 0.5 : 1.0)
            .onAppear {
                if !initialized {
                    selectedIndex = serverValue
                    lastSentValue = serverValue
                    initialized = true
                }
            }
            .onChange(of: serverValue) { _, new in
                if new != lastSentValue {
                    selectedIndex = new
                    lastSentValue = new
                }
            }
            .modifier(A11yLabelModifier(label: a11yLabel))
        )
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
