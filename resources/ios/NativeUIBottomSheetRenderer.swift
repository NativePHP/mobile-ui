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
    @State private var fitHeight: CGFloat?
    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let visible = node.props.getBool("visible")
        let onDismissCb = node.props.getCallbackId("on_dismiss")
        let detentsStr = node.props.getString("detents", default: "medium,large")
        let fits = Self.detentTokens(detentsStr).contains("fit")
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
                // The sheet hosts its own keyboard accessory bar — the
                // screen-root host's bar sits BEHIND a presented sheet, so
                // fields inside the sheet publish to this copy instead
                // (`sheetDepth` makes the root host yield while we're up).
                NativeUIKeyboardAccessoryHost {
                    VStack(spacing: 0) {
                        ForEach(node.children) { child in
                            NodeView(node: child).equatable()
                        }
                    }
                    .fixedSize(horizontal: false, vertical: fits)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if fits, height > 0 { fitHeight = height }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.surface)
                }
                .onAppear { NativeUIKeyboardAccessoryState.shared.sheetDepth += 1 }
                .onDisappear { NativeUIKeyboardAccessoryState.shared.sheetDepth -= 1 }
                .modifier(DetentsModifier(
                    detents: resolveDetents(detentsStr),
                    selection: fits ? $selectedDetent : nil
                ))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(permanent)
                .presentationBackgroundInteraction(bgInteraction ? .enabled : .automatic)
                .modifier(A11yLabelModifier(label: a11yLabel))
            }
            .onAppear { present(visible) }
            .onChange(of: visible) { _, v in present(v) }
            .onChange(of: fitHeight) { old, _ in
                if selectedDetent == Self.fitDetent(for: old) { selectedDetent = fitDetent }
            }
    }

    private func present(_ visible: Bool) {
        if visible && !isPresented { selectedDetent = fitDetent }
        isPresented = visible
    }

    /// `.medium` stands in until the content has been measured: it doesn't
    /// shrink the screen behind the way `.large` does, so a sheet whose
    /// first measure lands after presenting only resizes, never re-scales.
    private var fitDetent: PresentationDetent { Self.fitDetent(for: fitHeight) }

    private static func fitDetent(for height: CGFloat?) -> PresentationDetent {
        height.map { .height($0) } ?? .medium
    }

    private static func detentTokens(_ str: String) -> [String] {
        str.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    private func resolveDetents(_ str: String) -> Set<PresentationDetent> {
        var detents = Set<PresentationDetent>()
        for part in Self.detentTokens(str) {
            switch part {
            case "small":  detents.insert(.fraction(0.25))
            case "medium": detents.insert(.medium)
            case "large":  detents.insert(.large)
            case "full":   detents.insert(.fraction(1.0))
            case "fit":    detents.insert(fitDetent)
            default:
                if let fraction = Double(part), fraction > 0, fraction <= 1 {
                    detents.insert(.fraction(CGFloat(fraction)))
                }
            }
        }
        return detents.isEmpty ? [.medium, .large] : detents
    }
}

/// A fit detent's height changes as the content does, and a sheet left
/// on a detent that's no longer in the set snaps elsewhere, so a fit
/// sheet binds its selection to follow. Other sheets keep SwiftUI's own.
private struct DetentsModifier: ViewModifier {
    let detents: Set<PresentationDetent>
    let selection: Binding<PresentationDetent>?

    func body(content: Content) -> some View {
        if let selection { content.presentationDetents(detents, selection: selection) }
        else { content.presentationDetents(detents) }
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}
