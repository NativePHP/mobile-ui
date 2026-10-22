import SwiftUI

/// SwiftUI TabRow — horizontal tab strip with underline indicator on the
/// selected tab. Scrollable when tabs overflow.
///
/// Echo-prevention on the selected-index integer (plan K). Theme-sourced
/// colors — active tab uses `theme.primary`, inactive uses
/// `theme.onSurfaceVariant`. Underline uses `theme.primary`.
struct NativeUITabRowRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedIndex: Int = 0
    @State private var lastSentValue: Int = 0
    @State private var initialized: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let serverValue = p.getInt("value")
        let onChangeCb  = p.getCallbackId("on_change")
        let a11yLabel   = p.getString("a11y_label")

        let tabs = node.children.filter { $0.type == "tab" }
        guard !tabs.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            let label = tab.props.getString("label")
                            let icon  = tab.props.getString("icon")
                            let tabA11y = tab.props.getString("a11y_label")
                            let isSelected = index == selectedIndex
                            // Icon-only tabs (no visible label) must still be
                            // labeled for VoiceOver: prefer the explicit
                            // a11y_label, then a humanized icon name. Tabs
                            // with a visible label are read automatically.
                            let effectiveA11y = !tabA11y.isEmpty
                                ? tabA11y
                                : (label.isEmpty
                                    ? (NativeIcon.customName(icon) ?? icon).replacingOccurrences(of: "_", with: " ")
                                          .replacingOccurrences(of: "-", with: " ")
                                    : "")

                            Button(action: {
                                selectedIndex = index
                                lastSentValue = index
                                if onChangeCb != 0 {
                                    NativeElementBridge.sendTabChangeEvent(onChangeCb, nodeId: node.id, index: index)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    if !icon.isEmpty {
                                        NativeIcon.image(icon)
                                    }
                                    if !label.isEmpty {
                                        Text(label).nuiScaledFont(size: theme.fontSm, weight: .medium)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .foregroundStyle(isSelected ? theme.primary : theme.onSurfaceVariant)
                                // Extend the hit area to 44pt without changing
                                // the visual label/padding metrics.
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Rectangle()
                                        .fill(theme.primary)
                                        .frame(height: 2)
                                }
                            }
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                            .modifier(A11yLabelModifier(label: effectiveA11y))
                        }
                    }
                }
                Rectangle().fill(theme.outline).frame(height: 1)
            }
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

/// No-op placeholder — tabs are rendered by TabRowRenderer.
struct NativeUITabRenderer: View {
    let node: NativeUINode
    var body: some View { EmptyView() }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
