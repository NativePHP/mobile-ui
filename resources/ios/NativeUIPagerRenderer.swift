import SwiftUI

/// Full-screen snap pager (`pager`). A paging `ScrollView` lays out `count`
/// logical pages, each sized to the container; PHP ships only the children
/// inside `window_from..window_to` and every other page shows a
/// placeholder until the next render brings it in.
///
/// Media on a page plays itself based on its own on-screen visibility
/// (media-player's `video_player` does), so this renderer knows nothing
/// about playback and nothing in core mediates.
///
/// Page-change protocol: the page nearest the leading edge → `on_page_change`
/// over the TAB_CHANGE transport (one int), as soon as it becomes the
/// nearest one mid-swipe, or only once the scroll phase goes idle with
/// `report_on_settle`. The pager position survives re-renders; the `page`
/// prop only moves it when PHP sends an index that differs from the one
/// native last reported (a programmatic jump).
///
/// With `tabs`, a row of tabs sits above the pages (`PagerTabStrip`). It
/// reads the pager's scroll position every frame, so its indicator follows
/// the swipe and its highlight moves as the swipe passes halfway, without
/// PHP. A tap scrolls the pager there; a tap on the tab already showing
/// goes to PHP as `on_tab_reselect`.
///
/// See `src/Elements/Pager.php` for the matching element class.
struct NativeUIPagerRenderer: View {
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

        PagerBody(
            nodeId: node.id,
            count: pageCount,
            loaded: count,
            requestedPage: requestedPage,
            horizontal: p.getBool("horizontal"),
            reportOnSettle: p.getBool("report_on_settle"),
            cbId: p.getCallbackId("on_page_change"),
            pageByIndex: pageByIndex,
            placeholders: p.getStringList("placeholders"),
            tabs: PagerTabs(props: p),
            a11yLabel: p.getString("a11y_label")
        )
    }
}

/// Owns the scroll position state so it outlives parent re-renders.
private struct PagerBody: View {
    let nodeId: Int
    /// Pages laid out, including the trailing loading page when `has_more`.
    let count: Int
    /// Items PHP has loaded; indexes at or past this are the loading tail.
    let loaded: Int
    let requestedPage: Int
    let horizontal: Bool
    /// Report only once the scroll rests, not as soon as a page becomes the
    /// nearest one mid-swipe.
    let reportOnSettle: Bool
    let cbId: Int
    let pageByIndex: [Int: NativeUINode]
    /// Image per page index for pages PHP hasn't shipped; "" for none.
    let placeholders: [String]
    /// The tab row above the pages, if the pager has one.
    let tabs: PagerTabs?
    let a11yLabel: String

    /// Programmatic-jump binding only. Reading it back is useless here:
    /// under `.paging` it goes nil the moment the pager moves.
    @State private var position: Int?
    /// Page nearest the leading edge, derived from the scroll geometry.
    @State private var leading: Int
    /// Pages reported to PHP that it has not echoed back yet, oldest first.
    /// A `page` prop matching one of these is an echo, not a jump.
    @State private var reported: [Int]
    /// The page PHP last knew about: the one most recently sent to it, or
    /// the one it jumped to. Kept apart from the pending acknowledgements:
    /// an echo clears those, and without this the idle callback would
    /// report the same page a second time, repeating any pagination the
    /// handler does.
    @State private var lastReported: Int
    /// Where the pager is, in pages, for the tab row. Held but never read
    /// here, so a swipe redraws the row and not the pages.
    @State private var progress: PagerProgress

    /// Loaded-but-unshipped pages this far from the current one get their
    /// placeholder image; the rest stay empty. Wide enough that a fast
    /// flick past the shipped window lands on a still, small enough that a
    /// long feed never fetches stills it may never reach.
    static let placeholderRadius = 4

