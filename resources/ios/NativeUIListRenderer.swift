import SwiftUI
import UIKit

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

    @Environment(\.defaultMinListRowHeight) private var minRowHeight
    /// Set when this list is a page of a pager with a header, which the list
    /// draws above its rows (see NativeUIPagerHeader).
    @Environment(\.nativeUIPagerHeader) private var pagerHeader

    /// The height of each row this list has drawn, for a placeholder drawn in its place.
    @State private var rowHeights = ListRowHeights()

    /// The rows on screen, for `on_visible_range` and `on_scroll_end`.
    @State private var visibleRange = ListVisibleRange()

    var body: some View {
        let horizontal = node.props.getBool("horizontal")
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let separator = node.props.getBool("separator")
        let rowColor = node.props.getColor("row_color", default: 0)
        let onRefreshCb = node.props.getCallbackId("on_refresh")
        let onEndReachedCb = node.props.getCallbackId("on_end_reached")
        let endReachedBuffer = max(1, node.props.getInt("end_reached_buffer", default: 3))
        let onVisibleRangeCb = node.props.getCallbackId("on_visible_range")
        let onScrollEndCb = node.props.getCallbackId("on_scroll_end")
        let nodeId = node.id
        let children = node.children

        // A list is "sectioned" when any direct child is a `list_section`.
        // Sectioned lists adopt the inset-grouped look by default (matching
        // SwiftUI's grouped style); `->plain()` opts back to plain rows.
        let hasSections = children.contains { $0.type == "list_section" }
        let grouped = hasSections && !node.props.getBool("plain") && pagerHeader == nil

        // A `sticky_header` pins once it reaches the top. Only a plain List's
        // section headers pin, so each sticky header heads a section of the
        // rows after it, up to the next one, which pushes it off.
        let hasStickyHeaders = !hasSections && children.contains { $0.type == "sticky_header" }

        // Map each leaf row id → its global index across all sections, so
        // end-reached fires near the true bottom rather than when a section
        // container first appears. Computed once per render.
        let (leafIndex, leafCount) = Self.leafRowIndex(children)
        // Rows are measured while the list reports its visible range: that's
        // what a list putting placeholders in rows' places goes by.
        let tracksRows = onVisibleRangeCb != 0 || onScrollEndCb != 0
        let rowStyle = ListRowStyle(separator: separator, rowColor: rowColor, grouped: grouped, minHeight: minRowHeight,
                                    heights: onVisibleRangeCb != 0 ? rowHeights : nil,
                                    visibleRange: tracksRows ? visibleRange : nil)
        // The tracker reads positions from the frame showing now. It isn't
        // observed, so this doesn't draw the list again.
        let _ = visibleRange.update(callbackId: onVisibleRangeCb, scrollEndCallbackId: onScrollEndCb, nodeId: nodeId,
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
                if let pagerHeader {
                    // The header, then every row in one section under the
                    // pager's tabs, which pin once the header has gone. The
                    // rows of any list sections go in it too: a section in a
                    // section isn't a thing.
                    NativeUIPagerHeaderRow(header: pagerHeader)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    Section {
                        ForEach(Self.leafRows(children)) { row in
                            Self.row(row, style: rowStyle,
                                endReachedCb: Self.endReachedCallback(at: leafIndex[row.id], leafCount: leafCount,
                                    buffer: endReachedBuffer, cb: onEndReachedCb),
                                listId: nodeId)
                        }
                    } header: {
                        if pagerHeader.hasTabs {
                            NativeUIPagerHeaderStrip(header: pagerHeader)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                } else if hasStickyHeaders {
                    let (leading, groups) = Self.stickyGroups(children)
                    ForEach(leading) { child in
                        Self.row(child, style: rowStyle,
                            endReachedCb: Self.endReachedCallback(at: leafIndex[child.id], leafCount: leafCount,
                                buffer: endReachedBuffer, cb: onEndReachedCb),
                            listId: nodeId)
                    }
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.rows) { row in
                                Self.row(row, style: rowStyle,
                                    endReachedCb: Self.endReachedCallback(at: leafIndex[row.id], leafCount: leafCount,
                                        buffer: endReachedBuffer, cb: onEndReachedCb),
                                    listId: nodeId)
                            }
                        } header: {
                            Self.stickyHeaderView(group.header)
                        }
                        // Lines above and below a section are a section's,
                        // not a row's. Rows draw their own.
                        .listSectionSeparator(.hidden)
                    }
                } else if hasSections {
                    ForEach(children) { child in
                        if child.type == "list_section" {
                            let header = child.props.getString("header", default: "")
                            let footer = child.props.getString("footer", default: "")
                            Section {
                                ForEach(Array(child.children.enumerated()), id: \.element.id) { index, row in
                                    Self.row(row, style: rowStyle, isLastInSection: index == child.children.count - 1,
                                        endReachedCb: Self.endReachedCallback(at: leafIndex[row.id], leafCount: leafCount,
                                            buffer: endReachedBuffer, cb: onEndReachedCb),
                                        listId: nodeId)
                                }
                            } header: {
                                if !header.isEmpty { Text(header).nuiScaledFont(size: 13) }
                            } footer: {
                                if !footer.isEmpty { Text(footer).nuiScaledFont(size: 13) }
                            }
                        } else {
                            Self.row(child, style: rowStyle,
                                endReachedCb: Self.endReachedCallback(at: leafIndex[child.id], leafCount: leafCount,
                                    buffer: endReachedBuffer, cb: onEndReachedCb),
                                listId: nodeId)
                        }
                    }
                } else {
                    // Without sections each child is one row, and the ForEach
                    // says so by building exactly one view for it.
                    ForEach(children) { child in
                        Self.row(child, style: rowStyle,
                            endReachedCb: Self.endReachedCallback(at: leafIndex[child.id], leafCount: leafCount,
                                buffer: endReachedBuffer, cb: onEndReachedCb),
                            listId: nodeId)
                    }
                }
            }
            .modifier(GroupedOrPlainListStyle(grouped: grouped))
            .modifier(StickyHeaderSpacingModifier(enabled: hasStickyHeaders))
            .environment(\.nativeUIListRowMargin, NativeUIListRowMargin.system)
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
            .modifier(ListScrollPhaseModifier(tracker: onScrollEndCb != 0 ? visibleRange : nil))
            .modifier(NativeUIPagerHeaderListModifier(header: pagerHeader))
            // Only this list draws the header, not one in its rows.
            .environment(\.nativeUIPagerHeader, nil)
        }
    }

    /// The rows of a list, with each list section's rows in its place.
    private static func leafRows(_ children: [NativeUINode]) -> [NativeUINode] {
        children.flatMap { $0.type == "list_section" ? $0.children : [$0] }
    }

    /// One list row: the node, then what the List reads off it, outside the
    /// node's EquatableView, where the List can see it (see ListRow). Or a
    /// placeholder at the row's height, styled like the row, so swapping one
    /// for the other moves nothing.
    @ViewBuilder
    private static func row(_ child: NativeUINode, style: ListRowStyle, isLastInSection: Bool = false,
                            endReachedCb: Int, listId: Int) -> some View {
        let traits = ListRowTraits(separator: style.separator && !isLastInSection, rowColor: style.rowColor, grouped: style.grouped)
        let visible = VisibleRowModifier(rowId: child.id, visibleRange: style.visibleRange)
        if child.type == "list_placeholder" {
            ListPlaceholderRow(height: placeholderHeight(child, heights: style.heights),
                               endReachedCb: endReachedCb, listId: listId)
                .equatable()
                .modifier(visible)
                .modifier(traits)
        } else {
            let row = ListRow(node: child, minHeight: style.minHeight, endReachedCb: endReachedCb, listId: listId)
            let measured = RowHeightModifier(rowId: child.id, heights: style.heights)
            if let swipeActions = ListRowSwipeActions(node: child) {
                row
                    .equatable()
                    .modifier(measured)
                    .modifier(visible)
                    .modifier(traits)
                    .modifier(swipeActions)
            } else {
                row
                    .equatable()
                    .modifier(measured)
                    .modifier(visible)
                    .modifier(traits)
            }
        }
    }

    /// The height the list last drew the row a placeholder stands in for, or
    /// the placeholder's estimate, or the list's average row.
    private static func placeholderHeight(_ child: NativeUINode, heights: ListRowHeights?) -> CGFloat {
        let estimated = CGFloat(child.props.getFloat("estimated_height", default: 0))

        return heights?.height(of: child.id) ?? (estimated > 0 ? estimated : heights?.typical ?? 44)
    }

    /// The list's end-reached callback for a row within the configured number
    /// of leaf rows of the end, or 0. Works across sections via the
    /// precomputed leaf index.
    private static func endReachedCallback(at index: Int?, leafCount: Int, buffer: Int, cb: Int) -> Int {
        guard cb != 0, let index, index >= leafCount - buffer else { return 0 }

        return cb
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
            } else if child.type == "sticky_header" {
                continue
            } else {
                map[child.id] = counter
                counter += 1
            }
        }
        return (map, counter)
    }

    /// A sticky header, edge to edge with no minimum height, so it draws
    /// only what the node does. A hidden one draws nothing and takes no space.
    @ViewBuilder
    private static func stickyHeaderView(_ header: NativeUINode) -> some View {
        if header.layout?.display != Display.none {
            NodeView(node: header)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
        }
    }

    /// Split a list's direct children at its sticky headers: the rows before
    /// the first one, then each header with the rows after it.
    private static func stickyGroups(_ children: [NativeUINode]) -> ([NativeUINode], [StickyGroup]) {
        var leading: [NativeUINode] = []
        var groups: [StickyGroup] = []
        for child in children {
            if child.type == "sticky_header" {
                groups.append(StickyGroup(header: child, rows: []))
            } else if groups.isEmpty {
                leading.append(child)
            } else {
                groups[groups.count - 1].rows.append(child)
            }
        }
        return (leading, groups)
    }
}

