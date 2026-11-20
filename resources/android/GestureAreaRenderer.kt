package com.nativephp.plugins.native_ui.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitHorizontalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.awaitVerticalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.gestures.verticalDrag
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.positionChangeIgnoreConsumed
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
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
 *   - `pan-x-trigger` /
 *     `pan-y-trigger`  (float) — how far from rest a pull on a bound
 *                                axis goes to trigger, its sign the way
 *                                it goes (see PanTrigger): the drag only
 *                                starts that way, follows the finger to
 *                                the point with resistance past it, plays
 *                                a light haptic each time it goes out
 *                                past it, and springs back to rest on
 *                                release. Takes the place of snap points;
 *                                one-axis pans only.
 *   - `on_trigger`     (int)   — callback fired when a pull is let go
 *                                past its trigger point (rides the PRESS
 *                                format, which carries nothing).
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
 *                                TEXT_CHANGE format). Once it passes
 *                                touch slop the drag is the swipe's,
 *                                so a pressable inside or around the
 *                                area doesn't also fire.
 *   - `swipe-fingers`  (int)   — touches required for the swipe
 *                                (default 1; Jump-style is 3).
 *   - `bounded`        (bool)  — keep the zoomed content inside the
 *                                area (see PanBounds): pan stops at the
 *                                content's edges, an axis the content
 *                                fits on stays centred, a drag past an
 *                                edge meets resistance, and the content
 *                                springs back into place on release. A
 *                                pinch zooms around the fingers and a
 *                                double tap aims at the tapped point,
 *                                both moving the bound pans. A
 *                                one-finger drag is the area's only
 *                                while the content has room to move on
 *                                a bound axis (see MinRoomDp) at the
 *                                zoom it has when the drag starts.
 *                                Content that fits leaves the drag to
 *                                whatever is around the area (a pager,
 *                                a drag to close, a scroll container),
 *                                so a photo at whole size pages and
 *                                closes with its pans bound. Two
 *                                fingers down are a pinch, and the
 *                                area's either way.
 *   - `content-ratio`  (float) — the content's width over height,
 *                                fitted inside the area, for `bounded`
 *                                (0 = the content fills the area).
 *   - `double-tap-zoom` (float)— the scale a double tap zooms the pinch
 *                                to from 1, bringing the tapped point to
 *                                the middle as far as `bounded` allows; a
 *                                double tap past 1 goes back to 1.
 *                                Animated, then `on_pinch_end` reports
 *                                the new scale.
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
        val doubleTapZoom = node.props.getFloat("double-tap-zoom", 0f)

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
        val triggerX = PanTrigger(node.props.getFloat("pan-x-trigger", 0f))
        val triggerY = PanTrigger(node.props.getFloat("pan-y-trigger", 0f))
        val onTrigger = node.props.getInt("on_trigger", 0)
        val haptics = LocalHapticFeedback.current
        // Where a trigger axis rests, as PHP last published it. Read when a
        // pull moves and ends rather than keying the gesture on it, so a
        // write-back doesn't cut a pull short.
        val restX by rememberUpdatedState(panXInitial)
        val restY by rememberUpdatedState(panYInitial)

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
        SyncBinding(panXId, panXInitial, if (snapX.isEmpty && triggerX.isEmpty) null else { value -> snapping.to(panXId, value, scope) })
        SyncBinding(panYId, panYInitial, if (snapY.isEmpty && triggerY.isEmpty) null else { value -> snapping.to(panYId, value, scope) })
        SyncBinding(pinchId, pinchInitial)

        Box(
            modifier = modifier
                .nuiA11y(node.props.getString("a11y_label"), node.props.getString("a11y_hint"))
                .onSizeChanged { size ->
                    areaSize = with(density) { Size(size.width.toDp().value, size.height.toDp().value) }
                }
                .pointerInput(panXId, panYId, pinchId, onDragEnd, bounds, snapX, snapY, triggerX, triggerY, onTrigger) {
                    if (panXId == 0 && panYId == 0 && onDragEnd == 0) return@pointerInput
                    if (bounds.enabled) {
                        // The undamped pan the finger asked for, and what was
                        // last written, per axis: a pinch or the spring back
                        // moving the pan between steps is picked up again.
                        var rawX = 0f
                        var rawY = 0f
                        var writtenX = 0f
                        var writtenY = 0f
                        val step: (Offset) -> Unit = step@{ dragAmount ->
                            // Two fingers down: the pinch moves the pan with
                            // both of them, so the first finger alone mustn't.
                            if (settle.pinching) return@step
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
                        // Whether the content has room to move on a bound axis
                        // at the zoom it has right now. The scale is read here,
                        // not keyed on, so a pinch or a double tap that has just
                        // zoomed in counts on the very next drag. While a double
                        // tap's zoom animates there must be room both now and
                        // where the zoom is heading, so the smaller scale counts.
                        // A drag as it zooms back out is left to the pager, and
                        // the zoom finishes and reports, rather than the drag
                        // stopping it part way and keeping the content zoomed. A
                        // drag in the first frames of a zoom in pages too, rather
                        // than freezing the content barely zoomed; once the zoom
                        // in has real room the drag takes it and stops it there.
                        val roomToMove = {
                            val live = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
                            val scale = minOf(live, settle.zoomingTo ?: live)
                            (panXId != 0 && bounds.limit(horizontal = true, scale = scale) > MinRoomDp) ||
                                (panYId != 0 && bounds.limit(horizontal = false, scale = scale) > MinRoomDp)
                        }
                        val slop = viewConfiguration.touchSlop
                        awaitEachGesture {
                            // Content that fits the area has nowhere to pan, so a
                            // drag over it is left unconsumed for whatever is
                            // around the area: a pager pages, a drag to close
                            // closes, a scroll container scrolls, as if no pan
                            // were bound. With room to move the drag is the
                            // area's, and consuming it keeps the pager and the
                            // drag to close still. Two fingers down are a pinch,
                            // which is the area's too: a drag to close follows
                            // the first finger alone, and would move while a
                            // pinch in at whole size zooms nothing.
                            //
                            // Room is judged once, when the finger first passes
                            // touch slop. Once a parent has consumed the drag it
                            // keeps it, however the zoom changes after, until a
                            // second finger comes down and makes it a pinch.
                            // Compose's awaitTouchSlopOrCancellation can't do
                            // this: left unconsumed it starts the slop over, and
                            // a fast drag that passes slop again on its next
                            // event is judged again before the parent sees it.
                            var pointer = awaitFirstDown(requireUnconsumed = false).id
                            var travel = Offset.Zero
                            var parentHasIt = false
                            var overSlop = Offset.Zero
                            var start: PointerInputChange? = null
                            while (start == null) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == pointer } ?: return@awaitEachGesture
                                if (change.changedToUpIgnoreConsumed()) {
                                    pointer = event.changes.firstOrNull { it.pressed }?.id ?: return@awaitEachGesture
                                    continue
                                }
                                val pinching = pinchId != 0 && event.changes.count { it.pressed } >= 2
                                if (parentHasIt) {
                                    if (pinching) start = change
                                } else {
                                    // Something inside the area took it first.
                                    if (change.isConsumed) return@awaitEachGesture
                                    travel += change.positionChangeIgnoreConsumed()
                                    val distance = travel.getDistance()
                                    if (distance >= slop) {
                                        if (pinching || roomToMove()) {
                                            start = change
                                            overSlop = travel * ((distance - slop) / distance)
                                        } else {
                                            travel = Offset.Zero
                                        }
                                    }
                                }
                                if (start == null) {
                                    // Every handler has had this event by the
                                    // Final pass: a parent that took it has it.
                                    awaitPointerEvent(PointerEventPass.Final)
                                    if (change.isConsumed) parentHasIt = true
                                }
                            }
                            start.consume()
                            step(overSlop)
                            val lifted = drag(start.id) { change ->
                                step(change.positionChange())
                                change.consume()
                            }
                            val (x, y) = settle.into(bounds, scope, panXId, panYId, pinchId)
                            if (lifted && onDragEnd != 0) {
                                NativeUIBridge.sendTextChangeEvent(onDragEnd, node.id, "$x,$y")
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
                    // A one-axis pan's trigger, if it has one, and whether the
                    // pull is past its point.
                    val pullsX = panXId != 0 && panYId == 0 && !triggerX.isEmpty
                    val pullsY = panYId != 0 && panXId == 0 && !triggerY.isEmpty
                    var past = false
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
                        // A pull is measured from rest, so one caught on its way
                        // back carries on from where it is.
                        if (panXId != 0) {
                            SharedValueStore.set(panXId, when {
                                pullsX -> restX + triggerX.resisted(rawX - restX)
                                snapX.isEmpty -> SharedValueStore.valueOf(panXId) + bound.x.toDp().value
                                else -> snapX.resisted(rawX)
                            })
                        }
                        if (panYId != 0) {
                            SharedValueStore.set(panYId, when {
                                pullsY -> restY + triggerY.resisted(rawY - restY)
                                snapY.isEmpty -> SharedValueStore.valueOf(panYId) + bound.y.toDp().value
                                else -> snapY.resisted(rawY)
                            })
                        }
                        if (pullsX || pullsY) {
                            val now = if (pullsX) triggerX.passed(SharedValueStore.valueOf(panXId) - restX) else triggerY.passed(SharedValueStore.valueOf(panYId) - restY)
                            if (now && !past) haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
                            past = now
                        }
                    }
                    // Whether the finger lifted, rather than the drag being cancelled.
                    val onEnd: (Boolean) -> Unit = { lifted ->
                        // px per second, into dp like the pan itself. A pull
                        // always goes back to rest.
                        val fling = velocity.calculateVelocity()
                        val x = when {
                            panXId == 0 -> gestureX
                            pullsX -> restX.also { snapping.to(panXId, it, scope) }
                            else -> snapping.settle(panXId, snapX, fling.x.toDp().value, scope)
                        }
                        val y = when {
                            panYId == 0 -> gestureY
                            pullsY -> restY.also { snapping.to(panYId, it, scope) }
                            else -> snapping.settle(panYId, snapY, fling.y.toDp().value, scope)
                        }
                        if (past && lifted && onTrigger != 0) {
                            NativeUIBridge.sendPressEvent(onTrigger, node.id)
                        }
                        past = false
                        if (onDragEnd != 0) {
                            NativeUIBridge.sendTextChangeEvent(onDragEnd, node.id, "$x,$y")
                        }
                        gestureX = 0f
                        gestureY = 0f
                    }
                    when {
                        // A pull: the same as below, but only a drag its own way.
                        pullsX || pullsY -> detectPull(
                            horizontal = pullsX,
                            way = if (pullsX) triggerX.distance else triggerY.distance,
                            onStart = onStart,
                            onEnd = onEnd,
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            val raw = change.position - change.previousPosition
                            onDrag(if (pullsX) Offset(dragAmount, 0f) else Offset(0f, dragAmount), raw)
                        }
                        // One axis bound: detect on that axis only, so the
                        // other direction stays free for an enclosing
                        // scroll container.
                        panXId != 0 && panYId == 0 -> detectHorizontalDragGestures(
                            onDragStart = onStart,
                            onDragEnd = { onEnd(true) },
                            onDragCancel = { onEnd(false) },
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            onDrag(Offset(dragAmount, 0f), change.position - change.previousPosition)
                        }
                        panXId == 0 && panYId != 0 -> detectVerticalDragGestures(
                            onDragStart = onStart,
                            onDragEnd = { onEnd(true) },
                            onDragCancel = { onEnd(false) },
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            onDrag(Offset(0f, dragAmount), change.position - change.previousPosition)
                        }
                        else -> detectDragGestures(
                            onDragStart = onStart,
                            onDragEnd = { onEnd(true) },
                            onDragCancel = { onEnd(false) },
                        ) { change, dragAmount ->
                            velocity.addPosition(change.uptimeMillis, change.position)
                            onDrag(dragAmount, dragAmount)
                        }
                    }
                }
                .pointerInput(pinchId, onPinchEnd, pinchMin, pinchMax, bounds, panXId, panYId) {
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
                                // Carry on from the store each step, as iOS
                                // does, not from where it was when the gesture
                                // began: a double tap's zoom animates after its
                                // second tap lifts, so a pinch straight after it
                                // would otherwise start from the old scale.
                                if (pinchId != 0) scale = SharedValueStore.valueOf(pinchId)
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
                .pointerInput(doubleTapZoom, pinchId, pinchMin, pinchMax, bounds, panXId, panYId, onPinchEnd) {
                    if (doubleTapZoom <= 1f || pinchId == 0) return@pointerInput
                    // Two taps close together in time and place. Nothing is
                    // consumed, so a pinch, a pan, a pager or a drag to close
                    // around the area work as before; a tap that moves past
                    // touch slop isn't a tap, and leaves the drag to them.
                    awaitEachGesture {
                        val first = awaitTap(awaitFirstDown(requireUnconsumed = false)) ?: return@awaitEachGesture
                        val second = withTimeoutOrNull(viewConfiguration.doubleTapTimeoutMillis) {
                            awaitFirstDown(requireUnconsumed = false)
                        } ?: return@awaitEachGesture
                        if ((second.position - first).getDistance() > viewConfiguration.touchSlop * 4) return@awaitEachGesture
                        val at = awaitTap(second) ?: return@awaitEachGesture
                        // Zoom as on iOS: from 1, to the double-tap zoom with
                        // the tapped point brought to the middle as far as the
                        // bounds let the pan go; past 1, back to 1 and the
                        // middle. A point at c from the middle shows the
                        // content point (c - pan) / scale, which sits in the
                        // middle once the pan is -zoom times it.
                        val scale = SharedValueStore.valueOf(pinchId)
                        val panX = if (panXId != 0) SharedValueStore.valueOf(panXId) else 0f
                        val panY = if (panYId != 0) SharedValueStore.valueOf(panYId) else 0f
                        val zoomedIn = scale > 1.01f
                        var target = if (zoomedIn) 1f else doubleTapZoom
                        if (pinchMin > 0f) target = maxOf(pinchMin, target)
                        if (pinchMax > 0f) target = minOf(pinchMax, target)
                        var toX = 0f
                        var toY = 0f
                        if (!zoomedIn && scale > 0f) {
                            val pointX = (at.x.toDp().value - bounds.area.width / 2 - panX) / scale
                            val pointY = (at.y.toDp().value - bounds.area.height / 2 - panY) / scale
                            toX = bounds.settled(-target * pointX, horizontal = true, scale = target)
                            toY = bounds.settled(-target * pointY, horizontal = false, scale = target)
                        }
                        val zoomTo = target
                        settle.zoom(scope, zoomTo, listOf(Triple(pinchId, scale, zoomTo), Triple(panXId, panX, toX), Triple(panYId, panY, toY))) {
                            if (onPinchEnd != 0) {
                                NativeUIBridge.sendSliderChangeEvent(onPinchEnd, node.id, zoomTo)
                            }
                        }
                    }
                }
                .pointerInput(onSwipe, swipeFingers) {
                    if (onSwipe == 0) return@pointerInput
                    val threshold = 60.dp.toPx()
                    val slop = viewConfiguration.touchSlop
                    awaitEachGesture {
                        // Accumulate the centroid pan while exactly the
                        // required finger count is down; resolve to a
                        // direction on release. Firing only when the max
                        // simultaneous count matches keeps a 3-finger
                        // swipe from also triggering 1-finger handlers.
                        var maxPointers = 0
                        var pan = Offset.Zero
                        // Whether the pan has passed touch slop yet, and
                        // whether this swipe then took the drag for itself.
                        var pastSlop = false
                        var claimed = false
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
                            // Past touch slop the gesture is a swipe, not a
                            // tap, as it is on iOS where a tap fails once the
                            // touch moves. Compose's clickable only cancels
                            // when the pointer leaves it or a change is
                            // consumed, so consume the rest of the gesture: a
                            // pressable inside the area or around it then
                            // doesn't also fire on release. Leave the drag to
                            // anything that took it first in the Main pass,
                            // such as an enclosing scroll container or the
                            // area's own pan, so a vertical drag through a
                            // list of swipeable rows still scrolls the list.
                            if (claimed) {
                                if (maxPointers == swipeFingers) {
                                    event.changes.forEach { it.consume() }
                                }
                            } else if (!pastSlop && count == swipeFingers &&
                                maxOf(abs(pan.x), abs(pan.y)) >= slop
                            ) {
                                pastSlop = true
                                // The Final pass of this same event: every
                                // handler has had its Main pass by now, and a
                                // pressable inside checks this pass for a
                                // consumed change.
                                val final = awaitPointerEvent(PointerEventPass.Final)
                                if (final.changes.none { it.isConsumed }) {
                                    claimed = true
                                    final.changes.forEach { it.consume() }
                                }
                            }
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
     * Follows a press to its release and says where it lifted, or null when
     * it wasn't a tap: it moved past touch slop, or a second finger came down.
     */
    private suspend fun AwaitPointerEventScope.awaitTap(down: PointerInputChange): Offset? {
        val slop = viewConfiguration.touchSlop
        while (true) {
            val event = awaitPointerEvent()
            if (event.changes.count { it.pressed } > 1) return null
            val change = event.changes.firstOrNull { it.id == down.id } ?: return null
            if ((change.position - down.position).getDistance() > slop) return null
            if (!change.pressed) return change.position
        }
    }

    /**
     * A one-axis drag that only starts once the finger passes touch slop
     * the way of [way]'s sign, as a trigger's pull goes, and otherwise
     * runs like detectHorizontalDragGestures. A drag the other way isn't
     * taken, so whatever else wants it can have it.
     */
    private suspend fun PointerInputScope.detectPull(
        horizontal: Boolean,
        way: Float,
        onStart: (Offset) -> Unit,
        onEnd: (Boolean) -> Unit,
        onDrag: (PointerInputChange, Float) -> Unit,
    ) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            var overSlop = 0f
            // Left unconsumed, a drag the other way past slop starts the
            // slop over from there rather than taking the gesture.
            val pulls: (PointerInputChange, Float) -> Unit = { change, over ->
                if (over * way > 0f) {
                    change.consume()
                    overSlop = over
                }
            }
            val start = if (horizontal) {
                awaitHorizontalTouchSlopOrCancellation(down.id, pulls)
            } else {
                awaitVerticalTouchSlopOrCancellation(down.id, pulls)
            } ?: return@awaitEachGesture
            onStart(start.position)
            onDrag(start, overSlop)
            val lifted = if (horizontal) {
                horizontalDrag(start.id) { change ->
                    onDrag(change, change.positionChange().x)
                    change.consume()
                }
            } else {
                verticalDrag(start.id) { change ->
                    onDrag(change, change.positionChange().y)
                    change.consume()
                }
            }
            onEnd(lifted)
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

        /**
         * The scale a double tap's zoom is heading to while it animates, else
         * null. A drag judges room by it, so one that starts as the zoom goes
         * back to 1 is the pager's, not the half-zoomed content's.
         */
        var zoomingTo: Float? = null
            private set

        private var job: Job? = null

        fun stop() {
            job?.cancel()
            job = null
            zoomingTo = null
        }

        /**
         * Animates a double tap's zoom to [scale]: each (id, from, to) in
         * step, then [landed]. A pinch or a drag stopping it first means it
         * never lands.
         */
        fun zoom(scope: CoroutineScope, scale: Float, moves: List<Triple<Int, Float, Float>>, landed: () -> Unit) {
            stop()
            val moving = moves.filter { (id, from, to) -> id != 0 && abs(to - from) > 0.01f }
            if (moving.isEmpty()) {
                landed()
                return
            }
            zoomingTo = scale
            job = scope.launch {
                animate(0f, 1f, animationSpec = tween(SettleMillis, easing = EaseOutCubic)) { progress, _ ->
                    moving.forEach { (id, from, to) -> SharedValueStore.set(id, from + (to - from) * progress) }
                }
                zoomingTo = null
                landed()
            }
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

    /**
     * A pull that acts when let go far enough (`pan-x-trigger` /
     * `pan-y-trigger`): how far from rest it goes to trigger, its sign the
     * way it goes. Zero when the axis doesn't trigger. A data class, so a
     * pointerInput keyed on it restarts only when the distance changes.
     */
    private data class PanTrigger(val distance: Float) {
        val isEmpty: Boolean get() = distance == 0f

        /**
         * What the pull shows for the finger's offset from rest: nothing
         * the other way, the finger itself as far as the point, and past it
         * a third of the finger's movement, as past the outer snap points.
         */
        fun resisted(offset: Float): Float {
            val sign = if (distance < 0f) -1f else 1f
            val reach = abs(distance)
            val toward = offset * sign
            val shown = when {
                toward <= 0f -> 0f
                toward <= reach -> toward
                else -> reach + (toward - reach) / 3f
            }
            return shown * sign
        }

        /** Whether a pull this far from rest is at the point or past it. */
        fun passed(offset: Float): Boolean =
            !isEmpty && if (distance < 0f) offset <= distance else offset >= distance
    }

    /** Springs a snapping or trigger axis to where it rests, on release or a PHP write-back. */
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

    /** Room to pan under this many dp counts as none, so a pinch let go just past 1x (about 1.01x on a phone) doesn't keep drags from the pager. */
    private const val MinRoomDp = 2f

    /** How long a pan takes to spring back inside its bounds or onto a snap point. */
    private const val SettleMillis = 350

    /** Fast away from where it was let go, slowing into place. */
    private val EaseOutCubic = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)
}
