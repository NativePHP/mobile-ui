import SwiftUI
import UIKit

/// Captures touch gestures over its content frame. Continuous gestures
/// (pan, pinch) write per-frame values into the bound `SharedValue` on
/// `SharedValueStore`; discrete gestures (swipe, pinch-end) fire a
/// callback into PHP. Children render normally — gesture detection
/// wraps the whole content frame.
///
/// Driven by props:
///   - `pan-x-id` /
///     `pan-x-initial`        — same as pan-y, for the horizontal axis.
///   - `on_drag_end`    (int)   — callback fired when a drag ends,
///                                carrying the final "x,y" translation
///                                (points) as text; an unbound axis
///                                reports the raw gesture translation.
///   - `pan-y-id`       (int)   — id of the SharedValue receiving the
///                                cumulative vertical drag translation.
///   - `pan-y-initial`  (float) — value to seed the store with on first
///                                appearance, so child elements bound
///                                through formulas have something to
///                                evaluate against before the user
///                                touches the screen.
///   - `pinch-id`       (int)   — id of the SharedValue receiving the
///                                cumulative pinch scale factor
///                                (1.0 = identity).
///   - `pinch-initial`  (float) — seed scale (defaults to 1).
///   - `pinch-min` /
///     `pinch-max`      (float) — bounds applied to the scale at the
///                                source, per gesture step (0 =
///                                unbounded). Clamping here — not just
///                                at the display binding — keeps the
///                                raw value from compounding past the
///                                bound, which would force a direction
///                                reversal to unwind the overshoot
///                                before anything visibly moves.
///   - `on_pinch_end`   (int)   — callback fired when the pinch ends,
///                                carrying the final scale as a float
///                                (rides the SLIDER_CHANGE format).
///   - `on_swipe`       (int)   — callback fired on a directional
///                                swipe, carrying "left" / "right" /
///                                "up" / "down" as text (rides the
///                                TEXT_CHANGE format).
///   - `swipe-fingers`  (int)   — touches required for the swipe
///                                (default 1; Jump-style is 3).
///
/// On gesture end, each anchor is reset so subsequent gestures continue
/// from the current value rather than snapping back.
struct NativeUIGestureAreaRenderer: View {
    let node: NativeUINode

    @State private var dragStartX: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @ObservedObject private var store = SharedValueStore.shared

