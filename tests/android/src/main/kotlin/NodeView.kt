package com.nativephp.mobile.ui.nativerender

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * Draws a container's children for the gesture area tests: a 300x120 box
 * tagged `node-<id>`, made clickable the way core makes a `pressable` when
 * the node has a press handler.
 */
@Composable
fun NodeView(node: NativeUINode, overrideModifier: Modifier? = null) {
    var modifier = Modifier.size(300.dp, 120.dp).testTag("node-${node.id}")
    if (node.onPress != 0) {
        modifier = modifier.clickable { NativeUIBridge.sendPressEvent(node.onPress, node.id) }
    }
    Box(modifier)
}