    init(nodeId: Int, count: Int, loaded: Int, requestedPage: Int, horizontal: Bool, reportOnSettle: Bool, cbId: Int, pageByIndex: [Int: NativeUINode], placeholders: [String], tabs: PagerTabs?, a11yLabel: String) {
        self.nodeId = nodeId
        self.count = count
        self.loaded = loaded
        self.requestedPage = requestedPage
        self.horizontal = horizontal
        self.reportOnSettle = reportOnSettle
        self.cbId = cbId
        self.pageByIndex = pageByIndex
        self.placeholders = placeholders
        self.tabs = tabs
        self.a11yLabel = a11yLabel
        _position = State(initialValue: requestedPage)
        _leading = State(initialValue: requestedPage)
        _reported = State(initialValue: [requestedPage])
        _lastReported = State(initialValue: requestedPage)
        _progress = State(initialValue: PagerProgress(CGFloat(requestedPage)))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let tabs {
                PagerTabStrip(tabs: tabs, progress: progress, select: selectTab)
            }
            pager
                .modifier(PagerA11yLabelModifier(label: a11yLabel))
        }
    }

    @ViewBuilder
    private var pager: some View {
        let axis: Axis.Set = horizontal ? .horizontal : .vertical

        // Pages are sized to the pager's measured frame — the visible
        // viewport. Under a navigation bar the ScrollView extends beneath
        // the bar and insets its content by the bar height; `.paging`
        // steps by the visible length, so this is the one sizing that
        // snaps cleanly. (`containerRelativeFrame` and `.ignoresSafeArea`
        // both size pages against the extended container and drift by
        // the inset on every swipe.)
        GeometryReader { geo in
            // A horizontal pager runs under a bar at the bottom of the
            // screen (a tab bar), as a screen's own list does. Its pages
            // take the full height and hand the bar's inset back to their
            // content as safe area, so a list in a page draws under the
            // bar and still scrolls its last row clear of it. Paging is
            // sideways, so the extra height can't make the pages drift.
            let bottomInset = horizontal ? geo.safeAreaInsets.bottom : 0
            ScrollView(axis) {
                pages(size: CGSize(width: geo.size.width, height: geo.size.height + bottomInset), bottomInset: bottomInset)
                    .scrollTargetLayout()
            }
            .ignoresSafeArea(.container, edges: horizontal ? .bottom : [])
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
                // Report the moment a page becomes the nearest one, mid-swipe,
                // so PHP's round-trip overlaps the animation instead of
                // starting after it. Idle re-reports the same page (no-op).
                // With `report_on_settle` only idle reports, so the frame
                // the report causes never lands during the animation.
                if !reportOnSettle {
                    report(page)
                }
            }
            // The same position, unrounded, for the tab row. Nil until the
            // pager has a size, so the row doesn't flash the first tab.
            .onScrollGeometryChange(for: CGFloat?.self) { geometry in
                let visible = geometry.visibleRect
                let length = horizontal ? visible.width : visible.height
                guard length > 0 else { return nil }
                return (horizontal ? visible.minX : visible.minY) / length
            } action: { _, value in
                if tabs != nil, let value {
                    progress.value = value
                }
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .idle else { return }
                report(leading)
            }
            .onChange(of: requestedPage) { _, page in
                // An echo of something we reported: drop it and everything
                // reported before it. Anything else is a programmatic jump.
                // PHP asked for that page, so it already knows it. Without
                // this, on settle, a jump that never reaches the idle report
                // leaves `lastReported` on the old page, and a swipe back to
                // that page would go unreported.
                if let at = reported.firstIndex(of: page) {
                    reported.removeFirst(at + 1)
                    return
                }
                reported = [page]
                lastReported = page
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
    ///
    /// Placeholder images are the one thing that would make the eager
    /// stack expensive, so they only exist within `placeholderRadius` of
    /// the current page; further slots are clear until scrolled towards.
    @ViewBuilder
    private func pages(size: CGSize, bottomInset: CGFloat) -> some View {
        if horizontal {
            HStack(spacing: 0) { pageViews(size: size, bottomInset: bottomInset) }
        } else {
            VStack(spacing: 0) { pageViews(size: size, bottomInset: bottomInset) }
        }
    }

    private func pageViews(size: CGSize, bottomInset: CGFloat) -> some View {
        ForEach(0..<count, id: \.self) { index in
            Group {
                if let child = pageByIndex[index] {
                    NodeView(node: child).equatable()
                } else if index >= loaded {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading")
                } else if abs(index - leading) <= Self.placeholderRadius {
                    placeholder(index)
                } else {
                    Color.clear
                        .accessibilityHidden(true)
                }
            }
            .safeAreaPadding(.bottom, bottomInset)
            .frame(width: size.width, height: size.height)
            .clipped()
            .id(index)
        }
    }

    /// A tap on a tab: scroll there, and the page is reported when the
    /// pager settles as for a swipe. The tab already showing goes to PHP
    /// instead, usually to take its page back to the top.
    private func selectTab(_ index: Int) {
        guard index >= 0, index < count else { return }

        if index == leading, abs(progress.value - CGFloat(index)) < 0.01 {
            if let cb = tabs?.reselectCbId, cb != 0 {
                NativeElementBridge.sendTabChangeEvent(cb, nodeId: nodeId, index: index)
            }
            return
        }

        withAnimation { position = index }
    }

    private func report(_ index: Int) {
        guard cbId != 0, lastReported != index else { return }
        lastReported = index
        reported.append(index)
        NativeElementBridge.sendTabChangeEvent(cbId, nodeId: nodeId, index: index)
    }

    /// An unshipped page: its placeholder image if PHP gave one, else
    /// nothing (the pager's own background shows through).
    @ViewBuilder
    private func placeholder(_ index: Int) -> some View {
        if index < placeholders.count, !placeholders[index].isEmpty, let url = URL(string: placeholders[index]) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .accessibilityHidden(true)
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }
}

private struct PagerA11yLabelModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        if label.isEmpty { content } else { content.accessibilityLabel(label) }
    }
}

