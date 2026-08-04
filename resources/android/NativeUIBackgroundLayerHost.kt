package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.nativephp.mobile.ui.nativerender.NativeRendererRegistry
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView

/**
 * Renders the `background_layer` sentinel BENEATH the screen content —
 * Compose counterpart of the iOS host. The layer's child sits at a fixed
 * structural position, so `remember`ed state inside its renderer (a
 * MapLibre MapView, a player) survives every publish: tab switches and
 * pushes update props in place instead of recreating the native view.
 *
 * NOTE: this file must compile against every core this plugin installs
 * into — it must not reference core symbols that only exist on newer
 * cores. The `LocalBackgroundLayerPresent` transparency signal (so the
 * tabs Scaffold can go transparent above the layer) returns here once
 * the distributed core ships that composition local alongside the
 * tabs-hosting work.
 */
@Composable
fun NativeUIBackgroundLayerHost(
    layerNode: NativeUINode?,
    content: @Composable () -> Unit,
) {
    val child = layerNode?.children?.firstOrNull()

    if (child == null) {
        content()
        return
    }

    Box(Modifier.fillMaxSize()) {
        // Dispatch the layer's renderer DIRECTLY instead of via NodeView:
        // NodeView wraps children in key(node.id), and flat-buffer ids
        // shift whenever the tree's shape changes (every navigation) —
        // which would discard the subtree and recreate the native view.
        // Direct dispatch keys the renderer to THIS stable call site, so
        // its remembered state (a MapView, a player) survives any publish.
        // The layer needs no gesture/style modifier chain, so skipping
        // NodeView loses nothing.
        val renderer = NativeRendererRegistry.get(child.type)
        if (renderer != null) {
            renderer.Render(child, Modifier.fillMaxSize())
        } else {
            NodeView(node = child, overrideModifier = Modifier.fillMaxSize())
        }

        // Content composes SECOND — Compose draws later Box children on
        // top, which is what keeps the layer beneath the screen.
        content()
    }
}
