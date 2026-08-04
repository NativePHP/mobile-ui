import SwiftUI

/// Pull-to-refresh wrapper using SwiftUI's first-class `.refreshable`
/// modifier. Children render inside a vertical `ScrollView`; the
/// platform's native spinner appears when the user pulls down.
///
/// On iOS 17+ this is the canonical pull-to-refresh API — gives real
/// system haptics, accessibility (VoiceOver "pull to refresh" hint),
/// and the rubber-band physics users expect.
///
/// Driven by props:
///   - `on_refresh` (int) — callback ID fired when the user releases
///     the pull past threshold. The refresh spinner stays visible
///     until our `await Task.sleep(800ms)` completes, giving PHP time
///     to handle the event and publish a new tree.
///   - `shows_indicators` (bool, default true) — same contract as
///     scroll-view; hides the scroll indicators when false.
///
/// Children should NOT include their own `<scroll-view>` — this
/// element IS the scrolling container.
struct NativeUIRefreshableRenderer: View {
    let node: NativeUINode

    var body: some View {
        let refreshCallback = node.props.getInt("on_refresh", default: 0)
        let showsIndicators = node.props.getBool("shows_indicators", default: true)
        let nodeId = node.id

        ScrollView(.vertical, showsIndicators: showsIndicators) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(node.children) { child in
                    NodeView(node: child)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            guard refreshCallback != 0 else { return }
            NativeElementBridge.sendPressEvent(refreshCallback, nodeId: nodeId)
            // SwiftUI keeps the spinner visible until this async body
            // returns. Sleep for a short minimum so the user sees the
            // spinner even when PHP handlers are fast. PHP's handler
            // typically completes within this window; the next tree
            // publish appears just after the spinner hides.
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }
}
