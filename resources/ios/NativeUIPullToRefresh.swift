/// The gesture behind a list's custom pull-to-refresh, used when a plugin
/// draws the indicator: SwiftUI's `.refreshable` only shows the system
/// spinner. Fed the list's overscroll at its top and whether a finger is on
/// it, it says how far the list is pulled, when a release starts a refresh,
/// and where the indicator goes in the gap the pull opens above the rows.
///
/// A refresh keeps `margin` of room above the content until it ends, so the
/// indicator stays in view once the list settles back.
struct NativeUIPullToRefresh: Equatable {
    /// How far the list is pulled to refresh when it's let go.
    static let threshold: Double = 80
    /// The room kept above the content while refreshing.
    static let restHeight: Double = 60

    private(set) var isRefreshing = false
    /// Where the rows' top rests, below the bars, without the room a
    /// refresh keeps.
    private(set) var restTop: Double = 0
    private var pull: Double = 0
    private var interacting = false

    /// How far the list is pulled, from 0 at rest to 1 at the threshold; 1
    /// while refreshing.
    var progress: Double {
        isRefreshing ? 1 : min(pull / Self.threshold, 1)
    }

    /// The room to keep above the content.
    var margin: Double {
        isRefreshing ? Self.restHeight : 0
    }

    /// The height of the gap above the content, where the indicator draws.
    var gap: Double {
        pull
    }

    /// Where the indicator's top goes in the gap, for an indicator [size]
    /// tall: centred in the gap as it opens, then held as near the top as
    /// it sits while refreshing.
    func indicatorTop(size: Double) -> Double {
        min(gap, Self.restHeight) / 2 - size / 2
    }

    /// The list's top overscroll: how far its content sits below where it
    /// rests, the room kept while refreshing included.
    mutating func scrolled(overscroll: Double) {
        pull = max(0, overscroll)
    }

    /// The list's scroll offset and top content inset. The inset is taken as
    /// the rows' rest only outside a refresh, since it may or may not count
    /// the room the refresh keeps.
    mutating func scrolled(offset: Double, inset: Double) {
        if !isRefreshing {
            restTop = inset
        }
        scrolled(overscroll: -offset - restTop)
    }

    /// Returns whether letting go starts a refresh.
    @discardableResult
    mutating func interactionChanged(interacting: Bool) -> Bool {
        let released = self.interacting && !interacting
        self.interacting = interacting
        guard released, !isRefreshing, pull >= Self.threshold else { return false }
        isRefreshing = true
        return true
    }

    mutating func finishRefresh() {
        isRefreshing = false
    }
}