/// A sticky header and the rows it pins over.
private struct StickyGroup: Identifiable {
    let header: NativeUINode
    var rows: [NativeUINode]

    var id: Int { header.id }
}

/// A plain List gives every section header a minimum height and about 22pt
/// of room above it, which shows until the header pins. A sticky header is a
/// row like any other, so it gets neither: one hidden takes no space, and one
/// showing sits flush against the row above.
private struct StickyHeaderSpacingModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, #available(iOS 17.0, *) {
            content
                .environment(\.defaultMinListHeaderHeight, 0)
                .listSectionSpacing(0)
        } else if enabled {
            content
                .environment(\.defaultMinListHeaderHeight, 0)
        } else {
            content
        }
    }
}

/// How every row of a list is styled, from the list's own props.
private struct ListRowStyle {
    let separator: Bool
    let rowColor: Int
    let grouped: Bool
    let minHeight: CGFloat
    /// Set when the list measures its rows.
    let heights: ListRowHeights?
    /// Set when the list reports its visible range.
    let visibleRange: ListVisibleRange?
}

/// The part of a list row SwiftUI can skip: the row's node, built from plain
/// values and compared with `==`.
///
/// SwiftUI's List runs the ForEach's content for every row each time the list
/// draws. A row of modifiers carrying closures (swipe actions, onAppear) never
/// compared equal to last frame's, so each frame updated every row SwiftUI had
/// made, whether one row had changed or none of the ones on screen had.
/// mobile-air's frame diff keeps the node object of a subtree that didn't
/// change, so an unchanged row now compares equal and SwiftUI skips it.
///
/// It goes in an EquatableView, which costs less than leaving SwiftUI to find
/// `==` itself. The List doesn't see insets, backgrounds, separators or swipe
/// actions set inside one, so those go on outside it (ListRowTraits,
/// ListRowSwipeActions).
private struct ListRow: View, Equatable {
    let node: NativeUINode
    /// The list's minimum row height, passed in so it's part of `==`.
    let minHeight: CGFloat
    /// The list's end-reached callback when this row is near enough the end to fire it, otherwise 0.
    let endReachedCb: Int
    /// The list's node id, which the end-reached event is sent for.
    let listId: Int

