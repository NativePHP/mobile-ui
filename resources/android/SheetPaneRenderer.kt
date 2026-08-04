package com.nativephp.plugins.native_ui.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
 */
object SheetPaneRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        val density = LocalDensity.current

        val detents = remember(p.getString("detents", "")) {
            p.getString("detents", "200,560,780")
                .split(",")
                .mapNotNull { it.trim().toFloatOrNull() }
                .sorted()
                .ifEmpty { listOf(200f, 560f) }
        }
        val maxDetent = detents.last()
        val cornerRadius = p.getFloat("corner_radius", 44f)
        val insetX = p.getFloat("inset_x", 8f)
        val insetBottom = p.getFloat("inset_bottom", 8f)
        val detentProp = p.getFloat("detent", detents.first())
        val changeCb = p.getCallbackId("on_change")

        val height = remember { Animatable(detentProp.coerceIn(detents.first(), maxDetent)) }
        val appliedDetent = remember { mutableFloatStateOf(detentProp) }
        val scope = rememberCoroutineScope()

        // Only a genuinely NEW PHP-side detent moves the pane — republished
        // frames with the value we just reported are ignored.
        LaunchedEffect(detentProp) {
            if (detentProp != appliedDetent.floatValue) {
                appliedDetent.floatValue = detentProp
                height.animateTo(detentProp, spring(dampingRatio = 0.8f, stiffness = 300f))
            }
        }

        Box(modifier.fillMaxSize()) {
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
                            scope.launch { height.snapTo(rubberBand(proposed, detents)) }
                        },
                        onDragStopped = { velocityPx ->
                            // Upward fling (negative y velocity) grows the pane.
                            val velocityDp = with(density) { -velocityPx.toDp().value }
                            val projected = height.value + velocityDp * 0.15f
                            val target = detents.minByOrNull { abs(it - projected) } ?: height.value

                            appliedDetent.floatValue = target
                            scope.launch {
                                height.animateTo(
                                    target,
                                    spring(dampingRatio = 0.8f, stiffness = 300f),
                                    initialVelocity = velocityDp
                                )
                            }
                            if (changeCb != 0) {
                                NativeUIBridge.sendTextChangeEvent(changeCb, node.id, target.toInt().toString())
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
                        .height(maxDetent.dp)
                ) {}
            }
        }
    }

    /** Soft overshoot past the outermost detents instead of a hard stop. */
    private fun rubberBand(proposed: Float, detents: List<Float>): Float {
        val lo = detents.first()
        val hi = detents.last()
        return when {
            proposed > hi -> hi + (proposed - hi) * 0.25f
            proposed < lo -> lo - (lo - proposed) * 0.25f
            else -> proposed
        }
    }
}
