import SwiftUI
import UIKit

/// Single-choice segmented selector: the system `UISegmentedControl` (Liquid
/// Glass on iOS 26), like Android's Material `SingleChoiceSegmentedButtonRow`.
/// The selected segment takes theme.primary with onPrimary text, the same
/// colours as Android.
///
/// Echo-prevention on selected-index (plan K). Theme-sourced colors — no
/// per-instance `color` override (Model 3).
struct NativeUIButtonGroupRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let p = node.props
        let options   = p.getStringList("options")
        let disabled  = p.getBool("disabled")
        let a11yLabel = p.getString("a11y_label")

        guard !options.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            SegmentedControl(
                nodeId: node.id,
                options: options,
                serverValue: p.getInt("value"),
                onChangeCb: p.getCallbackId("on_change"),
                selectedTint: UIColor(theme.primary),
                selectedText: UIColor(theme.onPrimary),
                text: UIColor(theme.onSurface)
            )
            .disabled(disabled)
            .modifier(A11yLabelModifier(label: a11yLabel))
        )
    }
}

private struct SegmentedControl: UIViewRepresentable {
    let nodeId: Int
    let options: [String]
    let serverValue: Int
    let onChangeCb: Int
    let selectedTint: UIColor
    let selectedText: UIColor
    let text: UIColor

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options)
        control.selectedSegmentIndex = serverValue
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        context.coordinator.lastSentValue = serverValue
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        let coordinator = context.coordinator
        coordinator.nodeId = nodeId
        coordinator.onChangeCb = onChangeCb

        let titles = (0..<control.numberOfSegments).map { control.titleForSegment(at: $0) ?? "" }
        if titles != options {
            control.removeAllSegments()
            for (index, label) in options.enumerated() {
                control.insertSegment(withTitle: label, at: index, animated: false)
            }
            control.selectedSegmentIndex = coordinator.lastSentValue
        }

        // Only a server value we didn't just send moves the selection, so a
        // round-trip never snaps the control back mid-tap.
        if serverValue != coordinator.lastSentValue {
            control.selectedSegmentIndex = serverValue
            coordinator.lastSentValue = serverValue
        }

        control.selectedSegmentTintColor = selectedTint
        control.setTitleTextAttributes([.foregroundColor: selectedText], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: text], for: .normal)
        control.isEnabled = context.environment.isEnabled
    }

    /// Fill the offered width, keep the system height.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        let natural = uiView.intrinsicContentSize
        return CGSize(width: proposal.width ?? natural.width, height: natural.height)
    }

    final class Coordinator: NSObject {
        var nodeId = 0
        var onChangeCb = 0
        var lastSentValue = 0

        @objc func valueChanged(_ control: UISegmentedControl) {
            let index = control.selectedSegmentIndex
            lastSentValue = index
            if onChangeCb != 0 {
                NativeElementBridge.sendTabChangeEvent(onChangeCb, nodeId: nodeId, index: index)
            }
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
