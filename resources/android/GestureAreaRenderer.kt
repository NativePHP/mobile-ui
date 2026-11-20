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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollDispatcher
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.positionChangeIgnoreConsumed
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.mobile.ui.nativerender.SharedValueStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.exp

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
 *                                area (see PanBounds), and clip it to
 *                                the area: pan stops at the content's
 *                                edges, an axis the content fits on
 *                                stays centred, and let go the content
 *                                glides on at the finger's speed and
 *                                bounces off an edge (see PanGlide). A
 *                                pinch zooms around the fingers and a
 *                                double tap aims at the tapped point,
 *                                both moving the bound pans. A
 *                                one-finger drag is the area's only
 *                                while the content is zoomed and has
 *                                room to move the way the finger is
 *                                going (see MinRoomDp) at the zoom it
 *                                has when the drag starts. At whole
 *                                size the drag goes to whatever is
 *                                around the area (a pager, a drag to
 *                                close, a scroll container), so a photo
 *                                pages and closes with its pans bound.
 *                                Zoomed, at an edge the finger is
 *                                heading for, it goes to a scroll
 *                                container but not a drag to close.
 *                                A drag that reaches an edge goes on
 *                                to the scroll container around the
 *                                area through nested scrolling (a
 *                                pager pulls on to the next page), or
 *                                meets resistance with none. Two
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
/**
 * The axes the gesture areas around a node pan on (`pan-x-id` /
 * `pan-y-id` on an area that isn't `bounded`).
 */
internal data class GesturePans(val x: Boolean = false, val y: Boolean = false)

