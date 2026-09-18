import SwiftUI
import UIKit

/// Init function invoked by the generated `PluginBridgeFunctionRegistration`
/// at app startup (before the first tree render). Registers native-ui's
/// root-host chrome on core's `NativeRootHostRegistry`. Declared in the plugin
/// manifest under `ios.init_function`.
func registerNativeUIChrome() {
    NativeRootHostRegistry.shared.register("native-ui.drawer", consumes: "native_drawer") { root, content in
        let drawerNode = root.children.first { $0.type == "native_drawer" }
        return AnyView(NativeDrawerHost(drawerNode: drawerNode) { content })
    }

    NativeRootHostRegistry.shared.register("native-ui.floating-overlay", consumes: "floating_overlay") { root, content in
        let overlayNode = root.children.first { $0.type == "floating_overlay" }
        return AnyView(NativeFloatingOverlayHost(overlayNode: overlayNode) { content })
    }

    NativeRootHostRegistry.shared.register("native-ui.background-layer", consumes: "background_layer") { root, content in
        let layerNode = root.children.first { $0.type == "background_layer" }
        return AnyView(NativeUIBackgroundLayerHost(layerNode: layerNode) { content })
    }

    // Resolve chrome font tokens (per-layout / per-bar `font_name` props on
    // the root sentinels) for core's chrome renderers — bundle lookup +
    // CoreText registration + PostScript naming is this plugin's knowledge.
    NativeChromeFontResolver.resolvePostScriptName = { token in
        NativeUIFontResolver.postScriptName(for: token)
    }
}

/// Global open/close state for the content-agnostic side drawer
/// (`native_drawer`). A singleton so edge-swipe, the ☰ affordance, and
/// scrim/content taps can all drive the same drawer that `NativeDrawerHost`
/// (folded around the tree root by core's `NativeRootHostRegistry`) presents.
final class DrawerHostState: ObservableObject {
    static let shared = DrawerHostState()

    @Published var isOpen = false

    func open() { isOpen = true }
    func close() { isOpen = false }
    func toggle() { isOpen.toggle() }
}

/// Wraps the rendered screen tree in an interactive side drawer when the
/// published tree carries a `native_drawer` element. The drawer content is
/// **arbitrary** — its children render through the generic `NodeView`, so
/// developers can put any Blade/elements inside.
///
/// Two presentation modes (from the element's `mode` prop):
///   - `modal`  — drawer slides in over the content with a dim scrim.
///   - `reveal` — the content slides aside to expose the drawer behind it
///     (no scrim over the drawer — that would dim it and eat its taps).
///
/// A ☰ affordance is drawn here (top-leading) rather than in a nav-bar
/// renderer, so the button is guaranteed present regardless of which chrome
/// (or none) the screen uses.
///
/// When `drawerNode` is nil this is a transparent pass-through, so it's safe
/// to wrap every tree unconditionally.
struct NativeDrawerHost<Content: View>: View {
    let drawerNode: NativeUINode?
    @ViewBuilder var content: Content

    @ObservedObject private var state = DrawerHostState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private let edgeSwipeThreshold: CGFloat = 30

