import SwiftUI
import Combine

/// Windowed list. The native side renders `count` logical slots in a
/// lazy `List`; PHP only ships the rows inside `window_from..window_to`.
/// Slots outside the window display a fixed-height skeleton so SwiftUI's
/// lazy machinery can compute total scroll extent without allocating a
/// real subtree per row.
///
/// As the visible range moves, the tracker debounces onAppear/onDisappear
/// events and (with hysteresis) fires `on_window_change(from, to)` to
/// PHP only when the visible range is approaching the edge of the data
/// PHP has already shipped. PHP's next render emits the new slice.
///
/// See `Plugins/nativephp/mobile-ui/src/Elements/NativeVirtualList.php`
/// for the matching element class.
struct NativeUIVirtualListRenderer: View {
    let node: NativeUINode

    var body: some View {
        let count = max(0, node.props.getInt("count"))
        let windowFrom = node.props.getInt("window_from")
        let windowTo = node.props.getInt("window_to")
        let estimatedRowHeight = CGFloat(node.props.getFloat("estimated_row_height", default: 56))
        let overscan = node.props.getInt("overscan", default: 30)
        let cbId = node.props.getCallbackId("on_window_change")
        let nodeId = node.id

        // Map absolute index -> child node, built once per render so the
        // inner per-row lookup is O(1).
        let rowByIndex: [Int: NativeUINode] = {
            var map: [Int: NativeUINode] = [:]
            map.reserveCapacity(node.children.count)
            for (offset, child) in node.children.enumerated() {
                map[windowFrom + offset] = child
            }
            return map
        }()

        VirtualListBody(
            count: count,
            windowFrom: windowFrom,
            windowTo: windowTo,
            estimatedRowHeight: estimatedRowHeight,
            overscan: overscan,
            cbId: cbId,
            nodeId: nodeId,
            rowByIndex: rowByIndex
        )
    }
}

/// Separating the body into a real View lets us own `@StateObject` for
/// the debouncer without rebuilding it every parent render.
private struct VirtualListBody: View {
    let count: Int
    let windowFrom: Int
    let windowTo: Int
    let estimatedRowHeight: CGFloat
    let overscan: Int
    let cbId: Int
    let nodeId: Int
    let rowByIndex: [Int: NativeUINode]

    @StateObject private var tracker = VisibleWindowTracker()

    var body: some View {
        // Push the latest window bounds into the tracker on every render
        // so the hysteresis check uses what PHP currently has — not the
        // values captured at first appear. `.task(id:)` re-runs whenever
        // any of the inputs changes (including after PHP grows the
        // window in response to an earlier emit).
        List {
            ForEach(0..<count, id: \.self) { index in
                Group {
                    if let child = rowByIndex[index] {
                        NodeView(node: child).equatable()
                    } else {
                        // Placeholder skeleton — meaningless to VoiceOver.
                        Color(.systemGray6)
                            .frame(height: estimatedRowHeight)
                            .accessibilityHidden(true)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear { tracker.markVisible(index) }
                .onDisappear { tracker.markHidden(index) }
            }
        }
        .listStyle(.plain)
        .task(id: "\(count)/\(windowFrom)/\(windowTo)/\(overscan)/\(cbId)/\(nodeId)") {
            tracker.update(
                count: count,
                windowFrom: windowFrom,
                windowTo: windowTo,
                overscan: overscan,
                cbId: cbId,
                nodeId: nodeId
            )
        }
    }
}

/// Tracks first/last visible row indexes and emits debounced. Holds the
/// CURRENT window bounds (set on each render) so the hysteresis check
/// never sees stale values after PHP grows the window.
private final class VisibleWindowTracker: ObservableObject {
    private var count: Int = 0
    private var windowFrom: Int = 0
    private var windowTo: Int = 0
    private var overscan: Int = 30
    private var cbId: Int = 0
    private var nodeId: Int = 0

    private var visibleIndexes: Set<Int> = []
    private var debounceTask: DispatchWorkItem?
    private var lastEmittedFirst: Int = -1
    private var lastEmittedLast: Int = -1

    func update(count: Int, windowFrom: Int, windowTo: Int, overscan: Int, cbId: Int, nodeId: Int) {
        self.count = count
        self.windowFrom = windowFrom
        self.windowTo = windowTo
        self.overscan = overscan
        self.cbId = cbId
        self.nodeId = nodeId
        // After a window update from PHP, re-evaluate immediately — the
        // visible range probably still needs more data (this is exactly
        // the "user is scrolled to row 199 when PHP resets window to
        // 0..79" case).
        scheduleEmit(delay: 0.01)
    }

    func markVisible(_ index: Int) {
        visibleIndexes.insert(index)
        scheduleEmit()
    }

    func markHidden(_ index: Int) {
        visibleIndexes.remove(index)
        scheduleEmit()
    }

    private func scheduleEmit(delay: TimeInterval = 0.2) {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.emitIfNeeded() }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func emitIfNeeded() {
        guard cbId != 0, count > 0, !visibleIndexes.isEmpty else { return }
        let first = visibleIndexes.min() ?? 0
        let last = visibleIndexes.max() ?? 0

        // Hysteresis: only request a new window if the visible range is
        // approaching the edge of what PHP has already sent.
        let trigger = max(1, overscan / 3)
        let needsLeft = first - trigger < windowFrom && windowFrom > 0
        let needsRight = last + trigger > windowTo && windowTo < count - 1
        guard needsLeft || needsRight else { return }

        let from = max(0, first - overscan)
        let to = min(count - 1, last + overscan)
        if from == lastEmittedFirst && to == lastEmittedLast { return }
        lastEmittedFirst = from
        lastEmittedLast = to
        NativeElementBridge.sendTextChangeEvent(cbId, nodeId: nodeId, text: "\(from),\(to)")
    }
}
