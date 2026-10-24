package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListState
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
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
import androidx.compose.ui.graphics.graphicsLayer
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
import androidx.compose.ui.unit.IntOffset
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
import kotlin.math.abs
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
        val horizontal = p.getBool("horizontal", false)
        // The header and the overlay ride beside the pages; neither is one.
        val pages = remember(node) { node.children.filter { it.type != "pager_header" && it.type != "pager_overlay" } }
        // Only a horizontal pager's pages scroll up and down under a header.
        val header = if (horizontal) node.children.firstOrNull { it.type == "pager_header" } else null
        val overlay = node.children.firstOrNull { it.type == "pager_overlay" }
        val count = p.getInt("count", pages.size).coerceAtLeast(0)
        val windowFrom = p.getInt("window_from", 0)
        // `has_more` appends one loading page after the last loaded item —
        // a feed has no total, so the user can pull into the tail while
        // PHP fetches the next batch. Settling there reports index == count.
        val hasMore = p.getBool("has_more", false)
        val pageCount = if (hasMore) count + 1 else count
        // Image per page index for pages PHP hasn't shipped; "" for none.
        val placeholders = p.getStringList("placeholders")
        val requestedPage = p.getInt("page", 0).coerceIn(0, (pageCount - 1).coerceAtLeast(0))
        val cbId = p.getCallbackId("on_page_change")
        val reportOnSettle = p.getBool("report_on_settle", false)
        val tabs = PagerTabs.from(p)
        val scope = rememberCoroutineScope()

        val pageByIndex: Map<Int, NativeUINode> = remember(node, windowFrom) {
            val out = HashMap<Int, NativeUINode>(pages.size)
            pages.forEachIndexed { offset, child -> out[windowFrom + offset] = child }
            out
        }

        val pagerState = rememberPagerState(initialPage = requestedPage) { pageCount }

        // The pager this one sits in a page of, if any: a page of a page
        // is only available while every pager around it is settled on its
        // page (see PagerPageContext).
        val parentPage = LocalPagerPage.current

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

        val selectTab: (Int) -> Unit = { index ->
            // The tab consumes the tap, so drop the keyboard
            // here unless the focused field keeps focus.
            KeyboardFocusPolicy.dismissForInteractiveTap()
            if (index == pagerState.currentPage && !pagerState.isScrollInProgress) {
                // The tab already showing: PHP decides, usually
                // to take the page back to its top.
                if (tabs != null && tabs.reselectCbId != 0) {
                    NativeElementBridge.sendTabChangeEvent(tabs.reselectCbId, node.id, index)
                }
            } else if (index in 0 until pageCount) {
                // Reported when the pager settles, as for a swipe.
                scope.launch { pagerState.animateScrollToPage(index) }
            }
        }

        // Where the header is, and each page's list, when there's a header.
        val headerScroll = remember { PagerHeaderScroll() }
        if (header != null) {
            LaunchedEffect(pagerState) {
                snapshotFlow { pagerState.currentPage }.collect { headerScroll.lead(it) }
            }
        }
        val background = PagerTabColor(
            node.style?.bgColor?.takeIf { it != 0 },
            if (p.has("dark_bg_color")) p.getColor("dark_bg_color", 0).takeIf { it != 0 } else null,
        )

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
                    // Where the pager is, live, for whatever the page
                    // contains: the pages beside the one showing stay
                    // composed, so a page's contents must not act as the
                    // page showing until the pager settles on it (see
                    // PagerPageContext). Remembered, so the context survives
                    // recomposition and its identity only changes when the
                    // pager or the page around it does.
                    val pageContext = remember(pagerState, index, parentPage) { PagerPageContext(index, pagerState, parentPage) }
                    CompositionLocalProvider(LocalPagerPage provides pageContext) {
                        val child = pageByIndex[index]
                        if (child != null && header != null) {
                            // The page's list draws the header and the tabs (see PagerHeader).
                            CompositionLocalProvider(LocalPagerHeader provides headerScroll.header(index, header, tabs, pagerState, selectTab, background)) {
                                NodeView(node = child)
                            }
                        } else if (child != null) {
                            NodeView(node = child)
                        } else if (hasMore && index >= count) {
                            PagerLoadingPage()
                        } else {
                            PagerPlaceholder(placeholders.getOrNull(index).orEmpty())
                        }
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

            // The overlay hangs under the tabs: under a header, wherever it
            // has scrolled them to.
            val withOverlay: @Composable (Modifier, PagerHeaderScroll?) -> Unit = { pagesModifier, scroll ->
                if (overlay == null) {
                    pages(pagesModifier)
                } else {
                    Box(modifier = pagesModifier) {
                        pages(Modifier.fillMaxSize())
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .offset { IntOffset(0, scroll?.stripBottom()?.roundToInt() ?: 0) },
                        ) { PagerChildren(overlay) }
                    }
                }
            }

            if (header != null) {
                withOverlay(sized.onGloballyPositioned { headerScroll.pagerTop = it.positionInRoot().y }, headerScroll)
            } else if (tabs == null) {
                withOverlay(sized, null)
            } else {
                Column(modifier = sized) {
                    PagerTabStrip(tabs, pagerState, selectTab)
                    withOverlay(Modifier.fillMaxWidth().weight(1f), null)
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
    internal fun PagerTabStrip(tabs: PagerTabs, pagerState: PagerState, onSelect: (Int) -> Unit) {
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
internal class PagerTabs(p: GenericProps) {
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
internal class PagerTabColor(private val light: Int?, private val dark: Int?) {
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

/**
 * A pager's `pager_header`, as one of its pages gets it through
 * [LocalPagerHeader]. The page's list draws it ([ListRenderer]): the header
 * as its first item, then the pager's tabs as a sticky header over every
 * other row, so the tabs pin once the header has scrolled away. Both are
 * held still while the pager swipes, so the pages seem to slide under them.
 *
 * One per page for the life of the pager. A render updates it in place.
 */
@Stable
class PagerHeader internal constructor(
    val page: Int,
    node: NativeUINode,
    internal val scroll: PagerHeaderScroll,
    internal val pagerState: PagerState,
) {
    var node by mutableStateOf(node)
        internal set
    internal var tabs: PagerTabs? = null
    internal var select: (Int) -> Unit = {}
    internal var background = PagerTabColor(null, null)

    val hasTabs: Boolean get() = tabs != null
}

/** The header a page's list draws, if the page is in a pager with one. */
val LocalPagerHeader = compositionLocalOf<PagerHeader?> { null }

/**
 * The pager a page is in, for what the page contains to read: which page
 * this is ([page]) of which pager ([pagerState]), and the same for the
 * pager around that one, if any ([parent]).
 *
 * The pages beside the one showing stay composed
 * (`beyondViewportPageCount = 1`), so a page can be composed without being
 * the page showing. A list on such a page publishes a scroll target
 * (`scroll_target`) that a bottom-tab reselect must not act on until the
 * pager settles back on that page: PHP names the new page a round trip
 * after the swipe, and only the pager itself knows where it is in the
 * meantime. [isAvailable] answers that, read live from the pager's own
 * state — never from a prop PHP sends, which is exactly what lags.
 */
@Stable
class PagerPageContext(
    val page: Int,
    val pagerState: PagerState,
    val parent: PagerPageContext? = null,
) {
    /**
     * The pager is at rest on this page, and every pager around it is at
     * rest on its own: no drag and no settle still running, this page both
     * the nearest one and the one a running gesture targets.
     *
     * All three of the pager's own clauses are needed. [PagerState.targetPage]
     * alone commits as soon as a swipe leans toward a page, so the page
     * being swiped to would count as available while it is still moving;
     * [PagerState.currentPage] adds that this page is the nearest one; and
     * `isScrollInProgress` waits out the whole swipe and settle, so that
     * neither the page being left nor the one arriving is available
     * mid-flight — a reselect during that window must find nothing to act
     * on. Reads are live at whatever moment asks (a tap, a scroll's settle
     * gate), not at composition time: composition can lag the swipe by a
     * frame or two, which is precisely the gap this closes.
     */
    fun isAvailable(): Boolean =
        !pagerState.isScrollInProgress &&
            pagerState.currentPage == page &&
            pagerState.targetPage == page &&
            (parent?.isAvailable() ?: true)
}

/** The page a composable is on, if it is in a pager at all. Null outside one. */
val LocalPagerPage = compositionLocalOf<PagerPageContext?> { null }

/**
 * How far the header has scrolled, from the page showing, and each page's
 * list, so the pages beside it can be kept level with it.
 *
 * While any of the header shows, every list scrolls with it: a swipe finds
 * the next page's header at the same height, so the two meet seamlessly.
 * Once it has gone, each list keeps its own place, and only a list higher
 * than the header has gone is brought down to where it pins the tabs.
 */
@Stable
class PagerHeaderScroll {
    /** The header's height in pixels, without the tabs. */
    var headerHeight by mutableIntStateOf(0)
        internal set
    /** How much of the header has scrolled away, 0 to [headerHeight]. */
    var collapse by mutableFloatStateOf(0f)
        private set
    /** The page the header follows. */
    private var shownPage by mutableIntStateOf(0)
    /** Where each page's tabs end on screen, and where the pager starts, in root pixels. */
    internal val stripBottoms = mutableStateMapOf<Int, Float>()
    internal var pagerTop by mutableFloatStateOf(0f)

    private var leading = 0
    private val lists = HashMap<Int, LazyListState>()
    private val offsets = HashMap<Int, Float>()
    private val headers = HashMap<Int, PagerHeader>()

    internal fun header(page: Int, node: NativeUINode, tabs: PagerTabs?, pagerState: PagerState, select: (Int) -> Unit, background: PagerTabColor): PagerHeader {
        val header = headers.getOrPut(page) { PagerHeader(page, node, this, pagerState) }
        if (header.node !== node) header.node = node
        header.tabs = tabs
        header.select = select
        header.background = background
        return header
    }

    /** Where the bottom of the tabs is, below the pager's top edge, in pixels, as the page showing has them on screen. */
    fun stripBottom(): Float = ((stripBottoms[shownPage] ?: pagerTop) - pagerTop).coerceAtLeast(0f)

    /** The page nearest the pager's leading edge, which the header follows. */
    internal fun lead(page: Int) {
        if (page == leading) return
        leading = page
        shownPage = page
        follow(offsets[page] ?: 0f)
    }

    /** A page's list. A page that isn't showing is brought level with the header before it can be seen. */
    internal fun attach(page: Int, state: LazyListState) {
        lists[page] = state
        offsets[page] = offsetOf(state)
        if (page != leading) align(page)
    }

    internal fun detach(page: Int, state: LazyListState) {
        if (lists[page] === state) lists.remove(page)
    }

    /** A page's list scrolled. */
    internal fun scrolled(page: Int, state: LazyListState) {
        val y = offsetOf(state)
        offsets[page] = y
        if (page == leading) follow(y)
    }

    /** A page's list has more room at its end, so it can be brought level now. */
    internal fun realign(page: Int) {
        if (page != leading) align(page)
    }

    /** How far down its own content a list is: exact while the header shows, past it after. */
    private fun offsetOf(state: LazyListState): Float =
        if (state.firstVisibleItemIndex == 0) state.firstVisibleItemScrollOffset.toFloat() else headerHeight + 1f

    private fun follow(y: Float) {
        val collapse = y.coerceAtMost(headerHeight.toFloat())
        if (collapse == this.collapse) return
        this.collapse = collapse
        for (page in lists.keys) {
            if (page != leading) align(page)
        }
    }

    private fun align(page: Int) {
        val state = lists[page] ?: return
        if (headerHeight <= 0) return

        val own = offsets[page] ?: 0f
        val height = headerHeight.toFloat()
        val target = if (collapse < height) collapse else maxOf(own, height)
        if (abs(target - own) <= 0.5f) return

        offsets[page] = target
        state.requestScrollToItem(0, target.roundToInt())
    }
}

/** The header as a page's list draws it: its first item. */
@Composable
internal fun PagerHeaderRow(header: PagerHeader) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .pagerStationary(header)
            .onSizeChanged { header.scroll.headerHeight = it.height },
    ) {
        CompositionLocalProvider(LocalPagerHeader provides null) {
            PagerChildren(header.node)
        }
    }
}

/** The pager's tabs as a page's list draws them: a sticky header, pinned once the header has gone. */
@Composable
internal fun PagerHeaderStrip(header: PagerHeader) {
    val tabs = header.tabs ?: return
    val isDark = isSystemInDarkTheme()
    val theme = if (isDark) NativeUITheme.dark else NativeUITheme.light

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .pagerStationary(header)
            .background(header.background.resolve(isDark, theme.surface))
            .onGloballyPositioned { header.scroll.stripBottoms[header.page] = it.positionInRoot().y + it.size.height },
    ) {
        PagerRenderer.PagerTabStrip(tabs, header.pagerState, header.select)
    }
}

/**
 * Space after a page's last row, so a short list can still scroll the
 * header away and keep level with the others. Measured from where it sits
 * while the header is on screen; past the header the list is long enough.
 */
@Composable
internal fun PagerHeaderRoom(header: PagerHeader, state: LazyListState, key: Any) {
    val density = LocalDensity.current
    var room by remember { mutableIntStateOf(0) }

    LaunchedEffect(state, header) {
        snapshotFlow {
            val info = state.layoutInfo
            val first = info.visibleItemsInfo.firstOrNull()
            val last = info.visibleItemsInfo.lastOrNull()
            if (first?.index == 0 && last?.key == key) {
                val viewport = info.viewportEndOffset - info.viewportStartOffset
                // Where this item starts in the list's content, without the room it has now.
                val roomTop = last.offset - first.offset
                (viewport + header.scroll.headerHeight - roomTop).coerceAtLeast(0)
            } else {
                null
            }
        }.collect { needed ->
            if (needed != null && needed != room) {
                room = needed
                header.scroll.realign(header.page)
            }
        }
    }

    Spacer(Modifier.fillMaxWidth().height(with(density) { room.toDp() }))
}

/** What a `pager_header` or `pager_overlay` holds, stacked. Their own renderer draws nothing: the pager places them. */
@Composable
private fun PagerChildren(node: NativeUINode) {
    Column(modifier = Modifier.fillMaxWidth()) {
        node.children.forEach { NodeView(node = it) }
    }
}

/**
 * Holds a page's header still while the pager swipes, by moving it against
 * the page, in the draw phase. The pages beside each other are level, so the
 * two headers on screen meet as one.
 */
private fun Modifier.pagerStationary(header: PagerHeader): Modifier = graphicsLayer {
    translationX = (header.pagerState.currentPage + header.pagerState.currentPageOffsetFraction - header.page) * size.width
}
