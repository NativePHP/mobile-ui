package com.nativephp.plugins.native_ui.ui

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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Full-screen modal overlay. Visibility driven by the `visible` prop.
 *
 * Theme-sourced background (Model 3). A header row with a close icon
 * renders when `dismissible` is true — tapping it fires `@dismiss`, which
 * typically flips the bound property so the modal closes on the next
 * re-render.
 */
object ModalRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val visible = node.props.getBool("visible")
        val dismissible = node.props.getBool("dismissible", true)
        val onDismissCb = node.props.getCallbackId("on_dismiss")
        val a11yLabel = node.props.getString("a11y_label")
        val nodeId = node.id

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

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
                            horizontalArrangement = Arrangement.End,
                        ) {
                            IconButton(onClick = {
                                showModal = false
                                fireDismiss()
                            }) {
                                Icon(
                                    imageVector = Icons.Filled.Close,
                                    contentDescription = "Close",
                                    tint = theme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                    node.children.forEach { child -> NodeView(node = child) }
                }
            }
        }
    }
}
