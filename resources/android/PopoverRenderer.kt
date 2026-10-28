package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.RenderNode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Popover — a raised Material surface in a [Popup] beside the spot this
 * element is laid over, driven by `visible`. The element draws nothing and
 * takes no touches; its children are the bubble's content.
 *
 * [AboveOrBelow] centres the bubble on the anchor and puts it on the
 * preferred side (`placement`, top by default) unless it wouldn't fit
 * between the anchor and the system bars there.
 *
 * A tap outside or back fires `on_dismiss`; PHP setting `visible` false
 * never does.
 */
object PopoverRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val visible = p.getBool("visible")
        val onDismissCb = p.getCallbackId("on_dismiss")
        val prefersBelow = p.getString("placement", "top") == "bottom"
        val a11yLabel = p.getString("a11y_label")

        // Closed by the person while PHP still has it open: stay closed until
        // PHP catches up, rather than fire @dismiss for every tap after.
        var dismissed by remember { mutableStateOf(false) }
        LaunchedEffect(visible) { if (!visible) dismissed = false }

        val density = LocalDensity.current
        val topInset = WindowInsets.statusBars.getTop(density)
        val bottomInset = WindowInsets.navigationBars.getBottom(density)
        val gap = with(density) { 8.dp.roundToPx() }
        val positions = remember(prefersBelow, topInset, bottomInset, gap) {
            AboveOrBelow(prefersBelow, gap, topInset, bottomInset)
        }

        Box(modifier) {
            if (visible && !dismissed) {
                val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

                Popup(
                    popupPositionProvider = positions,
                    onDismissRequest = {
                        dismissed = true
                        if (onDismissCb != 0) {
                            NativeUIBridge.sendSheetDismissEvent(onDismissCb, node.id)
                        }
                    },
                    properties = PopupProperties(focusable = true),
                ) {
                    Surface(
                        shape = RoundedCornerShape(24.dp),
                        color = theme.surface,
                        contentColor = theme.onSurface,
                        shadowElevation = 6.dp,
                    ) {
                        Column(
                            modifier = if (a11yLabel.isNotEmpty()) Modifier.semantics { contentDescription = a11yLabel } else Modifier,
                        ) {
                            node.children.forEach { RenderNode(it) }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Centres the bubble on the anchor, clamped to the window, on the preferred
 * side when it fits between the anchor and the system bars, otherwise on
 * the side with more room.
 */
internal class AboveOrBelow(
    private val prefersBelow: Boolean,
    private val gap: Int,
    private val topInset: Int,
    private val bottomInset: Int,
) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset {
        val x = (anchorBounds.center.x - popupContentSize.width / 2)
            .coerceIn(gap, (windowSize.width - popupContentSize.width - gap).coerceAtLeast(gap))

        val needed = popupContentSize.height + gap * 2
        val above = anchorBounds.top - topInset
        val below = windowSize.height - bottomInset - anchorBounds.bottom
        val opensBelow = if (prefersBelow) below >= needed || below >= above else above < needed && below > above

        val y = if (opensBelow) anchorBounds.bottom + gap else anchorBounds.top - gap - popupContentSize.height

        return IntOffset(x, y)
    }
}
