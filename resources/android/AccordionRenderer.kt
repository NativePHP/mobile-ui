package com.nativephp.plugins.native_ui.ui

import androidx.compose.runtime.Composable
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.plugins.native_ui.NativeUITheme
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.animation.animateContentSize
import androidx.compose.ui.unit.dp
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.ui.draw.rotate

object AccordionRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getBool("expanded")
        val onChangeCb  = p.getCallbackId("on_change")

        var isExpanded by remember { mutableStateOf(p.getBool("expanded")) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        val rotationAngle by animateFloatAsState(
            targetValue = if (isExpanded) 180f else 0f,
            label = "Chevron Rotation"
        )

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                isExpanded = serverValue
                lastSentValue = serverValue
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .animateContentSize().then(modifier)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) {
                        val new = !isExpanded
                        isExpanded = new
                        lastSentValue = new
                        if (onChangeCb != 0) {
                            NativeUIBridge.sendToggleChangeEvent(onChangeCb, node.id, new)
                        }
                    },
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                node.children.forEach { child ->
                    if (child.type == "accordion_header") {
                        child.children.forEach { child1 -> NodeView(node = child1) }
                    }
                }

                IconButton(modifier = Modifier.then(Modifier.size(24.dp)),
                    onClick = {
                        val new = !isExpanded
                        isExpanded = new
                        lastSentValue = new
                        if (onChangeCb != 0) {
                            NativeUIBridge.sendToggleChangeEvent(onChangeCb, node.id, new)
                        }
                    }
                ) {
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowDown,
                        contentDescription = null,
                        modifier = Modifier.rotate(rotationAngle),
                    )
                }
            }

            AnimatedVisibility(visible = isExpanded) {
                node.children.forEach { child ->
                    if (child.type == "accordion_content") {
                        child.children.forEach { child1 -> NodeView(node = child1) }
                    }
                }
            }
        }
    }
}