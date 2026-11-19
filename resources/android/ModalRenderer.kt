package com.nativephp.plugins.native_ui.ui

import android.view.WindowManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import com.nativephp.mobile.ui.MainActivity
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.plugins.native_ui.NativeUITheme
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * Full-screen modal overlay. Visibility driven by the `visible` prop.
 *
 * Theme-sourced background (Model 3). A header row with a close icon
 * renders when `dismissible` is true — tapping it fires `@dismiss`, which
 * typically flips the bound property so the modal closes on the next
 * re-render.
 *
 * With `transition="fade"`, or a morph, it fades in over the screen and
 * out again instead (see FadingModal).
 */
object ModalRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        if (node.props.getString("transition") == "fade" || node.props.getString("morph_from").isNotEmpty()) {
            FadingModal(node)
            return
        }

        val visible = node.props.getBool("visible")
        val dismissible = node.props.getBool("dismissible", true)
        val onDismissCb = node.props.getCallbackId("on_dismiss")
        val nodeId = node.id

        var showModal by remember { mutableStateOf(false) }
        LaunchedEffect(visible) { showModal = visible }

        if (!showModal) return

        val fireDismiss = {
            if (onDismissCb != 0) {
                NativeElementBridge.sendPressEvent(onDismissCb, nodeId)
            }
        }

        Dialog(
            onDismissRequest = {
                if (dismissible) {
                    showModal = false
                    fireDismiss()
                }
            },
            properties = DialogProperties(
                dismissOnBackPress = dismissible,
                dismissOnClickOutside = dismissible,
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
        ) {
            MatchScreenStatusBar()
            ModalContent(node, node.children) {
                showModal = false
                fireDismiss()
            }
        }
    }

    /**
     * A modal that fades in over the screen and out again. Its window plays
     * no animation of its own and doesn't dim what's behind it, and its
     * content fades.
     *
     * With `morph_from` and `morph_to` (the refs of an image on the screen
     * and an image in the modal), a copy of the picture flies between where
     * the two are drawn while the content fades, both real images hidden
     * until it lands (see NativeUIImageMorph). Opening waits a moment for
     * the image in the modal to load, and just fades if it doesn't, or if
     * the one on the screen isn't on screen. Closing flies back from
     * wherever the image in the modal is drawn then, zoomed or dragged, to
     * whichever image `morph_from` names by then.
     *
     * PHP can empty the modal as it closes it, so the content, and the refs
     * to fly between, are what it last showed while it was visible. Back
     * asks PHP to close it, as the close button does, and it fades out when
     * PHP does.
     */
    @Composable
    private fun FadingModal(node: NativeUINode) {
        val visible = node.props.getBool("visible")
        val dismissible = node.props.getBool("dismissible", true)
        val onDismissCb = node.props.getCallbackId("on_dismiss")
        val nodeId = node.id
        val fireDismiss = {
            if (onDismissCb != 0) {
                NativeElementBridge.sendPressEvent(onDismissCb, nodeId)
            }
        }

        val last = remember { Remembered() }
        if (visible) {
            last.children = node.children
            last.morphFrom = node.props.getString("morph_from")
            last.morphTo = node.props.getString("morph_to")
        }

        var present by remember { mutableStateOf(false) }
        var flight by remember { mutableStateOf<NativeUIImageFlight?>(null) }
        val shown = remember { Animatable(0f) }
        val travel = remember { Animatable(0f) }

        LaunchedEffect(visible) {
            val from = last.morphFrom
            val to = last.morphTo
            try {
                if (visible) {
                    if (present) {
                        // Back before it had gone: fade up again from where it is.
                        flight = null
                        NativeUIImageMorph.show(from, to)
                        shown.animateTo(1f, tween(FadeMillis))
                        return@LaunchedEffect
                    }
                    shown.snapTo(0f)
                    present = true
                    val source = NativeUIImageMorph.onScreen(from)
                    val target = if (source != null) NativeUIImageMorph.awaitOnScreen(to, DrawWaitMillis) else null
                    if (source != null && target != null) {
                        fly(NativeUIImageFlight(source, target), from, to, shown, 1f, travel) { flight = it }
                    } else {
                        shown.animateTo(1f, tween(FadeMillis))
                    }
                } else if (present) {
                    val target = NativeUIImageMorph.onScreen(to)
                    val source = if (target != null) NativeUIImageMorph.onScreen(from) else null
                    if (source != null && target != null) {
                        fly(NativeUIImageFlight(target, source), from, to, shown, 0f, travel) { flight = it }
                    } else {
                        shown.animateTo(0f, tween(FadeMillis))
                    }
                    present = false
                    last.children = emptyList()
                }
            } finally {
                flight = null
                NativeUIImageMorph.show(from, to)
            }
        }

        if (!present) return

        Dialog(
            onDismissRequest = { if (dismissible) fireDismiss() },
            properties = DialogProperties(
                dismissOnBackPress = dismissible,
                dismissOnClickOutside = false,
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
        ) {
            val dialogView = LocalView.current
            SideEffect {
                (dialogView.parent as? DialogWindowProvider)?.window?.let { window ->
                    window.setWindowAnimations(0)
                    window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                    window.setDimAmount(0f)
                }
            }
            MatchScreenStatusBar()

            var origin by remember { mutableStateOf(Offset.Zero) }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .onGloballyPositioned { origin = it.localToScreen(Offset.Zero) }
            ) {
                Box(modifier = Modifier.fillMaxSize().graphicsLayer { alpha = shown.value }) {
                    ModalContent(node, if (visible) node.children else last.children, fireDismiss)
                }
                flight?.let { NativeUIImageFlightView(it, travel.value, origin) }
            }
        }
    }

    /**
     * Flies [flight] with both real images hidden while [shown] goes to
     * [showTo] alongside it. The copy stays a frame after the real images
     * draw again under it, just where they are.
     */
    private suspend fun fly(
        flight: NativeUIImageFlight,
        from: String,
        to: String,
        shown: Animatable<Float, AnimationVector1D>,
        showTo: Float,
        travel: Animatable<Float, AnimationVector1D>,
        setFlight: (NativeUIImageFlight?) -> Unit,
    ) {
        NativeUIImageMorph.hide(from, to)
        travel.snapTo(0f)
        setFlight(flight)
        coroutineScope {
            launch { shown.animateTo(showTo, tween(FadeMillis)) }
            travel.animateTo(1f, tween(FadeMillis, easing = FastOutSlowInEasing))
        }
        NativeUIImageMorph.show(from, to)
        withFrameNanos { }
        setFlight(null)
    }

    /** What a modal draws: the close row when it's dismissible, then its children. */
    @Composable
    private fun ModalContent(node: NativeUINode, children: List<NativeUINode>, close: () -> Unit) {
        val dismissible = node.props.getBool("dismissible", true)
        val a11yLabel = node.props.getString("a11y_label")
        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        val dialogModifier = Modifier
            .fillMaxSize()
            .background(theme.background)
            .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m }

        Box(modifier = dialogModifier) {
            Column(modifier = Modifier.fillMaxSize()) {
                if (dismissible) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .statusBarsPadding()
                            .padding(8.dp),
                        // Material 3 full-screen dialogs put close at the start of
                        // the top bar, where the navigation icon goes; it follows
                        // the layout direction, so it moves to the right in RTL.
                        horizontalArrangement = Arrangement.Start,
                    ) {
                        IconButton(onClick = close) {
                            Icon(
                                imageVector = Icons.Filled.Close,
                                contentDescription = "Close",
                                tint = theme.onSurfaceVariant,
                            )
                        }
                    }
                }
                children.forEach { child -> NodeView(node = child) }
            }
        }
    }

    /**
     * The dialog has its own window, and its status bar icons stay white
     * unless it is told otherwise. Copy the appearance from the activity,
     * which applies `status_bar_style`, so the modal matches the screen
     * behind it. The side effect runs again when the theme changes.
     */
    @Composable
    private fun MatchScreenStatusBar() {
        val dialogView = LocalView.current
        SideEffect {
            val dialogWindow = (dialogView.parent as? DialogWindowProvider)?.window
            val screenWindow = MainActivity.instance?.window
            if (dialogWindow != null && screenWindow != null) {
                WindowCompat.getInsetsController(dialogWindow, dialogView).isAppearanceLightStatusBars =
                    WindowCompat.getInsetsController(screenWindow, screenWindow.decorView).isAppearanceLightStatusBars
            }
        }
    }

    /** What a fading modal showed while it was visible. */
    private class Remembered {
        var children: List<NativeUINode> = emptyList()
        var morphFrom = ""
        var morphTo = ""
    }

    /** How long a fade or a flight takes. */
    private const val FadeMillis = 350

    /** How long opening waits for the image in the modal to load. */
    private const val DrawWaitMillis = 300L
}
