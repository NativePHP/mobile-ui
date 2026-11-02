package com.nativephp.plugins.native_ui.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.AlignItems
import com.nativephp.mobile.ui.nativerender.FlexContainer
import com.nativephp.mobile.ui.nativerender.FlexDirection
import com.nativephp.mobile.ui.nativerender.JustifyContent
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.min

/**
 * Inline draggable bottom pane (`sheet_pane`) — Compose counterpart of the
 * iOS renderer. Bottom-anchored rounded pane that tracks vertical drags
 * continuously and spring-settles to the nearest detent, seeded with the
 * release velocity so flings feel continuous. The settled detent (dp) is
 * reported through the element's `on_change` callback; PHP republishes it
 * as the `detent` prop, which only moves the pane when the value actually
 * changes.
 *
 * Content is laid out ONCE at the tallest detent (reveal model) so nothing
 * reflows mid-drag; the animated frame clips it. Children go through
 * FlexContainer so EDGE flex semantics (a scroll-view's flex-1) behave as
 * in a regular column — and inner scrollables consume drags within their
 * bounds, so dragging the header moves the pane while dragging a list
 * scrolls it.
 *
 * A `fit` detent rests at the content's natural height, measured on the
 * device and capped at the screen. A fit pane lays its content out at that
 * height, pinned to the top, so lower detents cut it off at the bottom.
 * Resting on it reports `fit` rather than a number, and the pane follows
 * the content as its height changes.
 */
object SheetPaneRenderer {
    private sealed interface Detent {
        object Fit : Detent
        data class Points(val dp: Float) : Detent
    }

    private class Detents(val points: List<Float>, val fits: Boolean)

    private class RestingHeight(val detent: Detent, val height: Float)

    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        val density = LocalDensity.current

        val detentsRaw = p.getString("detents", "200,560,780")
        val config = remember(detentsRaw) { parseDetents(detentsRaw) }
        val cornerRadius = p.getFloat("corner_radius", 44f)
        val insetX = p.getFloat("inset_x", 8f)
        val insetBottom = p.getFloat("inset_bottom", 8f)
        val detentProp: Detent = if (p.getString("detent") == "fit") {
            Detent.Fit
        } else {
            config.points.firstOrNull()?.let { Detent.Points(p.getFloat("detent", it)) } ?: Detent.Fit
        }
        val changeCb = p.getCallbackId("on_change")

        val height = remember {
            Animatable(
                (detentProp as? Detent.Points)
                    ?.dp
                    ?.coerceIn(config.points.first(), config.points.last())
                    ?: 0f
            )
        }
        val appliedDetent = remember { mutableStateOf(detentProp) }
        var fitHeight by remember { mutableStateOf<Float?>(null) }
        var dragging by remember { mutableStateOf(false) }
        val scope = rememberCoroutineScope()

