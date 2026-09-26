import SwiftUI

/// SwiftUI Toggle renderer.
///
/// Binary on/off with echo-prevention value sync (plan K) and `sync_mode`
/// support (plan L — though for a discrete tap the behavior is the same
/// across modes; included for API consistency). Theme-sourced tint, no
/// per-instance color overrides (Model 3).
struct NativeUIToggleRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isOn: Bool = false
    @State private var lastSentValue: Bool = false
    @State private var initialized: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let serverValue = p.getBool("value")
        let onChangeCb  = p.getCallbackId("on_change")
        let disabled    = p.getBool("disabled")
        let label       = p.getString("label")
        let a11yLabel   = p.getString("a11y_label")
        let a11yHint    = p.getString("a11y_hint")

        Toggle(label, isOn: $isOn)
            .tint(theme.primary)
            .disabled(disabled)
            .onAppear {
                if !initialized {
                    isOn = serverValue
                    lastSentValue = serverValue
                    initialized = true
                }
            }
            .onChange(of: serverValue) { _, new in
                // Echo-prevention — ignore server pushes that match our last
                // commit; accept genuine programmatic updates.
                if new != lastSentValue {
                    isOn = new
                    lastSentValue = new
                }
            }
            .onChange(of: isOn) { _, new in
                // Setting isOn from the server value (onAppear, a server
                // push) also lands here; only a user tap should report.
                guard new != lastSentValue else { return }
                lastSentValue = new
                if onChangeCb != 0 {
                    NativeElementBridge.sendToggleChangeEvent(onChangeCb, nodeId: node.id, value: new)
                }
            }
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