    /// Slide animation for the drawer. Suppressed when the user has Reduce
    /// Motion enabled — open/close state then applies instantly instead of
    /// sliding (`withAnimation(nil)` / `.animation(nil, value:)`).
    private var drawerAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.25)
    }

    /// Real top safe-area inset read straight from the window. The host's own
    /// nested GeometryReader reports an unreliable `safeAreaInsets.top` (it
    /// double-counts the content's safe-area handling), so position the ☰
    /// against the window inset instead — same approach as NativeTreeRenderer.
    private var windowSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        if let drawerNode {
            drawerLayout(drawerNode)
        } else {
            // No drawer on this screen — pass through, and make sure a drawer
            // left open on a previous screen doesn't linger in shared state.
            content.onAppear {
                if state.isOpen { state.isOpen = false }
            }
        }
    }

    @ViewBuilder
    private func drawerLayout(_ drawerNode: NativeUINode) -> some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let propWidth = CGFloat(drawerNode.props.getInt("width", default: 0))
            let drawerWidth: CGFloat = propWidth > 0
                ? propWidth
                : geometry.size.width * (isLandscape ? 0.4 : 0.85)
            let isReveal = drawerNode.props.getString("mode", default: "modal") == "reveal"

            // Fraction open in [0, 1] — combines the committed open state
            // with any in-flight drag so the drawer tracks the finger.
            let base: CGFloat = state.isOpen ? drawerWidth : 0
            let openWidth = max(0, min(drawerWidth, base + dragOffset))
            let progress = drawerWidth > 0 ? openWidth / drawerWidth : 0

            let edgeSwipe = DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard !state.isOpen,
                          value.startLocation.x < edgeSwipeThreshold,
                          value.translation.width > 0 else { return }
                    dragOffset = min(value.translation.width, drawerWidth)
                }
                .onEnded { value in settleOpen(value: value, width: drawerWidth) }

            let closeDrag = DragGesture()
                .onChanged { value in
                    guard state.isOpen, value.translation.width < 0 else { return }
                    dragOffset = max(value.translation.width, -drawerWidth)
                }
                .onEnded { value in settleClose(value: value, width: drawerWidth) }

            ZStack(alignment: .leading) {
                if isReveal {
                    // Drawer pinned at the left edge, behind the content.
                    drawerView(drawerNode, width: drawerWidth)
                        .zIndex(0)

                    // Content slides right to expose the drawer. No scrim
                    // dims the drawer; a transparent catcher over the pushed-
                    // aside content closes the drawer on tap / drag.
                    content
                        .offset(x: openWidth)
                        .zIndex(1)

                    if state.isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .offset(x: openWidth)
                            .onTapGesture { animateClosed() }
                            .gesture(closeDrag)
                            .zIndex(2)
                    }
                } else {
                    // Modal: content stays put; drawer slides over with a scrim.
                    content
                        .zIndex(0)

                    if progress > 0 {
                        Color.black
                            .opacity(Double(progress) * 0.45)
                            .ignoresSafeArea()
                            .onTapGesture { animateClosed() }
                            .gesture(closeDrag)
                            .zIndex(1)
                    }

                    drawerView(drawerNode, width: drawerWidth)
                        .offset(x: openWidth - drawerWidth)
                        .gesture(closeDrag)
                        .zIndex(2)
                }

                // Left-edge detector for swipe-to-open (both modes), when closed.
                if !state.isOpen {
                    Color.clear
                        .frame(width: edgeSwipeThreshold)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(edgeSwipe)
                        .ignoresSafeArea(edges: .leading)
                        .zIndex(3)
                }

                // ☰ affordance, top-leading, shown while the drawer is closed.
                if !state.isOpen {
                    Button {
                        withAnimation(drawerAnimation) { state.isOpen = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .nuiScaledFont(size: 18, weight: .semibold)
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .nuiMinTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open menu")
                    .padding(.leading, 12)
                    .padding(.top, windowSafeAreaTop + 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(4)
                }
            }
            .animation(drawerAnimation, value: state.isOpen)
        }
        // Full-screen coordinate space — the wrapped content manages its own
        // safe-area inset (via the environment, like NativeTreeRenderer), so a
        // respecting reader here would double-inset it and mis-place the ☰.
        .ignoresSafeArea()
        // If the drawer element disappears between publishes (navigated to a
        // screen / layout without one), make sure we don't strand it open.
        .onChange(of: drawerNode.id) { _ in
            if dragOffset != 0 { dragOffset = 0 }
        }
    }

    @ViewBuilder
    private func drawerView(_ drawerNode: NativeUINode, width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(drawerNode.children) { child in
                    NodeView(node: child).equatable()
                }
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Gesture settling

    private func settleOpen(value: DragGesture.Value, width: CGFloat) {
        let velocity = value.predictedEndTranslation.width - value.translation.width
        let opened = value.translation.width > width * 0.3 || velocity > 300
        withAnimation(drawerAnimation) {
            state.isOpen = opened
            dragOffset = 0
        }
    }

    private func settleClose(value: DragGesture.Value, width: CGFloat) {
        let velocity = value.predictedEndTranslation.width - value.translation.width
        let closed = abs(value.translation.width) > width * 0.3 || velocity < -300
        withAnimation(drawerAnimation) {
            state.isOpen = !closed
            dragOffset = 0
        }
    }

    private func animateClosed() {
        withAnimation(drawerAnimation) {
            state.isOpen = false
            dragOffset = 0
        }
    }
}
