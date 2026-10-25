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
///   - `bounded`        (bool)  — keep the zoomed content inside the
///                                area (see NativeUIPanBounds): pan stops at the
///                                content's edges, an axis the content
///                                fits on stays centred, a drag past an
///                                edge meets resistance, and the content
///                                springs back into place on release. A
///                                pinch zooms around the fingers.
///   - `content-ratio`  (float) — the content's width over height,
///                                fitted inside the area, for `bounded`
///                                (0 = the content fills the area).
///
/// On gesture end, each anchor is reset so subsequent gestures continue
/// from the current value rather than snapping back.
struct NativeUIGestureAreaRenderer: View {
    let node: NativeUINode

    @State private var dragStartX: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @ObservedObject private var store = SharedValueStore.shared

    // `bounded` only: the area's size, the drag's last translation (bounded
    // drags move by each step's change, so a pinch can move the pan in the
    // same gesture), the undamped pan the finger asked for and what was last
    // written, whether two fingers are pinching (the pinch then moves the
    // pan, not the drag), and the spring back.
    @State private var areaSize: CGSize = .zero
    @State private var lastTranslation: CGSize = .zero
    @State private var rawPan: CGSize = .zero
    @State private var writtenPan: CGSize = .zero
    @State private var pinching = false
    @State private var settle = NativeUIPanSettle()

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
        let bounds = NativeUIPanBounds(
            enabled: node.props.getBool("bounded"),
            area: areaSize,
            contentRatio: CGFloat(node.props.getFloat("content-ratio", default: 0))
        )
        let a11yLabel = node.props.getString("a11y_label")
        let a11yHint = node.props.getString("a11y_hint")