/// The pager's scroll position in pages: 1.5 is halfway from the second
/// page to the third. Observable so only the views that read it (the tab
/// row) redraw as it changes every frame.
@Observable
private final class PagerProgress {
    var value: CGFloat

    init(_ value: CGFloat) {
        self.value = value
    }
}

/// The `tabs` row and its look, read from the pager's props. Colours are
/// ARGB and nil where PHP sent none, so the row falls back to the theme.
private struct PagerTabs {
    let labels: [String]
    let a11yLabels: [String]
    let scrollable: Bool
    let reselectCbId: Int
    let color: (light: Int?, dark: Int?)
    let activeColor: (light: Int?, dark: Int?)
    let indicatorColor: (light: Int?, dark: Int?)
    let dividerColor: (light: Int?, dark: Int?)
    let font: String
    let fontSize: CGFloat?
    let indicatorHeight: CGFloat
    let paddingX: CGFloat
    let paddingTop: CGFloat
    let paddingBottom: CGFloat
    let edgePadding: CGFloat

    init?(props p: GenericProps) {
        let labels = p.getStringList("tabs")
        guard !labels.isEmpty else { return nil }

        func color(_ key: String) -> (light: Int?, dark: Int?) {
            (p.has(key) ? p.getColor(key, default: 0) : nil,
             p.has("dark_" + key) ? p.getColor("dark_" + key, default: 0) : nil)
        }

        func points(_ key: String, _ fallback: CGFloat) -> CGFloat {
            p.has(key) ? CGFloat(p.getFloat(key)) : fallback
        }

        self.labels = labels
        self.a11yLabels = p.getStringList("tab_a11y_labels")
        self.scrollable = p.getBool("tabs_scrollable")
        self.reselectCbId = p.getCallbackId("on_tab_reselect")
        self.color = color("tab_color")
        self.activeColor = color("tab_active_color")
        self.indicatorColor = color("tab_indicator_color")
        self.dividerColor = color("tab_divider_color")
        self.font = p.getString("tab_font")
        self.fontSize = p.has("tab_font_size") ? CGFloat(p.getFloat("tab_font_size")) : nil
        self.indicatorHeight = points("tab_indicator_height", 3)
        self.paddingX = points("tab_padding_x", 12)
        self.paddingTop = points("tab_padding_top", 14)
        self.paddingBottom = points("tab_padding_bottom", 11)
        self.edgePadding = points("tab_edge_padding", 4)
    }
}

