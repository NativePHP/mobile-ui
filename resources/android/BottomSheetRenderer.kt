package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.RenderNode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 ModalBottomSheet. Visibility driven by `visible`; drag-down and
 * tap-outside both route to the `@dismiss` callback.
 *
 * Theme-sourced container + scrim (Model 3). No per-instance `background_color`.
 *
 * Detent parsing matches the iOS renderer's vocabulary — accepts any
 * comma-separated mix of `small` / `medium` / `large` / `full` plus
 * free-form fractions (`"0.33,0.66"`). M3's `ModalBottomSheet` only
 * exposes two stops (partial + full), so fractions can't snap precisely
 * the way iOS's `PresentationDetent.fraction(_:)` does — we degrade
 * gracefully: any partial-intent token (named or fractional `< 1.0`)
 * enables the partial-expanded state; otherwise we skip straight to full.
 */
object BottomSheetRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val visible = p.getBool("visible")
        val onDismissCb = p.getCallbackId("on_dismiss")
        val detentsStr = p.getString("detents", "medium,large")
        val a11yLabel = p.getString("a11y_label")
        // Counterpart of iOS `.interactiveDismissDisabled`: block drag-to-hide
        // and back-press, and swallow scrim-tap dismiss requests. NOTE:
        // `background_interaction` has no Android counterpart here — M3's
        // ModalBottomSheet is a modal window, so the scrim always intercepts
        // touches; a Maps-style pane over a live background is what
        // `sheet_pane` is for.
        val permanent = p.getBool("permanent")

        if (!visible) return

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        val skipPartial = !hasPartialDetent(detentsStr)
        val sheetState = rememberModalBottomSheetState(
            skipPartiallyExpanded = skipPartial,
            confirmValueChange = { value -> !(permanent && value == SheetValue.Hidden) },
        )

        val sheetModifier = modifier
            .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m }

        ModalBottomSheet(
            onDismissRequest = {
                if (!permanent && onDismissCb != 0) {
                    NativeUIBridge.sendSheetDismissEvent(onDismissCb, node.id)
                }
            },
            sheetState = sheetState,
            properties = ModalBottomSheetProperties(shouldDismissOnBackPress = !permanent),
            containerColor = theme.surface,
            contentColor = theme.onSurface,
            scrimColor = BottomSheetDefaults.ScrimColor,
        ) {
            // M3 ModalBottomSheet sizes itself to content by default — for
            // multi-detent sheets that means short content collapses the
            // partial/expanded anchors to the same height and you can't drag
            // between them. iOS's `presentationDetents` drives container
            // height instead, so the sheet always has the detent's worth of
            // room and content sits inside. `fillMaxHeight()` reproduces
            // that semantic on Android: content area always fills the
            // current detent's height, leaving drag-room to the next one.
            Column(modifier = sheetModifier.fillMaxHeight()) {
                node.children.forEach { RenderNode(it) }
            }
        }
    }
}

/**
 * Returns true iff the detents string requests at least one partial stop.
 *
 * Tokenization mirrors the iOS renderer: comma-separated, case-insensitive,
 * trimmed. Recognized names: `small`, `medium`, `large`, `full`. Anything
 * else is parsed as a `Double`; values in `(0, 1)` count as partial,
 * values `>= 1` count as full. Unrecognized tokens are skipped.
 *
 * If no token can be interpreted, defaults to `true` (the PHP default
 * `medium,large` always has a partial stop, so the empty/garbled fallback
 * matches that intent).
 */
private fun hasPartialDetent(str: String): Boolean {
    val parts = str.split(",")
        .map { it.trim().lowercase() }
        .filter { it.isNotEmpty() }
    if (parts.isEmpty()) return true
    var sawAny = false
    for (part in parts) {
        when (part) {
            "small", "medium" -> return true
            "large", "full" -> { sawAny = true }
            else -> {
                val f = part.toDoubleOrNull()
                if (f != null && f > 0.0) {
                    if (f < 1.0) return true
                    sawAny = true
                }
            }
        }
    }
    return !sawAny
}