    var body: some View {
        NodeView(node: node)
            .equatable()
            // A node fills the height it is offered with its content pinned
            // to the top, so a one-line row in a cell taller than itself (the
            // list's minimum row height, 52pt on iOS 26) sat high. Keep the
            // row at its own height and centre it in that minimum instead.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .onAppear(perform: Self.endReachedAction(cb: endReachedCb, listId: listId))
    }

    /// What a row does when it appears: fire the end-reached callback if the
    /// list gave this row one.
    ///
    /// Static and built from plain values on purpose. SwiftUI keeps a row's
    /// closures until the row draws again, which for a row scrolled past is
    /// never. A closure that called an instance method captured `self`, and
    /// with it this list's whole node tree, so every row above the viewport
    /// kept the entire list from the frame it last drew in. A long list held
    /// many copies of itself and the app ran out of memory.
    fileprivate static func endReachedAction(cb: Int, listId: Int) -> () -> Void {
        guard cb != 0 else { return {} }

        return { NativeElementBridge.sendPressEvent(cb, nodeId: listId) }
    }
}

/// An empty row at the height the list last drew the row it stands in for.
/// It fires end-reached like the row would.
private struct ListPlaceholderRow: View, Equatable {
    let height: CGFloat
    let endReachedCb: Int
    let listId: Int

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
            .onAppear(perform: ListRow.endReachedAction(cb: endReachedCb, listId: listId))
    }
}

