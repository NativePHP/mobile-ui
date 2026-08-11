import SwiftUI
import UIKit

struct NativeUIScrollViewRenderer: View {
    let node: NativeUINode

    var body: some View {
        let horizontal = node.props.getBool("horizontal")
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let spacing = CGFloat(node.layout?.gap ?? 0)
        let axis = node.props.getString("axis", default: "")
        let stickBottom = node.props.getString("scroll_anchor", default: "") == "bottom"
        let messageSignal = stickBottom ? Self.descendantCount(node) : 0

        // 2D mode. Bypass the Lazy stacks (which force 1D layout) and use a
        // plain ZStack so each child renders at its declared frame. The
        // child should have explicit `w-[N]` / `h-[N]` larger than the
        // viewport; SwiftUI's `ScrollView([.horizontal, .vertical])`
        // handles the panning.
        if axis == "both" {
            // 2D pan content. Wrapping in a SwiftUI stack (ZStack/VStack)
            // here causes the inner content to inherit the stack's
            // proposal-driven sizing — ScrollView then proposes its
            // viewport, the stack collapses, and the vertical axis
            // rubber-bands. Idiomatic SwiftUI 2D scrolling places the
            // content view directly inside the ScrollView so the content's
            // own `.frame(...)` (set by NodeLayoutModifier from `w-[N]` /
            // `h-[N]` classes) drives the scrollable size.
            //
            // Multi-child 2D scrolls are rare (typical use is one large
            // image / canvas). For multiple children we layer them in a
            // ZStack pinned via `.fixedSize` and accept that NavigationStack
            // may wobble on the vertical axis — author can wrap in a
            // single `<stack>` child as a workaround.
            ScrollView([.horizontal, .vertical], showsIndicators: showsIndicators) {
                if node.children.count == 1, let only = node.children.first {
                    NodeView(node: only).equatable()
                } else {
                    ZStack(alignment: .topLeading) {
                        ForEach(node.children) { child in
                            NodeView(node: child).equatable()
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        } else if horizontal {
            ScrollView(.horizontal, showsIndicators: showsIndicators) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(node.children) { child in
                        NodeView(node: child)
                            .equatable()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        } else if hasFillHeightChild {
            // A `fill` / `h-full` child asked to be at least as tall as the
            // VIEWPORT — the "short screen centred, still scrolls when the
            // keyboard appears" pattern. Nothing inside a ScrollView knows the
            // viewport height (that's the whole point of a scroll view), so a
            // GeometryReader outside it measures the viewport and the height is
            // handed to the child as a MINIMUM.
            //
            // Only taken when a child actually asks: GeometryReader is greedy —
            // it claims all offered space and reports it — so wrapping every
            // scroll view in one would change how content-sized scroll views
            // measure. Gating keeps the common path byte-for-byte unchanged.
            GeometryReader { geo in
                verticalScroll(
                    showsIndicators: showsIndicators,
                    spacing: spacing,
                    stickBottom: stickBottom,
                    messageSignal: messageSignal,
                    viewportHeight: geo.size.height
                )
            }
        } else {
            verticalScroll(
                showsIndicators: showsIndicators,
                spacing: spacing,
                stickBottom: stickBottom,
                messageSignal: messageSignal,
                viewportHeight: nil
            )
        }
    }

    /// Whether any DIRECT child asked to fill the scroll view's height.
    ///
    /// Direct children only: `fill` resolves against the scroll viewport, and a
    /// nested descendant's fill resolves against ITS parent, which is ordinary
    /// flex behaviour and needs nothing from here.
    private var hasFillHeightChild: Bool {
        node.children.contains { $0.layout?.heightMode == SizeMode.fill }
    }

    /// The standard vertical scroll body.
    ///
    /// `viewportHeight` is non-nil only when a `fill`-height child is present;
    /// it becomes that child's minimum height so `justify-center` has space to
    /// distribute. It is a MINIMUM, not an exact height: content taller than
    /// the viewport must still grow and scroll, which is also what CSS
    /// `min-height: 100%` does.
    @ViewBuilder
    private func verticalScroll(
        showsIndicators: Bool,
        spacing: CGFloat,
        stickBottom: Bool,
        messageSignal: Int,
        viewportHeight: CGFloat?
    ) -> some View {
        // Chat-style bottom anchoring (`scroll-anchor="bottom"`). Deterministic
        // ScrollViewReader + a zero-height bottom anchor: scroll to it on
        // appear (open at the latest message) and whenever the content grows
        // (follow new messages). Works on every iOS version and with lazy
        // content, unlike `.defaultScrollAnchor` which is iOS 17+ and flaky
        // with LazyVStack. `messageSignal` is a recursive descendant count so
        // it changes even when messages sit inside a wrapping <column>.
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                LazyVStack(alignment: .leading, spacing: spacing) {
                    ForEach(node.children) { child in
                        NodeView(node: child)
                            .equatable()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Applied per-child rather than to the LazyVStack:
                            // a lazy stack sizes children to their ideal height
                            // and does NOT redistribute slack the way a plain
                            // VStack does, so a minimum on the stack would grow
                            // the stack and leave the child hugging regardless.
                            .modifier(MinViewportHeightModifier(
                                minHeight: child.layout?.heightMode == SizeMode.fill
                                    ? viewportHeight
                                    : nil
                            ))
                    }
                    if stickBottom {
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                            // Re-pin when the anchor itself materializes.
                            // The outer onAppear's one-runloop defer can
                            // still beat the lazy content's first layout
                            // when this scroll-view is embedded in another
                            // scrolling container (e.g. the Jump docs
                            // reader) — this fires after the anchor has
                            // real geometry, so the pin always lands.
                            .onAppear {
                                DispatchQueue.main.async {
                                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard stickBottom else { return }
                // Defer past first layout — lazy content isn't measured yet
                // inside onAppear, so an immediate scrollTo no-ops.
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: messageSignal) { _ in
                guard stickBottom else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            // The keyboard shrinks the scroll viewport (the screen shifts
            // up for keyboard avoidance). Re-pin the latest message to the
            // bottom so it stays visible just above the input row instead
            // of hiding behind it, moving IN SYNC with the keyboard: a
            // one-runloop `async` lets SwiftUI register the new (shrunk)
            // safe area so `scrollTo` targets the final layout, and the
            // scroll animates with the keyboard's own reported duration so
            // both travel together.
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)
            ) { note in
                guard stickBottom else { return }
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: duration)) {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let bottomAnchorID = "nphp.scroll.bottom.anchor"

    /// Recursive descendant count — a content signal that changes whenever a
    /// message is added anywhere in the subtree (even inside a wrapping
    /// <column> where the scroll-view itself has a single child).
    private static func descendantCount(_ node: NativeUINode) -> Int {
        var count = node.children.count
        for child in node.children {
            count += descendantCount(child)
        }
        return count
    }
}

/// Applies a minimum height only when there is one, so children that didn't
/// ask for viewport height keep the exact modifier chain they always had.
private struct MinViewportHeightModifier: ViewModifier {
    let minHeight: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let minHeight, minHeight > 0 {
            content.frame(minHeight: minHeight)
        } else {
            content
        }
    }
}