    var body: some View {
        let panXId = node.props.getInt("pan-x-id", default: 0)
        let panXInitial = CGFloat(node.props.getFloat("pan-x-initial", default: 0))
        let panYId = node.props.getInt("pan-y-id", default: 0)
        let panYInitial = CGFloat(node.props.getFloat("pan-y-initial", default: 0))
        let onDragEnd = node.props.getInt("on_drag_end", default: 0)
        let hasPan = panXId != 0 || panYId != 0 || onDragEnd != 0
        let pinchId = node.props.getInt("pinch-id", default: 0)
        let pinchInitial = CGFloat(node.props.getFloat("pinch-initial", default: 1))
        let pinchMin = CGFloat(node.props.getFloat("pinch-min", default: 0))
        let pinchMax = CGFloat(node.props.getFloat("pinch-max", default: 0))
        let onPinchEnd = node.props.getInt("on_pinch_end", default: 0)
        let onSwipe = node.props.getInt("on_swipe", default: 0)
        let swipeFingers = node.props.getInt("swipe-fingers", default: 1)
        let a11yLabel = node.props.getString("a11y_label")
        let a11yHint = node.props.getString("a11y_hint")

        VStack(spacing: 0) {
            ForEach(node.children) { child in
                NodeView(node: child).equatable()
            }
        }
        .contentShape(Rectangle())
        // `including: .subviews` disables the drag entirely when no pan
        // binding exists — DragGesture(minimumDistance: 0) recognizes on
        // touch-down and would otherwise starve the swipe recognizers
        // and any other non-simultaneous gesture on the area.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if panXId != 0 {
                        store.set(dragStartX + value.translation.width, for: panXId)
                    }
                    if panYId != 0 {
                        store.set(dragStart + value.translation.height, for: panYId)
                    }
                }
                .onEnded { value in
                    if panXId != 0 { dragStartX = store.value(for: panXId) }
                    if panYId != 0 { dragStart = store.value(for: panYId) }
                    guard onDragEnd != 0 else { return }
                    // Report the resting translation of each bound axis;
                    // an unbound axis reports the raw gesture translation
                    // so a callback-only area (no SharedValue) still learns
                    // where the finger let go.
                    let x = panXId != 0 ? store.value(for: panXId) : value.translation.width
                    let y = panYId != 0 ? store.value(for: panYId) : value.translation.height
                    NativeElementBridge.sendTextChangeEvent(onDragEnd, nodeId: node.id, text: "\(x),\(y)")
                },
            including: hasPan ? .all : .subviews
        )
        .modifier(PinchModifier(
            nodeId: node.id,
            pinchId: pinchId,
            onPinchEnd: onPinchEnd,
            minScale: pinchMin,
            maxScale: pinchMax
        ))
        .modifier(SwipeModifier(
            nodeId: node.id,
            onSwipe: onSwipe,
            fingers: swipeFingers
        ))
        .onAppear {
            seedPanX(panXId, initial: panXInitial)
            seedPan(panYId, initial: panYInitial)
            seedPinch(pinchId, initial: pinchInitial)
        }
        // Two distinct re-publish situations to handle while this view
        // stays alive (onAppear won't re-fire):
        //
        //  1. PHP minted a NEW SharedValue id (fresh `SharedValue::make`
        //     each render) — seed the unknown id so the next gesture
        //     continues from the initial PHP published, not from 0.
        //  2. Same id, but `pinch-initial` / `pan-y-initial` CHANGED —
        //     PHP called `setValue()` on a persistent SharedValue. That
        //     is an explicit write-back: push it into the store even
        //     though the id already has a live value (a reset button,
        //     a snap-to-position, etc.).
        .onChange(of: panXId) { _, newId in
            seedPanX(newId, initial: panXInitial)
        }
        .onChange(of: panYId) { _, newId in
            seedPan(newId, initial: panYInitial)
        }
        .onChange(of: panXInitial) { _, newInitial in
            guard panXId != 0 else { return }
            store.set(newInitial, for: panXId)
            dragStartX = newInitial
        }
        .onChange(of: pinchId) { _, newId in
            seedPinch(newId, initial: pinchInitial)
        }
        .onChange(of: panYInitial) { _, newInitial in
            guard panYId != 0 else { return }
            store.set(newInitial, for: panYId)
            dragStart = newInitial
        }
        .onChange(of: pinchInitial) { _, newInitial in
            guard pinchId != 0 else { return }
            store.set(newInitial, for: pinchId)
        }
        .modifier(A11yLabelModifier(label: a11yLabel))
        .modifier(A11yHintModifier(hint: a11yHint))
    }

    private func seedPanX(_ id: Int, initial: CGFloat) {
        guard id != 0 else { return }
        if store.values[id] == nil {
            store.seed(initial, for: id)
        }
        dragStartX = store.value(for: id)
    }

    private func seedPan(_ id: Int, initial: CGFloat) {
        guard id != 0 else { return }
        if store.values[id] == nil {
            store.seed(initial, for: id)
        }
        dragStart = store.value(for: id)
    }

    private func seedPinch(_ id: Int, initial: CGFloat) {
        guard id != 0 else { return }
        if store.values[id] == nil {
            store.seed(initial, for: id)
        }
    }
}

// MARK: - Pinch (conditional)

/// Attached only when a pinch SharedValue or `@pinchEnd` callback is
/// wired. Simultaneous with the pan gesture so a pinch mid-drag still
/// tracks.
///
/// The scale advances INCREMENTALLY: each change multiplies the current
/// value by the ratio of this frame's magnification to the last frame's,
/// clamping every step. Anchoring to a gesture-start snapshot instead
/// (`start * magnification`) would let the un-clamped product run past
/// the bound while the display sits pinned at it — reversing direction
/// then has to unwind the whole overshoot before anything visibly
/// moves. With per-step clamping, reversals respond on the first frame.
private struct PinchModifier: ViewModifier {
    let nodeId: Int
    let pinchId: Int
    let onPinchEnd: Int
    let minScale: CGFloat  // 0 = unbounded
    let maxScale: CGFloat  // 0 = unbounded

