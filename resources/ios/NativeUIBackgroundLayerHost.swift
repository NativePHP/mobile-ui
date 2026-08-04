import SwiftUI

/// Renders the `background_layer` sentinel BENEATH the screen content — the
/// counterpart of the floating overlay's top layer. The layer's child sits
/// at a fixed structural position in this view, so SwiftUI keeps its state
/// objects (a map's camera model, a video player) alive across publishes:
/// tab switches and pushes update the layer's props in place instead of
/// re-creating the native view. That's the whole point — a Flighty-style
/// map behind the app that never reloads.
///
/// When `layerNode` is nil this is a transparent pass-through, so it's safe
/// to wrap every tree unconditionally.
struct NativeUIBackgroundLayerHost<Content: View>: View {
    let layerNode: NativeUINode?
    @ViewBuilder var content: Content

    var body: some View {
        if let layerNode, let child = layerNode.children.first {
            ZStack {
                // Fixed structural position — identity survives republish.
                NodeView(node: child)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                content
            }
        } else {
            content
        }
    }
}
