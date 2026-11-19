package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.*

/**
 * `native:lazy-stack`: a vertical scroll of children drawn lazily, in a
 * LazyColumn, each child keyed by its node id.
 *
 * It's for long feeds that change often. It does less than a list on
 * purpose: no separators, swipe actions, pull-to-refresh, sections or row
 * callbacks. Rows draw themselves.
 *
 * - Spacing between children is the node's `gap-*`.
 * - `p-*` and `bg-*` come in on [modifier] like any element. The
 *   `content_padding_*` props pad the scrolled content instead, so the first
 *   and last child can sit clear of the edges and still scroll under them.
 * - `shows_indicators` is accepted and has no effect: a LazyColumn draws no
 *   scroll indicator to begin with.
 * - A child added above the screen doesn't move what's on it: LazyColumn
 *   keeps the first visible child in place by key. It does that at the very
 *   top too, which would hide what was just added, so a reader at the very
 *   top is kept there and sees new children come in.
 */
object LazyStackRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val children = node.children
        val gap = (node.layout?.gap ?: 0f).dp
        val contentPadding = PaddingValues(
            start = node.props.getFloat("content_padding_left").dp,
            top = node.props.getFloat("content_padding_top").dp,
            end = node.props.getFloat("content_padding_right").dp,
            bottom = node.props.getFloat("content_padding_bottom").dp,
        )

        val state = rememberLazyListState()
        StayAtTopWhenPrepended(children.firstOrNull()?.id, state)
        HideKeyboardOnDrag(state)

        // A LazyColumn measured with an unbounded height (a lazy stack inside
        // a scroll view) throws, and there would be no viewport to be lazy
        // in anyway. Fall back to a plain column that wraps its children,
        // like the lazy grid does.
        BoxWithConstraints(modifier = modifier) {
            if (constraints.hasBoundedHeight) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    state = state,
                    contentPadding = contentPadding,
                    verticalArrangement = Arrangement.spacedBy(gap),
                ) {
                    items(children, key = { it.id }) { child ->
                        NodeView(node = child)
                    }
                }
            } else {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(contentPadding),
                    verticalArrangement = Arrangement.spacedBy(gap),
                ) {
                    children.forEach { child -> NodeView(node = child) }
                }
            }
        }
    }

    /**
     * When a new first child arrives and the reader was at the very top,
     * ask for the top again in the next measure.
     *
     * This runs in composition, before the LazyColumn measures the new
     * children, so the scroll position it reads is still the one the reader
     * was looking at. After that measure LazyColumn has already moved to keep
     * the old first child, and the reader would no longer look "at the top".
     * The reads skip snapshot observation so scrolling doesn't recompose the
     * stack.
     */
    @Composable
    private fun StayAtTopWhenPrepended(firstId: Int?, state: LazyListState) {
        val lastFirstId = remember { intArrayOf(NO_ID) }
        val previous = lastFirstId[0]
        lastFirstId[0] = firstId ?: NO_ID
        if (firstId == null || previous == NO_ID || firstId == previous) return

        val atTop = Snapshot.withoutReadObservation {
            state.firstVisibleItemIndex == 0 && state.firstVisibleItemScrollOffset <= 1
        }
        if (atTop) state.requestScrollToItem(0)
    }

    /** Dismiss the keyboard when the reader drags the stack, like a scroll view. */
    @Composable
    private fun HideKeyboardOnDrag(state: LazyListState) {
        val keyboard = LocalSoftwareKeyboardController.current
        LaunchedEffect(state, keyboard) {
            state.interactionSource.interactions.collect { interaction ->
                if (interaction is DragInteraction.Start) keyboard?.hide()
            }
        }
    }

    private const val NO_ID = Int.MIN_VALUE
}
