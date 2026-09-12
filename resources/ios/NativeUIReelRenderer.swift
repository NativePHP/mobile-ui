import SwiftUI

/// Full-screen snap pager (`reel`). A paging `ScrollView` lays out `count`
/// logical pages, each sized to the container; PHP ships only the children
/// inside `window_from..window_to` and every other page shows a
/// placeholder until the next render brings it in.
///
/// Media on a page plays itself based on its own on-screen visibility
/// (media-player's `video_player` does), so this renderer knows nothing
/// about playback and nothing in core mediates.
///
/// Page-change protocol: once the scroll phase goes idle, the page nearest
/// the leading edge → `on_page_change` over the TAB_CHANGE transport (one
/// int). The pager position survives re-renders; the `page` prop
/// only moves it when PHP sends an index that differs from the one native
/// last reported (a programmatic jump).
///
/// See `src/Elements/Reel.php` for the matching element class.
struct NativeUIReelRenderer: View {
    let node: NativeUINode

    var body: some View {
        let p = node.props
        let count = max(0, p.getInt("count", default: node.children.count))
        let windowFrom = p.getInt("window_from")
        // `has_more` appends one loading page after the last loaded item —
        // a feed has no total, so the user can pull into the tail while
        // PHP fetches the next batch. Settling there reports index == count.
        let hasMore = p.getBool("has_more")
        let pageCount = hasMore ? count + 1 : count
        let requestedPage = min(max(0, p.getInt("page")), max(0, pageCount - 1))

        let pageByIndex: [Int: NativeUINode] = {
            var map: [Int: NativeUINode] = [:]
            map.reserveCapacity(node.children.count)
            for (offset, child) in node.children.enumerated() {
                map[windowFrom + offset] = child
            }
            return map
        }()

        ReelBody(
            nodeId: node.id,
            count: pageCount,
            loaded: count,
            requestedPage: requestedPage,
            horizontal: p.getBool("horizontal"),
            cbId: p.getCallbackId("on_page_change"),
            pageByIndex: pageByIndex
        )
        .modifier(ReelA11yLabelModifier(label: p.getString("a11y_label")))
    }
}

/// Owns the scroll position state so it outlives parent re-renders.
private struct ReelBody: View {
    let nodeId: Int
    /// Pages laid out, including the trailing loading page when `has_more`.
    let count: Int
    /// Items PHP has loaded; indexes at or past this are the loading tail.
    let loaded: Int
    let requestedPage: Int
    let horizontal: Bool
    let cbId: Int
    let pageByIndex: [Int: NativeUINode]

    /// Programmatic-jump binding only. Reading it back is useless here:
    /// under `.paging` it goes nil the moment the pager moves.
    @State private var position: Int?
    /// Page nearest the leading edge, derived from the scroll geometry.
    @State private var leading: Int
    /// The index PHP knows about — what we last sent, or what it last sent.
    @State private var knownPage: Int

    init(nodeId: Int, count: Int, loaded: Int, requestedPage: Int, horizontal: Bool, cbId: Int, pageByIndex: [Int: NativeUINode]) {
        self.nodeId = nodeId
        self.count = count
        self.loaded = loaded
        self.requestedPage = requestedPage
        self.horizontal = horizontal
        self.cbId = cbId
        self.pageByIndex = pageByIndex
        _position = State(initialValue: requestedPage)
        _leading = State(initialValue: requestedPage)
        _knownPage = State(initialValue: requestedPage)
    }

    var body: some View {
        let axis: Axis.Set = horizontal ? .horizontal : .vertical

        // Pages are sized to the reel's measured frame — the visible
        // viewport. Under a navigation bar the ScrollView extends beneath
        // the bar and insets its content by the bar height; `.paging`
        // steps by the visible length, so this is the one sizing that
        // snaps cleanly. (`containerRelativeFrame` and `.ignoresSafeArea`
        // both size pages against the extended container and drift by
        // the inset on every swipe.)
        GeometryReader { geo in
            ScrollView(axis) {
                pages(size: geo.size)
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(0)
            // `visibleRect` is inset-adjusted: its origin is 0 on page 0
            // and its length is the viewport, whatever the bar insets are.
            .onScrollGeometryChange(for: Int.self) { geometry in
                let visible = geometry.visibleRect
                let length = horizontal ? visible.width : visible.height
                guard length > 0, count > 0 else { return 0 }
                let offset = horizontal ? visible.minX : visible.minY
                return min(count - 1, max(0, Int((offset / length).rounded())))
            } action: { _, page in
                leading = page
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .idle else { return }
                report(leading)
            }
            .onChange(of: requestedPage) { _, page in
                guard page != knownPage else { return }
                knownPage = page
                position = page
            }
        }
    }

    /// Deliberately NOT a lazy stack. Only the shipped window (a handful
    /// of pages) is real content; everything else is a flat colour, so a
    /// plain stack stays cheap into the hundreds of pages. A lazy stack
    /// would materialise the next page only as it scrolls in, so its
    /// video surface would be created mid-swipe and pop from black to
    /// its first frame in front of the user. This way a neighbour is live
    /// (and buffering) the moment PHP ships it.
    @ViewBuilder
    private func pages(size: CGSize) -> some View {
        if horizontal {
            HStack(spacing: 0) { pageViews(size: size) }
        } else {
            VStack(spacing: 0) { pageViews(size: size) }
        }
    }

    private func pageViews(size: CGSize) -> some View {
        ForEach(0..<count, id: \.self) { index in
            Group {
                if let child = pageByIndex[index] {
                    NodeView(node: child).equatable()
                } else if index >= loaded {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading")
                } else {
                    // Transparent: the reel's own background (`bg-*` on the
                    // tag) shows through, so an unshipped page never flashes
                    // a system colour over a dark feed.
                    Color.clear
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .id(index)
        }
    }

    private func report(_ index: Int) {
        guard cbId != 0, index != knownPage else { return }
        knownPage = index
        NativeElementBridge.sendTabChangeEvent(cbId, nodeId: nodeId, index: index)
    }
}

private struct ReelA11yLabelModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        if label.isEmpty { content } else { content.accessibilityLabel(label) }
    }
}
