package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.LocalAvailableHeight
import com.nativephp.mobile.ui.nativerender.LocalReelPageActive
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Full-screen snap pager (`reel`). Compose's `VerticalPager` /
 * `HorizontalPager` lays out `count` logical pages; PHP ships only the
 * children inside `window_from..window_to` and every other page shows a
 * placeholder until the next render brings it in.
 *
 * Playback seam: each page is composed under `LocalReelPageActive`, true
 * only for the settled page, so media renderers (media-player's
 * `video_player`) play the visible page and pause the pre-composed
 * neighbours without this plugin knowing about them.
 *
 * Page-change protocol: `settledPage` → `on_page_change` as decimal text
 * (the `reel_page` callback kind). The pager position survives re-renders;
 * the `page` prop only moves it when PHP sends an index that differs from
 * the one native last reported (a programmatic jump).
 *
 * See `src/Elements/Reel.php` for the matching element class.
 */
object ReelRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val count = p.getInt("count", node.children.size).coerceAtLeast(0)
        val windowFrom = p.getInt("window_from", 0)
        val requestedPage = p.getInt("page", 0).coerceIn(0, (count - 1).coerceAtLeast(0))
        val horizontal = p.getBool("horizontal", false)
        val cbId = p.getCallbackId("on_page_change")

        val pageByIndex: Map<Int, NativeUINode> = remember(node, windowFrom) {
            val out = HashMap<Int, NativeUINode>(node.children.size)
            node.children.forEachIndexed { offset, child -> out[windowFrom + offset] = child }
            out
        }

        val pagerState = rememberPagerState(initialPage = requestedPage) { count }

        // The index PHP knows about: what we last sent it, or what it last
        // sent us. Stops a re-render that echoes our own page back from
        // being mistaken for a jump, and vice versa.
        val knownPage = remember { mutableIntStateOf(requestedPage) }

        LaunchedEffect(requestedPage) {
            if (requestedPage != knownPage.intValue) {
                knownPage.intValue = requestedPage
                pagerState.scrollToPage(requestedPage)
            }
        }

        if (cbId != 0) {
            LaunchedEffect(pagerState, cbId) {
                snapshotFlow { pagerState.settledPage }
                    .distinctUntilChanged()
                    .collect { index ->
                        if (index != knownPage.intValue) {
                            knownPage.intValue = index
                            NativeElementBridge.sendTextChangeEvent(cbId, node.id, index.toString())
                        }
                    }
            }
        }

        val reelModifier = modifier.nuiA11y(p.getString("a11y_label"), p.getString("a11y_hint"))

        // A pager needs a bounded main axis. Inside a lazy parent (the
        // plain vertical scroll_view is a LazyColumn) the incoming height
        // is infinite, so fall back to one viewport.
        val availableHeight = LocalAvailableHeight.current
        BoxWithConstraints(modifier = reelModifier) {
            val sized = if (constraints.hasBoundedHeight) {
                Modifier.fillMaxSize()
            } else {
                Modifier.fillMaxWidth().height(availableHeight.dp)
            }

            val page: @Composable (Int) -> Unit = { index ->
                CompositionLocalProvider(LocalReelPageActive provides (pagerState.settledPage == index)) {
                    Box(modifier = Modifier.fillMaxSize()) {
                        val child = pageByIndex[index]
                        if (child != null) {
                            NodeView(node = child)
                        } else {
                            ReelPlaceholder()
                        }
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
    private fun ReelPlaceholder() {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surfaceVariant)
        )
    }
}
