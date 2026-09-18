package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Pull-to-refresh wrapper using Compose Material 3's PullToRefreshBox.
 * Children render inside a `LazyColumn`; the standard Material refresh
 * indicator appears when the user pulls down past threshold.
 *
 * Driven by props:
 *   - `on_refresh` (int) — callback ID fired when user releases past
 *     threshold. We keep `isRefreshing` true for 800ms after firing so
 *     the user sees the spinner even when PHP handlers complete fast;
 *     the next tree publish typically lands within that window.
 *   - `shows_indicators` (bool) — accepted for parity with iOS but a
 *     no-op here: `LazyColumn` draws no scroll indicators to begin
 *     with, so there is nothing to hide.
 *
 * Children should NOT include their own `<scroll-view>` — this
 * element IS the scrolling container.
 */
@OptIn(ExperimentalMaterial3Api::class)
object RefreshableRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val refreshCallback = node.props.getInt("on_refresh", 0)
        val nodeId = node.id
        var isRefreshing by remember { mutableStateOf(false) }
        val scope = rememberCoroutineScope()

        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                if (refreshCallback != 0) {
                    isRefreshing = true
                    NativeElementBridge.sendPressEvent(refreshCallback, nodeId)
                    scope.launch {
                        // Minimum visible spinner so quick PHP handlers
                        // don't make the refresh feel skipped. PHP's
                        // tree publish typically lands within this.
                        delay(800)
                        isRefreshing = false
                    }
                }
            },
            modifier = modifier.fillMaxSize(),
        ) {
            LazyColumn {
                items(node.children, key = { it.id }) { child ->
                    NodeView(node = child)
                }
            }
        }
    }
}
