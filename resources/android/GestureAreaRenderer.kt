package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.mobile.ui.nativerender.SharedValueStore
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
        SyncBinding(panXId, panXInitial)
        SyncBinding(panYId, panYInitial)
        SyncBinding(pinchId, pinchInitial)

        Box(
            modifier = modifier
                .nuiA11y(node.props.getString("a11y_label"), node.props.getString("a11y_hint"))
                .pointerInput(panXId, panYId, onDragEnd) {
                    if (panXId == 0 && panYId == 0 && onDragEnd == 0) return@pointerInput
                    // Raw gesture translation for this drag, in dp — what
                    // `on_drag_end` reports for an axis with no SharedValue.
                    var gestureX = 0f
                    var gestureY = 0f
                    // dragAmount is in raw pixels; convert to dp so the
                    // SharedValue stays density-independent and the
                    // user's `interpolate([0, 200], ...)` formulas match
                    // iOS point-based behavior. PointerInputScope
                    // extends Density, so .toDp() is in scope.
                    val onDrag: (Offset) -> Unit = { dragAmount ->
                        val dx = dragAmount.x.toDp().value
                        val dy = dragAmount.y.toDp().value
                        gestureX += dx
                        gestureY += dy
                        if (panXId != 0) {
                            SharedValueStore.set(panXId, SharedValueStore.valueOf(panXId) + dx)
                        }
                        if (panYId != 0) {
                            SharedValueStore.set(panYId, SharedValueStore.valueOf(panYId) + dy)
                        }
                    }
                    val onEnd: () -> Unit = {
                        if (onDragEnd != 0) {
                            val x = if (panXId != 0) SharedValueStore.valueOf(panXId) else gestureX
                            val y = if (panYId != 0) SharedValueStore.valueOf(panYId) else gestureY
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
                            onDragEnd = onEnd,
                            onDragCancel = onEnd,
                        ) { _, dragAmount -> onDrag(Offset(dragAmount, 0f)) }
                        panXId == 0 && panYId != 0 -> detectVerticalDragGestures(
                            onDragEnd = onEnd,
                            onDragCancel = onEnd,
                        ) { _, dragAmount -> onDrag(Offset(0f, dragAmount)) }
                        else -> detectDragGestures(
                            onDragEnd = onEnd,
                            onDragCancel = onEnd,
                        ) { _, dragAmount -> onDrag(dragAmount) }
                    }
                }
                .pointerInput(pinchId, onPinchEnd, pinchMin, pinchMax) {
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
                        awaitFirstDown(requireUnconsumed = false)
                        var pressed = true
                        while (pressed) {
                            val event = awaitPointerEvent()
                            if (event.changes.count { it.pressed } >= 2) {
                                val zoom = event.calculateZoom()
                                if (zoom != 1f) {
                                    zoomed = true
                                    scale *= zoom
                                    if (pinchMin > 0f && scale < pinchMin) scale = pinchMin
                                    if (pinchMax > 0f && scale > pinchMax) scale = pinchMax
                                    if (pinchId != 0) {
                                        SharedValueStore.set(pinchId, scale)
                                    }
                                }
                            }
                            pressed = event.changes.any { it.pressed }
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
    private fun SyncBinding(id: Int, initial: Float) {
        if (id == 0) return
        val holder = remember { BindingHolder() }
        val prev = holder.pair
        if (prev?.first != id) {
            SharedValueStore.seed(id, initial)
        } else if (prev.second != initial) {
            SharedValueStore.set(id, initial)
        }
        holder.pair = id to initial
    }

    private class BindingHolder {
        var pair: Pair<Int, Float>? = null
    }
}
