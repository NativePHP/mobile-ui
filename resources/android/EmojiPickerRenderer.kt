package com.nativephp.plugins.native_ui.ui

import android.view.ViewGroup
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.rememberNestedScrollInteropConnection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.emoji2.emojipicker.EmojiPickerView
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Emoji picker — Jetpack's `EmojiPickerView` (androidx.emoji2) in a Material3
 * bottom sheet, shown while `visible` is true. Draws nothing in place.
 *
 * The picker brings the platform's categories, a recently used row, and
 * skin-tone, gender and direction variants on a long press, and keeps up
 * with new emoji through emoji2 rather than the OS version.
 *
 * Each pick goes to PHP as a select-change event (`on_change`) and the sheet
 * stays up: PHP closes it by setting `visible` false, so one pick or several
 * is the screen's choice. A swipe down, a tap on the scrim or back fires
 * `on_dismiss`; PHP setting `visible` false never does.
 */
object EmojiPickerRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val visible = p.getBool("visible")
        val onChangeCb by rememberUpdatedState(p.getCallbackId("on_change"))
        val onDismissCb = p.getCallbackId("on_dismiss")
        val a11yLabel = p.getString("a11y_label")

        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

        // As with the bottom sheet: stay composed while hide() plays out the
        // slide-down when PHP closes the picker.
        var shown by remember { mutableStateOf(visible) }
        LaunchedEffect(visible) {
            if (visible) {
                shown = true
            } else if (shown) {
                sheetState.hide()
                shown = false
            }
        }

        if (!shown) return

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        // EmojiPickerView fills the rows it's given; about half the screen
        // shows five or six rows and leaves the thread in view above.
        val pickerHeight = (LocalConfiguration.current.screenHeightDp * 0.5f).dp

        ModalBottomSheet(
            onDismissRequest = {
                shown = false
                if (onDismissCb != 0) {
                    NativeUIBridge.sendSheetDismissEvent(onDismissCb, node.id)
                }
            },
            sheetState = sheetState,
            containerColor = theme.surface,
            contentColor = theme.onSurface,
            scrimColor = BottomSheetDefaults.ScrimColor,
        ) {
            AndroidView(
                factory = { context ->
                    EmojiPickerView(context).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                        )
                        setOnEmojiPickedListener { item ->
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendSelectChangeEvent(onChangeCb, node.id, item.emoji)
                            }
                        }
                    }
                },
                // Not the node's own modifier: the element has no place in
                // the layout, only this sheet.
                modifier = Modifier
                    .fillMaxWidth()
                    .height(pickerHeight)
                    // Lets the picker's grid scroll before the sheet drags.
                    .nestedScroll(rememberNestedScrollInteropConnection())
                    .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m },
            )
        }
    }
}
