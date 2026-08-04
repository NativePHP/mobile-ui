package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
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
        val onRefreshCb = node.props.getCallbackId("on_refresh")
        val onEndReachedCb = node.props.getCallbackId("on_end_reached")

        val scrollState = rememberLazyListState()
        val isRefreshing = remember { mutableStateOf(false) }
        val endReachedFired = remember { mutableStateOf(false) }

        // Detect end reached — fire when within 3 items of the bottom
        if (onEndReachedCb != 0) {
            LaunchedEffect(scrollState) {
                snapshotFlow {
                    val info = scrollState.layoutInfo
                    val lastVisible = info.visibleItemsInfo.lastOrNull()?.index ?: 0
                    val total = info.totalItemsCount
                    total > 0 && lastVisible >= total - 3
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
                            if (header.isNotEmpty()) {
                                stickyHeader(key = "h_${child.id}") { SectionHeader(header) }
                            }
                            child.children.forEachIndexed { i, row ->
                                item(key = row.id) {
                                    if (grouped) {
                                        SectionRow(
                                            isFirst = i == 0,
                                            isLast = i == child.children.size - 1,
                                        ) { ListRow(row) }
                                    } else {
                                        ListRow(row)
                                        if (separator && i < child.children.size - 1) {
                                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                                        }
                                    }
                                }
                            }
                            if (footer.isNotEmpty()) {
                                item(key = "f_${child.id}") { SectionFooter(footer, grouped) }
                            }
                        } else {
                            item(key = child.id) {
                                ListRow(child)
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

/**
 * One list row: the node plus its leading/trailing swipe actions. Shared
 * by flat rows and section children so the swipe behaviour is identical
 * in both. The legacy single `on_swipe_delete` callback maps to a single
 * destructive trailing action when no structured actions are present.
 */
@Composable
private fun ListRow(child: NativeUINode) {
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
            NodeView(node = child)
        }
    } else {
        NodeView(node = child)
    }
}

/**
 * A section's sticky header — a small uppercase label that pins to the
 * top while the section's rows scroll beneath it (mirroring SwiftUI's
 * sticky `Section` header). The opaque background keeps rows from
 * showing through while pinned.
 */
@Composable
private fun SectionHeader(text: String) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 6.dp)
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

/**
 * One row inside an inset-grouped section. Rows share a continuous
 * `surfaceVariant` card (no vertical gaps between LazyColumn items), with
 * the first row rounding its top corners and the last its bottom corners.
 * Inset separators sit inside the card between rows — hand-rolling the
 * look SwiftUI's `.insetGrouped` gives for free.
 */
@Composable
private fun SectionRow(isFirst: Boolean, isLast: Boolean, content: @Composable () -> Unit) {
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
                .background(MaterialTheme.colorScheme.surfaceVariant)
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
