import SwiftUI

/// Bottom sheet — slides up from the bottom, driven by `visible`. Uses
/// SwiftUI's `.sheet` with `presentationDetents` so system drag-to-dismiss
/// and detent snapping come for free.
///
/// A `title` gives the sheet the system's own bar, as Apple's sheets have
/// (`SheetTitleBar`). An untitled sheet is the bare panel.
///
/// Model 3: container color from `theme.surface`. No per-instance override.
struct NativeUIBottomSheetRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPresented: Bool = false
    /// PHP set `visible` to false, and the sheet hasn't finished closing yet.
    @State private var closedByPhp: Bool = false
    @State private var fitHeight: CGFloat?
    // A titled fit sheet is as tall as its content and its bar together.
    @State private var contentHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
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
        let title = node.props.getString("title")
        let closeLabel = node.props.getString("close_label")

        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: $isPresented, onDismiss: {
                // SwiftUI calls onDismiss for every close, also the one PHP
                // asked for, and it writes the binding for both, so only
                // present(false) can tell them apart. Report the user's
                // dismissals only, as Android's onDismissRequest does.
                if closedByPhp {
                    closedByPhp = false
                    return
                }
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
                        contentHeight = height
                        if fits, height > 0 { fitHeight = height + barHeight }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.surface)
                    .modifier(SheetTitleBar(
                        title: title,
                        closeLabel: closeLabel,
                        closable: !permanent,
                        background: theme.surface,
                        close: { isPresented = false },
                        measured: { height in
                            barHeight = height
                            if fits, contentHeight > 0 { fitHeight = contentHeight + height }
                        }
                    ))
                }
                .onAppear {
                    NativeUIKeyboardAccessoryState.shared.sheetDepth += 1
                    // A close that never reached onDismiss must not swallow
                    // the user's dismissal of this presentation.
                    closedByPhp = false
                }
                .onDisappear { NativeUIKeyboardAccessoryState.shared.sheetDepth -= 1 }
                .modifier(DetentsModifier(
                    detents: resolveDetents(detentsStr),
                    selection: fits ? $selectedDetent : nil
                ))
                // The system shows the grabber only when the sheet can be
                // resized, as Apple's HIG has it. A single-detent sheet has
                // nothing to drag between, so a grabber would only mislead.
                .presentationDragIndicator(.automatic)
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
        if !visible && isPresented { closedByPhp = true }
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

/// A titled sheet is drawn as Apple's own sheets are (HIG, Sheets): its
/// content sits in a NavigationStack whose inline bar carries the title and
/// the system's close button on its leading edge, and the bar keeps the
/// content clear of the grabber. Closing is the user's dismissal, so it goes
/// through `isPresented` and onDismiss reports it as `@dismiss`, like a
/// swipe-down. `measured` hands over the bar's height, which a fit sheet
/// adds to its content's.
private struct SheetTitleBar: ViewModifier {
    let title: String
    let closeLabel: String
    let closable: Bool
    let background: Color
    let close: () -> Void
    let measured: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if title.isEmpty {
            content
        } else {
            NavigationStack {
                content
                    .background {
                        // Reaches up under the bar, so its top inset IS the bar.
                        background
                            .ignoresSafeArea()
                            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { measured($0) }
                    }
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar {
                        if closable {
                            ToolbarItem(placement: .cancellationAction) { closeButton }
                        }
                    }
            }
        }
    }

    /// The system's close button: `role: .close` on iOS 26, the filled
    /// circle sheets used before it. `close_label` replaces the system's
    /// VoiceOver label, so an app can pass its own translation.
    @ViewBuilder
    private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: close)
                .modifier(A11yLabelModifier(label: closeLabel))
        } else {
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(closeLabel.isEmpty ? "Close" : closeLabel)
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
