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

    var body: some View {
        let horizontal = node.props.getBool("horizontal")
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let separator = node.props.getBool("separator")
        let onRefreshCb = node.props.getCallbackId("on_refresh")
        let onEndReachedCb = node.props.getCallbackId("on_end_reached")
        let endReachedBuffer = max(1, node.props.getInt("end_reached_buffer", default: 3))
        let nodeId = node.id
        let children = node.children

        // A list is "sectioned" when any direct child is a `list_section`.
        // Sectioned lists adopt the inset-grouped look by default (matching
        // SwiftUI's grouped style); `->plain()` opts back to plain rows.
        let hasSections = children.contains { $0.type == "list_section" }
        let grouped = hasSections && !node.props.getBool("plain")

        // A `sticky_header` pins once it reaches the top. Only a plain List's
        // section headers pin, so each sticky header heads a section of the
        // rows after it, up to the next one, which pushes it off.
        let hasStickyHeaders = !hasSections && children.contains { $0.type == "sticky_header" }

        // Map each leaf row id → its global index across all sections, so
        // end-reached fires near the true bottom rather than when a section
        // container first appears. Computed once per render.
        let (leafIndex, leafCount) = Self.leafRowIndex(children)

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
                if hasStickyHeaders {
                    let (leading, groups) = Self.stickyGroups(children)
                    ForEach(leading) { child in
                        rowView(child, separator: separator)
                            .onAppear {
                                fireEndReached(rowId: child.id, leafIndex: leafIndex,
                                               leafCount: leafCount, buffer: endReachedBuffer,
                                               cb: onEndReachedCb, nodeId: nodeId)
                            }
                    }
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.rows) { row in
                                rowView(row, separator: separator)
                                    .onAppear {
                                        fireEndReached(rowId: row.id, leafIndex: leafIndex,
                                                       leafCount: leafCount, buffer: endReachedBuffer,
                                                       cb: onEndReachedCb, nodeId: nodeId)
                                    }
                            }
                        } header: {
                            stickyHeaderView(group.header)
                        }
                        // Lines above and below a section are a section's,
                        // not a row's. Rows draw their own.
                        .listSectionSeparator(.hidden)
                    }
                } else {
                    ForEach(children) { child in
                        if child.type == "list_section" {
                            let header = child.props.getString("header", default: "")
                            let footer = child.props.getString("footer", default: "")
                            Section {
                                ForEach(Array(child.children.enumerated()), id: \.element.id) { index, row in
                                    rowView(row, separator: separator, isLastInSection: index == child.children.count - 1)
                                        .onAppear {
                                            fireEndReached(rowId: row.id, leafIndex: leafIndex,
                                                           leafCount: leafCount, buffer: endReachedBuffer,
                                                           cb: onEndReachedCb, nodeId: nodeId)
                                        }
                                }
                            } header: {
                                if !header.isEmpty { Text(header).nuiScaledFont(size: 13) }
                            } footer: {
                                if !footer.isEmpty { Text(footer).nuiScaledFont(size: 13) }
                            }
                        } else {
                            rowView(child, separator: separator)
                                .onAppear {
                                    fireEndReached(rowId: child.id, leafIndex: leafIndex,
                                                   leafCount: leafCount, buffer: endReachedBuffer,
                                                   cb: onEndReachedCb, nodeId: nodeId)
                                }
                        }
                    }
                }
            }
            .modifier(GroupedOrPlainListStyle(grouped: grouped))
            .modifier(StickyHeaderSpacingModifier(enabled: hasStickyHeaders))
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
    /// row-level styling. Shared by both flat rows and section children.
    @ViewBuilder
    private func rowView(_ child: NativeUINode, separator: Bool, isLastInSection: Bool = false) -> some View {
        // Legacy single-action API.
        let legacyDeleteCb = child.props.getCallbackId("on_swipe_delete")
        // New multi-action API.
        let leading = decodeActions(child.props.getString("leading_actions_json", default: ""))
        let trailing = decodeActions(child.props.getString("trailing_actions_json", default: ""))

        NodeView(node: child)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    actionButton(spec: action, nodeId: child.id)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: trailing.contains(where: { $0.role == "destructive" }) || legacyDeleteCb != 0) {
                // New multi-action takes precedence over legacy.
                if !trailing.isEmpty {
                    ForEach(trailing) { action in
                        actionButton(spec: action, nodeId: child.id)
                    }
                } else if legacyDeleteCb != 0 {
                    Button(role: .destructive) {
                        NativeElementBridge.sendPressEvent(legacyDeleteCb, nodeId: child.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    /// A sticky header, edge to edge with no minimum height, so it draws
    /// only what the node does. A hidden one draws nothing and takes no space.
    @ViewBuilder
    private func stickyHeaderView(_ header: NativeUINode) -> some View {
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

    /// Fire the end-reached callback when a row within the configured number
    /// of leaf rows appears. Works across sections via the precomputed leaf index.
    private func fireEndReached(rowId: Int, leafIndex: [Int: Int], leafCount: Int,
                                buffer: Int, cb: Int, nodeId: Int) {
        guard cb != 0, let gi = leafIndex[rowId] else { return }
        if gi >= leafCount - buffer {
            NativeElementBridge.sendPressEvent(cb, nodeId: nodeId)
        }
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

    /// Build a SwiftUI Button for one swipe action spec.
    /// Destructive role gets the red treatment automatically; otherwise
    /// the configured tint (if any) wins.
    @ViewBuilder
    private func actionButton(spec: SwipeActionSpec, nodeId: Int) -> some View {
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
