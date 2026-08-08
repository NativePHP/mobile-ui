import SwiftUI

/// SwiftUI RadioGroup — vertical stack of `<radio>` children with
/// single-selection state owned by the group.
///
/// Echo-prevention (plan K), theme-sourced colors (Model 3).
struct NativeUIRadioGroupRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedValue: String = ""
    @State private var lastSentValue: String = ""
    @State private var initialized: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let serverValue = node.props.getString("value")
        let label       = node.props.getString("label")
        let onChangeCb  = node.props.getCallbackId("on_change")
        let groupDisabled = node.props.getBool("disabled")
        let a11yLabel   = node.props.getString("a11y_label")
        let a11yHint    = node.props.getString("a11y_hint")
        let isError     = node.props.getBool("is_error")
        let supporting  = node.props.getString("supporting")

        // Error state rides the hint channel unless an explicit hint is
        // set (same convention as the text inputs).
        let errorText = (isError && !supporting.isEmpty) ? supporting : ""
        let effectiveA11yHint = a11yHint.isEmpty ? errorText : a11yHint

        VStack(alignment: .leading, spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .nuiScaledFont(size: theme.fontSm, weight: .medium)
                    .foregroundStyle(isError ? theme.destructive : theme.onSurfaceVariant)
            }

            ForEach(node.children.filter { $0.type == "radio" }) { child in
                NativeUIRadioRenderer(
                    node: child,
                    selectedValue: selectedValue,
                    groupDisabled: groupDisabled,
                    theme: theme,
                    onSelect: { value in
                        selectedValue = value
                        lastSentValue = value
                        if onChangeCb != 0 {
                            NativeElementBridge.sendRadioChangeEvent(onChangeCb, nodeId: node.id, value: value)
                        }
                    }
                )
            }

            if !supporting.isEmpty {
                Text(supporting)
                    .nuiScaledFont(size: theme.fontSm)
                    .foregroundStyle(isError ? theme.destructive : theme.onSurfaceVariant)
            }
        }
        .onAppear {
            if !initialized {
                selectedValue = serverValue
                lastSentValue = serverValue
                initialized = true
            }
        }
        .onChange(of: serverValue) { _, new in
            if new != lastSentValue {
                selectedValue = new
                lastSentValue = new
            }
        }
        .modifier(A11yLabelModifier(label: a11yLabel))
        .modifier(A11yHintModifier(hint: effectiveA11yHint))
    }
}

struct NativeUIRadioRenderer: View {
    let node: NativeUINode
    let selectedValue: String
    let groupDisabled: Bool
    let theme: NativeUITokens
    let onSelect: (String) -> Void

    var body: some View {
        let p = node.props
        let value    = p.getString("value")
        let label    = p.getString("label")
        let disabled = groupDisabled || p.getBool("disabled")
        let isSelected = selectedValue == value

        Button(action: {
            guard !disabled else { return }
            onSelect(value)
        }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .nuiScaledFont(size: 22)
                    .foregroundColor(isSelected ? theme.primary : theme.onSurfaceVariant)
                if !label.isEmpty {
                    Text(label).nuiScaledFont(size: 17).foregroundColor(theme.onSurface)
                }
            }
            .nuiMinTapTarget()
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
