import SwiftUI

/// A decoded swipe-action descriptor (one button on either edge).
private struct SwipeActionSpec: Decodable, Identifiable {
    let cb: Int
    let label: String
    let icon: String
    let tint: String
    let role: String

    var id: Int { cb }
}

private func decodeActions(_ json: String) -> [SwipeActionSpec] {
    guard !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([SwipeActionSpec].self, from: data)) ?? []
}

private func colorFromHex(_ hex: String) -> Color? {
    let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    let r = Double((v >> 16) & 0xFF) / 255.0
    let g = Double((v >> 8) & 0xFF) / 255.0
    let b = Double(v & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
}

struct NativeUIListRenderer: View {
    let node: NativeUINode

    /// The height of each row this list has drawn, for a placeholder drawn in its place.
    @State private var rowHeights = ListRowHeights()

    /// The rows on screen, for `on_visible_range`.
    @State private var visibleRange = ListVisibleRange()

    var body: some View {
        let horizontal = node.props.getBool("horizontal")
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let separator = node.props.getBool("separator")
        let onRefreshCb = node.props.getCallbackId("on_refresh")
        let onEndReachedCb = node.props.getCallbackId("on_end_reached")
        let endReachedBuffer = max(1, node.props.getInt("end_reached_buffer", default: 3))
        let onVisibleRangeCb = node.props.getCallbackId("on_visible_range")
        let nodeId = node.id
        let children = node.children

        // A list is "sectioned" when any direct child is a `list_section`.
        // Sectioned lists adopt the inset-grouped look by default (matching
        // SwiftUI's grouped style); `->plain()` opts back to plain rows.
        let hasSections = children.contains { $0.type == "list_section" }
        let grouped = hasSections && !node.props.getBool("plain")

        // Map each leaf row id → its global index across all sections, so
        // end-reached fires near the true bottom rather than when a section
        // container first appears. Computed once per render.
        let (leafIndex, leafCount) = Self.leafRowIndex(children)

        // Rows are measured while the list reports its visible range: that's
        // what a list putting placeholders in rows' places goes by.
        let rows = ListRowContext(
            separator: separator,
            heights: onVisibleRangeCb != 0 ? rowHeights : nil,
            visibleRange: onVisibleRangeCb != 0 ? visibleRange : nil
        )
        // The tracker reads positions from the frame showing now. It isn't
        // observed, so this doesn't draw the list again.
        let _ = visibleRange.update(callbackId: onVisibleRangeCb, nodeId: nodeId,
                                    step: max(1, node.props.getInt("visible_range_step", default: 10)),
                                    leafIndex: leafIndex)

        if horizontal {
            ScrollView(.horizontal, showsIndicators: showsIndicators) {
                LazyHStack(spacing: 0) {
                    ForEach(children) { child in
                        NodeView(node: child)
                            .equatable()
                    }
                }
            }
        } else {
            List {
                ForEach(children) { child in
                    if child.type == "list_section" {
                        let header = child.props.getString("header", default: "")
                        let footer = child.props.getString("footer", default: "")
                        Section {
                            ForEach(Array(child.children.enumerated()), id: \.element.id) { index, row in
                                rowView(row, rows, isLastInSection: index == child.children.count - 1)
                                    .onAppear(perform: Self.endReachedAction(at: leafIndex[row.id], leafCount: leafCount,
                                        buffer: endReachedBuffer, cb: onEndReachedCb, nodeId: nodeId))
                            }
                        } header: {
                            if !header.isEmpty { Text(header).nuiScaledFont(size: 13) }
                        } footer: {
                            if !footer.isEmpty { Text(footer).nuiScaledFont(size: 13) }
                        }
                    } else {
                        rowView(child, rows)
                            .onAppear(perform: Self.endReachedAction(at: leafIndex[child.id], leafCount: leafCount,
                                buffer: endReachedBuffer, cb: onEndReachedCb, nodeId: nodeId))
                    }
                }
            }
            .modifier(GroupedOrPlainListStyle(grouped: grouped))
            .modifier(ListBackgroundModifier(node: node))
            // `List` has no showsIndicators initializer — the modifier is
            // the supported route (iOS 16+).
            .scrollIndicators(showsIndicators ? .automatic : .hidden)
            .scrollDismissesKeyboard(.interactively)
            // Attach the refresh control only when the list declares an
            // on-refresh handler — an unconditional .refreshable installs
            // pull-to-refresh (spinner and all) on every list, including
            // static settings/forms where it does nothing. Android's renderer
            // already gates its PullToRefreshBox the same way.
            .modifier(ListRefreshModifier(onRefreshCb: onRefreshCb, nodeId: nodeId))
        }
    }

    /// One list row: the node plus its leading/trailing swipe actions and
    /// row-level styling, or a placeholder at the row's height. Shared by
    /// both flat rows and section children.
    @ViewBuilder
    private func rowView(_ child: NativeUINode, _ rows: ListRowContext, isLastInSection: Bool = false) -> some View {
        if child.type == "list_placeholder" {
            placeholderView(child, rows, isLastInSection: isLastInSection)
        } else {
            nodeRowView(child, rows, isLastInSection: isLastInSection)
        }
    }

    @ViewBuilder
    private func nodeRowView(_ child: NativeUINode, _ rows: ListRowContext, isLastInSection: Bool) -> some View {
        let separator = rows.separator
        // Legacy single-action API.
        let legacyDeleteCb = child.props.getCallbackId("on_swipe_delete")
        // New multi-action API.
        let leading = decodeActions(child.props.getString("leading_actions_json", default: ""))
        let trailing = decodeActions(child.props.getString("trailing_actions_json", default: ""))
        // The swipe closures capture only this, not the row or `self` (see endReachedAction).
        let rowId = child.id

        NodeView(node: child)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RowHeightModifier(rowId: rowId, heights: rows.heights))
            .modifier(VisibleRowModifier(rowId: rowId, visibleRange: rows.visibleRange))
            .listRowInsets(EdgeInsets())
            // Rows carry SwiftUI's opaque system fill, which paints over the
            // list's own background — so hiding the scroll background via
            // ListBackgroundModifier still left a white sheet on a themed
            // screen. Clear the row and let its content decide.
            .listRowBackground(Color.clear)
            // Drive dividers from the bottom edge only; always hide the top
            // edge. The top separator renders solely on a section's first row,
            // so hiding it removes the stray full-width line that otherwise
            // sits on top of an inset-grouped section (under its header).
            // Also hide the bottom edge on a section's last row so the group
            // ends clean (SwiftUI's grouped default), rather than drawing a
            // divider under the final row.
            .listRowSeparator(separator && !isLastInSection ? .visible : .hidden, edges: .bottom)
            .listRowSeparator(.hidden, edges: .top)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                ForEach(leading) { action in
                    Self.actionButton(spec: action, nodeId: rowId)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: trailing.contains(where: { $0.role == "destructive" }) || legacyDeleteCb != 0) {
                // New multi-action takes precedence over legacy.
                if !trailing.isEmpty {
                    ForEach(trailing) { action in
                        Self.actionButton(spec: action, nodeId: rowId)
                    }
                } else if legacyDeleteCb != 0 {
                    Button(role: .destructive) {
                        NativeElementBridge.sendPressEvent(legacyDeleteCb, nodeId: rowId)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    /// An empty row at the height the list last drew the row it stands in for,
    /// with the row's separators, so swapping one for the other moves nothing.
    @ViewBuilder
    private func placeholderView(_ child: NativeUINode, _ rows: ListRowContext, isLastInSection: Bool) -> some View {
        let estimated = CGFloat(child.props.getFloat("estimated_height", default: 0))
        let height = rows.heights?.height(of: child.id)
            ?? (estimated > 0 ? estimated : rows.heights?.typical ?? 44)

        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
            .modifier(VisibleRowModifier(rowId: child.id, visibleRange: rows.visibleRange))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(rows.separator && !isLastInSection ? .visible : .hidden, edges: .bottom)
            .listRowSeparator(.hidden, edges: .top)
    }

    /// What a row does when it appears: fire the end-reached callback if it's
    /// within the configured number of leaf rows of the end. Works across
    /// sections via the precomputed leaf index.
    ///
    /// Static and built from plain values on purpose. SwiftUI keeps a row's
    /// closures until the row draws again, which for a row scrolled past is
    /// never. A closure that called an instance method captured `self`, and
    /// with it this list's whole node tree, so every row above the viewport
    /// kept the entire list from the frame it last drew in. A long list held
    /// many copies of itself and the app ran out of memory.
    private static func endReachedAction(at index: Int?, leafCount: Int, buffer: Int,
                                         cb: Int, nodeId: Int) -> () -> Void {
        guard cb != 0, let index, index >= leafCount - buffer else { return {} }

        return { NativeElementBridge.sendPressEvent(cb, nodeId: nodeId) }
    }

    /// Flatten the list's direct children into an ordered map of leaf-row id
    /// → global index (sections contribute their children in order), plus the
    /// total leaf count. Used only for end-reached detection.
    private static func leafRowIndex(_ children: [NativeUINode]) -> ([Int: Int], Int) {
        var map: [Int: Int] = [:]
        var counter = 0
        for child in children {
            if child.type == "list_section" {
                for row in child.children {
                    map[row.id] = counter
                    counter += 1
                }
            } else {
                map[child.id] = counter
                counter += 1
            }
        }
        return (map, counter)
    }

    /// Build a SwiftUI Button for one swipe action spec.
    /// Destructive role gets the red treatment automatically; otherwise
    /// the configured tint (if any) wins.
    @ViewBuilder
    private static func actionButton(spec: SwipeActionSpec, nodeId: Int) -> some View {
        let role: ButtonRole? = spec.role == "destructive" ? .destructive : nil
        let button = Button(role: role) {
            NativeElementBridge.sendPressEvent(spec.cb, nodeId: nodeId)
        } label: {
            if !spec.icon.isEmpty {
                Label(spec.label.isEmpty ? " " : spec.label, systemImage: spec.icon)
            } else {
                Text(spec.label.isEmpty ? " " : spec.label)
            }
        }

        if role != .destructive, let tint = colorFromHex(spec.tint) {
            button.tint(tint)
        } else {
            button
        }
    }
}

/// What every row of a list needs from it besides its node.
private struct ListRowContext {
    let separator: Bool
    /// Set when the list measures its rows.
    let heights: ListRowHeights?
    /// Set when the list reports its visible range.
    let visibleRange: ListVisibleRange?
}

/// The height each row of a list last drew at, by node id. A node's id comes
/// from its key, so a placeholder with a row's key finds the row's height.
/// Not observed: a row measuring itself doesn't draw the list again.
private final class ListRowHeights {
    private var heights: [Int: CGFloat] = [:]
    private var total: CGFloat = 0

    func height(of rowId: Int) -> CGFloat? {
        heights[rowId]
    }

    /// The average row, for a placeholder whose row was never drawn.
    var typical: CGFloat? {
        heights.isEmpty ? nil : total / CGFloat(heights.count)
    }

    func set(_ height: CGFloat, for rowId: Int) {
        total += height - (heights[rowId] ?? 0)
        heights[rowId] = height
    }
}

/// Keeps a row's height in the list's cache whenever it lays out.
private struct RowHeightModifier: ViewModifier {
    let rowId: Int
    let heights: ListRowHeights?

    func body(content: Content) -> some View {
        if let heights {
            // Captures the cache and the id only (see endReachedAction).
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                heights.set(height, for: rowId)
            }
        } else {
            content
        }
    }
}

/// Tells the list's tracker when a row comes on screen and goes off it.
private struct VisibleRowModifier: ViewModifier {
    let rowId: Int
    let visibleRange: ListVisibleRange?

    func body(content: Content) -> some View {
        if let visibleRange {
            content
                .onAppear { visibleRange.appeared(rowId) }
                .onDisappear { visibleRange.disappeared(rowId) }
        } else {
            content
        }
    }
}

/// The rows of a list on screen. Sends `on_visible_range` the positions of
/// the first and last, as "first,last", once either has moved by the step
/// since the last report. Positions count rows as end-reached does, and come
/// from the frame showing when it reports, so a row inserted above the screen
/// doesn't leave them stale.
///
/// A new frame takes every row on screen off it and puts it back, so the
/// range is read a moment after it moves, when that has settled, and no more
/// than every 150ms while scrolling.
private final class ListVisibleRange {
    private var callbackId = 0
    private var nodeId = 0
    private var step = 10
    private var leafIndex: [Int: Int] = [:]

    private var onScreen: Set<Int> = []
    /// The range last reported. The list starts at the top, so a range near
    /// it isn't reported until it moves a step.
    private var reported = (first: 0, last: 0)
    private var reportedAt: CFAbsoluteTime = 0
    private var pending: DispatchWorkItem?

    private static let settle: CFAbsoluteTime = 0.05
    private static let interval: CFAbsoluteTime = 0.15

    func update(callbackId: Int, nodeId: Int, step: Int, leafIndex: [Int: Int]) {
        self.callbackId = callbackId
        self.nodeId = nodeId
        self.step = step
        self.leafIndex = leafIndex
    }

    func appeared(_ rowId: Int) {
        onScreen.insert(rowId)
        changed()
    }

    func disappeared(_ rowId: Int) {
        onScreen.remove(rowId)
        changed()
    }

    private func changed() {
        guard callbackId != 0, pending == nil, let range = currentRange(),
              abs(range.first - reported.first) >= step || abs(range.last - reported.last) >= step else { return }

        let wait = max(Self.settle, reportedAt + Self.interval - CFAbsoluteTimeGetCurrent())
        let task = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.report()
        }
        pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: task)
    }

    private func report() {
        guard callbackId != 0, let range = currentRange() else { return }
        reported = range
        reportedAt = CFAbsoluteTimeGetCurrent()
        NativeElementBridge.sendTextChangeEvent(callbackId, nodeId: nodeId, text: "\(range.first),\(range.last)")
    }

    private func currentRange() -> (first: Int, last: Int)? {
        let indexes = onScreen.compactMap { leafIndex[$0] }
        guard let first = indexes.min(), let last = indexes.max() else { return nil }
        return (first, last)
    }
}

/// `.listStyle` is generic over a single concrete `ListStyle`, so a
/// `grouped ? .insetGrouped : .plain` ternary fails to type-check (the two
/// branches are different types). Branch at the view level instead.
private struct GroupedOrPlainListStyle: ViewModifier {
    let grouped: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if grouped {
            content.listStyle(.insetGrouped)
        } else {
            content.listStyle(.plain)
        }
    }
}

