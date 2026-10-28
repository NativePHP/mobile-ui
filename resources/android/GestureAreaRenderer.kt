package com.nativephp.plugins.native_ui.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.mobile.ui.nativerender.SharedValueStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * Captures touch gestures over its content frame. Continuous gestures
 * (pan, pinch) write per-frame values into the bound `SharedValue` on
 * `SharedValueStore`; discrete gestures (swipe, pinch-end) fire a
 * callback into PHP. Children render normally — gesture detection
 * wraps the whole content frame.
 *
 * Driven by props:
 *   - `pan-y-id`       (int)   — id of the SharedValue receiving the
 *                                cumulative vertical drag translation.
 *   - `pan-y-initial`  (float) — initial value to seed the store with.
 *   - `pan-x-id` /
 *     `pan-x-initial`          — same, for the horizontal axis. Bind one
 *                                axis or both.
 *   - `pan-x-snap` /
 *     `pan-y-snap`     (string)— comma-separated points a bound axis
 *                                settles on (see PanSnap): it follows the
 *                                finger between the lowest and highest
 *                                with resistance past them, springs to
 *                                the nearest on release, and springs to a
 *                                PHP write-back too.
 *   - `on_drag_end`    (int)   — callback fired when a drag ends,
 *                                carrying the final "x,y" translation
 *                                (dp) as text (rides the TEXT_CHANGE
 *                                format). An unbound axis reports the
 *                                raw gesture translation.
 *   - `pinch-id`       (int)   — id of the SharedValue receiving the
 *                                cumulative pinch scale factor
 *                                (1.0 = identity).
 *   - `pinch-initial`  (float) — seed scale (defaults to 1).
 *   - `pinch-min` /
 *     `pinch-max`      (float) — bounds applied to the scale at the
 *                                source, per gesture step (0 =
 *                                unbounded). Clamping here — not just
 *                                at the display binding — keeps the
 *                                raw value from compounding past the
 *                                bound, which would force a direction
 *                                reversal to unwind the overshoot
 *                                before anything visibly moves.
 *   - `on_pinch_end`   (int)   — callback fired when the pinch ends,
 *                                carrying the final scale as a float
 *                                (rides the SLIDER_CHANGE format).
 *   - `on_swipe`       (int)   — callback fired on a directional
 *                                swipe, carrying "left" / "right" /
 *                                "up" / "down" as text (rides the
 *                                TEXT_CHANGE format).
 *   - `swipe-fingers`  (int)   — touches required for the swipe
 *                                (default 1; Jump-style is 3).
 *   - `bounded`        (bool)  — keep the zoomed content inside the
 *                                area (see PanBounds): pan stops at the
 *                                content's edges, an axis the content
 *                                fits on stays centred, a drag past an
 *                                edge meets resistance, and the content
 *                                springs back into place on release. A
 *                                pinch zooms around the fingers.
 *   - `content-ratio`  (float) — the content's width over height,
 *                                fitted inside the area, for `bounded`
 *                                (0 = the content fills the area).
 *
 * Per-frame value updates happen on the Compose render thread; PHP is
 * only involved on the discrete events.
 */
object GestureAreaRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val panXId = node.props.getInt("pan-x-id", 0)
        val panXInitial = node.props.getFloat("pan-x-initial", 0f)
        val panYId = node.props.getInt("pan-y-id", 0)
        val panYInitial = node.props.getFloat("pan-y-initial", 0f)
        val onDragEnd = node.props.getInt("on_drag_end", 0)
        val pinchId = node.props.getInt("pinch-id", 0)
        val pinchInitial = node.props.getFloat("pinch-initial", 1f)
        val pinchMin = node.props.getFloat("pinch-min", 0f)
        val pinchMax = node.props.getFloat("pinch-max", 0f)
        val onPinchEnd = node.props.getInt("on_pinch_end", 0)
        val onSwipe = node.props.getInt("on_swipe", 0)
        val swipeFingers = node.props.getInt("swipe-fingers", 1)

        // `bounded` only: the area's size in dp (pan values are dp), and the
        // two-finger state and spring back the drag and pinch share.
        val density = LocalDensity.current
        var areaSize by remember { mutableStateOf(Size.Zero) }
        val bounds = PanBounds(
            enabled = node.props.getBool("bounded"),
            area = areaSize,
            contentRatio = node.props.getFloat("content-ratio", 0f),
        )
        val scope = rememberCoroutineScope()
        val settle = remember { BoundedPan() }
        val snapX = PanSnap.parse(node.props.getString("pan-x-snap"))
        val snapY = PanSnap.parse(node.props.getString("pan-y-snap"))
        val snapping = remember { SnapPan() }

        // Seed during COMPOSITION (inline, before children compose) rather
        // than in a LaunchedEffect: effects run after children have
        // composed, and a child's `evaluate()` read materializes the store
        // entry — which would turn a post-composition seed into a no-op.
        //
        // Two distinct re-publish situations to handle:
        //  1. PHP minted a NEW SharedValue id (fresh `SharedValue::make`
        //     each render) — seed the unknown id.
        //  2. Same id, but the initial CHANGED — PHP called `setValue()`
        //     on a persistent SharedValue. That is an explicit
        //     write-back: push it into the store even though the id
        //     already has a live value (a reset button, snap-to, etc.).
        SyncBinding(panXId, panXInitial, if (snapX.isEmpty) null else { value -> snapping.to(panXId, value, scope) })
        SyncBinding(panYId, panYInitial, if (snapY.isEmpty) null else { value -> snapping.to(panYId, value, scope) })
        SyncBinding(pinchId, pinchInitial)

        Box(
            modifier = modifier
                .nuiA11y(node.props.getString("a11y_label"), node.props.getString("a11y_hint"))
                .onSizeChanged { size ->
                    areaSize = with(density) { Size(size.width.toDp().value, size.height.toDp().value) }
                }
                .pointerInput(panXId, panYId, onDragEnd, bounds, snapX, snapY) {
                    if (panXId == 0 && panYId == 0 && onDragEnd == 0) return@pointerInput
                    if (bounds.enabled) {
                        // The undamped pan the finger asked for, and what was
                        // last written, per axis: a pinch or the spring back
                        // moving the pan between steps is picked up again.
                        var rawX = 0f
                        var rawY = 0f
                        var writtenX = 0f
                        var writtenY = 0f
                        detectDragGestures(
                            onDragEnd = {
                                val (x, y) = settle.into(bounds, scope, panXId, panYId, pinchId)
                                if (onDragEnd != 0) {
                                    NativeUIBridge.sendTextChangeEvent(onDragEnd, node.id, "$x,$y")
                                }
                            },
                            onDragCancel = { settle.into(bounds, scope, panXId, panYId, pinchId) },
                        ) { _, dragAmount ->
                            // Two fingers down: the pinch moves the pan with
                            // both of them, so the first finger alone mustn't.
                            if (settle.pinching) return@detectDragGestures
                            settle.stop()
                            val scale = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
                            if (panXId != 0) {
                                val current = SharedValueStore.valueOf(panXId)
                                if (current != writtenX) rawX = current
                                rawX += dragAmount.x.toDp().value
                                writtenX = bounds.resisted(rawX, horizontal = true, scale = scale)
                                SharedValueStore.set(panXId, writtenX)
                            }
                            if (panYId != 0) {
                                val current = SharedValueStore.valueOf(panYId)
                                if (current != writtenY) rawY = current
                                rawY += dragAmount.y.toDp().value
                                writtenY = bounds.resisted(rawY, horizontal = false, scale = scale)
                                SharedValueStore.set(panYId, writtenY)
                            }
                        }
                        return@pointerInput
                    }
                    // Raw gesture translation for this drag, in dp — what
                    // `on_drag_end` reports for an axis with no SharedValue.
                    var gestureX = 0f
                    var gestureY = 0f
                    // dragAmount is in raw pixels; convert to dp so the
                    // SharedValue stays density-independent and the
                    // user's `interpolate([0, 200], ...)` formulas match
                    // iOS point-based behavior. PointerInputScope
                    // extends Density, so .toDp() is in scope.
                    // `bound` is what the detector reports for the axis (or
                    // axes) it watches and is what moves the SharedValue;
                    // `raw` is the pointer's full movement, kept for both
                    // axes so `on_drag_end` can report an unbound one too.
                    // A snapping axis follows the finger from where it was
                    // when the drag began (rawX / rawY), with resistance
                    // past its outer points, and the tracker's fling picks
                    // the point it springs to on release.
                    var rawX = 0f
                    var rawY = 0f
                    val velocity = VelocityTracker()
                    val onStart: (Offset) -> Unit = {
                        snapping.stop()
                        rawX = if (panXId != 0) SharedValueStore.valueOf(panXId) else 0f
                        rawY = if (panYId != 0) SharedValueStore.valueOf(panYId) else 0f
                        velocity.resetTracking()
                    }
                    val onDrag: (Offset, Offset) -> Unit = { bound, raw ->
                        gestureX += raw.x.toDp().value
                        gestureY += raw.y.toDp().value
                        rawX += bound.x.toDp().value
                        rawY += bound.y.toDp().value
                        if (panXId != 0) {
                            SharedValueStore.set(panXId, if (snapX.isEmpty) SharedValueStore.valueOf(panXId) + bound.x.toDp().value else snapX.resisted(rawX))
                        }
                        if (panYId != 0) {
                            SharedValueStore.set(panYId, if (snapY.isEmpty) SharedValueStore.valueOf(panYId) + bound.y.toDp().value else snapY.resisted(rawY))
                        }
                    }
                    val onEnd: () -> Unit = {
                        // px per second, into dp like the pan itself.
                        val fling = velocity.calculateVelocity()
                        val x = if (panXId != 0) snapping.settle(panXId, snapX, fling.x.toDp().value, scope) else gestureX
                        val y = if (panYId != 0) snapping.settle(panYId, snapY, fling.y.toDp().value, scope) else gestureY
                        if (onDragEnd != 0) {
                            NativeUIBridge.sendTextChangeEvent(onDragEnd, node.id, "$x,$y")
                        }
                        gestureX = 0f
                        gestureY = 0f
                    }
                    when {
                        // One axis bound: detect on that axis only, so the
                        // other direction stays free for an enclosing
                        // scroll container.
                        panXId != 0 && panYId == 0 -> detectHorizontalDragGestures(
                            onDragStart = onStart,
                            onDragEnd = onEnd,
                            onDragCancel = onEnd,
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            onDrag(Offset(dragAmount, 0f), change.position - change.previousPosition)
                        }
                        panXId == 0 && panYId != 0 -> detectVerticalDragGestures(
                            onDragStart = onStart,
                            onDragEnd = onEnd,
                            onDragCancel = onEnd,
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            onDrag(Offset(0f, dragAmount), change.position - change.previousPosition)
                        }
                        else -> detectDragGestures(
                            onDragStart = onStart,
                            onDragEnd = onEnd,
                            onDragCancel = onEnd,
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            onDrag(dragAmount, dragAmount)
                        }
                    }
                }
                .pointerInput(pinchId, onPinchEnd, pinchMin, pinchMax, bounds) {
                    if (pinchId == 0 && onPinchEnd == 0) return@pointerInput
                    awaitEachGesture {
                        // The zoom factor is dimensionless — no px/dp
                        // conversion needed to match iOS. Compounds onto
                        // the running scale so repeated pinches continue
                        // from where the last one ended. Each step clamps
                        // into [pinch-min, pinch-max] (0 = unbounded) so
                        // the raw value can't run past the bound —
                        // reversals respond on the first frame.
                        var scale = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
                        var zoomed = false
                        var moved = false
                        awaitFirstDown(requireUnconsumed = false)
                        var pressed = true
                        while (pressed) {
                            val event = awaitPointerEvent()
                            val fingers = event.changes.count { it.pressed }
                            if (fingers >= 2) {
                                val zoom = event.calculateZoom()
                                val previous = scale
                                if (zoom != 1f) {
                                    zoomed = true
                                    scale *= zoom
                                    if (pinchMin > 0f && scale < pinchMin) scale = pinchMin
                                    if (pinchMax > 0f && scale > pinchMax) scale = pinchMax
                                    if (pinchId != 0) {
                                        SharedValueStore.set(pinchId, scale)
                                    }
                                }
                                if (bounds.enabled && pinchId != 0 && previous > 0f) {
                                    settle.pinching = true
                                    settle.stop()
                                    // Zoom around the fingers and move with them:
                                    // a point at c from the centre maps to
                                    // scale * p + pan, so keeping the point that
                                    // was under the fingers' last centre (c - its
                                    // move) under the new one gives
                                    // pan' = c - r * (c - move - pan).
                                    val applied = scale / previous
                                    val centroid = event.calculateCentroid(useCurrent = true)
                                    val move = event.calculatePan()
                                    if (centroid != Offset.Unspecified) {
                                        if (move != Offset.Zero) moved = true
                                        val cx = centroid.x.toDp().value - bounds.area.width / 2
                                        val cy = centroid.y.toDp().value - bounds.area.height / 2
                                        val lastX = cx - move.x.toDp().value
                                        val lastY = cy - move.y.toDp().value
                                        if (panXId != 0) {
                                            val pan = SharedValueStore.valueOf(panXId)
                                            SharedValueStore.set(panXId, cx - applied * (lastX - pan))
                                        }
                                        if (panYId != 0) {
                                            val pan = SharedValueStore.valueOf(panYId)
                                            SharedValueStore.set(panYId, cy - applied * (lastY - pan))
                                        }
                                    }
                                }
                            } else {
                                settle.pinching = false
                            }
                            pressed = event.changes.any { it.pressed }
                        }
                        settle.pinching = false
                        if ((zoomed || moved) && bounds.enabled) {
                            settle.into(bounds, scope, panXId, panYId, pinchId)
                        }
                        if (zoomed && onPinchEnd != 0) {
                            NativeUIBridge.sendSliderChangeEvent(onPinchEnd, node.id, scale)
                        }
                    }
                }
                .pointerInput(onSwipe, swipeFingers) {
                    if (onSwipe == 0) return@pointerInput
                    val threshold = 60.dp.toPx()
                    awaitEachGesture {
                        // Accumulate the centroid pan while exactly the
                        // required finger count is down; resolve to a
                        // direction on release. Firing only when the max
                        // simultaneous count matches keeps a 3-finger
                        // swipe from also triggering 1-finger handlers.
                        var maxPointers = 0
                        var pan = Offset.Zero
                        awaitFirstDown(requireUnconsumed = false)
                        var pressed = true
                        while (pressed) {
                            val event = awaitPointerEvent()
                            val count = event.changes.count { it.pressed }
                            if (count > maxPointers) maxPointers = count
                            if (count == swipeFingers) {
                                // Average raw position delta of the pressed
                                // pointers, ignoring consumption — a child
                                // ripple or an enclosing scroll container
                                // consuming the change must not zero out
                                // our accumulation (calculatePan would).
                                var delta = Offset.Zero
                                event.changes.forEach { change ->
                                    if (change.pressed) {
                                        delta += change.position - change.previousPosition
                                    }
                                }
                                pan += delta / count.toFloat()
                            }
                            pressed = event.changes.any { it.pressed }
                        }
                        if (maxPointers == swipeFingers) {
                            val direction = when {
                                abs(pan.x) >= abs(pan.y) && pan.x <= -threshold -> "left"
                                abs(pan.x) >= abs(pan.y) && pan.x >= threshold -> "right"
                                abs(pan.y) > abs(pan.x) && pan.y <= -threshold -> "up"
                                abs(pan.y) > abs(pan.x) && pan.y >= threshold -> "down"
                                else -> null
                            }
                            if (direction != null) {
                                NativeUIBridge.sendTextChangeEvent(onSwipe, node.id, direction)
                            }
                        }
                    }
                }
        ) {
            node.children.forEach { child ->
                NodeView(node = child)
            }
        }
    }

    /**
     * Keep a SharedValue binding in sync with what PHP published, during
     * composition. Unknown id → seed (don't stomp a live gesture value);
     * known id with a changed initial → PHP `setValue()` write-back.
     *
     * The holder is a plain object (not MutableState) — it's a memo of
     * the last-synced pair, not something composition should observe.
     */
    @Composable
    private fun SyncBinding(id: Int, initial: Float, springTo: ((Float) -> Unit)? = null) {
        if (id == 0) return
        val holder = remember { BindingHolder() }
        val prev = holder.pair
        if (prev?.first != id) {
            SharedValueStore.seed(id, initial)
        } else if (prev.second != initial) {
            // A snapping axis springs to a write-back, as it does on
            // release, so closing a revealed row from PHP slides it shut.
            if (springTo != null) springTo(initial) else SharedValueStore.set(id, initial)
        }
        holder.pair = id to initial
    }

    private class BindingHolder {
        var pair: Pair<Int, Float>? = null
    }

    /**
     * Where `bounded` lets the pan go, in dp. The content is the area, or
     * `content-ratio` fitted inside it (where `fit="contain"` draws an
     * image). Zoomed by `scale` about the centre, it may move until its
     * edges meet the area's: `(scale * content - area) / 2` each way, or
     * not at all on an axis it fits on, which keeps it centred there.
     */
    private data class PanBounds(val enabled: Boolean, val area: Size, val contentRatio: Float) {
        private val content: Size
            get() {
                if (contentRatio <= 0f || area.width <= 0f || area.height <= 0f) return area
                return if (area.width / area.height > contentRatio) {
                    Size(area.height * contentRatio, area.height)
                } else {
                    Size(area.width, area.width / contentRatio)
                }
            }

        fun limit(horizontal: Boolean, scale: Float): Float {
            val content = content
            return if (horizontal) {
                maxOf(0f, (scale * content.width - area.width) / 2)
            } else {
                maxOf(0f, (scale * content.height - area.height) / 2)
            }
        }

        /** Where a pan comes to rest: inside the limit. */
        fun settled(pan: Float, horizontal: Boolean, scale: Float): Float {
            if (!enabled) return pan
            val limit = limit(horizontal, scale)
            return pan.coerceIn(-limit, limit)
        }

        /**
         * What the finger's undamped pan shows: itself inside the limit,
         * and past it an overshoot that grows ever slower, never more than
         * the area's own size (iOS's rubber band, so both feel the same).
         */
        fun resisted(pan: Float, horizontal: Boolean, scale: Float): Float {
            val limit = limit(horizontal, scale)
            val overshoot = abs(pan) - limit
            if (overshoot <= 0f) return pan
            val extent = maxOf(1f, if (horizontal) area.width else area.height)
            val damped = (1 - 1 / (overshoot * 0.55f / extent + 1)) * extent
            return (if (pan < 0) -1 else 1) * (limit + damped)
        }
    }

    /**
     * What a bounded area's drag and pinch share: whether two fingers are
     * down (the pinch then moves the pan, not the drag), and the spring
     * back inside the bounds.
     */
    private class BoundedPan {
        var pinching = false

        private var job: Job? = null

        fun stop() {
            job?.cancel()
            job = null
        }

        /**
         * Moves each bound axis back inside the bounds at the current zoom,
         * and returns where they'll rest (x, y) for `on_drag_end`.
         */
        fun into(bounds: PanBounds, scope: CoroutineScope, panXId: Int, panYId: Int, pinchId: Int): Pair<Float, Float> {
            stop()
            val scale = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
            val moves = listOf(panXId to true, panYId to false)
                .filter { (id, _) -> id != 0 }
                .map { (id, horizontal) ->
                    val from = SharedValueStore.valueOf(id)
                    Triple(id, from, bounds.settled(from, horizontal, scale))
                }
            if (moves.any { (_, from, to) -> abs(to - from) > 0.01f }) {
                job = scope.launch {
                    animate(0f, 1f, animationSpec = tween(SettleMillis, easing = EaseOutCubic)) { progress, _ ->
                        moves.forEach { (id, from, to) -> SharedValueStore.set(id, from + (to - from) * progress) }
                    }
                }
            }
            val x = moves.firstOrNull { it.first == panXId }?.third ?: 0f
            val y = moves.firstOrNull { it.first == panYId }?.third ?: 0f
            return x to y
        }
    }

    /**
     * The points a snapping axis settles on (`pan-x-snap` / `pan-y-snap`),
     * lowest first. Empty when the axis doesn't snap. A data class, so a
     * pointerInput keyed on it restarts only when the points change.
     */
    private data class PanSnap(val points: List<Float>) {
        val isEmpty: Boolean get() = points.size < 2

        /** A third of the finger's movement past the outer points, so the edge reads as a stop. */
        fun resisted(raw: Float): Float {
            if (isEmpty) return raw
            val low = points.first()
            val high = points.last()
            return when {
                raw < low -> low - (low - raw) / 3f
                raw > high -> high + (raw - high) / 3f
                else -> raw
            }
        }

        /**
         * Where the pan rests: the point nearest where a tenth of a second
         * more of the fling would carry it, so a quick flick opens a row
         * the finger only moved part of the way.
         */
        fun target(current: Float, velocity: Float): Float {
            if (isEmpty) return current
            val projected = current + velocity * 0.1f
            return points.minByOrNull { abs(it - projected) } ?: current
        }

        companion object {
            fun parse(wire: String): PanSnap =
                PanSnap(wire.split(',').mapNotNull { it.trim().toFloatOrNull() }.distinct().sorted())
        }
    }

    /** Springs a snapping axis to where it rests, on release or a PHP write-back. */
    private class SnapPan {
        private var job: Job? = null

        fun stop() {
            job?.cancel()
            job = null
        }

        /** Settles [id] for [snap] after a fling of [velocity] dp/s, and returns where it rests. */
        fun settle(id: Int, snap: PanSnap, velocity: Float, scope: CoroutineScope): Float {
            val current = SharedValueStore.valueOf(id)
            val rest = snap.target(current, velocity)
            to(id, rest, scope)
            return rest
        }

        fun to(id: Int, target: Float, scope: CoroutineScope) {
            stop()
            val from = SharedValueStore.valueOf(id)
            if (abs(target - from) <= 0.01f) {
                SharedValueStore.set(id, target)
                return
            }
            job = scope.launch {
                animate(0f, 1f, animationSpec = tween(SettleMillis, easing = EaseOutCubic)) { progress, _ ->
                    SharedValueStore.set(id, from + (target - from) * progress)
                }
            }
        }
    }

    /** How long a pan takes to spring back inside its bounds or onto a snap point. */
    private const val SettleMillis = 350

    /** Fast away from where it was let go, slowing into place. */
    private val EaseOutCubic = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)
}
