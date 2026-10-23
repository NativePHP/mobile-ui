package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.foundation.clickable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeScrollTargetRegistry
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Note: `shows_indicators` is accepted for parity with iOS but is a no-op
 * here — LazyColumn/LazyRow draw no scroll indicators to begin with.
 */
object ListRenderer {
    @OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val horizontal = node.props.getBool("horizontal")
        val separator = node.props.getBool("separator")
        val rowColor = node.props.getColor("row_color", 0)
        val rowBackground = if (rowColor != 0) Color(rowColor) else null
        val onRefreshCb = node.props.getCallbackId("on_refresh")
        val onEndReachedCb = node.props.getCallbackId("on_end_reached")
        val endReachedBuffer = node.props.getInt("end_reached_buffer", 3).coerceAtLeast(1)
        val onVisibleRangeCb = node.props.getCallbackId("on_visible_range")
        val visibleRangeStep = node.props.getInt("visible_range_step", 10).coerceAtLeast(1)

        val scrollState = rememberLazyListState()
        // Set when this list is a page of a pager with a header, which the
        // list draws above its rows (see PagerHeader).
        val pagerHeader = if (horizontal) null else LocalPagerHeader.current
        // The key a Tab::onReselect() names to act on this list from a
        // bottom-tab reselect. Absent by default: nothing registers and
        // the list behaves exactly as before the seam. See ListScrollTarget.
        val scrollTarget = node.props.getString("scroll_target", "")
        if (scrollTarget.isNotEmpty()) {
            ListScrollTarget(scrollTarget, scrollState, LocalPagerPage.current)
        }
        // Rows are measured while the list reports its visible range: that's
        // what a list putting placeholders in rows' places goes by.
        val rowHeights = remember { ListRowHeights() }
        val heights = if (onVisibleRangeCb != 0) rowHeights else null
        val isRefreshing = remember { mutableStateOf(false) }
        val endReachedFired = remember { mutableStateOf(false) }

        // Detect end reached — fire when within the configured number of items of the bottom
        if (onEndReachedCb != 0) {
            LaunchedEffect(scrollState) {
                snapshotFlow {
                    val info = scrollState.layoutInfo
                    val lastVisible = info.visibleItemsInfo.lastOrNull()?.index ?: 0
                    // Under a pager header, the room after the rows isn't one.
                    val total = info.totalItemsCount - if (pagerHeader != null) 1 else 0
                    total > 0 && lastVisible >= total - endReachedBuffer
                }.collect { nearEnd ->
                    if (nearEnd && !endReachedFired.value) {
                        endReachedFired.value = true
                        NativeElementBridge.sendPressEvent(onEndReachedCb, node.id)
                    } else if (!nearEnd) {
                        endReachedFired.value = false
                    }
                }
            }
        }

        if (pagerHeader != null) {
            DisposableEffect(pagerHeader, scrollState) {
                pagerHeader.scroll.attach(pagerHeader.page, scrollState)
                onDispose { pagerHeader.scroll.detach(pagerHeader.page, scrollState) }
            }
            LaunchedEffect(pagerHeader, scrollState) {
                snapshotFlow { scrollState.firstVisibleItemIndex to scrollState.firstVisibleItemScrollOffset }
                    .collect { pagerHeader.scroll.scrolled(pagerHeader.page, scrollState) }
            }
        }

        if (onVisibleRangeCb != 0) {
            // Positions count rows as iOS does: a section's rows in its place,
            // headers and footers not at all. Read from the frame showing when
            // it reports, so a row inserted above the screen doesn't leave them stale.
            val leafIndex = rememberUpdatedState(remember(node) { leafRowIndex(node.children) })
            LaunchedEffect(scrollState, onVisibleRangeCb, visibleRangeStep) {
                fun currentRange(): Pair<Int, Int>? {
                    val indexes = scrollState.layoutInfo.visibleItemsInfo.mapNotNull { leafIndex.value[it.key] }
                    val first = indexes.minOrNull() ?: return null
                    return first to (indexes.maxOrNull() ?: first)
                }
                // The list starts at the top, so a range near it isn't reported until it moves a step.
                var reported = 0 to 0
                var reportedAt = 0L
                snapshotFlow { currentRange() }.collect { range ->
                    if (range == null) return@collect
                    val moved = kotlin.math.abs(range.first - reported.first) >= visibleRangeStep ||
                        kotlin.math.abs(range.second - reported.second) >= visibleRangeStep
                    if (!moved) return@collect
                    // No more than every 150ms while scrolling, with the latest range at the end of it.
                    val wait = reportedAt + VISIBLE_RANGE_INTERVAL_MS - System.currentTimeMillis()
                    if (wait > 0) delay(wait)
                    val latest = currentRange() ?: return@collect
                    reported = latest
                    reportedAt = System.currentTimeMillis()
                    NativeElementBridge.sendTextChangeEvent(onVisibleRangeCb, node.id, "${latest.first},${latest.second}")
                }
            }
        }

