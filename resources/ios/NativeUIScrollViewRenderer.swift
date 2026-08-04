import SwiftUI
import UIKit

struct NativeUIScrollViewRenderer: View {
    let node: NativeUINode

    var body: some View {
        let horizontal = node.props.getBool("horizontal")
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let spacing = CGFloat(node.layout?.gap ?? 0)
        let axis = node.props.getString("axis", default: "")
        // Explicit index targeting (`auto-scroll-to`) wins over bottom
        // anchoring when both are set — the author named a specific child,
        // so honour that rather than yanking them to the end.
        let autoScrollIndex = node.props.getInt("auto_scroll_to", default: -1)
        let hasAutoScroll = autoScrollIndex >= 0
        let stickBottom = !hasAutoScroll && node.props.getString("scroll_anchor", default: "") == "bottom"
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
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: showsIndicators) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(node.children) { child in
                            NodeView(node: child)
                                .equatable()
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard hasAutoScroll else { return }
                    // Defer past first layout — lazy content isn't measured
                    // yet inside onAppear, so an immediate scrollTo no-ops.
                    DispatchQueue.main.async {
                        Self.scroll(proxy, to: autoScrollIndex, in: node, anchor: .leading)
                    }
                }
                .onChange(of: autoScrollIndex) { index in
                    withAnimation(.easeOut(duration: 0.25)) {
                        Self.scroll(proxy, to: index, in: node, anchor: .leading)
                    }
                }
            }
        } else {
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
                    guard stickBottom || hasAutoScroll else { return }
                    // Defer past first layout — lazy content isn't measured yet
                    // inside onAppear, so an immediate scrollTo no-ops.
                    DispatchQueue.main.async {
                        if hasAutoScroll {
                            Self.scroll(proxy, to: autoScrollIndex, in: node, anchor: .top)
                        } else {
                            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                // Follow an `auto-scroll-to` index as it moves — a chat log
                // binding it to the last message re-pins on every new arrival.
                .onChange(of: autoScrollIndex) { index in
                    withAnimation(.easeOut(duration: 0.25)) {
                        Self.scroll(proxy, to: index, in: node, anchor: .top)
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
    }

    private static let bottomAnchorID = "nphp.scroll.bottom.anchor"

    /// Bring the direct child at `index` into view. Indexes the scroll-view's
    /// OWN children, so a log wrapped in a `<column>` addresses the column,
    /// not the messages inside it. A negative or out-of-range index is a
    /// no-op — content that hasn't arrived yet must not crash the render, and
    /// `-1` is the "unset" sentinel for the prop.
    private static func scroll(_ proxy: ScrollViewProxy, to index: Int, in node: NativeUINode, anchor: UnitPoint) {
        guard index >= 0, index < node.children.count else { return }

        proxy.scrollTo(node.children[index].id, anchor: anchor)
    }

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
