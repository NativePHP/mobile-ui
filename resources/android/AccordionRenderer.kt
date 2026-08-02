package com.nativephp.plugins.native_ui.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView

object AccordionRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getBool("expanded")
        val onChangeCb = p.getCallbackId("on_change")

        // Both keyed on node.id so a recycled node re-seeds from its own
        // props rather than inheriting the previous occupant's state.
        var isExpanded by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        val rotationAngle by animateFloatAsState(
            targetValue = if (isExpanded) 180f else 0f,
            label = "Chevron Rotation"
        )

        LaunchedEffect(serverValue) {
            // Echo-prevention — ignore server pushes that match our last
            // commit; accept genuine programmatic updates.
            if (serverValue != lastSentValue) {
                isExpanded = serverValue
                lastSentValue = serverValue
            }
        }

        // One definition of "the user toggled it", shared by the header row
        // and the chevron button so either route reports back to PHP.
        val toggle = {
            val new = !isExpanded
            isExpanded = new
            lastSentValue = new
            if (onChangeCb != 0) {
                NativeUIBridge.sendToggleChangeEvent(onChangeCb, node.id, new)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .animateContentSize()
                .then(modifier)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) { toggle() },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Weighted so the header can never crowd the chevron out of
                // the row: a `<row>` header defaults to STRETCH alignment and
                // therefore fillMaxWidth, which would otherwise take the lot.
                Row(
                    modifier = Modifier.weight(1f, fill = false),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    node.children.forEach { child ->
                        if (child.type == "accordion_header") {
                            child.children.forEach { child1 -> NodeView(node = child1) }
                        }
                    }
                }

                IconButton(
                    modifier = Modifier.size(24.dp),
                    onClick = { toggle() }
                ) {
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowDown,
                        contentDescription = null,
                        modifier = Modifier.rotate(rotationAngle),
                    )
                }
            }

            AnimatedVisibility(visible = isExpanded) {
                // Column, not a bare lambda: AnimatedVisibility lays its
                // content out in a Box, so multiple content children would
                // otherwise stack on top of each other.
                Column {
                    node.children.forEach { child ->
                        if (child.type == "accordion_content") {
                            child.children.forEach { child1 -> NodeView(node = child1) }
                        }
                    }
                }
            }
        }
    }
}