internal val LocalGesturePans = compositionLocalOf { GesturePans() }

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
        // The axes a gesture area around this one pans on, such as a drag
        // to close, which zoomed content keeps its drags from.
        val around = LocalGesturePans.current

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

        // `bounded` only: the drag past the content's edges goes to
        // whatever scrolls around the area, through nested scrolling.
        val dispatcher = remember { NestedScrollDispatcher() }
        val noScroll = remember { object : NestedScrollConnection {} }

        Box(
            modifier = modifier
                .nuiA11y(node.props.getString("a11y_label"), node.props.getString("a11y_hint"))
                // Zoomed content stays inside the area, so it doesn't draw
                // over what's around it or onto the next page as it slides in.
                .then(if (bounds.enabled) Modifier.clipToBounds() else Modifier)
                .onSizeChanged { size ->
                    areaSize = with(density) { Size(size.width.toDp().value, size.height.toDp().value) }
                }
                .nestedScroll(noScroll, dispatcher)
                .pointerInput(panXId, panYId, pinchId, onDragEnd, bounds, snapX, snapY, triggerX, triggerY, onTrigger, around) {
                    if (panXId == 0 && panYId == 0 && onDragEnd == 0) return@pointerInput
                    if (bounds.enabled) {
                        // The undamped pan the finger asked for, and what was
                        // last written, per axis: a pinch or the spring back
                        // moving the pan between steps is picked up again.
                        var rawX = 0f
                        var rawY = 0f
                        var writtenX = 0f
                        var writtenY = 0f
                        // How far this drag has moved whatever is around the
                        // area (a pager), in px: its share of the drag past
                        // the content's edges, less what it gave back.
                        var handed = Offset.Zero
                        val velocity = VelocityTracker()
                        val step: (Offset) -> Unit = step@{ dragAmount ->
                            // Two fingers down: the pinch moves the pan with
                            // both of them, so the first finger alone mustn't.
                            if (settle.pinching) return@step
                            settle.stop()
                            val scale = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
                            val drag = Offset(if (panXId != 0) dragAmount.x else 0f, if (panYId != 0) dragAmount.y else 0f)
                            // What the drag handed on takes its share back
                            // first, so a pager pulled part way to the next
                            // page goes back before the content pans again.
                            // Only as far as it was handed: Compose's pager
                            // would take the whole step and carry on past its
                            // own page towards the one before.
                            val owed = Offset(owed(drag.x, handed.x), owed(drag.y, handed.y))
                            val back = if (owed == Offset.Zero) Offset.Zero else dispatcher.dispatchPreScroll(owed, NestedScrollSource.UserInput)
                            handed += back
                            val left = drag - back
                            // The content moves as far as its edge; the rest
                            // goes to whatever is around the area, so a zoomed
                            // photo dragged on past its edge pulls the pager
                            // on to the next one. What that leaves stretches
                            // the content past the edge.
                            if (panXId != 0) {
                                val current = SharedValueStore.valueOf(panXId)
                                if (current != writtenX) rawX = bounds.unresisted(current, horizontal = true, scale = scale)
                            }
                            if (panYId != 0) {
                                val current = SharedValueStore.valueOf(panYId)
                                if (current != writtenY) rawY = bounds.unresisted(current, horizontal = false, scale = scale)
                            }
                            val freeX = bounds.free(rawX, left.x.toDp().value, horizontal = true, scale = scale)
                            val freeY = bounds.free(rawY, left.y.toDp().value, horizontal = false, scale = scale)
                            val free = Offset(freeX.dp.toPx(), freeY.dp.toPx())
                            val past = dispatcher.dispatchPostScroll(free, left - free, NestedScrollSource.UserInput)
                            handed += past
                            val stretch = left - free - past
                            if (panXId != 0) {
                                rawX += freeX + stretch.x.toDp().value
                                writtenX = bounds.resisted(rawX, horizontal = true, scale = scale)
                                SharedValueStore.set(panXId, writtenX)
                            }
                            if (panYId != 0) {
                                rawY += freeY + stretch.y.toDp().value
                                writtenY = bounds.resisted(rawY, horizontal = false, scale = scale)
                                SharedValueStore.set(panYId, writtenY)
                            }
                        }
                        // Whether the drag is the content's. At whole size,
                        // with no room to move on a bound axis (see
                        // MinRoomDp) at the zoom it has right now, it isn't.
                        // Zoomed, it is while the content can move the way the
                        // finger is going: on an axis the drag runs within 60
                        // degrees of, more than MinRoomDp from its edge that
                        // way. So a zoomed photo at its right edge leaves a
                        // swipe left to the pager. It keeps a drag it can't
                        // use from a gesture area's pan around it, though: a
                        // drag to close only gets drags while the content is
                        // at whole size, so panning a zoomed photo up to its
                        // edge doesn't start closing the viewer.
                        //
                        // The scale is read here, not keyed on, so a pinch or
                        // a double tap that has just zoomed in counts on the
                        // very next drag. While a double tap's zoom animates
                        // there must be room both now and where the zoom is
                        // heading, so the smaller scale counts. A drag as it
                        // zooms back out is left to the pager, and the zoom
                        // finishes and reports, rather than the drag stopping
                        // it part way and keeping the content zoomed. A drag
                        // in the first frames of a zoom in pages too, rather
                        // than freezing the content barely zoomed; once the
                        // zoom in has real room the drag takes it and stops
                        // it there.
                        val roomToMove: (Offset) -> Boolean = room@{ travel ->
                            val live = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
                            val scale = minOf(live, settle.zoomingTo ?: live)
                            val zoomed = (panXId != 0 && bounds.limit(horizontal = true, scale = scale) > MinRoomDp) ||
                                (panYId != 0 && bounds.limit(horizontal = false, scale = scale) > MinRoomDp)
                            if (!zoomed) return@room false
                            val distance = maxOf(travel.getDistance(), 0.0001f)
                            val alongX = panXId != 0 && abs(travel.x) / distance >= 0.5f
                            val alongY = panYId != 0 && abs(travel.y) / distance >= 0.5f
                            (alongX && bounds.room(SharedValueStore.valueOf(panXId), travel.x, horizontal = true, scale = scale) > MinRoomDp) ||
                                (alongY && bounds.room(SharedValueStore.valueOf(panYId), travel.y, horizontal = false, scale = scale) > MinRoomDp) ||
                                (alongX && around.x) ||
                                (alongY && around.y)
                        }
                        val slop = viewConfiguration.touchSlop
                        awaitEachGesture {
                            // Content that can't move the way the finger goes
                            // leaves the drag unconsumed for whatever is around
                            // the area: a pager pages, a drag to close closes,
                            // a scroll container scrolls, as if no pan were
                            // bound. So a photo at whole size pages and closes,
                            // and a zoomed one at its right edge pages on a
                            // swipe left. With room to move the drag is the
                            // area's, and consuming it keeps the pager and the
                            // drag to close still until the content reaches an
                            // edge. Two fingers down are a pinch, which is the
                            // area's too: a drag to close follows the first
                            // finger alone, and would move while a pinch in at
                            // whole size zooms nothing.
                            //
                            // Room is judged once, when the finger first passes
                            // touch slop. Once a parent has consumed the drag it
                            // keeps it, however the zoom changes after, until a
                            // second finger comes down and makes it a pinch.
                            // Compose's awaitTouchSlopOrCancellation can't do
                            // this: left unconsumed it starts the slop over, and
                            // a fast drag that passes slop again on its next
                            // event is judged again before the parent sees it.
                            val down = awaitFirstDown(requireUnconsumed = false)
                            // A touch stops the content gliding, as a scroll
                            // view's does.
                            settle.catch()
                            var pointer = down.id
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
                                        if (pinching || roomToMove(travel)) {
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
                            handed = Offset.Zero
                            velocity.resetTracking()
                            velocity.addPointerInputChange(start)
                            var tracked = start.id
                            var movedAt = start.uptimeMillis
                            step(overSlop)
                            val lifted = drag(start.id) { change ->
                                // Only one finger's movement counts towards the
                                // fling: none while a pinch has two down, and
                                // the one left over afresh.
                                if (change.id != tracked || settle.pinching) {
                                    velocity.resetTracking()
                                    tracked = change.id
                                }
                                velocity.addPointerInputChange(change)
                                movedAt = change.uptimeMillis
                                step(change.positionChange())
                                change.consume()
                            }
                            // A finger held still before it lifts sends nothing
                            // while it's still, so the tracker only has the
                            // speed it last moved at. Still for longer than a
                            // move takes to come in, it leaves the content
                            // where it is.
                            val up = currentEvent.changes.firstOrNull { it.id == tracked }
                            val still = up == null || up.uptimeMillis - movedAt > StillMillis
                            val fling = if (lifted && !still) velocity.calculateVelocity() else Velocity.Zero
                            // Whatever the drag pulled along settles with the
                            // fling on its axis, so a flick past a zoomed
                            // photo's edge pages, and the content stays at
                            // that edge. On the other axes the content glides.
                            val handedX = abs(handed.x) > 0.5f
                            val handedY = abs(handed.y) > 0.5f
                            if (handedX || handedY) {
                                val onward = Velocity(if (handedX) fling.x else 0f, if (handedY) fling.y else 0f)
                                scope.launch {
                                    val taken = dispatcher.dispatchPreFling(onward)
                                    dispatcher.dispatchPostFling(taken, onward - taken)
                                }
                            }
                            val glide = Offset(
                                if (handedX) 0f else fling.x.toDp().value,
                                if (handedY) 0f else fling.y.toDp().value,
                            )
                            val (x, y) = settle.glide(bounds, scope, panXId, panYId, pinchId, glide)
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
            // A bounded area inside this one keeps its zoomed drags from
            // this one's pans.
            val pans = if (bounds.enabled) around else GesturePans(x = around.x || panXId != 0, y = around.y || panYId != 0)
            CompositionLocalProvider(LocalGesturePans provides pans) {
                node.children.forEach { child ->
                    NodeView(node = child)
                }
            }
        }
    }

    /**
     * How much of a drag step [by] goes back to whatever the drag has
     * [handed] that much to: none unless it's the other way, and no more
     * than was handed.
     */
    private fun owed(by: Float, handed: Float): Float = when {
        by > 0f && handed < 0f -> minOf(by, -handed)
        by < 0f && handed > 0f -> maxOf(by, -handed)
        else -> 0f
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

        /**
         * The undamped pan that `resisted` shows as [shown], so a drag that
         * picks the content up past an edge (where a pinch left it, or part
         * way through the spring back) carries on from there instead of
         * jumping in. The damped overshoot never reaches the area's size, so
         * one at or past it starts from just inside.
         */
        fun unresisted(shown: Float, horizontal: Boolean, scale: Float): Float {
            val limit = limit(horizontal, scale)
            val overshoot = abs(shown) - limit
            if (overshoot <= 0f) return shown
            val extent = maxOf(1f, if (horizontal) area.width else area.height)
            val damped = minOf(overshoot, extent * 0.99f)
            val raw = damped * extent / ((extent - damped) * 0.55f)
            return (if (shown < 0) -1 else 1) * (limit + raw)
        }

        /** How far a pan at [pan] can go the way of [way]'s sign before it meets the edge. */
        fun room(pan: Float, way: Float, horizontal: Boolean, scale: Float): Float {
            val limit = limit(horizontal, scale)
            return when {
                way > 0f -> limit - pan
                way < 0f -> pan + limit
                else -> 0f
            }
        }

        /**
         * How much of a step [by] moves the undamped pan [raw] without
         * taking it further past an edge. The rest is past the edge.
         */
        fun free(raw: Float, by: Float, horizontal: Boolean, scale: Float): Float {
            val limit = limit(horizontal, scale)
            return when {
                by > 0f -> minOf(by, maxOf(0f, limit - raw))
                by < 0f -> maxOf(by, minOf(0f, -limit - raw))
                else -> 0f
            }
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

        /** The axes of the content gliding after a drag, while it does. */
        private var gliding: List<PanGlide> = emptyList()

        fun stop() {
            job?.cancel()
            job = null
            zoomingTo = null
            gliding = emptyList()
        }

        /**
         * A finger landing on content that's gliding stops it where it is.
         * Content bouncing back from past an edge carries on into place.
         */
        fun catch() {
            if (gliding.isNotEmpty() && gliding.all { abs(it.position) <= it.limit }) stop()
        }

        /**
         * Lets the content go at [velocity] (dp/s per axis) after a drag:
         * it glides on and slows to a stop, bounces off an edge it reaches,
         * and comes back to the edge from past it. An axis the content fits
         * on doesn't glide, and content let go past an edge only goes back.
         * Returns where it comes to rest (x, y) for `on_drag_end`.
         */
        fun glide(bounds: PanBounds, scope: CoroutineScope, panXId: Int, panYId: Int, pinchId: Int, velocity: Offset): Pair<Float, Float> {
            stop()
            val scale = if (pinchId != 0) SharedValueStore.valueOf(pinchId) else 1f
            val axes = listOf(Triple(panXId, true, velocity.x), Triple(panYId, false, velocity.y))
                .filter { (id, _, _) -> id != 0 }
                .map { (id, horizontal, speed) ->
                    val limit = bounds.limit(horizontal, scale)
                    val position = SharedValueStore.valueOf(id)
                    val outward = abs(position) > limit && speed * position > 0f
                    // Too slow to carry it half a dp is no glide at all.
                    val still = abs(speed) / GlideDecay < 0.5f
                    val v = if (limit <= MinRoomDp || outward || still) 0f else speed.coerceIn(-MaxGlide, MaxGlide)
                    PanGlide(id, position, v, limit)
                }
            val rests = axes.associate { it.id to it.rest() }
            val moving = axes.filter { it.velocity != 0f || abs(it.position) > it.limit }
            if (moving.isNotEmpty()) {
                gliding = moving
                job = scope.launch {
                    var last = withFrameNanos { it }
                    while (moving.any { !it.done }) {
                        val now = withFrameNanos { it }
                        val dt = ((now - last) / 1_000_000_000f).coerceIn(0f, 0.05f)
                        last = now
                        moving.forEach { axis ->
                            if (axis.done) return@forEach
                            axis.step(dt)
                            // Landing where it said it would, for the report.
                            SharedValueStore.set(axis.id, if (axis.done) rests.getValue(axis.id) else axis.position)
                        }
                    }
                    gliding = emptyList()
                }
            }
            return (rests[panXId] ?: 0f) to (rests[panYId] ?: 0f)
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

    /**
     * One axis of content let go after a drag, as a UIScrollView moves:
     * inside its limit it slows at UIScrollView's normal rate (0.998 a
     * millisecond), and past it a critically damped spring takes it back
     * to the edge. Each step is the exact solution over its time, so the
     * frame rate doesn't change where it ends up.
     */
    private class PanGlide(val id: Int, position: Float, velocity: Float, val limit: Float) {
        var position = position
            private set
        var velocity = velocity
            private set
        var done = false
            private set

        fun step(dt: Float) {
            if (done) return
            if (abs(position) <= limit) {
                val decay = exp(-GlideDecay * dt)
                position += velocity * (1 - decay) / GlideDecay
                velocity *= decay
                // Under a quarter of a dp left to go: there.
                if (abs(position) <= limit && abs(velocity) / GlideDecay < 0.25f) {
                    position = (position + velocity / GlideDecay).coerceIn(-limit, limit)
                    velocity = 0f
                    done = true
                }
            } else {
                // x(t) = (x + (v + w x) t) e^(-w t), from the edge.
                val edge = if (position < 0f) -limit else limit
                val x = position - edge
                val b = velocity + GlideBounce * x
                val decay = exp(-GlideBounce * dt)
                val next = (x + b * dt) * decay
                velocity = (velocity - GlideBounce * b * dt) * decay
                position = edge + next
                if (abs(next) < 0.25f && abs(velocity) < 4f) {
                    position = edge
                    velocity = 0f
                    done = true
                }
            }
        }

        /** Where it comes to rest, worked out ahead without moving it. */
        fun rest(): Float {
            val ahead = PanGlide(id, position, velocity, limit)
            var steps = 0
            while (!ahead.done && steps < 2400) {
                ahead.step(1 / 240f)
                steps++
            }
            return ahead.position.coerceIn(-limit, limit)
        }
    }

    /** How fast content let go slows: UIScrollView's normal rate, 0.998 a millisecond, per second. */
    private const val GlideDecay = 2.002f

    /** The stiffness of the spring that brings content back from past an edge (its natural frequency, per second). */
    private const val GlideBounce = 14f

    /** The fastest content glides off, in dp/s. */
    private const val MaxGlide = 8000f

    /** A finger still this long before it lifts lets go without a fling, as a scroll view does. */
    private const val StillMillis = 40L

    /** Room to pan under this many dp counts as none, so a pinch let go just past 1x (about 1.01x on a phone) doesn't keep drags from the pager. */
    private const val MinRoomDp = 2f

    /** How long a pan takes to spring back inside its bounds or onto a snap point. */
    private const val SettleMillis = 350

    /** Fast away from where it was let go, slowing into place. */
    private val EaseOutCubic = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)
}
