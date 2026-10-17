package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import coil3.compose.AsyncImage
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.ui.nativerender.GenericProps
import com.nativephp.mobile.ui.nativerender.KeyboardFocusPolicy
import com.nativephp.mobile.ui.nativerender.LocalAvailableHeight
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import com.nativephp.plugins.native_ui.NativeUITheme
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt

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
 * Page-change protocol: `currentPage` → `on_page_change` over the
 * TAB_CHANGE transport (one int), or `settledPage` with
 * `report_on_settle`. The pager position survives re-renders;
 * the `page` prop only moves it when PHP sends an index that differs from
 * the one native last reported (a programmatic jump).
 *
 * With `tabs`, a row of tabs sits above the pages ([PagerTabStrip]). It
 * reads `currentPage` and `currentPageOffsetFraction` as the pager moves,
 * so its indicator follows the swipe and its highlight moves as the swipe
 * passes halfway, without PHP. A tap scrolls the pager there; a tap on the
 * tab already showing goes to PHP as `on_tab_reselect`.
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
        val reportOnSettle = p.getBool("report_on_settle", false)
        val tabs = PagerTabs.from(p)
        val scope = rememberCoroutineScope()

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

        // The page PHP last knew about: the one most recently sent to it, or
        // the one it asked for. Kept apart from `reported`, which an echo
        // empties: the start page used to be reported straight after the
        // pager appeared, and a swipe back to a page PHP had jumped from
        // could go unreported.
        var lastReported by remember { mutableIntStateOf(requestedPage) }

        LaunchedEffect(requestedPage) {
            val at = reported.indexOf(requestedPage)
            if (at >= 0) {
                repeat(at + 1) { reported.removeAt(0) }
            } else {
                reported.clear()
                reported.add(requestedPage)
                lastReported = requestedPage
                pagerState.scrollToPage(requestedPage)
            }
        }

        if (cbId != 0) {
            // `currentPage` flips as soon as a page becomes the nearest one
            // mid-swipe (settledPage waits for rest), so PHP's round-trip
            // overlaps the animation instead of starting after it. With
            // `report_on_settle` the frame the report causes never lands
            // during the animation.
            LaunchedEffect(pagerState, cbId, reportOnSettle) {
                snapshotFlow { if (reportOnSettle) pagerState.settledPage else pagerState.currentPage }
                    .distinctUntilChanged()
                    .collect { index ->
                        if (lastReported != index) {
                            lastReported = index
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

            val pages: @Composable (Modifier) -> Unit = { pagesModifier ->
                if (horizontal) {
                    HorizontalPager(
                        state = pagerState,
                        modifier = pagesModifier,
                        beyondViewportPageCount = 1,
                        key = { it },
                    ) { index -> page(index) }
                } else {
                    VerticalPager(
                        state = pagerState,
                        modifier = pagesModifier,
                        beyondViewportPageCount = 1,
                        key = { it },
                    ) { index -> page(index) }
                }
            }

            if (tabs == null) {
                pages(sized)
            } else {
                Column(modifier = sized) {
                    PagerTabStrip(tabs, pagerState) { index ->
                        // The tab consumes the tap, so drop the keyboard
                        // here unless the focused field keeps focus.
                        KeyboardFocusPolicy.dismissForInteractiveTap()
                        if (index == pagerState.currentPage && !pagerState.isScrollInProgress) {
                            // The tab already showing: PHP decides, usually
                            // to take the page back to its top.
                            if (tabs.reselectCbId != 0) {
                                NativeElementBridge.sendTabChangeEvent(tabs.reselectCbId, node.id, index)
                            }
                        } else if (index in 0 until pageCount) {
                            // Reported when the pager settles, as for a swipe.
                            scope.launch { pagerState.animateScrollToPage(index) }
                        }
                    }
                    pages(Modifier.fillMaxWidth().weight(1f))
                }
            }
        }
    }

    /**
     * The row of tabs above a pager's pages. The indicator is drawn from the
     * pager's position (`currentPage + currentPageOffsetFraction`) between
     * the labels either side of it, in the draw phase, so a swipe redraws it
     * without recomposing. The highlight is `currentPage`, the nearest page,
     * so it moves as the swipe passes halfway. A scrollable row also scrolls
     * itself to keep the indicator in view. Nothing here waits for PHP.
     */
    @Composable
    private fun PagerTabStrip(tabs: PagerTabs, pagerState: PagerState, onSelect: (Int) -> Unit) {
        val isDark = isSystemInDarkTheme()
        val theme = if (isDark) NativeUITheme.dark else NativeUITheme.light
        val density = LocalDensity.current
        val last = tabs.labels.size - 1

        // Each label's left edge and width, and the row's left edge, all in
        // root coordinates, so they can be measured in any order.
        val labelBounds = remember { mutableStateMapOf<Int, Pair<Float, Float>>() }
        var rowLeft by remember { mutableFloatStateOf(0f) }
        var viewportWidth by remember { mutableIntStateOf(0) }
        val scrollState = rememberScrollState()

        // The indicator's left edge in the row and its width: between the
        // labels of the pages either side of the pager's position, in
        // proportion to how far it is from one to the other.
        fun indicator(): Pair<Float, Float>? {
            val position = (pagerState.currentPage + pagerState.currentPageOffsetFraction).coerceIn(0f, last.toFloat())
            val from = floor(position).toInt()
            val to = min(from + 1, last)
            val a = labelBounds[from] ?: return null
            val b = labelBounds[to] ?: return null
            val t = position - from

            return (a.first + (b.first - a.first) * t - rowLeft) to (a.second + (b.second - a.second) * t)
        }

        if (tabs.scrollable) {
            // Keeps the indicator in the middle of the row, as far as the
            // row's ends allow.
            LaunchedEffect(pagerState, tabs.edgePadding) {
                val edge = with(density) { tabs.edgePadding.dp.toPx() }
                snapshotFlow { indicator() to viewportWidth }
                    .collect { (frame, width) ->
                        if (frame != null && width > 0) {
                            val target = edge + frame.first + frame.second / 2 - width / 2f
                            scrollState.scrollTo(target.roundToInt().coerceIn(0, scrollState.maxValue))
                        }
                    }
            }
        }

        val active = pagerState.currentPage.coerceIn(0, last)
        val fontFamily = nuiNodeFontFamily(tabs.font)
        val fontSize = tabs.fontSize?.sp ?: theme.fontMd
        val activeColor = tabs.activeColor.resolve(isDark, theme.onSurface)
        val inactiveColor = tabs.color.resolve(isDark, theme.onSurfaceVariant)
        val indicatorColor = tabs.indicatorColor.resolve(isDark, theme.primary)
        val indicatorHeight = tabs.indicatorHeight.dp

        val row: @Composable () -> Unit = {
            Row(
                modifier = Modifier
                    .then(if (tabs.scrollable) Modifier.padding(horizontal = tabs.edgePadding.dp) else Modifier.fillMaxWidth())
                    .onGloballyPositioned { rowLeft = it.positionInRoot().x }
                    .drawBehind {
                        val (left, width) = indicator() ?: return@drawBehind
                        val height = indicatorHeight.toPx()
                        drawRoundRect(
                            color = indicatorColor,
                            topLeft = Offset(left, size.height - height),
                            size = Size(width, height),
                            cornerRadius = CornerRadius(height / 2),
                        )
                    }
                    .selectableGroup(),
            ) {
                tabs.labels.forEachIndexed { index, label ->
                    val a11yLabel = tabs.a11yLabels.getOrNull(index).orEmpty()

                    Box(
                        modifier = (if (tabs.scrollable) Modifier else Modifier.weight(1f))
                            .heightIn(min = 48.dp)
                            .selectable(selected = index == active, role = Role.Tab, onClick = { onSelect(index) })
                            .then(if (a11yLabel.isNotEmpty()) Modifier.semantics { contentDescription = a11yLabel } else Modifier)
                            .padding(
                                start = tabs.paddingX.dp,
                                end = tabs.paddingX.dp,
                                top = tabs.paddingTop.dp,
                                bottom = tabs.paddingBottom.dp + indicatorHeight,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = label,
                            color = if (index == active) activeColor else inactiveColor,
                            fontSize = fontSize,
                            fontFamily = fontFamily,
                            // A bundled font file is one weight already.
                            fontWeight = if (fontFamily == null) FontWeight.SemiBold else null,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.onGloballyPositioned {
                                labelBounds[index] = it.positionInRoot().x to it.size.width.toFloat()
                            },
                        )
                    }
                }
            }
        }

        Column(modifier = Modifier.fillMaxWidth()) {
            if (tabs.scrollable) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .onSizeChanged { viewportWidth = it.width }
                        .horizontalScroll(scrollState),
                ) { row() }
            } else {
                row()
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(tabs.dividerColor.resolve(isDark, theme.outlineVariant)),
            )
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

/**
 * The `tabs` row and its look, read from the pager's props. Colours are
 * null where PHP sent none, so the row falls back to the theme.
 */
private class PagerTabs(p: GenericProps) {
    val labels: List<String> = p.getStringList("tabs")
    val a11yLabels: List<String> = p.getStringList("tab_a11y_labels")
    val scrollable = p.getBool("tabs_scrollable", false)
    val reselectCbId = p.getCallbackId("on_tab_reselect")
    val color = PagerTabColor.from(p, "tab_color")
    val activeColor = PagerTabColor.from(p, "tab_active_color")
    val indicatorColor = PagerTabColor.from(p, "tab_indicator_color")
    val dividerColor = PagerTabColor.from(p, "tab_divider_color")
    val font = p.getString("tab_font")
    val fontSize: Float? = if (p.has("tab_font_size")) p.getFloat("tab_font_size") else null
    val indicatorHeight = p.getFloat("tab_indicator_height", 3f)
    val paddingX = p.getFloat("tab_padding_x", 12f)
    val paddingTop = p.getFloat("tab_padding_top", 14f)
    val paddingBottom = p.getFloat("tab_padding_bottom", 11f)
    val edgePadding = p.getFloat("tab_edge_padding", 4f)

    companion object {
        fun from(p: GenericProps): PagerTabs? =
            if (p.getStringList("tabs").isEmpty()) null else PagerTabs(p)
    }
}

/** A tab colour PHP sent, with its dark shade when it came from a theme token. */
private class PagerTabColor(private val light: Int?, private val dark: Int?) {
    fun resolve(isDark: Boolean, fallback: Color): Color {
        val argb = if (isDark) dark ?: light else light

        return argb?.let { Color(it) } ?: fallback
    }

    companion object {
        fun from(p: GenericProps, key: String) = PagerTabColor(
            if (p.has(key)) p.getColor(key, 0) else null,
            if (p.has("dark_$key")) p.getColor("dark_$key", 0) else null,
        )
    }
}
