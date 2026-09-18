import SwiftUI

/// Bottom sheet — slides up from the bottom, driven by `visible`. Uses
/// SwiftUI's `.sheet` with `presentationDetents` so system drag-to-dismiss
/// and detent snapping come for free.
///
/// Model 3: container color from `theme.surface`. No per-instance override.
struct NativeUIBottomSheetRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPresented: Bool = false

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let visible = node.props.getBool("visible")
        let onDismissCb = node.props.getCallbackId("on_dismiss")
        let detentsStr = node.props.getString("detents", default: "medium,large")
        let a11yLabel = node.props.getString("a11y_label")
        // Flighty/Maps-style always-on panel: no swipe-away, and the view
        // behind stays interactive (HIG "sheets with interaction behind").
        let permanent = node.props.getBool("permanent")
        let bgInteraction = node.props.getBool("background_interaction")

        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: $isPresented, onDismiss: {
                if onDismissCb != 0 {
                    NativeUIBridge.sendSheetDismissEvent(onDismissCb, nodeId: node.id)
                }
            }) {
                VStack(spacing: 0) {
                    ForEach(node.children) { child in
                        NodeView(node: child).equatable()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(theme.surface)
                .presentationDetents(resolveDetents(detentsStr))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(permanent)
                .presentationBackgroundInteraction(bgInteraction ? .enabled : .automatic)
                .modifier(A11yLabelModifier(label: a11yLabel))
            }
            .onAppear { isPresented = visible }
            .onChange(of: visible) { _, v in isPresented = v }
    }

    private func resolveDetents(_ str: String) -> Set<PresentationDetent> {
        let parts = str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var detents = Set<PresentationDetent>()
        for part in parts {
            switch part {
            case "small":  detents.insert(.fraction(0.25))
            case "medium": detents.insert(.medium)
            case "large":  detents.insert(.large)
            case "full":   detents.insert(.fraction(1.0))
            default:
                if let fraction = Double(part), fraction > 0, fraction <= 1 {
                    detents.insert(.fraction(CGFloat(fraction)))
                }
            }
        }
        return detents.isEmpty ? [.medium, .large] : detents
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