    @State private var lastMagnification: CGFloat = 1
    /// Running scale when no SharedValue is bound (`@pinchEnd` only).
    @State private var localScale: CGFloat = 1

    func body(content: Content) -> some View {
        if pinchId == 0 && onPinchEnd == 0 {
            content
        } else {
            content.simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let ratio = value.magnification / lastMagnification
                        lastMagnification = value.magnification
                        if pinchId != 0 {
                            let next = clamped(SharedValueStore.shared.value(for: pinchId) * ratio)
                            SharedValueStore.shared.set(next, for: pinchId)
                        } else {
                            localScale = clamped(localScale * ratio)
                        }
                    }
                    .onEnded { _ in
                        lastMagnification = 1
                        let final = pinchId != 0
                            ? SharedValueStore.shared.value(for: pinchId)
                            : localScale
                        if onPinchEnd != 0 {
                            NativeElementBridge.sendSliderChangeEvent(onPinchEnd, nodeId: nodeId, value: Float(final))
                        }
                    }
            )
        }
    }

    private func clamped(_ v: CGFloat) -> CGFloat {
        var out = v
        if minScale > 0 { out = max(minScale, out) }
        if maxScale > 0 { out = min(maxScale, out) }
        return out
    }
}

// MARK: - Swipe (conditional)

/// Directional swipe with a configurable touch count (`swipe-fingers`,
/// e.g. 3 for the Jump-style three-finger swipe). SwiftUI gestures
/// can't observe touch count, so this wraps `UISwipeGestureRecognizer`
/// via `UIGestureRecognizerRepresentable` (iOS 18+, matching the
/// project deployment target) — one recognizer per direction, since
/// UIKit can't report which direction fired on a multi-direction
/// recognizer.
private struct SwipeModifier: ViewModifier {
    let nodeId: Int
    let onSwipe: Int
    let fingers: Int

    func body(content: Content) -> some View {
        if onSwipe == 0 {
            content
        } else {
            content
                .gesture(SwipeRecognizer(direction: .left, fingers: fingers) { fire("left") })
                .gesture(SwipeRecognizer(direction: .right, fingers: fingers) { fire("right") })
                .gesture(SwipeRecognizer(direction: .up, fingers: fingers) { fire("up") })
                .gesture(SwipeRecognizer(direction: .down, fingers: fingers) { fire("down") })
        }
    }

    private func fire(_ direction: String) {
        NativeElementBridge.sendTextChangeEvent(onSwipe, nodeId: nodeId, text: direction)
    }
}

private struct SwipeRecognizer: UIGestureRecognizerRepresentable {
    let direction: UISwipeGestureRecognizer.Direction
    let fingers: Int
    let onSwipe: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = direction
        recognizer.numberOfTouchesRequired = fingers
        // Let touches keep flowing to children (buttons, the pan drag)
        // while the swipe is being evaluated.
        recognizer.cancelsTouchesInView = false
        // Recognize alongside everything else (the sibling direction
        // recognizers, an enclosing ScrollView's pan, SwiftUI gestures
        // bridged by the host) — without this, whichever recognizer
        // claims the touch first silently kills the swipe.
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        // UISwipeGestureRecognizer is discrete — the action fires once,
        // in the .ended state, when the swipe is recognized.
        if recognizer.state == .ended {
            onSwipe()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - Accessibility modifiers (conditional)

private struct A11yLabelModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        if label.isEmpty { content }
        else { content.accessibilityLabel(label) }
    }
}

private struct A11yHintModifier: ViewModifier {
    let hint: String
    func body(content: Content) -> some View {
        if hint.isEmpty { content }
        else { content.accessibilityHint(hint) }
    }
}