        VStack(spacing: 0) {
            ForEach(node.children) { child in
                NodeView(node: child).equatable()
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { areaSize = $0 }
        // `including: .subviews` disables the drag entirely when no pan
        // binding exists — DragGesture(minimumDistance: 0) recognizes on
        // touch-down and would otherwise starve the swipe recognizers
        // and any other non-simultaneous gesture on the area.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if bounds.enabled {
                        dragBounded(value.translation, panXId: panXId, panYId: panYId, pinchId: pinchId, bounds: bounds)
                        return
                    }
                    if panXId != 0 {
                        store.set(dragStartX + value.translation.width, for: panXId)
                    }
                    if panYId != 0 {
                        store.set(dragStart + value.translation.height, for: panYId)
                    }
                }
                .onEnded { value in
                    if bounds.enabled {
                        lastTranslation = .zero
                        settleIntoBounds(panXId: panXId, panYId: panYId, pinchId: pinchId, bounds: bounds)
                    }
                    if panXId != 0 { dragStartX = store.value(for: panXId) }
                    if panYId != 0 { dragStart = store.value(for: panYId) }
                    guard onDragEnd != 0 else { return }
                    // Report the resting translation of each bound axis;
                    // an unbound axis reports the raw gesture translation
                    // so a callback-only area (no SharedValue) still learns
                    // where the finger let go.
                    let scale = pinchId != 0 ? store.value(for: pinchId) : 1
                    let x = panXId != 0 ? bounds.settled(store.value(for: panXId), axis: .horizontal, scale: scale) : value.translation.width
                    let y = panYId != 0 ? bounds.settled(store.value(for: panYId), axis: .vertical, scale: scale) : value.translation.height
                    NativeElementBridge.sendTextChangeEvent(onDragEnd, nodeId: node.id, text: "\(x),\(y)")
                },
            including: hasPan ? .all : .subviews
        )
        .modifier(PinchModifier(
            nodeId: node.id,
            pinchId: pinchId,
            onPinchEnd: onPinchEnd,
            minScale: pinchMin,
            maxScale: pinchMax,
            bounds: bounds,
            panXId: panXId,
            panYId: panYId,
            onBoundedBegin: {
                settle.stop()
                pinching = true
            },
            onBoundedEnd: {
                pinching = false
                settleIntoBounds(panXId: panXId, panYId: panYId, pinchId: pinchId, bounds: bounds)
            }
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

    /// A bounded drag step: moves each bound axis by this step's change,
    /// freely inside the bounds and with growing resistance past them.
    private func dragBounded(_ translation: CGSize, panXId: Int, panYId: Int, pinchId: Int, bounds: NativeUIPanBounds) {
        let step = CGSize(width: translation.width - lastTranslation.width, height: translation.height - lastTranslation.height)
        lastTranslation = translation
        // SwiftUI's drag follows one finger; while two are down the pinch
        // moves the pan with both of them.
        guard !pinching else { return }
        settle.stop()
        let scale = pinchId != 0 ? store.value(for: pinchId) : 1
        if panXId != 0 {
            // Something else (a pinch, the spring back) moved the pan since
            // the last step: carry on from where it is.
            let current = store.value(for: panXId)
            if current != writtenPan.width { rawPan.width = current }
            rawPan.width += step.width
            writtenPan.width = bounds.resisted(rawPan.width, axis: .horizontal, scale: scale)
            store.set(writtenPan.width, for: panXId)
        }
        if panYId != 0 {
            let current = store.value(for: panYId)
            if current != writtenPan.height { rawPan.height = current }
            rawPan.height += step.height
            writtenPan.height = bounds.resisted(rawPan.height, axis: .vertical, scale: scale)
            store.set(writtenPan.height, for: panYId)
        }
    }

    /// Springs each bound axis back inside the bounds at the current zoom.
    private func settleIntoBounds(panXId: Int, panYId: Int, pinchId: Int, bounds: NativeUIPanBounds) {
        let scale = pinchId != 0 ? store.value(for: pinchId) : 1
        var moves: [NativeUIPanSettle.Move] = []
        if panXId != 0 {
            let from = store.value(for: panXId)
            moves.append(.init(id: panXId, from: from, to: bounds.settled(from, axis: .horizontal, scale: scale)))
        }
        if panYId != 0 {
            let from = store.value(for: panYId)
            moves.append(.init(id: panYId, from: from, to: bounds.settled(from, axis: .vertical, scale: scale)))
        }
        settle.run(moves)
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
    /// With `bounded`, a UIKit pinch (see BoundedPinchRecognizer) zooms
    /// around the fingers and pans with them, and the content springs back
    /// into place when they lift.
    let bounds: NativeUIPanBounds
    let panXId: Int
    let panYId: Int
    let onBoundedBegin: () -> Void
    let onBoundedEnd: () -> Void

    @State private var lastMagnification: CGFloat = 1
    /// Running scale when no SharedValue is bound (`@pinchEnd` only).
    @State private var localScale: CGFloat = 1

    func body(content: Content) -> some View {
        if pinchId == 0 && onPinchEnd == 0 {
            content
        } else if bounds.enabled && pinchId != 0 {
            content.gesture(BoundedPinchRecognizer(
                bounds: bounds,
                pinchId: pinchId,
                panXId: panXId,
                panYId: panYId,
                clamp: { clamped($0) },
                onBegin: onBoundedBegin,
                onEnd: { final in
                    onBoundedEnd()
                    if onPinchEnd != 0 {
                        NativeElementBridge.sendSliderChangeEvent(onPinchEnd, nodeId: nodeId, value: Float(final))
                    }
                }
            ))
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

// MARK: - Bounded pan

/// The pinch of a `bounded` area. UIKit's pinch reports where the fingers
/// are on every step (SwiftUI's only where they started), so the zoom
/// follows them and both fingers pan together: a point at c from the
/// centre maps to scale * p + pan, so keeping the point that was under the
/// fingers' last centre under the new one gives
/// pan' = c - r * (last - pan).
private struct BoundedPinchRecognizer: UIGestureRecognizerRepresentable {
    let bounds: NativeUIPanBounds
    let pinchId: Int
    let panXId: Int
    let panYId: Int
    let clamp: (CGFloat) -> CGFloat
    let onBegin: () -> Void
    let onEnd: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let store = SharedValueStore.shared
        let location = context.converter.localLocation
        let centre = CGPoint(x: location.x - bounds.area.width / 2, y: location.y - bounds.area.height / 2)

        switch recognizer.state {
        case .began:
            recognizer.scale = 1
            context.coordinator.lastCentre = centre
            onBegin()
        case .changed:
            // A finger lifting or landing moves the centre without the
            // content moving: start again from the new centre.
            guard recognizer.numberOfTouches >= 2, let last = context.coordinator.lastCentre,
                  context.coordinator.touches == recognizer.numberOfTouches else {
                context.coordinator.touches = recognizer.numberOfTouches
                context.coordinator.lastCentre = centre
                recognizer.scale = 1
                return
            }
            let previous = store.value(for: pinchId)
            let next = clamp(previous * recognizer.scale)
            recognizer.scale = 1
            store.set(next, for: pinchId)
            let applied = previous > 0 ? next / previous : 1
            if panXId != 0 {
                store.set(centre.x - applied * (last.x - store.value(for: panXId)), for: panXId)
            }
            if panYId != 0 {
                store.set(centre.y - applied * (last.y - store.value(for: panYId)), for: panYId)
            }
            context.coordinator.lastCentre = centre
        case .ended, .cancelled, .failed:
            context.coordinator.lastCentre = nil
            context.coordinator.touches = 2
            onEnd(store.value(for: pinchId))
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastCentre: CGPoint?
        var touches = 2

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Where `bounded` lets the pan go. The content is the area, or
/// `content-ratio` fitted inside it (where `fit="contain"` draws an
/// image). Zoomed by `scale` about the centre, it may move until its
/// edges meet the area's: `(scale * content - area) / 2` each way, or not
/// at all on an axis it fits on, which keeps it centred there.
struct NativeUIPanBounds {
    enum Axis { case horizontal, vertical }

    let enabled: Bool
    let area: CGSize
    let contentRatio: CGFloat

    private var content: CGSize {
        guard contentRatio > 0, area.width > 0, area.height > 0 else { return area }
        return area.width / area.height > contentRatio
            ? CGSize(width: area.height * contentRatio, height: area.height)
            : CGSize(width: area.width, height: area.width / contentRatio)
    }

    func limit(_ axis: Axis, scale: CGFloat) -> CGFloat {
        let content = content
        return axis == .horizontal
            ? max(0, (scale * content.width - area.width) / 2)
            : max(0, (scale * content.height - area.height) / 2)
    }

    /// Where a pan comes to rest: inside the limit.
    func settled(_ pan: CGFloat, axis: Axis, scale: CGFloat) -> CGFloat {
        guard enabled else { return pan }
        let limit = limit(axis, scale: scale)
        return min(limit, max(-limit, pan))
    }

    /// What the finger's undamped pan shows: itself inside the limit, and
    /// past it an overshoot that grows ever slower, never more than the
    /// area's own size (UIScrollView's rubber band).
    func resisted(_ pan: CGFloat, axis: Axis, scale: CGFloat) -> CGFloat {
        let limit = limit(axis, scale: scale)
        let overshoot = abs(pan) - limit
        guard overshoot > 0 else { return pan }
        let extent = max(1, axis == .horizontal ? area.width : area.height)
        let damped = (1 - 1 / (overshoot * 0.55 / extent + 1)) * extent
        return (pan < 0 ? -1 : 1) * (limit + damped)
    }
}

/// Moves pan values back inside their bounds, frame by frame through the
/// store. The content's transform reads the store directly and its own
/// modifier turns SwiftUI animations off for it, so a `withAnimation`
/// write wouldn't move it smoothly.
final class NativeUIPanSettle: NSObject {
    struct Move {
        let id: Int
        let from: CGFloat
        let to: CGFloat
    }

    private static let duration: CFTimeInterval = 0.35

    private var link: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var moves: [Move] = []

    func run(_ moves: [Move]) {
        stop()
        self.moves = moves.filter { $0.id != 0 && abs($0.to - $0.from) > 0.01 }
        guard !self.moves.isEmpty else { return }
        startedAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let progress = min(1, (link.targetTimestamp - startedAt) / Self.duration)
        // Ease out: fast away from the edge, slowing into place.
        let eased = 1 - pow(1 - progress, 3)
        for move in moves {
            SharedValueStore.shared.set(move.from + (move.to - move.from) * eased, for: move.id)
        }
        if progress >= 1 {
            stop()
        }
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
