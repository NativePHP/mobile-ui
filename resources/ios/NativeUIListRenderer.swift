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
                                rowView(row, separator: separator, isLastInSection: index == child.children.count - 1)
                                    .onAppear {
                                        fireEndReached(rowId: row.id, leafIndex: leafIndex,
                                                       leafCount: leafCount, cb: onEndReachedCb, nodeId: nodeId)
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
                                               leafCount: leafCount, cb: onEndReachedCb, nodeId: nodeId)
                            }
                    }
                }
            }
            .modifier(GroupedOrPlainListStyle(grouped: grouped))
            .modifier(ListBackgroundModifier(node: node))
            // `List` has no showsIndicators initializer — the modifier is
            // the supported route (iOS 16+).
            .scrollIndicators(showsIndicators ? .automatic : .hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                if onRefreshCb != 0 {
                    NativeElementBridge.sendPressEvent(onRefreshCb, nodeId: nodeId)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
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

    /// Fire the end-reached callback when a row within the last 3 leaf rows
    /// appears. Works across sections via the precomputed leaf index.
    private func fireEndReached(rowId: Int, leafIndex: [Int: Int], leafCount: Int, cb: Int, nodeId: Int) {
        guard cb != 0, let gi = leafIndex[rowId] else { return }
        if gi >= leafCount - 3 {
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
private struct ListBackgroundModifier: ViewModifier {
    let node: NativeUINode
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let darkBg = colorScheme == .dark ? node.props.getColor("dark_bg_color", default: 0) : 0
        let argb = darkBg != 0 ? darkBg : (node.style?.bgColor ?? 0)
        if argb != 0 {
            content
                .scrollContentBackground(.hidden)
                .background(Color(argb: argb))
        } else {
            content
        }
    }
}