/// SwiftUI's List paints the system (grouped) background and ignores the
/// node's own background style, so a themed screen (`bg-theme-background`)
/// renders on the stock gray instead of the app's palette. When the node
/// declares a background, hide the system scroll background and paint the
/// node's color — matching how every other container element behaves.
///
/// Two more cases hide the system background without painting anything
/// here, because the node's own `NodeStyleModifier` (which wraps this
/// renderer) already draws what should show through:
///   - a gradient (`bg-gradient-to-* from-* via-* to-*`, carried as
///     `gradient_stops`), which the modifier paints behind the List;
///   - `transparent` — the list sits directly on the screen's background
///     (a gradient, an image, the background layer). `bg-transparent`
///     can't express this: it packs to the same 0 as "no colour".
private struct ListBackgroundModifier: ViewModifier {
    let node: NativeUINode
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let darkBg = colorScheme == .dark ? node.props.getColor("dark_bg_color", default: 0) : 0
        let argb = darkBg != 0 ? darkBg : (node.style?.bgColor ?? 0)
        let hasGradient = !node.props.getString("gradient_stops", default: "").isEmpty
        let transparent = node.props.getBool("transparent")

        if transparent || hasGradient {
            content
                .scrollContentBackground(.hidden)
        } else if argb != 0 {
            content
                .scrollContentBackground(.hidden)
                .background(Color(argb: argb))
        } else {
            content
        }
    }
}

/// Conditionally attaches pull-to-refresh: only lists with an `on_refresh`
/// callback get the control; every other list scrolls plainly.
private struct ListRefreshModifier: ViewModifier {
    let onRefreshCb: Int
    let nodeId: Int

    func body(content: Content) -> some View {
        if onRefreshCb != 0 {
            content.refreshable {
                NativeElementBridge.sendPressEvent(onRefreshCb, nodeId: nodeId)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } else {
            content
        }
    }
}
