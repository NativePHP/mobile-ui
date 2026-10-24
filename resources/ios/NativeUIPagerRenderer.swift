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
        let horizontal = p.getBool("horizontal")
        // The header and the overlay ride beside the pages; neither is one.
        let pages = node.children.filter { $0.type != "pager_header" && $0.type != "pager_overlay" }
        let count = max(0, p.getInt("count", default: pages.count))
        let windowFrom = p.getInt("window_from")
        // `has_more` appends one loading page after the last loaded item —
        // a feed has no total, so the user can pull into the tail while
        // PHP fetches the next batch. Settling there reports index == count.
        let hasMore = p.getBool("has_more")
        let pageCount = hasMore ? count + 1 : count
        let requestedPage = min(max(0, p.getInt("page")), max(0, pageCount - 1))

        let pageByIndex: [Int: NativeUINode] = {
            var map: [Int: NativeUINode] = [:]
            map.reserveCapacity(pages.count)
            for (offset, child) in pages.enumerated() {
                map[windowFrom + offset] = child
            }
            return map
        }()

        PagerBody(
            nodeId: node.id,
            count: pageCount,
            loaded: count,
            requestedPage: requestedPage,
            horizontal: horizontal,
            reportOnSettle: p.getBool("report_on_settle"),
            cbId: p.getCallbackId("on_page_change"),
            pageByIndex: pageByIndex,
            placeholders: p.getStringList("placeholders"),
            tabs: PagerTabs(props: p),
            // Only a horizontal pager's pages scroll up and down under a header.
            header: horizontal ? node.children.first { $0.type == "pager_header" } : nil,
            overlay: node.children.first { $0.type == "pager_overlay" },
            background: PagerColor(light: node.style?.bgColor, dark: p.has("dark_bg_color") ? p.getColor("dark_bg_color", default: 0) : nil),
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
    /// The `pager_header`, which each page's list draws above the tabs.
    let header: NativeUINode?
    /// The `pager_overlay`, laid over the pages under the tabs.
    let overlay: NativeUINode?
    /// The pager's own background, behind the tabs a header pins.
    let background: PagerColor
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
    /// Where the header is, and each page's list, when there's a header.
    @State private var headerScroll = PagerHeaderScroll()

    /// Loaded-but-unshipped pages this far from the current one get their
    /// placeholder image; the rest stay empty. Wide enough that a fast
    /// flick past the shipped window lands on a still, small enough that a
    /// long feed never fetches stills it may never reach.
    static let placeholderRadius = 4

    init(nodeId: Int, count: Int, loaded: Int, requestedPage: Int, horizontal: Bool, reportOnSettle: Bool, cbId: Int, pageByIndex: [Int: NativeUINode], placeholders: [String], tabs: PagerTabs?, header: NativeUINode?, overlay: NativeUINode?, background: PagerColor, a11yLabel: String) {
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
        self.header = header
        self.overlay = overlay
        self.background = background
        self.a11yLabel = a11yLabel
        _position = State(initialValue: requestedPage)
        _leading = State(initialValue: requestedPage)
        _reported = State(initialValue: [requestedPage])
        _lastReported = State(initialValue: requestedPage)
        _progress = State(initialValue: PagerProgress(CGFloat(requestedPage)))
    }

    var body: some View {
        if header != nil {
            // The pages' lists draw the header and the tabs themselves, so
            // they scroll with the page (see NativeUIPagerHeader).
            pager
                .overlay(alignment: .top) { overlayView }
                .modifier(PagerA11yLabelModifier(label: a11yLabel))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    headerScroll.pageWidth = frame.width
                    headerScroll.pagerMinY = frame.minY
                }
        } else {
            VStack(spacing: 0) {
                if let tabs {
                    PagerTabStrip(tabs: tabs, progress: progress, select: selectTab)
                }
                pager
                    .overlay(alignment: .top) { overlayView }
                    .modifier(PagerA11yLabelModifier(label: a11yLabel))
            }
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        if let overlay {
            PagerOverlayView(node: overlay, scroll: header == nil ? nil : headerScroll)
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
            // On a non-lazy stack SwiftUI ignores the initial value of
            // `position` (seen on iOS 18.6 and 26.2), so the pager opened
            // at page 0. The initial anchor puts the start page in place in
            // the first layout: page 0 never shows and is never reported.
            .defaultScrollAnchor(startAnchor, for: .initialOffset)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(0)
            // `visibleRect` is inset-adjusted: its origin is 0 on page 0
            // and its length is the viewport, whatever the bar insets are.
            // Before the first layout the pager has no size. That is no
            // page yet, not page 0: reported as page 0, PHP would think the
            // user had left the start page.
            .onScrollGeometryChange(for: Int?.self) { geometry in
                let visible = geometry.visibleRect
                let length = horizontal ? visible.width : visible.height
                guard length > 0, count > 0 else { return nil }
                let offset = horizontal ? visible.minX : visible.minY
                return min(count - 1, max(0, Int((offset / length).rounded())))
            } action: { _, page in
                guard let page else { return }
                leading = page
                // Report the moment a page becomes the nearest one, mid-swipe,
                // so PHP's round-trip overlaps the animation instead of
                // starting after it. Idle re-reports the same page (no-op).
                // With `report_on_settle` only idle reports, so the frame
                // the report causes never lands during the animation.
                if !reportOnSettle {
                    report(page)
                }
                // A header follows the page nearest the leading edge.
                headerScroll.lead(page)
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

    /// The start page as a point of the scroll range. Every page is one
    /// viewport long, so page `n` of `count` sits at `n / (count - 1)`.
    private var startAnchor: UnitPoint {
        let fraction = count > 1 ? CGFloat(requestedPage) / CGFloat(count - 1) : 0
        return horizontal ? UnitPoint(x: fraction, y: 0) : UnitPoint(x: 0, y: fraction)
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
                        .environment(\.nativeUIPagerHeader, header.map { pagerHeader(page: index, node: $0) })
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

    /// What page `index` gets of the header: the same object for the life
    /// of the pager, so a render only redraws the parts of it that changed.
    private func pagerHeader(page index: Int, node: NativeUINode) -> NativeUIPagerHeader {
        headerScroll.header(page: index, node: node, tabs: tabs, background: background, progress: progress, select: selectTab)
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
private struct PagerTabs: Equatable {
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

    static func == (lhs: PagerTabs, rhs: PagerTabs) -> Bool {
        lhs.labels == rhs.labels && lhs.a11yLabels == rhs.a11yLabels && lhs.scrollable == rhs.scrollable
            && lhs.reselectCbId == rhs.reselectCbId && lhs.color == rhs.color && lhs.activeColor == rhs.activeColor
            && lhs.indicatorColor == rhs.indicatorColor && lhs.dividerColor == rhs.dividerColor && lhs.font == rhs.font
            && lhs.fontSize == rhs.fontSize && lhs.indicatorHeight == rhs.indicatorHeight && lhs.paddingX == rhs.paddingX
            && lhs.paddingTop == rhs.paddingTop && lhs.paddingBottom == rhs.paddingBottom && lhs.edgePadding == rhs.edgePadding
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

// MARK: - Header

/// A colour as PHP sent it, light and dark, nil where it sent none.
struct PagerColor: Equatable {
    let light: Int?
    let dark: Int?

    init(light: Int?, dark: Int?) {
        self.light = light == 0 ? nil : light
        self.dark = dark == 0 ? nil : dark
    }

    func resolve(_ colorScheme: ColorScheme, fallback: Color) -> Color {
        let argb = colorScheme == .dark ? (dark ?? light) : light

        return argb.map { Color(argb: $0) } ?? fallback
    }
}

/// A pager's `pager_header`, as one of its pages gets it through the
/// environment. The page's list draws it (NativeUIListRenderer): the header
/// as its first row, then the pager's tabs as the header of a section
/// holding every other row, so the tabs pin once the header has scrolled
/// away. Both are held still while the pager swipes, so the pages seem to
/// slide under them.
///
/// One per page for the life of the pager. A render changes its properties
/// in place, which redraws only the views that read them.
@Observable
final class NativeUIPagerHeader {
    let page: Int
    var node: NativeUINode
    fileprivate var tabs: PagerTabs?
    var background: PagerColor
    fileprivate let progress: PagerProgress
    @ObservationIgnored fileprivate var select: (Int) -> Void
    let scroll: PagerHeaderScroll

    fileprivate init(page: Int, node: NativeUINode, tabs: PagerTabs?, background: PagerColor, progress: PagerProgress, select: @escaping (Int) -> Void, scroll: PagerHeaderScroll) {
        self.page = page
        self.node = node
        self.tabs = tabs
        self.background = background
        self.progress = progress
        self.select = select
        self.scroll = scroll
    }

    /// The tabs, drawn as the pager would draw them above its pages.
    var hasTabs: Bool { tabs != nil }

    fileprivate var strip: some View {
        Group {
            if let tabs {
                PagerTabStrip(tabs: tabs, progress: progress, select: select)
            }
        }
    }

    /// How far to move this page's header so it stays where the pager is:
    /// the page is `progress - page` pages off to the left.
    fileprivate var stationaryOffset: CGFloat {
        (progress.value - CGFloat(page)) * scroll.pageWidth
    }
}

private struct NativeUIPagerHeaderKey: EnvironmentKey {
    static let defaultValue: NativeUIPagerHeader? = nil
}

extension EnvironmentValues {
    /// The header the page's list draws, if the page is in a pager with one.
    /// A list clears it for its rows, so only the page's own list draws it.
    var nativeUIPagerHeader: NativeUIPagerHeader? {
        get { self[NativeUIPagerHeaderKey.self] }
        set { self[NativeUIPagerHeaderKey.self] = newValue }
    }
}

/// How far the header has scrolled, from the page showing, and each page's
/// list, so the pages beside it can be kept level with it.
///
/// While any of the header shows, every list scrolls with it: a swipe finds
/// the next page's header at the same height, so the two meet seamlessly.
/// Once it has gone, each list keeps its own place, and only a list higher
/// than the header has gone is brought down to where it pins the tabs.
///
/// The lists are moved through their UIKit scroll views, found from inside
/// the header row (PagerHeaderScrollViewFinder). SwiftUI gives no way to
/// set a List's offset.
@Observable
final class PagerHeaderScroll {
    /// The header's height, without the tabs.
    var headerHeight: CGFloat = 0
    /// How much of the header has scrolled away, 0 to `headerHeight`. Below
    /// 0 the page showing is being pulled down, and the header with it.
    var collapse: CGFloat = 0
    var pageWidth: CGFloat = 0
    /// The page the header follows.
    private(set) var shownPage = 0
    /// Where each page's tabs end on screen, and where the pager starts.
    var stripMaxY: [Int: CGFloat] = [:]
    var pagerMinY: CGFloat = 0

    @ObservationIgnored private var leading = 0 {
        didSet { shownPage = leading }
    }
    @ObservationIgnored private var offsets: [Int: CGFloat] = [:]
    @ObservationIgnored private var scrollViews: [Int: WeakScrollView] = [:]
    @ObservationIgnored private var headers: [Int: NativeUIPagerHeader] = [:]

    private struct WeakScrollView {
        weak var view: UIScrollView?
    }

    fileprivate func header(page: Int, node: NativeUINode, tabs: PagerTabs?, background: PagerColor, progress: PagerProgress, select: @escaping (Int) -> Void) -> NativeUIPagerHeader {
        guard let header = headers[page] else {
            let header = NativeUIPagerHeader(page: page, node: node, tabs: tabs, background: background, progress: progress, select: select, scroll: self)
            headers[page] = header
            return header
        }

        // Only what changed, so an unchanged header doesn't redraw.
        if header.node !== node { header.node = node }
        if header.tabs != tabs { header.tabs = tabs }
        if header.background != background { header.background = background }
        header.select = select

        return header
    }

    /// Where the bottom of the tabs is, below the pager's top edge, as the
    /// page showing has them on screen.
    var stripBottom: CGFloat {
        max(0, (stripMaxY[shownPage] ?? pagerMinY) - pagerMinY)
    }

    /// The page nearest the pager's leading edge, which the header follows.
    func lead(_ page: Int) {
        guard page != leading else { return }

        leading = page
        follow(offsets[page] ?? 0)
    }

    /// A page's list, found or found again in a fresh list. A page that isn't
    /// showing is brought level with the header before it can be seen.
    func attach(_ scrollView: UIScrollView, page: Int) {
        guard scrollViews[page]?.view !== scrollView else { return }

        scrollViews[page] = WeakScrollView(view: scrollView)
        offsets[page] = scrollView.contentOffset.y + scrollView.adjustedContentInset.top

        if page != leading {
            align(page)
        }
    }

    /// A page's list scrolled to `y`, its distance from its own top.
    func scrolled(page: Int, y: CGFloat) {
        offsets[page] = y

        if page == leading {
            follow(y)
        }
    }

    private func follow(_ y: CGFloat) {
        let collapse = min(y, headerHeight)

        guard collapse != self.collapse else { return }

        self.collapse = collapse

        for page in scrollViews.keys where page != leading {
            align(page)
        }
    }

    private func align(_ page: Int) {
        guard headerHeight > 0, let scrollView = scrollViews[page]?.view else { return }

        let own = offsets[page] ?? 0
        let shown = max(0, collapse)
        let target = shown < headerHeight ? shown : max(own, headerHeight)

        guard abs(target - own) > 0.5 else { return }

        offsets[page] = target
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target - scrollView.adjustedContentInset.top), animated: false)
    }
}

/// The header as a page's list draws it: its first row.
struct NativeUIPagerHeaderRow: View {
    let header: NativeUIPagerHeader

    var body: some View {
        PagerChildren(node: header.node)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if header.scroll.headerHeight != height { header.scroll.headerHeight = height }
            }
            .background(PagerHeaderScrollViewFinder { header.scroll.attach($0, page: header.page) })
            .modifier(PagerStationary(header: header))
    }
}

/// The pager's tabs as a page's list draws them: the header of the section
/// below the header row, which pins under the nav bar.
struct NativeUIPagerHeaderStrip: View {
    let header: NativeUIPagerHeader

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        header.strip
            .frame(maxWidth: .infinity)
            .background(header.background.resolve(colorScheme, fallback: themeStore.resolve(for: colorScheme).surface))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { maxY in
                if header.scroll.stripMaxY[header.page] != maxY { header.scroll.stripMaxY[header.page] = maxY }
            }
            .modifier(PagerStationary(header: header))
    }
}

/// Holds a page's header still while the pager swipes, by moving it against
/// the page. The pages beside each other are level, so the halves of the two
/// headers on screen meet as one.
private struct PagerStationary: ViewModifier {
    let header: NativeUIPagerHeader

    func body(content: Content) -> some View {
        content.offset(x: header.stationaryOffset)
    }
}

/// What a page's list does under a pager header: it tells the header where
/// it is, and makes room at its end for the header to scroll away.
struct NativeUIPagerHeaderListModifier: ViewModifier {
    let header: NativeUIPagerHeader?

    /// Space after the last row, so a short list can still scroll the
    /// header away and keep level with the others.
    @State private var room: CGFloat = 0

    func body(content: Content) -> some View {
        if let header {
            content
                // Section headers get a minimum height and space above.
                .environment(\.defaultMinListHeaderHeight, 0)
                .listSectionSpacing(0)
                .contentMargins(.bottom, room, for: .scrollContent)
                .onScrollGeometryChange(for: PagerListGeometry.self) { geometry in
                    PagerListGeometry(
                        y: geometry.contentOffset.y + geometry.contentInsets.top,
                        top: geometry.contentInsets.top,
                        bottom: geometry.contentInsets.bottom,
                        content: geometry.contentSize.height,
                        container: geometry.containerSize.height
                    )
                } action: { _, geometry in
                    header.scroll.scrolled(page: header.page, y: geometry.y)

                    // The room this list needs to scroll the header away, past
                    // the room it already has.
                    let needed = max(0, header.scroll.headerHeight + geometry.container - geometry.content - geometry.top - (geometry.bottom - room))
                    if abs(needed - room) > 0.5 {
                        room = needed
                    }
                }
        } else {
            content
        }
    }
}

private struct PagerListGeometry: Equatable {
    let y: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let content: CGFloat
    let container: CGFloat
}

/// The pager's `pager_overlay`, hung under the tabs. Under a header it
/// follows the tabs as the header scrolls.
private struct PagerOverlayView: View {
    let node: NativeUINode
    let scroll: PagerHeaderScroll?

    var body: some View {
        PagerChildren(node: node)
            .frame(maxWidth: .infinity)
            .offset(y: scroll?.stripBottom ?? 0)
    }
}

/// What a `pager_header` or `pager_overlay` holds, stacked. Their own
/// renderer draws nothing: the pager places them.
private struct PagerChildren: View {
    let node: NativeUINode

    var body: some View {
        VStack(spacing: 0) {
            ForEach(node.children) { child in
                NodeView(node: child).equatable()
            }
        }
    }
}

/// Finds the UIKit scroll view a view is drawn in, here the List's, so the
/// pager can scroll it.
private struct PagerHeaderScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.found = found
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        view.found = found
        view.find()
    }

    final class FinderView: UIView {
        var found: ((UIScrollView) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            find()
        }

        func find() {
            guard window != nil else { return }

            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    found?(scrollView)
                    return
                }
                view = current.superview
            }
        }
    }
}