        BoxWithConstraints(modifier.fillMaxSize()) {
            val fit = fitHeight?.let { min(it, maxHeight.value - insetBottom) }
            val heights = resolve(config, fit)
            val revealHeight = heights.maxOfOrNull { it.height } ?: 0f

            // Only a genuinely NEW PHP-side detent moves the pane — republished
            // frames with the value we just reported are ignored. A fit detent
            // applied before the content is measured waits for the measure.
            LaunchedEffect(detentProp) {
                if (detentProp != appliedDetent.value) {
                    appliedDetent.value = detentProp
                    val target = when (detentProp) {
                        Detent.Fit -> fit
                        is Detent.Points -> detentProp.dp
                    }
                    if (target != null) {
                        height.animateTo(target, spring(dampingRatio = 0.8f, stiffness = 300f))
                    }
                }
            }

            // The first measure places the pane; later ones animate it along.
            LaunchedEffect(fit) {
                if (appliedDetent.value == Detent.Fit && !dragging && fit != null && fit != height.value) {
                    if (height.value > 0f) {
                        height.animateTo(fit, spring(dampingRatio = 0.8f, stiffness = 300f))
                    } else {
                        height.snapTo(fit)
                    }
                }
            }

            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(start = insetX.dp, end = insetX.dp, bottom = insetBottom.dp)
                    .fillMaxWidth()
                    .height(height.value.dp)
                    .clip(RoundedCornerShape(cornerRadius.dp))
                    .background(theme.background)
                    .draggable(
                        orientation = Orientation.Vertical,
                        state = rememberDraggableState { deltaPx ->
                            val deltaDp = with(density) { deltaPx.toDp().value }
                            val proposed = height.value - deltaDp
                            scope.launch { height.snapTo(rubberBand(proposed, heights.map { it.height })) }
                        },
                        onDragStarted = { dragging = true },
                        onDragStopped = { velocityPx ->
                            dragging = false
                            // Upward fling (negative y velocity) grows the pane.
                            val velocityDp = with(density) { -velocityPx.toDp().value }
                            val projected = height.value + velocityDp * 0.15f
                            val settled = heights.minByOrNull { abs(it.height - projected) }

                            if (settled != null) {
                                val settledElsewhere = settled.detent != appliedDetent.value
                                appliedDetent.value = settled.detent
                                scope.launch {
                                    height.animateTo(
                                        settled.height,
                                        spring(dampingRatio = 0.8f, stiffness = 300f),
                                        initialVelocity = velocityDp
                                    )
                                }
                                // Only report a detent CHANGE — snapping back
                                // to the detent we started from is not one.
                                if (changeCb != 0 && settledElsewhere) {
                                    NativeUIBridge.sendTextChangeEvent(changeCb, node.id, reported(settled.detent))
                                }
                            }
                        }
                    )
            ) {
                // Reveal model: content at the tallest detent, clipped above.
                FlexContainer(
                    direction = FlexDirection.COLUMN,
                    justify = JustifyContent.START,
                    align = AlignItems.STRETCH,
                    gap = 0f,
                    wrap = 0,
                    childNodes = node.children,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .fillMaxWidth()
                        .then(
                            if (config.fits) {
                                Modifier
                                    .wrapContentHeight(align = Alignment.Top, unbounded = true)
                                    .onSizeChanged { size ->
                                        val measured = with(density) { size.height.toDp().value }
                                        if (measured > 0f) fitHeight = measured
                                    }
                            } else {
                                Modifier.height(revealHeight.dp)
                            }
                        )
                ) {}
            }
        }
    }

    private fun parseDetents(raw: String): Detents {
        val points = mutableListOf<Float>()
        var fits = false
        for (token in raw.split(",").map { it.trim().lowercase() }) {
            when (token) {
                "fit" -> fits = true
                else -> token.toFloatOrNull()?.let { points.add(it) }
            }
        }

        if (points.isEmpty() && !fits) points.addAll(listOf(200f, 560f))
        return Detents(points.sorted(), fits)
    }

    /** The fit detent joins the point ones once the content is measured. */
    private fun resolve(config: Detents, fit: Float?): List<RestingHeight> {
        val resolved = config.points.map { RestingHeight(Detent.Points(it), it) }.toMutableList()
        if (config.fits && fit != null) resolved.add(RestingHeight(Detent.Fit, fit))
        return resolved.sortedBy { it.height }
    }

    /**
     * What `on_change` sends PHP. Fractional detents are reported
     * faithfully: truncating `560.5` to `560` fails the applied-detent
     * equality on the republish and nudges the pane a frame after every
     * drag.
     */
    private fun reported(detent: Detent): String = when (detent) {
        Detent.Fit -> "fit"
        is Detent.Points -> if (detent.dp == floor(detent.dp)) detent.dp.toInt().toString() else detent.dp.toString()
    }

    /** Soft overshoot past the outermost detents instead of a hard stop. */
    private fun rubberBand(proposed: Float, detents: List<Float>): Float {
        val lo = detents.firstOrNull() ?: return proposed
        val hi = detents.last()
        return when {
            proposed > hi -> hi + (proposed - hi) * 0.25f
            proposed < lo -> lo - (lo - proposed) * 0.25f
            else -> proposed
        }
    }
}
