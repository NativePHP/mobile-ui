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

    /// The window width responsive variants resolve against, so the header
    /// moves beside the pages at the same width an `expanded:` class applies.
    @Environment(\.windowWidth) private var windowWidth
    @Environment(\.availableWidth) private var availableWidth

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

        // Only a horizontal pager's pages scroll up and down under a header.
        let header = horizontal ? node.children.first { $0.type == "pager_header" } : nil
        let besideFrom = CGFloat(p.getFloat("header_beside_from"))
        // As NodeView resolves the classes: the window has no width yet on
        // the first frame.
        let width = windowWidth > 0 ? windowWidth : availableWidth
        let beside = header != nil && besideFrom > 0 && width >= besideFrom

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
            revalidatesPlaceholders: p.revalidatesRemoteImages,
            tabs: PagerTabs(props: p),
            header: beside ? nil : header,
            besideHeader: beside ? header : nil,
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
    /// `revalidate` on the pager: its placeholder images follow the server's
    /// HTTP caching, as a `<native:image revalidate>` does.
    let revalidatesPlaceholders: Bool
    /// The tab row above the pages, if the pager has one.
    let tabs: PagerTabs?
    /// The `pager_header`, which each page's list draws above the tabs.
    let header: NativeUINode?
    /// The `pager_header` instead drawn in a column of its own beside the
    /// pages, once the window is wide enough (`header_beside_from`).
    let besideHeader: NativeUINode?
    /// The `pager_overlay`, laid over the pages under the tabs.
    let overlay: NativeUINode?
    /// The pager's own background, behind the tabs a header pins.
    let background: PagerColor
    let a11yLabel: String

    /// Programmatic-jump binding only. Reading it back is useless here:
    /// under `.paging` it goes nil the moment the pager moves.
    @State private var position: Int?
    /// A same-ID tap still needs an explicit scroll when geometry is off-grid.
    @State private var tabRequest = 0
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
    /// Where the header beside the pages ends and the pages begin.
    @State private var split = PagerSplit.even(0)
    /// How a horizontal pager gets back on its page after iOS resizes it
    /// while the app is in the background (see PagerResume).
    @State private var resume: PagerResume
    @Environment(\.scenePhase) private var scenePhase

    /// Loaded-but-unshipped pages this far from the current one get their
    /// placeholder image; the rest stay empty. Wide enough that a fast
    /// flick past the shipped window lands on a still, small enough that a
    /// long feed never fetches stills it may never reach.
    static let placeholderRadius = 4

    init(nodeId: Int, count: Int, loaded: Int, requestedPage: Int, horizontal: Bool, reportOnSettle: Bool, cbId: Int, pageByIndex: [Int: NativeUINode], placeholders: [String], revalidatesPlaceholders: Bool, tabs: PagerTabs?, header: NativeUINode?, besideHeader: NativeUINode?, overlay: NativeUINode?, background: PagerColor, a11yLabel: String) {
        self.nodeId = nodeId
        self.count = count
        self.loaded = loaded
        self.requestedPage = requestedPage
        self.horizontal = horizontal
        self.reportOnSettle = reportOnSettle
        self.cbId = cbId
        self.pageByIndex = pageByIndex
        self.placeholders = placeholders
        self.revalidatesPlaceholders = revalidatesPlaceholders
        self.tabs = tabs
        self.header = header
        self.besideHeader = besideHeader
        self.overlay = overlay
        self.background = background
        self.a11yLabel = a11yLabel
        _position = State(initialValue: requestedPage)
        _leading = State(initialValue: requestedPage)
        _reported = State(initialValue: [requestedPage])
        _lastReported = State(initialValue: requestedPage)
        _progress = State(initialValue: PagerProgress(CGFloat(requestedPage)))
        _resume = State(initialValue: PagerResume(page: requestedPage, count: count))
    }

    /// One layout whether the header is beside the pages, in them or absent,
    /// so crossing `header_beside_from` (unfolding, Split View) shows or
    /// hides the column and the tab row around the same paging scroll view
    /// instead of rebuilding it and every page's list.
    var body: some View {
        HStack(spacing: 0) {
            if let besideHeader {
                // The header scrolls by itself in the leading column, and
                // the tabs and pages fill the trailing one.
                ScrollView(.vertical) {
                    PagerChildren(node: besideHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(NativeUIScrollEdgeExtension())
                .frame(width: split.leading)
                Color.clear
                    .frame(width: split.gap)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                // Under a header the pages' lists draw the header and the
                // tabs themselves, so they scroll with the page (see
                // NativeUIPagerHeader).
                if let tabs, header == nil {
                    PagerTabStrip(tabs: tabs, progress: progress, select: selectTab)
                }
                pager
                    .overlay(alignment: .top) { overlayView }
                    .modifier(PagerA11yLabelModifier(label: a11yLabel))
                    .onGeometryChange(for: CGRect.self) { proxy in
                        // A page also spans the bar insets at its sides (see `pager`).
                        let sides = horizontal ? proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing : 0
                        let frame = proxy.frame(in: .global)
                        return CGRect(x: frame.minX, y: frame.minY, width: frame.width + sides, height: frame.height)
                    } action: { frame in
                        headerScroll.pageWidth = frame.width
                        headerScroll.pagerMinY = frame.minY
                    }
            }
        }
        .onGeometryChange(for: PagerSplit.self) { PagerSplit(in: $0) } action: { split = $0 }
        // Beside the pages, the header leaves their lists, which stop
        // reporting where they are but keep their scroll views. Forgotten
        // now, each is found again where it is once the header is back.
        .onChange(of: header == nil) { _, gone in
            if gone { headerScroll.reset() }
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
          ScrollViewReader { proxy in
            // A horizontal pager runs under a bar at the bottom of the
            // screen (a tab bar), as a screen's own list does. Its pages
            // take the full height and hand the bar's inset back to their
            // content as safe area, so a list in a page draws under the
            // bar and still scrolls its last row clear of it. Paging is
            // sideways, so the extra height can't make the pages drift.
            //
            // It runs under a bar at its side (an iPhone Duo's vertical bar)
            // the same way, so a page's list can put its scroll indicator at
            // the screen's edge while its rows stay clear of the bar. Each
            // page spans the insets, so `.paging` still steps by one page.
            let insets = horizontal
                ? EdgeInsets(top: 0, leading: geo.safeAreaInsets.leading, bottom: geo.safeAreaInsets.bottom, trailing: geo.safeAreaInsets.trailing)
                : EdgeInsets()
            ScrollView(axis) {
                pages(size: CGSize(width: geo.size.width + insets.leading + insets.trailing, height: geo.size.height + insets.bottom), insets: insets)
                    .scrollTargetLayout()
            }
            // A ScrollView draws past its sides, so the next page showed
            // beside the pager. Clip the sides only, at the edges the pages
            // run to: inside the safe-area extension, which lays this out
            // over the side insets. The pages still run under a bar at the
            // bottom.
            .clipShape(PagerSideClip(horizontal: horizontal))
            .ignoresSafeArea(.container, edges: horizontal ? [.bottom, .horizontal] : [])
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
            // `visibleRect` is inset-adjusted: its origin is 0 on page 0.
            // Its width is not a page, though: beside a sideways bar it
            // takes in the bar's inset too, so horizontally a page is the
            // ScrollView's own width, which `.paging` steps by.
            // Before the first layout the pager has no size. That is no
            // page yet, not page 0: reported as page 0, PHP would think the
            // user had left the start page.
            // Rounded selection and fractional progress share one sample,
            // so recovery ownership is checked before either can escape.
            .onScrollGeometryChange(for: PagerPosition?.self) { geometry in
                let visible = geometry.visibleRect
                let length = horizontal ? geometry.bounds.width : visible.height
                guard length > 0 else { return nil }
                return PagerPosition(pages: (horizontal ? visible.minX : visible.minY) / length, length: length)
            } action: { _, value in
                if observe(value, proxy: proxy) { return }
                guard let value else { return }
                if resume.phase == .idle, resume.userScrolling {
                    // Idle had no size; this is its first measurable finish.
                    resume.settled()
                    reconcile(value)
                    resume.armed = horizontal && !resume.active
                    return
                }
                if horizontal, resume.active, !resume.armed, let target = resume.target {
                    // A timeout cannot cancel a scroll already sent to UIKit.
                    // Keep following its fresh geometry, including a late ack.
                    if value.isOn(target) {
                        resume.settled()
                    }
                    reconcile(value)
                    return
                }
                if resume.holds(horizontal: horizontal) {
                    // Not the user's doing: iOS sizing the app while it's in
                    // the background, or the pager being put back. Nothing
                    // follows it until the pager is back on its page.
                    resume.armed = resume.armed || !resume.active
                    if resume.active, resume.armed {
                        restore(proxy)
                    }
                    return
                }
                guard resume.count > 0 else { return }
                let page = min(resume.count - 1, max(0, Int(value.pages.rounded())))
                leading = page
                // Report mid-swipe unless PHP requested settle-only reports.
                if !reportOnSettle, !(horizontal && resume.target != nil) {
                    report(page)
                }
                headerScroll.lead(page)
                if tabs != nil {
                    progress.value = value.pages
                }
            }
            .onScrollPhaseChange { _, phase, context in
                scrollPhaseChanged(phase, geometry: context.geometry, proxy: proxy)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                resume.active = phase == .active
                // Work queued before the app left the foreground is stale.
                resume.suspend()
                if !resume.active {
                    // Background sizing belongs to warm-resume, not an active
                    // resize's deadline. Keep its accepted selection and hold.
                    resume.resize = nil
                }
                if resume.active, resume.armed, horizontal {
                    // Hold the pager until it's checked: the geometry it
                    // came back with is not a page the user chose.
                    resume.restoring = true
                    restore(proxy)
                }
            }
            .onChange(of: count) { _, count in
                resume.count = count
                resume.accepted = min(resume.accepted, max(count - 1, 0))
                if count == 0 {
                    resume.settled()
                    resume.phase = .idle
                    return
                }
                if let target = resume.target {
                    resume.target = min(target, count - 1)
                }
                if let resize = resume.resize {
                    resize.page = min(resize.page, count - 1)
                }
                resume.suspend()
                if resume.active, resume.armed, horizontal {
                    restore(proxy)
                }
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
                resume.chosen(page)
                position = page
                if horizontal {
                    verifySelection(proxy)
                }
            }
            .onChange(of: tabRequest) { _, _ in
                verifySelection(proxy)
            }
          }
        }
    }

    /// Tracking is only a finger down. Keep the recovery until that finger
    /// actually moves, or check it again when the touch ends without a drag.
    private func scrollPhaseChanged(_ phase: ScrollPhase, geometry: ScrollGeometry, proxy: ScrollViewProxy) {
        resume.phase = phase
        if phase == .tracking {
            resume.suspend()
            return
        }
        if phase == .interacting {
            resume.settled()
            resume.userScrolling = true
            return
        }
        guard phase == .idle else { return }
        let finishedSwipe = resume.userScrolling
        let visible = geometry.visibleRect
        let length = horizontal ? geometry.bounds.width : visible.height
        guard length > 0, resume.count > 0 else {
            if horizontal, resume.armed, resume.target != nil {
                resume.restoring = true
            }
            return
        }
        let final = PagerPosition(pages: (horizontal ? visible.minX : visible.minY) / length, length: length)
        if observe(final, proxy: proxy) { return }
        resume.userScrolling = false
        if finishedSwipe {
            resume.settled()
            reconcile(final)
            // A real swipe can finish after the scene became inactive.
            // Accept it now; subsequent system resizes must not replace it.
            resume.armed = horizontal && !resume.active
        } else if horizontal, resume.armed, let target = resume.target {
            if resume.active, final.isOn(target) {
                resume.settled()
                reconcile(final)
            } else if resume.active {
                restore(proxy)
            }
        } else if resume.holds(horizontal: horizontal) {
            if resume.active, resume.armed {
                restore(proxy)
            }
        } else {
            if horizontal, let target = resume.target, final.isOn(target) {
                resume.settled()
            }
            reconcile(final)
        }
    }

    /// Classify a sample before it can change selection, header or PHP. Width
    /// changes belong to layout, unless a genuine swipe already owns the move.
    /// A quiet width groups the burst; it does not forget its selected page.
    private func observe(_ value: PagerPosition?, proxy: ScrollViewProxy) -> Bool {
        resume.position = value
        resume.geometryVersion += 1
        guard horizontal, let value else { return false }
        let changed = resume.width.map { abs($0 - value.length) > 0.5 } ?? false
        resume.width = value.length
        guard resume.active, !resume.userScrolling, resume.count > 0 else { return false }
        if changed {
            let page = resume.resize?.page ?? (resume.armed ? resume.target : nil) ?? resume.accepted
            // Quiet is not an acknowledgement. Churn cannot refill a live
            // or exhausted repair; only a completed selection can start anew.
            if resume.resize == nil || (resume.resize!.stable && !resume.resize!.checking && !resume.resize!.exhausted) {
                let resize = PagerResize(page: page)
                resume.resize = resize
            }
            let resize = resume.resize!
            resize.version += 1
            resize.stable = false
            let version = resize.version
            resume.suspend()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
                guard resume.resize === resize, resize.version == version else { return }
                resize.stable = true
                if resume.active, resume.armed, !resize.exhausted {
                    restore(proxy)
                }
            }
        }
        guard let resize = resume.resize, !resize.exhausted else { return false }
        if !resize.checking {
            resize.checking = true
            resize.timerVersion += 1
            let timer = resize.timerVersion
            // Bound each outstanding repair burst, not passive selection
            // ownership. Acknowledgement cancels this timer, not its budget.
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                guard resume.resize === resize, resize.timerVersion == timer, !resize.exhausted else { return }
                resize.overdue = true
                if resume.active, resume.phase == .idle, resume.armed {
                    failResume()
                }
            }
        }
        resume.accepted = min(resize.page, resume.count - 1)
        resume.target = resume.accepted
        resume.armed = true
        resume.restoring = true
        if resize.stable || resize.overdue, resume.phase == .idle {
            restore(proxy)
        }
        return true
    }

    /// Reconcile from one geometry sample, not separately delivered rounded
    /// and fractional callbacks. `report` de-duplicates a page PHP knows.
    private func reconcile(_ position: PagerPosition) {
        guard resume.count > 0 else { return }
        let page = min(max(Int(position.pages.rounded()), 0), resume.count - 1)
        resume.accepted = page
        leading = page
        headerScroll.lead(page)
        if tabs != nil {
            progress.value = position.pages
        }
        report(page)
    }

    /// Every explicit horizontal selection gets a check, including a binding
    /// assignment that does not move anything. Give an ordinary animation time
    /// to start; its idle callback owns completion if it is still running.
    private func verifySelection(_ proxy: ScrollViewProxy) {
        guard resume.active, resume.armed else { return }
        if resume.phase == .idle, let position = resume.position, position.isOn(resume.accepted) {
            resume.settled(preservingResize: true)
            reconcile(position)
            return
        }
        let generation = resume.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            guard generation == resume.generation, resume.active, resume.armed, resume.phase == .idle else { return }
            restore(proxy)
        }
    }

    /// Puts the pager back on the page it was meant to be on, once the app
    /// is in front again: one check at a time, on the next turn of the run
    /// loop, dropped if anything newer happened first. Each of two attempts
    /// waits for new geometry, with a bounded timeout if layout never replies.
    private func restore(_ proxy: ScrollViewProxy) {
        let generation = resume.generation
        guard resume.pending != generation else { return }
        resume.pending = generation
        DispatchQueue.main.async {
            if resume.pending == generation {
                resume.pending = nil
            }
            guard generation == resume.generation, resume.active, resume.armed, resume.phase == .idle else { return }
            if let resize = resume.resize {
                if resize.exhausted { return }
                if resize.overdue {
                    failResume()
                    return
                }
                if !resize.stable { return }
            }
            guard resume.count > 0 else {
                resume.settled()
                return
            }
            guard let position = resume.position else {
                // The next valid geometry sample continues this idle check.
                resume.restoring = true
                return
            }
            let page = min(max(resume.accepted, 0), resume.count - 1)
            if position.isOn(page) {
                resume.settled(preservingResize: true)
                reconcile(position)
                return
            }
            if let waiting = resume.waitingForGeometry, resume.geometryVersion <= waiting {
                return
            }
            if (resume.resize?.attempts ?? resume.attempts) >= 2 {
                failResume()
                return
            }
            resume.restoring = true
            resume.target = page
            resume.attempts += 1
            resume.resize?.attempts += 1
            resume.waitingForGeometry = resume.geometryVersion
            let attempt = resume.attempts
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(page, anchor: .leading) }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
                guard generation == resume.generation, resume.armed, resume.attempts == attempt else { return }
                failResume()
            }
        }
    }

    /// A failed correction is not a successful restore. Release the hold,
    /// reconcile PHP and native selection with the actual nearest page. Keep
    /// ownership of the issued scroll until it acknowledges or newer intent
    /// supersedes it: timing out cannot cancel a native scroll already issued.
    private func failResume() {
        NSLog("NativeUI pager resume correction failed after \(resume.attempts) attempt(s)")
        let target = resume.target
        resume.resize?.exhausted = true
        resume.settled(preservingResize: true)
        resume.target = target
        if let position = resume.position {
            reconcile(position)
            resume.resize?.page = resume.accepted
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
    private func pages(size: CGSize, insets: EdgeInsets) -> some View {
        if horizontal {
            HStack(spacing: 0) { pageViews(size: size, insets: insets) }
        } else {
            VStack(spacing: 0) { pageViews(size: size, insets: insets) }
        }
    }

    private func pageViews(size: CGSize, insets: EdgeInsets) -> some View {
        ForEach(0..<count, id: \.self) { index in
            Group {
                if let child = pageByIndex[index] {
                    NodeView(node: child).equatable()
                        .environment(\.nativeUIPagerHeader, (header ?? besideHeader).map { pagerHeader(page: index, node: $0) })
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
            .safeAreaPadding(insets)
            .frame(width: size.width, height: size.height)
            .clipped()
            .id(index)
        }
    }

    /// What page `index` gets of the header: the same object for the life
    /// of the pager, so a render only redraws the parts of it that changed.
    /// A page gets it beside the pages too, with nothing to draw, so its
    /// list is the same list either way and keeps its place.
    private func pagerHeader(page index: Int, node: NativeUINode) -> NativeUIPagerHeader {
        headerScroll.header(page: index, node: node, inList: header != nil, tabs: tabs, background: background, progress: progress, select: selectTab)
    }

    /// A tap on a tab: scroll there, and the page is reported when the
    /// pager settles as for a swipe. The tab already showing goes to PHP
    /// instead, usually to take its page back to the top.
    private func selectTab(_ index: Int) {
        guard index >= 0, index < count else { return }

        resume.chosen(index)
        if index == leading, abs(progress.value - CGFloat(index)) < 0.01, resume.position?.isOn(index) == true {
            resume.settled()
            if let cb = tabs?.reselectCbId, cb != 0 {
                NativeElementBridge.sendTabChangeEvent(cb, nodeId: nodeId, index: index)
            }
            return
        }

        if horizontal, resume.active, resume.phase == .idle, let actual = resume.position, actual.isOn(index) {
            resume.settled()
            reconcile(actual)
            return
        }
        if horizontal {
            tabRequest += 1
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
            NativeUIRemoteImage(url: url, revalidate: revalidatesPlaceholders) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.clear
                }
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
    let trackColor: (light: Int?, dark: Int?)
    let trackBorderColor: (light: Int?, dark: Int?)
    let trackBorderWidth: CGFloat
    let pill: Bool
    let trackPadding: CGFloat
    let font: String
    let activeFont: String
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
        self.trackColor = color("tab_track_color")
        self.trackBorderColor = color("tab_track_border_color")
        self.trackBorderWidth = points("tab_track_border_width", 1)
        self.pill = p.getString("tab_indicator_style") == "pill"
        self.trackPadding = points("tab_track_padding", 4)
        self.font = p.getString("tab_font")
        self.activeFont = p.getString("tab_active_font")
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
            && lhs.indicatorColor == rhs.indicatorColor && lhs.dividerColor == rhs.dividerColor && lhs.trackColor == rhs.trackColor
            && lhs.trackBorderColor == rhs.trackBorderColor && lhs.trackBorderWidth == rhs.trackBorderWidth
            && lhs.pill == rhs.pill && lhs.trackPadding == rhs.trackPadding && lhs.font == rhs.font && lhs.activeFont == rhs.activeFont
            && lhs.fontSize == rhs.fontSize && lhs.indicatorHeight == rhs.indicatorHeight && lhs.paddingX == rhs.paddingX
            && lhs.paddingTop == rhs.paddingTop && lhs.paddingBottom == rhs.paddingBottom && lhs.edgePadding == rhs.edgePadding
    }

    /// Whether a track is drawn behind the row, filled or outlined.
    var hasTrack: Bool {
        trackColor.light != nil || trackColor.dark != nil || hasTrackBorder
    }

    /// Whether the track is outlined.
    var hasTrackBorder: Bool {
        (trackBorderColor.light != nil || trackBorderColor.dark != nil) && trackBorderWidth > 0
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

    /// Each label's frame in the row, by tab index. The underline goes
    /// between these.
    @State private var labelFrames: [Int: CGRect] = [:]
    /// Each whole tab's frame in the row, by tab index. The pill goes
    /// between these.
    @State private var tabFrames: [Int: CGRect] = [:]
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
                .clipShape(PagerSideClip(horizontal: true))
                .scrollIndicators(.hidden)
                .scrollPosition($rowPosition)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
                .onChange(of: progress.value) { follow() }
                .onChange(of: labelFrames) { follow() }
                .onChange(of: tabFrames) { follow() }
                .onChange(of: viewportWidth) { follow() }
            } else {
                row(theme)
                    .padding(tabs.hasTrack ? tabs.edgePadding : 0)
            }

            Rectangle()
                .fill(resolve(tabs.dividerColor, fallback: theme.outlineVariant))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private func row(_ theme: NativeUITokens) -> some View {
        let active = activeIndex
        let drawsNamedFace = !tabs.activeFont.isEmpty
        let fontSize = tabs.fontSize ?? theme.fontMd

        return HStack(spacing: 0) {
            ForEach(tabs.labels.indices, id: \.self) { index in
                let label = tabs.labels[index]
                let a11yLabel = index < tabs.a11yLabels.count && !tabs.a11yLabels[index].isEmpty ? tabs.a11yLabels[index] : label
                let selected = index == active
                let fontName = selected && drawsNamedFace ? tabs.activeFont : tabs.font

                Button {
                    select(index)
                } label: {
                    Text(label)
                        // With an active font, each named font draws its own face, as on
                        // Android: the semibold weight would swap a `-Regular` file for its
                        // semibold sibling and draw every tab alike.
                        .nuiScaledFont(size: fontSize, weight: drawsNamedFace && !fontName.isEmpty ? .regular : .semibold, fontName: fontName.isEmpty ? nil : fontName)
                        .lineLimit(1)
                        .foregroundStyle(selected
                            ? resolve(tabs.activeColor, fallback: tabs.pill ? theme.onPrimary : theme.onSurface)
                            : resolve(tabs.color, fallback: theme.onSurfaceVariant))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { labelFrames[index] = $0 }
                        .padding(.horizontal, tabs.paddingX)
                        .padding(.top, tabs.paddingTop)
                        .padding(.bottom, tabs.paddingBottom + (tabs.pill ? 0 : tabs.indicatorHeight))
                        .frame(maxWidth: tabs.scrollable ? nil : .infinity)
                        .frame(minHeight: 44)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tabFrames[index] = $0 }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a11yLabel)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(tabs.hasTrack ? tabs.trackPadding : 0)
        // VoiceOver reads each as a tab, "1 of 3". Only the tabs: the
        // indicator and track stay out of the group.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        // The track and the pill sit behind the labels, the underline over them.
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if tabs.hasTrack {
                    Capsule()
                        .fill(resolve(tabs.trackColor, fallback: .clear))
                        .overlay {
                            if tabs.hasTrackBorder {
                                Capsule()
                                    .strokeBorder(resolve(tabs.trackBorderColor, fallback: .clear), lineWidth: tabs.trackBorderWidth)
                            }
                        }
                }

                if tabs.pill, let frame = pillFrame {
                    Capsule()
                        .fill(resolve(tabs.indicatorColor, fallback: theme.primary))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomLeading) {
            if !tabs.pill, let frame = indicatorFrame {
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

    /// The underline's x and width: between the labels of the pages either
    /// side of the pager's position.
    private var indicatorFrame: CGRect? {
        between(labelFrames)
    }

    /// The pill's frame: between the tabs of the pages either side of the
    /// pager's position.
    private var pillFrame: CGRect? {
        between(tabFrames)
    }

    /// A frame between those of the pages either side of the pager's
    /// position, in proportion to how far it is from one to the other.
    private func between(_ frames: [Int: CGRect]) -> CGRect? {
        let last = tabs.labels.count - 1
        let position = min(max(progress.value, 0), CGFloat(last))
        let from = Int(position.rounded(.down))
        let to = min(from + 1, last)

        guard let a = frames[from], let b = frames[to] else { return nil }

        let t = position - CGFloat(from)

        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    /// Keeps the indicator in the middle of a scrollable row, as far as the
    /// row's ends allow.
    private func follow() {
        guard viewportWidth > 0, let frame = tabs.pill ? pillFrame : indicatorFrame else { return }

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

/// Where a pager splits into its header and its pages: at a foldable's fold,
/// for an even split around the hinge. Flat, the columns meet on it. Partly
/// folded, its division region is active and they stop at its margins,
/// keeping controls out of the crease. Without a fold across the pager the
/// columns share the width evenly.
private struct PagerSplit: Equatable {
    var leading: CGFloat
    var gap: CGFloat

    static func even(_ width: CGFloat) -> PagerSplit {
        PagerSplit(leading: (width / 2).rounded(), gap: 0)
    }

    init(leading: CGFloat, gap: CGFloat) {
        self.leading = leading
        self.gap = gap
    }

    init(in proxy: GeometryProxy) {
        let width = proxy.size.width
        self = .even(width)
        // reservedRegions is new in the iOS 27.1 SDK, so Xcode 27.0 can't
        // compile the call even behind #available. Xcode 27.0 and 27.1 both
        // ship Swift 6.4, so a compiler check can't tell them apart. The SDK's
        // SwiftUICore version can: 8.0.84 in iOS 27.0, 8.0.85 in iOS 27.1.
        #if canImport(SwiftUICore, _version: 8.0.85)
        guard #available(iOS 27.1, *) else { return }
        guard let fold = Self.fold(in: proxy) else { return }
        if fold.isActive {
            self = PagerSplit(leading: fold.frame.minX, gap: fold.frame.width)
        } else {
            self = PagerSplit(leading: fold.frame.midX, gap: 0)
        }
        #endif
    }

    #if canImport(SwiftUICore, _version: 8.0.85)
    /// The upright fold across the pager nearest its middle, active or not.
    @available(iOS 27.1, *)
    private static func fold(in proxy: GeometryProxy) -> ReservedRegion? {
        let width: CGFloat = proxy.size.width
        let middle: CGFloat = width / 2
        let regions: [ReservedRegion] = proxy.reservedRegions(kind: .division, options: .includeInactive)
        let folds: [ReservedRegion] = regions.filter { (region: ReservedRegion) -> Bool in
            let frame: CGRect = region.frame
            return frame.height > frame.width && frame.minX > 0 && frame.maxX < width
        }

        return folds.min { (a: ReservedRegion, b: ReservedRegion) -> Bool in
            abs(a.frame.midX - middle) < abs(b.frame.midX - middle)
        }
    }
    #endif
}

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
    /// Whether the page's list draws the header and the tabs. Beside the
    /// pages, the pager draws them itself and the list only its own rows.
    var inList: Bool
    fileprivate var tabs: PagerTabs?
    var background: PagerColor
    fileprivate let progress: PagerProgress
    @ObservationIgnored fileprivate var select: (Int) -> Void
    let scroll: PagerHeaderScroll

    fileprivate init(page: Int, node: NativeUINode, inList: Bool, tabs: PagerTabs?, background: PagerColor, progress: PagerProgress, select: @escaping (Int) -> Void, scroll: PagerHeaderScroll) {
        self.page = page
        self.node = node
        self.inList = inList
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

    fileprivate func header(page: Int, node: NativeUINode, inList: Bool, tabs: PagerTabs?, background: PagerColor, progress: PagerProgress, select: @escaping (Int) -> Void) -> NativeUIPagerHeader {
        guard let header = headers[page] else {
            let header = NativeUIPagerHeader(page: page, node: node, inList: inList, tabs: tabs, background: background, progress: progress, select: select, scroll: self)
            headers[page] = header
            return header
        }

        // Only what changed, so an unchanged header doesn't redraw.
        if header.node !== node { header.node = node }
        if header.inList != inList { header.inList = inList }
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

        if page == leading {
            // The header follows this list from where it is, and any list
            // found before it is brought level with it.
            collapse = min(offsets[page] ?? 0, headerHeight)
            for other in scrollViews.keys where other != page {
                align(other)
            }
        } else if scrollViews[leading]?.view != nil {
            align(page)
        }
    }

    /// Forget every list and how far the header had gone, so each list is
    /// found again as it is.
    func reset() {
        collapse = 0
        stripMaxY = [:]
        offsets = [:]
        scrollViews = [:]
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
///
/// With the header beside the pages the row stays, drawing nothing, as does
/// the section the tabs head: taking either out reloads the whole list,
/// which loses its place.
struct NativeUIPagerHeaderRow: View {
    let header: NativeUIPagerHeader

    var body: some View {
        if header.inList {
            PagerChildren(node: header.node)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if header.scroll.headerHeight != height { header.scroll.headerHeight = height }
                }
                .background(PagerHeaderScrollViewFinder { header.scroll.attach($0, page: header.page) })
                .modifier(PagerStationary(header: header))
        } else {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// The pager's tabs as a page's list draws them: the header of the section
/// below the header row, which pins under the nav bar.
struct NativeUIPagerHeaderStrip: View {
    let header: NativeUIPagerHeader

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if header.inList {
            strip
        } else {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
        }
    }

    private var strip: some View {
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
                // Section headers get a minimum height and space above, and
                // rows a minimum height, which the header's row beside the
                // pages must not have.
                .environment(\.defaultMinListHeaderHeight, 0)
                .environment(\.defaultMinListRowHeight, 0)
                .listSectionSpacing(0)
                .contentMargins(.bottom, header.inList ? room : 0, for: .scrollContent)
                .onScrollGeometryChange(for: PagerListGeometry.self) { geometry in
                    PagerListGeometry(
                        y: geometry.contentOffset.y + geometry.contentInsets.top,
                        top: geometry.contentInsets.top,
                        bottom: geometry.contentInsets.bottom,
                        content: geometry.contentSize.height,
                        container: geometry.containerSize.height
                    )
                } action: { _, geometry in
                    guard header.inList else { return }

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

/// Clips a horizontal pager at its sides only, leaving a page's height of
/// room above and below, so its pages can still draw under a bar at the
/// bottom. A vertical pager gets that much room on every side as well.
private struct PagerSideClip: Shape {
    let horizontal: Bool

    func path(in rect: CGRect) -> Path {
        Path(horizontal
            ? rect.insetBy(dx: 0, dy: -rect.height)
            : rect.insetBy(dx: -rect.width, dy: -rect.height))
    }
}

/// Where the pager is, in pages, and how long a page is.
private struct PagerPosition: Equatable {
    let pages: CGFloat
    let length: CGFloat

    /// Within half a point of `page`.
    func isOn(_ page: Int) -> Bool {
        abs(pages - CGFloat(page)) * length <= 0.5
    }
}

/// A horizontal pager's way back to its page after iOS resizes it in the
/// background (on an iPhone Duo beside its side rail, the pager came back
/// between two pages). A class, so none of this redraws the pages.
private final class PagerResume {
    /// The page the pager is meant to be on: where it last came to rest on
    /// a page, a tapped tab, or a page PHP jumped to.
    var accepted: Int
    var count: Int
    /// The latest scroll geometry; nil while the pager has no size.
    var position: PagerPosition?
    /// Last measurable width survives zero-size layout samples.
    var width: CGFloat?
    var resize: PagerResize?
    var active = true
    var phase: ScrollPhase = .idle
    var userScrolling = false
    var geometryVersion = 0
    var waitingForGeometry: Int?
    /// An explicit selection or issued correction still owns its completion,
    /// even after its retry timeout. New user/PHP intent replaces this target.
    var target: Int?
    /// The pager moved while the app wasn't in front, so it may be off its page.
    var armed = false
    /// The pager is being put back; its moves are not the user's.
    var restoring = false
    var attempts = 0
    /// Bumped by anything that makes queued work stale.
    var generation = 0
    /// The generation a check is queued for.
    var pending: Int?

    init(page: Int, count: Int) {
        accepted = page
        self.count = count
    }

    /// Geometry changes aren't the user's: the app isn't in front, or the
    /// pager is being put back, and nobody is scrolling.
    func holds(horizontal: Bool) -> Bool {
        horizontal && (!active || restoring) && !userScrolling
    }

    /// A tab tap or a PHP jump: the pager goes there instead. In the
    /// background its move is only seen once the app is in front again.
    func chosen(_ page: Int) {
        let holding = restoring || !active
        settled()
        accepted = page
        target = page
        armed = true
        restoring = holding
    }

    /// Cancel queued checks and timeouts without losing the recovery intent.
    func suspend() {
        generation += 1
        waitingForGeometry = nil
        attempts = 0
    }

    /// The user scrolled: whatever was pending is theirs to decide.
    func settled(preservingResize: Bool = false) {
        suspend()
        restoring = false
        armed = false
        userScrolling = false
        target = nil
        if preservingResize {
            resize?.checking = false
            resize?.overdue = false
            resize?.timerVersion += 1
        } else {
            resize = nil
        }
    }
}

/// Selection survives an acknowledgement; command budget does not reset on
/// alignment, tracking or duplicate geometry. A later width burst gets a new
/// episode, while a same-width late clamp still belongs to this one.
private final class PagerResize {
    var page: Int
    var stable = false
    var exhausted = false
    var attempts = 0
    var version = 0
    var checking = false
    var overdue = false
    var timerVersion = 0

    init(page: Int) {
        self.page = page
    }
}