        val keyboardController = LocalSoftwareKeyboardController.current
        val dismissKeyboardModifier = Modifier.pointerInput(Unit) {
            detectVerticalDragGestures(onDragStart = { keyboardController?.hide() }) { _, _ -> }
        }

        val listContent: @Composable () -> Unit = {
            if (horizontal) {
                LazyRow(modifier = if (onRefreshCb != 0) Modifier else modifier, state = scrollState) {
                    node.children.forEachIndexed { index, child ->
                        item(key = child.id) {
                            NodeView(node = child)
                        }
                    }
                }
            } else if (pagerHeader != null) {
                LazyColumn(modifier = (if (onRefreshCb != 0) Modifier else modifier).then(dismissKeyboardModifier), state = scrollState) {
                    // The header, then the pager's tabs pinned over every row,
                    // the rows of any list sections among them.
                    item(key = PAGER_HEADER_KEY) { PagerHeaderRow(pagerHeader) }
                    if (pagerHeader.hasTabs) {
                        stickyHeader(key = PAGER_TABS_KEY) { PagerHeaderStrip(pagerHeader) }
                    }
                    val rows = node.children.flatMap { if (it.type == "list_section") it.children else listOf(it) }
                    rows.forEachIndexed { index, row ->
                        item(key = row.id) {
                            // Only this list draws the header, not one in its rows.
                            CompositionLocalProvider(LocalPagerHeader provides null) { ListRow(row, heights, rowBackground) }
                            if (separator && index < rows.size - 1) {
                                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                            }
                        }
                    }
                    item(key = PAGER_ROOM_KEY) { PagerHeaderRoom(pagerHeader, scrollState, PAGER_ROOM_KEY) }
                }
            } else {
                // A list is "sectioned" when any direct child is a
                // `list_section`. Sectioned lists adopt the inset-grouped
                // card look by default (mirroring iOS `.insetGrouped`);
                // `->plain()` keeps flat rows with plain sticky headers.
                val hasSections = node.children.any { it.type == "list_section" }
                val grouped = hasSections && !node.props.getBool("plain")

                LazyColumn(modifier = (if (onRefreshCb != 0) Modifier else modifier).then(dismissKeyboardModifier), state = scrollState) {
                    node.children.forEachIndexed { index, child ->
                        if (child.type == "list_section") {
                            val header = child.props.getString("header", "")
                            val footer = child.props.getString("footer", "")
                            if (header.isNotEmpty() && grouped) {
                                // iOS `.insetGrouped` headers scroll with their
                                // section and paint nothing; only plain-style
                                // headers pin. A pinned, opaque header here
                                // showed as a coloured band on any screen whose
                                // background differs from the theme's.
                                item(key = "h_${child.id}") { SectionHeader(header, pinned = false) }
                            } else if (header.isNotEmpty()) {
                                stickyHeader(key = "h_${child.id}") { SectionHeader(header, pinned = true) }
                            } else if (grouped) {
                                // A headerless grouped section still needs the gap a
                                // header's top padding would have given it — otherwise
                                // its card butts against the previous section's card
                                // (iOS `.insetGrouped` always spaces sections).
                                item(key = "s_${child.id}") { SectionGap() }
                            }
                            child.children.forEachIndexed { i, row ->
                                item(key = row.id) {
                                    if (grouped) {
                                        SectionRow(
                                            isFirst = i == 0,
                                            isLast = i == child.children.size - 1,
                                            background = rowBackground,
                                        ) { ListRow(row, heights) }
                                    } else {
                                        ListRow(row, heights, rowBackground)
                                        if (separator && i < child.children.size - 1) {
                                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                                        }
                                    }
                                }
                            }
                            if (footer.isNotEmpty()) {
                                item(key = "f_${child.id}") { SectionFooter(footer, grouped) }
                            }
                        } else if (child.type == "sticky_header" && !hasSections) {
                            // Pins once it reaches the top, until the next
                            // sticky header pushes it off, as on iOS. It
                            // paints its own background, if any.
                            stickyHeader(key = child.id) { NodeView(node = child) }
                        } else {
                            item(key = child.id) {
                                ListRow(child, heights, rowBackground)
                                if (separator && index < node.children.size - 1) {
                                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Pull-to-refresh wrapper
        if (onRefreshCb != 0) {
            val refreshState = rememberPullToRefreshState()

            val coroutineScope = androidx.compose.runtime.rememberCoroutineScope()

            PullToRefreshBox(
                isRefreshing = isRefreshing.value,
                onRefresh = {
                    isRefreshing.value = true
                    NativeElementBridge.sendPressEvent(onRefreshCb, node.id)
                    coroutineScope.launch {
                        delay(1500)
                        isRefreshing.value = false
                    }
                },
                state = refreshState,
                modifier = modifier
            ) {
                listContent()
            }
        } else {
            listContent()
        }
    }
}

/** How long a list waits between reports of its visible range while scrolling. */
private const val VISIBLE_RANGE_INTERVAL_MS = 150L

/**
 * Publishes [state] under [key] in the core [NativeScrollTargetRegistry]
 * while the list that owns it is composed — the list's half of the
 * bottom-tab reselect scroll seam. A reselect that names [key] scrolls
 * the list back to its top from native (no PHP round trip), or fires
 * its refresh method when the list already sits at exact top; see the
 * registry's docs for the seam. Android only — iOS ignores the prop.
 *
 * The effect is keyed on [state] as well as [key]: when a re-keyed or
 * remounted list gets a fresh `rememberLazyListState`, the entry is
 * re-registered against the new one, so no entry ever points at a
 * disposed state. `owner` is a fresh token per composition and the
 * registry unregisters by identity, so the stale `onDispose` of a
 * composition a newer one already replaced (a pager page recomposed
 * under a different list key) can never remove the live entry — only
 * its own.
 *
 * A list on a page of a pager ([page] from [LocalPagerPage]) only
 * publishes while its page is the one the pager is settled on: the pages
 * beside the one showing stay composed and would otherwise each answer
 * the same reselect, and PHP names the new page only a round trip after
 * the swipe. Two layers keep that true, one at each end of the registry:
 *
 * - The map: a list whose page is not the one showing holds no entry at
 *   all. Nothing registers while `active` is false, the dispose a page
 *   going away triggers unregisters, and a register under a key replaces
 *   whatever entry was there (the newest composition wins).
 * - The read: the registry's `get` consults the live `isAvailable`
 *   predicate at read time — a bottom-tab tap, or a scroll's settle gate —
 *   never at composition time, so an entry still present in the map
 *   during the frame or two between a swipe and this effect applying is
 *   filtered out all the same. To a caller an absent entry and an
 *   unavailable one are indistinguishable: both read as nothing to act
 *   on.
 *
 * Keying the effect on [active] also invalidates the entry's identity
 * when a page goes away and returns: the re-registered entry is a fresh
 * one, so the core settle gate's identity check cannot match a scroll
 * that started before the round trip.
 *
 * A list outside any pager passes `page = null` and registers exactly as
 * before the seam: always, with availability that reads true.
 *
 * Both orientations register, and "top" is the start of the list: item
 * 0 at a zero pixel offset, vertically or horizontally.
 */
@Composable
private fun ListScrollTarget(key: String, state: LazyListState, page: PagerPageContext?) {
    // Read here, in composition, so the pager's page flips are observed
    // and the effect below restarts when this page stops or starts being
    // the one showing. The boolean only flips on page changes — never
    // per frame — so the entry is not churned while the pager rests.
    val active = page?.isAvailable() ?: true
    val owner = remember { Any() }
    // `page` is keyed too: the context is remembered per pager and page,
    // so its identity only changes when the pager or the pager around it
    // does — without the key the registered predicate could go on reading
    // a context from a pager that has been replaced.
    DisposableEffect(key, state, page, active) {
        if (active) {
            NativeScrollTargetRegistry.register(
                key = key,
                owner = owner,
                isAtTop = { state.firstVisibleItemIndex == 0 && state.firstVisibleItemScrollOffset == 0 },
                scrollToTop = { state.animateScrollToItem(0) },
                isAvailable = { page?.isAvailable() ?: true },
            )
        }
        onDispose { NativeScrollTargetRegistry.unregister(key, owner) }
    }
}

/**
 * The height each row of a list last drew at, in pixels, by node id. A
 * node's id comes from its key, so a placeholder with a row's key finds the
 * row's height. Not snapshot state: a row measuring itself doesn't recompose
 * the list.
 */
private class ListRowHeights {
    private val heights = HashMap<Int, Int>()
    private var total = 0L

    fun height(rowId: Int): Int? = heights[rowId]

    /** The average row, for a placeholder whose row was never drawn. */
    val typical: Int? get() = if (heights.isEmpty()) null else (total / heights.size).toInt()

    fun set(rowId: Int, height: Int) {
        total += height - (heights[rowId] ?: 0)
        heights[rowId] = height
    }
}

/** Each leaf row's position: a section's rows in its place, counted as on iOS. */
private fun leafRowIndex(children: List<NativeUINode>): Map<Any, Int> {
    val map = HashMap<Any, Int>()
    var counter = 0
    for (child in children) {
        if (child.type == "list_section") {
            for (row in child.children) map[row.id] = counter++
        } else if (child.type != "sticky_header") {
            // A sticky header isn't a row, as on iOS.
            map[child.id] = counter++
        }
    }
    return map
}

/**
 * One list row, measured into [heights] when the list keeps them, or an
 * empty box at the height its row last drew at when it's a placeholder,
 * on the list's row colour like the row it stands in for.
 */
@Composable
private fun ListRow(child: NativeUINode, heights: ListRowHeights?, background: Color? = null) {
    if (child.type == "list_placeholder") {
        val estimated = child.props.getFloat("estimated_height", 0f)
        val density = LocalDensity.current
        val height = heights?.height(child.id)?.let { with(density) { it.toDp() } }
            ?: if (estimated > 0f) estimated.dp else heights?.typical?.let { with(density) { it.toDp() } } ?: 44.dp
        val fill = if (background != null) Modifier.background(background) else Modifier
        Spacer(Modifier.fillMaxWidth().height(height).then(fill))
    } else if (heights != null) {
        Box(Modifier.onSizeChanged { heights.set(child.id, it.height) }) { NodeRow(child, background) }
    } else {
        NodeRow(child, background)
    }
}

/**
 * One list row: the node plus its leading/trailing swipe actions. Shared
 * by flat rows and section children so the swipe behaviour is identical
 * in both. The legacy single `on_swipe_delete` callback maps to a single
 * destructive trailing action when no structured actions are present.
 */
@Composable
private fun NodeRow(child: NativeUINode, background: Color? = null) {
    val legacyDeleteCb = child.props.getCallbackId("on_swipe_delete")
    val leading = decodeSwipeActions(child.props.getString("leading_actions_json", ""))
    val trailing = decodeSwipeActions(child.props.getString("trailing_actions_json", ""))

    val effectiveTrailing = if (trailing.isNotEmpty()) trailing
        else if (legacyDeleteCb != 0) listOf(SwipeAction(legacyDeleteCb, "Delete", "delete", "", "#DC2626", "destructive"))
        else emptyList()

    if (leading.isNotEmpty() || effectiveTrailing.isNotEmpty()) {
        SwipeActionsRow(
            nodeKey = child.id,
            leading = leading,
            trailing = effectiveTrailing,
            onAction = { cb -> NativeElementBridge.sendPressEvent(cb, child.id) }
        ) {
            RowContent(child, background)
        }
    } else {
        RowContent(child, background)
    }
}

/** The row's node, on the list's row colour when it declares one. */
@Composable
private fun RowContent(child: NativeUINode, background: Color?) {
    if (background != null) {
        Box(Modifier.fillMaxWidth().background(background)) { NodeView(node = child) }
    } else {
        NodeView(node = child)
    }
}

/** Keys of the items a list adds under a pager header. Row keys are node ids, so these can't clash. */
private const val PAGER_HEADER_KEY = "nui_pager_header"
private const val PAGER_TABS_KEY = "nui_pager_tabs"
private const val PAGER_ROOM_KEY = "nui_pager_room"

/** Space above a section: a header's top padding, or a bare gap without one. */
private val SECTION_TOP_GAP = 20.dp

/**
 * A section header — a small uppercase label. In a plain list it pins to
 * the top while the section's rows scroll beneath it (mirroring SwiftUI's
 * sticky plain-style header), so it gets an opaque background to keep rows
 * from showing through. In a grouped list it scrolls with its section and
 * paints nothing, as on iOS.
 */
@Composable
private fun SectionHeader(text: String, pinned: Boolean) {
    Box(
        Modifier
            .fillMaxWidth()
            .then(if (pinned) Modifier.background(MaterialTheme.colorScheme.background) else Modifier)
            .padding(start = 16.dp, end = 16.dp, top = SECTION_TOP_GAP, bottom = 6.dp)
    ) {
        Text(
            text = text.uppercase(),
            fontFamily = nuiDefaultFontFamily(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.5.sp,
        )
    }
}

/** The breathing room above a grouped section that has no header to provide it. */
@Composable
private fun SectionGap() {
    Spacer(Modifier.fillMaxWidth().height(SECTION_TOP_GAP))
}

/**
 * One row inside an inset-grouped section. Rows share a continuous
 * `surfaceVariant` card (no vertical gaps between LazyColumn items), with
 * the first row rounding its top corners and the last its bottom corners.
 * Inset separators sit inside the card between rows — hand-rolling the
 * look SwiftUI's `.insetGrouped` gives for free.
 */
@Composable
private fun SectionRow(isFirst: Boolean, isLast: Boolean, background: Color? = null, content: @Composable () -> Unit) {
    val radius = 12.dp
    val shape = RoundedCornerShape(
        topStart = if (isFirst) radius else 0.dp,
        topEnd = if (isFirst) radius else 0.dp,
        bottomStart = if (isLast) radius else 0.dp,
        bottomEnd = if (isLast) radius else 0.dp,
    )
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(background ?: MaterialTheme.colorScheme.surfaceVariant)
        ) {
            content()
            if (!isLast) {
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant,
                    modifier = Modifier.padding(start = 16.dp),
                )
            }
        }
    }
}

/** A section's optional footer — small muted caption under the group. */
@Composable
private fun SectionFooter(text: String, grouped: Boolean) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = if (grouped) 24.dp else 16.dp, end = 16.dp, top = 6.dp, bottom = 12.dp)
    ) {
        Text(
            text = text,
            fontFamily = nuiDefaultFontFamily(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 12.sp,
        )
    }
}

/** Decoded swipe-action spec — one button on either edge. */
internal data class SwipeAction(
    val cb: Int,
    val label: String,
    val icon: String,         // resolved per-platform (Material name on Android)
    val iconVariant: String,  // "filled" / "outlined" / "" (Material font variant)
    val tint: String,         // hex string like "#10B981" or "" for default
    val role: String,         // "destructive" or ""
)

internal fun decodeSwipeActions(json: String): List<SwipeAction> {
    if (json.isEmpty()) return emptyList()
    return try {
        val arr = org.json.JSONArray(json)
        (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            SwipeAction(
                cb = o.optInt("cb", 0),
                label = o.optString("label", ""),
                icon = o.optString("icon", ""),
                iconVariant = o.optString("icon_variant", ""),
                tint = o.optString("tint", ""),
                role = o.optString("role", ""),
            )
        }.filter { it.cb != 0 }
    } catch (_: Exception) {
        emptyList()
    }
}

private fun parseHexColor(hex: String, fallback: Color): Color {
    val s = hex.trim().removePrefix("#")
    if (s.length != 6) return fallback
    return try {
        val v = s.toLong(16)
        Color(
            red = ((v shr 16) and 0xFF) / 255f,
            green = ((v shr 8) and 0xFF) / 255f,
            blue = (v and 0xFF) / 255f,
        )
    } catch (_: Exception) {
        fallback
    }
}

/**
 * Bi-directional swipe-actions row. Drag right to reveal `leading`
 * actions; drag left to reveal `trailing`. Tap an action button to
 * fire its callback. Destructive trailing actions allow full-swipe
 * dismiss (matching iOS `.swipeActions(allowsFullSwipe: true)`).
 *
 * Mirrors SwiftUI's `.swipeActions` semantics as closely as we can
 * without a Material 3 primitive — Compose Material doesn't ship a
 * multi-action swipe-reveal, so we roll our own with `pointerInput +
 * detectHorizontalDragGestures` and animated offset.
 */
@Composable
private fun SwipeActionsRow(
    nodeKey: Any,
    leading: List<SwipeAction>,
    trailing: List<SwipeAction>,
    onAction: (Int) -> Unit,
    content: @Composable () -> Unit,
) {
    val actionWidth = 80.dp
    val density = androidx.compose.ui.platform.LocalDensity.current
    val actionWidthPx = with(density) { actionWidth.toPx() }

    val leadingMaxPx = actionWidthPx * leading.size
    val trailingMaxPx = -(actionWidthPx * trailing.size)

    val offsetX = remember(nodeKey) { mutableStateOf(0f) }
    val animatedOffset = animateFloatAsState(targetValue = offsetX.value, label = "swipe")
    val offsetDp = with(density) { animatedOffset.value.toDp() }

    // The outer Box's height is driven by the foreground content
    // (the list-item row). Drawers use `matchParentSize()` so they
    // adopt the content row's height rather than pushing it taller —
    // without that, `fillMaxSize()` on the drawers + their buttons
    // created unbounded height demands and left huge gaps between
    // rows. Compose's `matchParentSize` opts the child out of the
    // parent's measurement pass, sizing it AFTER the parent is sized
    // by the foreground content.
    Box(
        Modifier
            .fillMaxWidth()
            .clipToBounds()
    ) {
        if (leading.isNotEmpty()) {
            androidx.compose.foundation.layout.Row(
                Modifier.matchParentSize(),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.Start,
            ) {
                leading.forEach { action ->
                    SwipeActionButton(action, actionWidth) {
                        offsetX.value = 0f
                        onAction(action.cb)
                    }
                }
            }
        }
        if (trailing.isNotEmpty()) {
            androidx.compose.foundation.layout.Row(
                Modifier.matchParentSize(),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.End,
            ) {
                trailing.forEach { action ->
                    SwipeActionButton(action, actionWidth) {
                        offsetX.value = 0f
                        onAction(action.cb)
                    }
                }
            }
        }

        Box(
            Modifier
                .fillMaxWidth()
                .offset(x = offsetDp)
                // Opaque theme surface (not hardcoded white) so the action
                // drawers stay hidden behind the row in dark mode too.
                .background(MaterialTheme.colorScheme.surface)
                .pointerInput(nodeKey) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            val pos = offsetX.value
                            offsetX.value = when {
                                pos > leadingMaxPx / 2  -> leadingMaxPx
                                pos < trailingMaxPx / 2 -> trailingMaxPx
                                else                    -> 0f
                            }
                        },
                        onHorizontalDrag = { _, dragAmount ->
                            offsetX.value = (offsetX.value + dragAmount)
                                .coerceIn(trailingMaxPx, leadingMaxPx)
                        }
                    )
                }
        ) {
            content()
        }
    }
}

@Composable
private fun SwipeActionButton(
    action: SwipeAction,
    width: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
) {
    val defaultBg = if (action.role == "destructive") Color(0xFFDC2626) else Color(0xFF6366F1)
    val bg = if (action.tint.isNotEmpty()) parseHexColor(action.tint, defaultBg) else defaultBg

    Box(
        Modifier
            .fillMaxHeight()
            .width(width)
            .background(bg)
            .clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        androidx.compose.foundation.layout.Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(2.dp),
        ) {
            if (action.icon.isNotEmpty()) {
                com.nativephp.mobile.ui.MaterialIcon(
                    name = action.icon,
                    contentDescription = action.label.ifEmpty { null },
                    size = 22.dp,
                    tint = Color.White,
                )
            }
            if (action.label.isNotEmpty()) {
                Text(
                    text = action.label,
                    fontFamily = nuiDefaultFontFamily(),
                    color = Color.White,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    fontSize = 12.sp,
                )
            }
        }
    }
}
