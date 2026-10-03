package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.LocalAvailableHeight
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Full-screen snap pager (`pager`). Compose's `VerticalPager` /
 * `HorizontalPager` lays out `count` logical pages; PHP ships only the
 * children inside `window_from..window_to` and every other page shows a
 * placeholder until the next render brings it in.
 *
 * Media on a page plays itself based on its own on-screen visibility
 * (media-player's `video_player` does), so this renderer knows nothing
 * about playback and nothing in core mediates.
 *
 * Page-change protocol: `settledPage` → `on_page_change` over the
 * TAB_CHANGE transport (one int). The pager position survives re-renders;
 * the `page` prop only moves it when PHP sends an index that differs from
 * the one native last reported (a programmatic jump).
 *
 * See `src/Elements/Pager.php` for the matching element class.
 */
object PagerRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val count = p.getInt("count", node.children.size).coerceAtLeast(0)
        val windowFrom = p.getInt("window_from", 0)
        // `has_more` appends one loading page after the last loaded item —
        // a feed has no total, so the user can pull into the tail while
        // PHP fetches the next batch. Settling there reports index == count.
        val hasMore = p.getBool("has_more", false)
        val pageCount = if (hasMore) count + 1 else count
        // Image per page index for pages PHP hasn't shipped; "" for none.
        val placeholders = p.getStringList("placeholders")
        val requestedPage = p.getInt("page", 0).coerceIn(0, (pageCount - 1).coerceAtLeast(0))
        val horizontal = p.getBool("horizontal", false)
        val cbId = p.getCallbackId("on_page_change")

        val pageByIndex: Map<Int, NativeUINode> = remember(node, windowFrom) {
            val out = HashMap<Int, NativeUINode>(node.children.size)
            node.children.forEachIndexed { offset, child -> out[windowFrom + offset] = child }
            out
        }

        val pagerState = rememberPagerState(initialPage = requestedPage) { pageCount }

        // Pages reported to PHP that it has not echoed back yet, oldest
        // first. A `page` prop matching one of these is an echo of our own
        // report, not a programmatic jump.
        val reported = remember { mutableStateListOf(requestedPage) }

        LaunchedEffect(requestedPage) {
            val at = reported.indexOf(requestedPage)
            if (at >= 0) {
                repeat(at + 1) { reported.removeAt(0) }
            } else {
                reported.clear()
                reported.add(requestedPage)
                pagerState.scrollToPage(requestedPage)
            }
        }

        if (cbId != 0) {
            // `currentPage` flips as soon as a page becomes the nearest one
            // mid-swipe (settledPage waits for rest), so PHP's round-trip
            // overlaps the animation instead of starting after it.
            LaunchedEffect(pagerState, cbId) {
                snapshotFlow { pagerState.currentPage }
                    .distinctUntilChanged()
                    .collect { index ->
                        if (reported.lastOrNull() != index) {
                            reported.add(index)
                            NativeElementBridge.sendTabChangeEvent(cbId, node.id, index)
                        }
                    }
            }
        }

        val pagerModifier = modifier.nuiA11y(p.getString("a11y_label"), p.getString("a11y_hint"))

        // A pager needs a bounded main axis. Inside a lazy parent (the
        // plain vertical scroll_view is a LazyColumn) the incoming height
        // is infinite, so fall back to one viewport.
        val availableHeight = LocalAvailableHeight.current
        BoxWithConstraints(modifier = pagerModifier) {
            val sized = if (constraints.hasBoundedHeight) {
                Modifier.fillMaxSize()
            } else {
                Modifier.fillMaxWidth().height(availableHeight.dp)
            }

            val page: @Composable (Int) -> Unit = { index ->
                Box(modifier = Modifier.fillMaxSize()) {
                    val child = pageByIndex[index]
                    if (child != null) {
                        NodeView(node = child)
                    } else if (hasMore && index >= count) {
                        PagerLoadingPage()
                    } else {
                        PagerPlaceholder(placeholders.getOrNull(index).orEmpty())
                    }
                }
            }

            if (horizontal) {
                HorizontalPager(
                    state = pagerState,
                    modifier = sized,
                    beyondViewportPageCount = 1,
                    key = { it },
                ) { index -> page(index) }
            } else {
                VerticalPager(
                    state = pagerState,
                    modifier = sized,
                    beyondViewportPageCount = 1,
                    key = { it },
                ) { index -> page(index) }
            }
        }
    }

    @Composable
    private fun PagerLoadingPage() {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
    }

    /**
     * An unshipped page: its placeholder image if PHP gave one, else
     * transparent so the pager's own background (`bg-*` on the tag) shows
     * through and never flashes a theme colour over a dark feed.
     */
    @Composable
    private fun PagerPlaceholder(imageUrl: String) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (imageUrl.isNotEmpty()) {
                AsyncImage(
                    model = imageUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}
