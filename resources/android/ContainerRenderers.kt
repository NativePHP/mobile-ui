package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.MaterialIcon
import com.nativephp.mobile.ui.nativerender.*

object ColumnRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        DefaultContainerNode(node, modifier)
    }
}

object RowRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        DefaultContainerNode(node, modifier)
    }
}

object StackRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        // contentAlignment = Center to match SwiftUI's ZStack default. Without
        // this, Compose Box stacks children at TopStart (upper-left), which
        // diverges from the iOS renderer.
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            node.children.forEach { child ->
                // Stack children may need fill sizing
                var childMod: Modifier = Modifier
                val layout = child.layout
                if (layout != null) {
                    if (layout.widthMode == SizeMode.FILL) childMod = childMod.fillMaxWidth()
                    if (layout.heightMode == SizeMode.FILL) childMod = childMod.fillMaxHeight()
                    if (layout.widthMode == SizeMode.FIXED && layout.width > 0f) childMod = childMod.width(layout.width.dp)
                    if (layout.heightMode == SizeMode.FIXED && layout.height > 0f) childMod = childMod.height(layout.height.dp)

                    // Absolute children pin to the stack's edges by inset —
                    // the docs-blessed "layer a badge over an icon" pattern.
                    // Same anchor convention as ComposeFlexLayout / the iOS
                    // FlexContainer: a NON-ZERO right/bottom inset anchors to
                    // that edge; otherwise offset from top-left. Non-zero (not
                    // positive) so NEGATIVE insets overhang the edge, matching
                    // Tailwind's `-right-8` bleed.
                    if (layout.positionType == PositionType.ABSOLUTE) {
                        val left = layout.positionLeft
                        val top = layout.positionTop
                        val right = layout.positionRight
                        val bottom = layout.positionBottom
                        val anchor = when {
                            right != 0f && bottom != 0f -> Alignment.BottomEnd
                            right != 0f                 -> Alignment.TopEnd
                            bottom != 0f                -> Alignment.BottomStart
                            else                        -> Alignment.TopStart
                        }
                        val offsetX = if (right != 0f) (-right).dp else left.dp
                        val offsetY = if (bottom != 0f) (-bottom).dp else top.dp
                        childMod = childMod.align(anchor).offset(x = offsetX, y = offsetY)
                    }
                }
                NodeView(node = child, overrideModifier = childMod)
            }
        }
    }
}

object PressableRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        if (node.props.getBool("has_menu")) {
            // `:menu` attached — render the pressable's content as the
            // tap target, with a DropdownMenu anchored to the same Box.
            // Tapping the content sets `expanded = true`; the @press
            // callback is shadowed (matches the locked-in spec — menu
            // wins). On platforms with Liquid Glass equivalents, the
            // theme's surface tokens give the menu its translucent look.
            var expanded by remember { mutableStateOf(false) }
            Box(modifier = modifier.clickable { expanded = true }) {
                DefaultContainerNode(node, Modifier)
                ExpressiveMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    node.children
                        .filter { it.type == "top_bar_action" }
                        .forEach { item ->
                            renderAttachedMenuItem(item) { expanded = false }
                        }
                }
            }
        } else {
            DefaultContainerNode(node, modifier)
        }
    }
}

/**
 * M3-Expressive "vertical menu" container. The classic `DropdownMenu`
 * popup (positioning, dismiss, scrim, enter/exit motion) wrapped with the
 * expressive surface treatment: a generously rounded container on the
 * themed `surface` color with a soft shadow — instead of the classic 4dp
 * near-square menu. Shared by all three menu sites (pressable / button /
 * list-item) so they stay identical.
 * See https://m3.material.io/components/menus/specs.
 */
@Composable
internal fun ExpressiveMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest,
        shape = RoundedCornerShape(24.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
        shadowElevation = 6.dp,
        content = content,
    )
}

/// Render one menu item attached to a Pressable / Button / ListItem
/// trailing slot via `:menu` / `:trailing-menu`. Mirrors the pattern in
/// `TopBarActionView` (which handles top-bar action dropdowns).
///
/// Expressive vertical-menu row: an inset, rounded row whose press
/// ripple is a rounded pill (the expressive selection shape) rather than
/// the classic full-bleed rectangle. Leading icon in `onSurfaceVariant`,
/// label in `onSurface` (`error` for destructive). A `divider()` renders
/// as a thin inset rule grouping sections.
@Composable
internal fun renderAttachedMenuItem(item: NativeUINode, onSelected: () -> Unit) {
    if (item.props.getBool("divider")) {
        HorizontalDivider(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
            color = MaterialTheme.colorScheme.outlineVariant,
        )
        return
    }
    val itemLabel = item.props.getString("label", "")
    val itemIcon = item.props.getString("icon", "")
    val isDestructive = item.props.getBool("destructive")

    val labelColor = if (isDestructive) MaterialTheme.colorScheme.error
        else MaterialTheme.colorScheme.onSurface
    val iconColor = if (isDestructive) MaterialTheme.colorScheme.error
        else MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        modifier = Modifier
            .fillMaxWidth()
            // Inset so the rounded press ripple has breathing room from the
            // container edges (the expressive pill look). Clip BEFORE
            // clickable so the ripple is bounded to the rounded shape.
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .clip(RoundedCornerShape(16.dp))
            .clickable {
                onSelected()
                if (item.onPress != 0) {
                    NativeUIBridge.sendPressEvent(item.onPress, item.id)
                }
            }
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (itemIcon.isNotEmpty()) {
            MaterialIcon(
                name = itemIcon,
                contentDescription = itemLabel,
                size = 24.dp,
                tint = iconColor,
            )
        }
        Text(
            itemLabel,
            fontFamily = nuiDefaultFontFamily(),
            color = labelColor,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f),
        )
    }
}

object CanvasRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        DefaultContainerNode(node, modifier.clipToBounds())
    }
}

/**
 * Self-scrolling grid backed by Compose `LazyVerticalGrid` /
 * `LazyHorizontalGrid`. Only the rows currently in (or about to enter)
 * the viewport are composed, so this scales to thousands of cells
 * without paying for them at first paint. Use in place of a manually
 * chunked row-of-row grid whenever the cell count is large enough to
 * matter.
 *
 * When the main axis is UNBOUNDED (the grid sits inside a scroll_view /
 * scrollable column), Compose's lazy grids throw ("measured with an
 * infinity maximum height constraints") where SwiftUI's LazyVGrid just
 * sizes to content — so we fall back to a non-lazy chunked grid that
 * wraps its content. Same visual result, no virtualization.
 */
object LazyGridRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val columns = node.props.getInt("columns", default = 2).coerceAtLeast(1)
        val gap = node.props.getFloat("gap", default = 0f).dp
        val horizontal = node.props.getBool("horizontal")

        // Screen scroll views are LazyColumns, so a grid nested in one is
        // measured with an infinite max on its MAIN axis — the lazy grids
        // throw on that instead of measuring. Lazy composition is
        // meaningless without a bounded viewport anyway, so fall back to a
        // non-lazy chunked grid that wraps its content. Applies to both
        // orientations (a horizontal grid inside a horizontal scroller hits
        // the same wall on width).
        BoxWithConstraints(modifier = modifier) {
            if (horizontal) {
                if (constraints.hasBoundedWidth) {
                    LazyHorizontalGrid(
                        rows = GridCells.Fixed(columns),
                        horizontalArrangement = Arrangement.spacedBy(gap),
                        verticalArrangement = Arrangement.spacedBy(gap),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(node.children, key = { it.id }) { child ->
                            NodeView(node = child)
                        }
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                        node.children.chunked(columns).forEach { columnChildren ->
                            Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                                columnChildren.forEach { child ->
                                    NodeView(node = child)
                                }
                            }
                        }
                    }
                }
            } else {
                if (constraints.hasBoundedHeight) {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(columns),
                        horizontalArrangement = Arrangement.spacedBy(gap),
                        verticalArrangement = Arrangement.spacedBy(gap),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(node.children, key = { it.id }) { child ->
                            NodeView(node = child)
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                        node.children.chunked(columns).forEach { rowChildren ->
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(gap),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                rowChildren.forEach { child ->
                                    Box(modifier = Modifier.weight(1f)) {
                                        NodeView(node = child)
                                    }
                                }
                                repeat(columns - rowChildren.size) {
                                    Spacer(modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Recursive descendant count — a cheap content signal that changes whenever a
 *  message is added anywhere in a scroll-view's subtree (even inside a wrapping
 *  <column>), used to re-trigger stick-to-bottom scrolling. */
private fun totalDescendants(node: NativeUINode): Int {
    var count = node.children.size
    for (child in node.children) {
        count += totalDescendants(child)
    }
    return count
}

object ScrollViewRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val horizontal = node.props.getBool("horizontal")
        val keyboardController = LocalSoftwareKeyboardController.current
        val scrollModifier = modifier.pointerInput(Unit) {
            detectVerticalDragGestures(onDragStart = { keyboardController?.hide() }) { _, _ -> }
        }

        if (horizontal) {
            LazyRow(modifier = modifier) {
                items(node.children, key = { it.id }) { child ->
                    NodeView(node = child)
                }
            }
        } else {
            // Chat-style bottom anchoring (`scroll-anchor="bottom"`): open at
            // the bottom and follow new content. Keyed on the recursive
            // descendant count (not direct children) so it fires even when
            // messages sit inside a wrapping <column> — a common chat layout
            // where the scroll-view has a single child. Scrolling to the last
            // item with a max offset lands at the very bottom regardless of how
            // the content is nested. Hooks are called unconditionally to satisfy
            // Compose's rules; the work is gated on the prop.
            val stickBottom = node.props.getString("scroll_anchor", "") == "bottom"
            val listState = rememberLazyListState()
            val didInitialScroll = remember { mutableStateOf(false) }
            val contentSignal = if (stickBottom) totalDescendants(node) else 0

            LaunchedEffect(stickBottom, contentSignal) {
                if (stickBottom && node.children.isNotEmpty()) {
                    val lastIndex = node.children.size - 1
                    if (!didInitialScroll.value) {
                        didInitialScroll.value = true
                        listState.scrollToItem(lastIndex, Int.MAX_VALUE) // jump on open
                    } else {
                        listState.animateScrollToItem(lastIndex, Int.MAX_VALUE)
                    }
                }
            }

            LazyColumn(modifier = scrollModifier, state = listState) {
                items(node.children, key = { it.id }) { child ->
                    NodeView(node = child)
                }
            }
        }
    }
}