/// What the List reads off every row, outside the row's EquatableView, where
/// it can see it.
private struct ListRowTraits: ViewModifier {
    let separator: Bool
    let rowColor: Int
    let grouped: Bool

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            // Plain rows are cleared: SwiftUI's opaque system fill paints
            // over the list's own background, leaving a white sheet on a
            // themed screen. Grouped rows keep a card — the system grouped
            // cell colour, which is what draws the rounded inset-grouped
            // sections — and `row_color` themes either.
            .listRowBackground(Self.rowBackground(rowColor: rowColor, grouped: grouped))
            // Drive dividers from the bottom edge only; always hide the top
            // edge. The top separator renders solely on a section's first row,
            // so hiding it removes the stray full-width line that otherwise
            // sits on top of an inset-grouped section (under its header).
            // Also hide the bottom edge on a section's last row so the group
            // ends clean (SwiftUI's grouped default), rather than drawing a
            // divider under the final row.
            .listRowSeparator(separator ? .visible : .hidden, edges: .bottom)
            .listRowSeparator(.hidden, edges: .top)
    }

    /// A row's fill: the list's `row_color` when set, else the system card
    /// colour in the grouped style and nothing in the plain one.
    private static func rowBackground(rowColor: Int, grouped: Bool) -> Color {
        if rowColor != 0 { return Color(argb: rowColor) }
        return grouped ? Color(uiColor: .secondarySystemGroupedBackground) : .clear
    }
}

/// A row's leading/trailing swipe actions, for a row that has any.
///
/// Kept as the props' JSON and decoded when drawn, so a frame that doesn't
/// change them compares equal and builds nothing again.
private struct ListRowSwipeActions: ViewModifier, Equatable {
    /// The swipe closures capture only this, not the row (see ListRow.endReachedAction).
    let rowId: Int
    /// New multi-action API.
    let leadingJson: String
    let trailingJson: String
    /// Legacy single-action API.
    let legacyDeleteCb: Int

    init?(node: NativeUINode) {
        rowId = node.id
        leadingJson = node.props.getString("leading_actions_json", default: "")
        trailingJson = node.props.getString("trailing_actions_json", default: "")
        legacyDeleteCb = node.props.getCallbackId("on_swipe_delete")
        if leadingJson.isEmpty && trailingJson.isEmpty && legacyDeleteCb == 0 { return nil }
    }

    func body(content: Content) -> some View {
        let leading = decodeActions(leadingJson)
        let trailing = decodeActions(trailingJson)

        content
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

    /// Build a SwiftUI Button for one swipe action spec.
    /// Destructive role gets the red treatment automatically; otherwise
    /// the configured tint (if any) wins.
    @ViewBuilder
    private static func actionButton(spec: SwipeActionSpec, nodeId: Int) -> some View {
        let role: ButtonRole? = spec.role == "destructive" ? .destructive : nil
        let button = Button(role: role) {
            NativeElementBridge.sendPressEvent(spec.cb, nodeId: nodeId)
        } label: {
            if spec.icon.hasPrefix(NativeIcon.customPrefix) {
                // Swipe icons are raw SF Symbol names (no getIconForName
                // mapping), so only custom icons take the NativeIcon path.
                Label { Text(spec.label.isEmpty ? " " : spec.label) } icon: { NativeIcon.image(spec.icon) }
            } else if !spec.icon.isEmpty {
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
            content.onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: Self.record(rowId, in: heights))
        } else {
            content
        }
    }

    /// Built from the row's id and the list's cache alone, like
    /// ListRow.endReachedAction: SwiftUI keeps a row's closures until it draws again.
    private static func record(_ rowId: Int, in heights: ListRowHeights) -> (CGFloat) -> Void {
        { height in heights.set(height, for: rowId) }
    }
}

/// Tells the list's tracker when a row comes on screen and goes off it.
private struct VisibleRowModifier: ViewModifier {
    let rowId: Int
    let visibleRange: ListVisibleRange?

    func body(content: Content) -> some View {
        if let visibleRange {
            content
                .onAppear(perform: Self.appeared(rowId, in: visibleRange))
                .onDisappear(perform: Self.disappeared(rowId, in: visibleRange))
        } else {
            content
        }
    }

    /// Built from the row's id and the list's tracker alone, like
    /// ListRow.endReachedAction: SwiftUI keeps a row's closures until it draws again.
    private static func appeared(_ rowId: Int, in tracker: ListVisibleRange) -> () -> Void {
        { tracker.appeared(rowId) }
    }

