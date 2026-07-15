@file:OptIn(kotlinx.coroutines.FlowPreview::class)

package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Windowed list. LazyColumn renders `count` logical slots; PHP only ships
 * the rows inside `window_from..window_to`. Slots outside the window get
 * a `Spacer` of `estimated_row_height` so total scroll extent is correct
 * even though the per-row content isn't allocated.
 *
 * Visible range is read from `LazyListState.layoutInfo` via `snapshotFlow`,
 * debounced 80ms (same pattern as on_end_reached in `ListRenderer.kt`).
 * The callback fires with `[from, to]` (overscan applied) as
 * `"$from,$to"` text — PHP decodes via the `virtual_window` callback kind.
 *
 * See `Plugins/nativephp/mobile-ui/src/Elements/NativeVirtualList.php` for
 * the matching element class.
 */
object VirtualListRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val count = node.props.getInt("count", 0).coerceAtLeast(0)
        val windowFrom = node.props.getInt("window_from", 0)
        val windowTo = node.props.getInt("window_to", 0)
        val estimatedRowHeight = node.props.getFloat("estimated_row_height", 56f)
        val overscan = node.props.getInt("overscan", 30)
        val cbId = node.props.getCallbackId("on_window_change")

        // Build the absolute-index -> child map once per composition. Cheap;
        // the children list is the small windowed slice, not `count`.
        val rowByIndex: Map<Int, NativeUINode> = remember(node, windowFrom) {
            val out = HashMap<Int, NativeUINode>(node.children.size)
            node.children.forEachIndexed { offset, child ->
                out[windowFrom + offset] = child
            }
            out
        }

        val scrollState = rememberLazyListState()

        if (cbId != 0 && count > 0) {
            LaunchedEffect(scrollState, count, overscan, windowFrom, windowTo) {
                snapshotFlow {
                    val info = scrollState.layoutInfo
                    val first = info.visibleItemsInfo.firstOrNull()?.index ?: -1
                    val last = info.visibleItemsInfo.lastOrNull()?.index ?: -1
                    Pair(first, last)
                }
                    .distinctUntilChanged()
                    .debounce(200)
                    .collect { (first, last) ->
                        if (first < 0 || last < 0) return@collect
                        // Hysteresis. Only ask PHP for a new window when the
                        // visible range is approaching the edge of the data
                        // PHP has already sent. `overscan / 3` is the trigger
                        // margin; the request itself is the full overscan.
                        val trigger = (overscan / 3).coerceAtLeast(1)
                        val needsLeft = first - trigger < windowFrom && windowFrom > 0
                        val needsRight = last + trigger > windowTo && windowTo < count - 1
                        if (!needsLeft && !needsRight) return@collect

                        val from = (first - overscan).coerceAtLeast(0)
                        val to = (last + overscan).coerceAtMost(count - 1)
                        NativeElementBridge.sendTextChangeEvent(cbId, node.id, "$from,$to")
                    }
            }
        }

        LazyColumn(modifier = modifier, state = scrollState) {
            items(count = count, key = { it }) { index ->
                val child = rowByIndex[index]
                if (child != null) {
                    NodeView(node = child)
                } else {
                    // Visible skeleton — beats an empty Spacer (which
                    // looks like the row is broken during fast scroll).
                    Box(modifier = Modifier
                        .fillMaxWidth()
                        .height(estimatedRowHeight.dp)
                        .background(MaterialTheme.colorScheme.surfaceVariant))
                }
            }
        }
    }
}
