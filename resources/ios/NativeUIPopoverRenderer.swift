import SwiftUI
import UIKit

/// Popover — a bubble beside the spot this element is laid over, driven by
/// `visible`. The element draws nothing and takes no touches; its children
/// are the bubble's content.
///
/// A system popover, kept a popover on iPhone with
/// `presentationCompactAdaptation(.popover)`. On iOS 18.1+ a single
/// `arrowEdge` pins the side, so the renderer picks it: the preferred side
/// (`placement`, top by default) unless the bubble wouldn't fit between the
/// anchor and the window's safe area there, in which case the other.
///
/// `on_dismiss` fires when the person closes it (a tap outside), never when
/// PHP sets `visible` false.
///
/// Model 3: the bubble's background is `theme.surface`.
struct NativeUIPopoverRenderer: View {
    let node: NativeUINode

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPresented = false
    @State private var anchor: CGRect = .zero
    /// The bubble's height the last time it showed. Before that, a guess
    /// that fits a row of buttons.
    @State private var bubbleHeight: CGFloat = 64

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)
        let visible = node.props.getBool("visible")
        let onDismissCb = node.props.getCallbackId("on_dismiss")
        let prefersBelow = node.props.getString("placement", default: "top") == "bottom"
        let a11yLabel = node.props.getString("a11y_label")
        let nodeId = node.id

        Color.clear
            .allowsHitTesting(false)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor = $0 }
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: opensBelow(prefersBelow: prefersBelow) ? .top : .bottom
            ) {
                VStack(spacing: 0) {
                    ForEach(node.children) { child in
                        NodeView(node: child).equatable()
                    }
                }
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bubbleHeight = $0 }
                .presentationCompactAdaptation(.popover)
                .presentationBackground(theme.surface)
                .modifier(A11yLabelModifier(label: a11yLabel))
            }
            .onAppear { isPresented = visible }
            .onChange(of: visible) { _, shown in isPresented = shown }
            .onChange(of: isPresented) { _, presented in
                // Closed by the system while PHP still has it open: the
                // person tapped outside it.
                if !presented && node.props.getBool("visible") && onDismissCb != 0 {
                    NativeUIBridge.sendSheetDismissEvent(onDismissCb, nodeId: nodeId)
                }
            }
    }

    /// Whether the bubble goes below the anchor: the preferred side when
    /// it fits there, otherwise the side with more room.
    private func opensBelow(prefersBelow: Bool) -> Bool {
        let window = Self.keyWindow
        let insets = window?.safeAreaInsets ?? .zero
        let height = window?.bounds.height ?? UIScreen.main.bounds.height
        // The arrow and a little air on either side of it.
        let needed = bubbleHeight + 24
        let above = anchor.minY - insets.top
        let below = height - insets.bottom - anchor.maxY

        if prefersBelow {
            return below >= needed || below >= above
        }

        return above < needed && below > above
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityElement(children: .contain).accessibilityLabel(label) }
    }
}