    private static func disappeared(_ rowId: Int, in tracker: ListVisibleRange) -> () -> Void {
        { tracker.disappeared(rowId) }
    }
}

/// Tells the list's tracker where a scroll is, for `on_scroll_end`.
private struct ListScrollPhaseModifier: ViewModifier {
    let tracker: ListVisibleRange?

    func body(content: Content) -> some View {
        if let tracker {
            content.onScrollPhaseChange(Self.phaseChanged(in: tracker))
        } else {
            content
        }
    }

    /// Built from the list's tracker alone, like ListRow.endReachedAction.
    private static func phaseChanged(in tracker: ListVisibleRange) -> (ScrollPhase, ScrollPhase) -> Void {
        { _, phase in tracker.scrollPhaseChanged(to: phase) }
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
///
/// When a scroll comes to rest, `on_scroll_end` gets the range instead, read
/// the same way, and a visible range report still to come is dropped for it.
private final class ListVisibleRange {
    private var callbackId = 0
    private var scrollEndCallbackId = 0
    private var nodeId = 0
    private var step = 10
    private var leafIndex: [Int: Int] = [:]

    /// How many of each row's views are on screen: a row and its placeholder
    /// are different views, and the new one can come on screen before the old
    /// one goes.
    private var onScreen: [Int: Int] = [:]
    /// The range last reported. The list starts at the top, so a range near
    /// it isn't reported until it moves a step.
    private var reported = (first: 0, last: 0)
    private var reportedAt: CFAbsoluteTime = 0
    private var pending: DispatchWorkItem?
    /// The list has moved since it was last at rest.
    private var moved = false
    /// The report of a scroll come to rest, waiting for the rows to settle.
    private var pendingEnd: DispatchWorkItem?

    private static let settle: CFAbsoluteTime = 0.05
    private static let interval: CFAbsoluteTime = 0.15

    func update(callbackId: Int, scrollEndCallbackId: Int, nodeId: Int, step: Int, leafIndex: [Int: Int]) {
        self.callbackId = callbackId
        self.scrollEndCallbackId = scrollEndCallbackId
        self.nodeId = nodeId
        self.step = step
        self.leafIndex = leafIndex
    }

    func appeared(_ rowId: Int) {
        onScreen[rowId, default: 0] += 1
        changed()
    }

    func disappeared(_ rowId: Int) {
        let views = (onScreen[rowId] ?? 0) - 1
        onScreen[rowId] = views > 0 ? views : nil
        changed()
    }

    /// A scroll ends when the list is idle again after moving. A finger that
    /// stops a fling and lifts without dragging ends it too; a tap that never
    /// moved the list doesn't.
    func scrollPhaseChanged(to phase: ScrollPhase) {
        if phase.isScrolling {
            moved = true
            pendingEnd?.cancel()
            pendingEnd = nil
        } else if phase == .idle, moved {
            moved = false
            scrollEnded()
        }
    }

    private func scrollEnded() {
        guard scrollEndCallbackId != 0 else { return }

        pending?.cancel()
        pending = nil
        let task = DispatchWorkItem { [weak self] in
            self?.pendingEnd = nil
            self?.reportScrollEnd()
        }
        pendingEnd = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: task)
    }

    private func reportScrollEnd() {
        guard scrollEndCallbackId != 0, let range = currentRange() else { return }
        reported = range
        reportedAt = CFAbsoluteTimeGetCurrent()
        NativeElementBridge.sendTextChangeEvent(scrollEndCallbackId, nodeId: nodeId, text: "\(range.first),\(range.last)")
    }

    private func changed() {
        guard callbackId != 0, pending == nil, pendingEnd == nil, let range = currentRange(),
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
        let indexes = onScreen.keys.compactMap { leafIndex[$0] }
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
///
/// Shared with `NativeUIVirtualListRenderer`, so both lists follow one set
/// of background rules.
struct ListBackgroundModifier: ViewModifier {
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

/// The horizontal inset of a list row's content: the system's minimum
/// layout margin (16pt on most iPhones, 20pt on the wide ones), which is
/// where iOS puts section headers, footers and its own cell content. Rows
/// pad by it so their text lines up with their headers on every device.
enum NativeUIListRowMargin {
    @MainActor
    static var system: CGFloat {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        return root?.systemMinimumLayoutMargins.leading ?? 16
    }
}

private struct NativeUIListRowMarginKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    /// Horizontal padding for list rows; 16pt outside a `native:list`.
    var nativeUIListRowMargin: CGFloat {
        get { self[NativeUIListRowMarginKey.self] }
        set { self[NativeUIListRowMarginKey.self] = newValue }
    }
}