/// The row of tabs above a pager's pages. It reads the pager's position
/// every frame: the indicator slides between the labels either side of it,
/// and the highlight is the nearest page, so it moves as the swipe passes
/// halfway. A scrollable row also scrolls itself to keep the indicator in
/// view. Nothing here waits for PHP.
private struct PagerTabStrip: View {
    let tabs: PagerTabs
    let progress: PagerProgress
    let select: (Int) -> Void

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Each label's frame in the row, by tab index. The indicator goes
    /// between these.
    @State private var labelFrames: [Int: CGRect] = [:]
    @State private var rowWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var rowPosition = ScrollPosition(edge: .leading)

    private static let space = "nativeui-pager-tabs"

    var body: some View {
        let theme = themeStore.resolve(for: colorScheme)

        VStack(spacing: 0) {
            if tabs.scrollable {
                ScrollView(.horizontal) {
                    row(theme)
                        .padding(.horizontal, tabs.edgePadding)
                }
                .scrollIndicators(.hidden)
                .scrollPosition($rowPosition)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
                .onChange(of: progress.value) { follow() }
                .onChange(of: labelFrames) { follow() }
                .onChange(of: viewportWidth) { follow() }
            } else {
                row(theme)
            }

            Rectangle()
                .fill(resolve(tabs.dividerColor, fallback: theme.outlineVariant))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private func row(_ theme: NativeUITokens) -> some View {
        let active = activeIndex
        let fontSize = tabs.fontSize ?? theme.fontMd

        return HStack(spacing: 0) {
            ForEach(tabs.labels.indices, id: \.self) { index in
                let label = tabs.labels[index]
                let a11yLabel = index < tabs.a11yLabels.count && !tabs.a11yLabels[index].isEmpty ? tabs.a11yLabels[index] : label
                let selected = index == active

                Button {
                    select(index)
                } label: {
                    Text(label)
                        .nuiScaledFont(size: fontSize, weight: .semibold, fontName: tabs.font.isEmpty ? nil : tabs.font)
                        .lineLimit(1)
                        .foregroundStyle(selected
                            ? resolve(tabs.activeColor, fallback: theme.onSurface)
                            : resolve(tabs.color, fallback: theme.onSurfaceVariant))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { labelFrames[index] = $0 }
                        .padding(.horizontal, tabs.paddingX)
                        .padding(.top, tabs.paddingTop)
                        .padding(.bottom, tabs.paddingBottom + tabs.indicatorHeight)
                        .frame(maxWidth: tabs.scrollable ? nil : .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a11yLabel)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        // VoiceOver reads each as a tab, "1 of 3". Only the tabs: the
        // indicator overlaid below stays out of the group.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .overlay(alignment: .bottomLeading) {
            if let frame = indicatorFrame {
                Capsule()
                    .fill(resolve(tabs.indicatorColor, fallback: theme.primary))
                    .frame(width: frame.width, height: tabs.indicatorHeight)
                    .offset(x: frame.minX)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The nearest page's tab, which flips as the swipe passes halfway.
    private var activeIndex: Int {
        min(max(Int(progress.value.rounded()), 0), tabs.labels.count - 1)
    }

    /// The indicator's x and width: between the labels of the pages either
    /// side of the pager's position, in proportion to how far it is from one
    /// to the other.
    private var indicatorFrame: CGRect? {
        let last = tabs.labels.count - 1
        let position = min(max(progress.value, 0), CGFloat(last))
        let from = Int(position.rounded(.down))
        let to = min(from + 1, last)

        guard let a = labelFrames[from], let b = labelFrames[to] else { return nil }

        let t = position - CGFloat(from)

        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: 0, width: a.width + (b.width - a.width) * t, height: 0)
    }

    /// Keeps the indicator in the middle of a scrollable row, as far as the
    /// row's ends allow.
    private func follow() {
        guard viewportWidth > 0, let frame = indicatorFrame else { return }

        let contentWidth = rowWidth + tabs.edgePadding * 2
        let target = tabs.edgePadding + frame.midX - viewportWidth / 2

        rowPosition.scrollTo(x: min(max(target, 0), max(contentWidth - viewportWidth, 0)))
    }

    private func resolve(_ color: (light: Int?, dark: Int?), fallback: Color) -> Color {
        let argb = colorScheme == .dark ? (color.dark ?? color.light) : color.light

        return argb.map { Color(argb: $0) } ?? fallback
    }
}
