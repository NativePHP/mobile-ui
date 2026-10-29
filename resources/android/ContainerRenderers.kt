package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpOffset
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
                    // Same anchor convention as the iOS stack renderer: +0.0
                    // means unset, non-zero anchors (negatives overhang —
                    // `-right-8` bleed), and IEEE -0.0 is an authored explicit
                    // zero (`bottom-0`), which anchors to that edge too. When
                    // both edges are authored, left/top win (CSS precedence).
                    if (layout.positionType == PositionType.ABSOLUTE) {
                        val left = layout.positionLeft
                        val top = layout.positionTop
                        val right = layout.positionRight
                        val bottom = layout.positionBottom
                        // -0.0f == 0f in Kotlin, so authored zeros need the
                        // raw sign bit.
                        fun isSet(v: Float) = v != 0f || v.toRawBits() != 0
                        val anchorEnd = isSet(right) && !isSet(left)
                        val anchorBottom = isSet(bottom) && !isSet(top)
                        val anchor = when {
                            anchorEnd && anchorBottom -> Alignment.BottomEnd
                            anchorEnd                 -> Alignment.TopEnd
                            anchorBottom              -> Alignment.BottomStart
                            else                      -> Alignment.TopStart
                        }
                        val offsetX = if (anchorEnd) (-right).dp else left.dp
                        val offsetY = if (anchorBottom) (-bottom).dp else top.dp
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
        } else if (node.props.getBool("has_context_menu")) {
            ContextMenuPressable(node, modifier)
        } else {
            DefaultContainerNode(node, modifier)
        }
    }

    /**
     * `:context-menu` attached — the same items as `:menu`, opened by a
     * long press, with the long-press haptic, from where the finger is.
     * The tap stays core's `@press`: its clickable is already on
     * `modifier`, and the long press is watched from outside it, so a
     * tap goes through untouched while a long press takes the rest of
     * the touch and the clickable never fires.
     */
    @Composable
    private fun ContextMenuPressable(node: NativeUINode, modifier: Modifier) {
        var expanded by remember { mutableStateOf(false) }
        var menuOffset by remember { mutableStateOf(DpOffset.Zero) }
        val anchor = remember { MenuAnchor() }
        val haptics = LocalHapticFeedback.current
        val density = LocalDensity.current
        val open = { offset: DpOffset ->
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            menuOffset = offset
            expanded = true
        }

        Box(
            modifier = Modifier
                .onGloballyPositioned { anchor.outer = it }
                .longPress { position -> open(anchor.offsetOf(position, density)) }
                // Outside core's semantics too, which an `a11y-label`
                // clears inside, so TalkBack can always open the menu.
                // Its long press has no finger, so the menu hangs below.
                .semantics { onLongClick { open(DpOffset.Zero); true } }
                .then(modifier)
                .onGloballyPositioned { anchor.inner = it },
            propagateMinConstraints = true,
        ) {
            DefaultContainerNode(node, Modifier)
            ExpressiveMenu(expanded = expanded, onDismissRequest = { expanded = false }, offset = menuOffset) {
                node.children
                    .filter { it.type == "top_bar_action" }
                    .forEach { item ->
                        renderAttachedMenuItem(item) { expanded = false }
                    }
            }
        }
    }

    /**
     * Calls [onLongPress] once a finger has rested for the long-press
     * timeout without lifting or moving past the touch slop, then eats
     * the rest of that touch. It watches the Initial pass, ahead of the
     * clickable and any scrolling list it's in, and consumes nothing
     * until then, so taps and scrolls behave as if it weren't there.
     */
    private fun Modifier.longPress(onLongPress: (Offset) -> Unit): Modifier =
        pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                val endedEarly = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                    while (true) {
                        val change = awaitPointerEvent(PointerEventPass.Initial).changes
                            .firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed || change.isConsumed ||
                            (change.position - down.position).getDistance() > viewConfiguration.touchSlop
                        ) {
                            break
                        }
                    }
                    true
                }
                if (endedEarly != null) return@awaitEachGesture

                onLongPress(down.position)
                do {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    event.changes.forEach { it.consume() }
                } while (event.changes.any { it.pressed })
            }
        }
}

/**
 * Where a long press landed, for a context menu to open there. A dropdown
 * hangs from the bottom edge of the bounds it's composed in, which sit
 * inside the pressable's padding, while the press is measured from the
 * pressable's outer edge, so the offset goes through both coordinates.
 */
private class MenuAnchor {
    var outer: LayoutCoordinates? = null
    var inner: LayoutCoordinates? = null

    fun offsetOf(position: Offset, density: Density): DpOffset {
        val outer = outer
        val inner = inner

        if (outer == null || inner == null || !outer.isAttached || !inner.isAttached) {
            return DpOffset.Zero
        }

        val at = inner.localPositionOf(outer, position)

        return with(density) { DpOffset(at.x.toDp(), (at.y - inner.size.height).toDp()) }
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
    offset: DpOffset = DpOffset.Zero,
    content: @Composable ColumnScope.() -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest,
        offset = offset,
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
 * `shows_indicators` is accepted for parity with iOS but is a no-op
 * here — Compose's lazy grids draw no scroll indicators to begin with.
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

/**
 * The author's declared intent: the index passed to
 * `ScrollView::autoScrollTo($index)`, or `-1` when they aren't driving the
 * scroll position at all (prop absent, or negative).
 *
 * Deliberately independent of the children, so that precedence over
 * `scroll-anchor` doesn't flicker while a list fills in.
 */
private fun autoScrollRequest(node: NativeUINode): Int {
    val requested = node.props.getInt("auto_scroll_to", -1)

    return if (requested < 0) -1 else requested
}

/**
 * The child to actually bring into view, or `-1` when there is nothing to
 * scroll to yet.
 *
 * An index past the end is IGNORED, not clamped. Clamping looked like a
 * kindness — land on the last child now, correct it later — but it ties the
 * scroll to a row that moves whenever the CONTENT does rather than when the
 * author's intent does. Removing rows then drags a reader down to the new end,
 * and a list streaming in scrolls repeatedly on its way to a target it hasn't
 * reached. Ignoring the index keeps the useful half: nothing happens until the
 * named child exists, and then the list goes there exactly once.
 */
private fun resolveAutoScrollTarget(node: NativeUINode): Int {
    val requested = autoScrollRequest(node)

    return if (requested >= node.children.size) -1 else requested
}

/**
 * Animates the list to [index] and lets a collapsing top bar follow it.
 *
 * Compose only moves the bar on nested-scroll deltas, and a programmatic
 * scroll emits none, so a chat log scrolling itself to a new message left a
 * large title fully expanded. When the list ends up further down than it
 * started, ask the bar to collapse as well. A list that couldn't move, or
 * that moved back up, leaves the bar where it is, since the controller can
 * only collapse.
 *
 * Compared after the scroll rather than predicted before it: a message that
 * has just arrived isn't measured yet, so `canScrollForward` would still say
 * a list sitting at the bottom can't move.
 */
private suspend fun LazyListState.animateScrollFollowingChrome(
    index: Int,
    scrollOffset: Int,
    chrome: ChromeScrollController?,
) {
    val startIndex = firstVisibleItemIndex
    val startOffset = firstVisibleItemScrollOffset

    animateScrollToItem(index, scrollOffset)

    val movedDown = firstVisibleItemIndex > startIndex ||
        (firstVisibleItemIndex == startIndex && firstVisibleItemScrollOffset > startOffset)

    if (movedDown) {
        chrome?.collapse()
    }
}

/**
 * Drives a lazy list from the resolved `auto_scroll_to` target.
 *
 * Keyed on the RESOLVED index, so the scroll fires when the author's intent
 * actually changes — not on every re-publish. A screen that re-renders for an
 * unrelated reason (a tick, a toggle elsewhere) carries the same index and
 * leaves a reader who has scrolled away exactly where they were.
 *
 * Armed when the author sets or changes the request and disarmed once the list
 * has gone there, so content that takes the target out of range and brings it
 * back (a refresh, a filter cleared) doesn't move the reader again.
 *
 * First application jumps, later ones animate — matching `scroll-anchor`:
 * a screen that opens already scrolled shouldn't visibly fly down from the
 * top, but a later move is a state change the user should see happen. Only
 * the later moves take the top bar with them, through [chrome], so opening a
 * screen never animates the bar shut.
 */
@Composable
private fun AutoScrollToEffect(
    request: Int,
    targetIndex: Int,
    listState: LazyListState,
    chrome: ChromeScrollController? = null,
) {
    val currentChrome by rememberUpdatedState(chrome)
    val didInitialScroll = remember { mutableStateOf(false) }
    val armed = remember(request) { mutableStateOf(request >= 0) }

    LaunchedEffect(request, targetIndex) {
        if (!armed.value || targetIndex < 0) return@LaunchedEffect

        armed.value = false
        if (!didInitialScroll.value) {
            didInitialScroll.value = true
            listState.scrollToItem(targetIndex)
        } else {
            listState.animateScrollFollowingChrome(targetIndex, 0, currentChrome)
        }
    }
}

object ScrollViewRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val horizontal = node.props.getBool("horizontal")
        val keyboardController = LocalSoftwareKeyboardController.current

        val autoScrollTarget = resolveAutoScrollTarget(node)

        // Item spacing from `gap-*`. The flex engine spaces ordinary
        // containers, but a lazy list places its own items, so the gap has
        // to become the list's arrangement here or it is dropped. iOS already
        // reads the same layout gap into its LazyVStack/LazyHStack spacing.
        val gap = (node.layout?.gap ?: 0f).dp

        if (horizontal) {
            val rowState = rememberLazyListState()

            AutoScrollToEffect(autoScrollRequest(node), autoScrollTarget, rowState)

            LazyRow(
                modifier = modifier,
                state = rowState,
                horizontalArrangement = Arrangement.spacedBy(gap),
            ) {
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
            // An explicit `auto_scroll_to` wins over `scroll-anchor="bottom"`.
            // Both drive the same LazyListState, so letting them run together
            // would have two effects fighting over the same list — the author
            // named a specific child, which is the more specific instruction.
            //
            // Gated on the REQUEST rather than the resolved target: an author
            // who named a child owns the scroll position from that moment,
            // including the frames before the child exists. Gating on the
            // resolved target would hand control back to the anchor whenever
            // the index is out of reach, so a list filling in would sit at the
            // bottom and then jump.
            val stickBottom = autoScrollRequest(node) < 0 &&
                node.props.getString("scroll_anchor", "") == "bottom"
            val listState = rememberLazyListState()
            val didInitialScroll = remember { mutableStateOf(false) }
            val contentSignal = if (stickBottom) totalDescendants(node) else 0
            // Null unless the screen's top bar collapses on scroll.
            val chromeScroll by rememberUpdatedState(LocalChromeScrollController.current)

            // Observe the list's own drags without consuming its pointer events.
            // Programmatic bottom anchoring must not dismiss the keyboard.
            LaunchedEffect(listState, keyboardController) {
                listState.interactionSource.interactions.collect { interaction ->
                    if (interaction is DragInteraction.Start) {
                        keyboardController?.hide()
                    }
                }
            }

            LaunchedEffect(stickBottom, contentSignal) {
                if (stickBottom && node.children.isNotEmpty()) {
                    val lastIndex = node.children.size - 1
                    if (!didInitialScroll.value) {
                        didInitialScroll.value = true
                        listState.scrollToItem(lastIndex, Int.MAX_VALUE) // jump on open
                    } else {
                        listState.animateScrollFollowingChrome(lastIndex, Int.MAX_VALUE, chromeScroll)
                    }
                }
            }

            AutoScrollToEffect(autoScrollRequest(node), autoScrollTarget, listState, chromeScroll)

            // A `fill` / `h-full` DIRECT child asked to be at least as tall as
            // the VIEWPORT — the "short screen centred, still scrolls when the
            // keyboard appears" pattern. A LazyColumn measures its items with
            // an unbounded main axis, so `fillMaxHeight()` inside one has
            // nothing to resolve against and the child hugs its content,
            // leaving `justify-center` no space to distribute.
            //
            // BoxWithConstraints supplies the viewport height, which is handed
            // to those children as a MINIMUM: content taller than the viewport
            // must still grow and scroll, exactly like CSS `min-height: 100%`.
            //
            // Direct children only — a nested descendant's fill resolves
            // against ITS parent, which is ordinary flex behaviour.
            //
            // Gated so the common path keeps the original LazyColumn with no
            // extra measurement pass around it.
            val hasFillHeightChild = node.children.any {
                it.layout?.heightMode == SizeMode.FILL
            }

            if (hasFillHeightChild) {
                BoxWithConstraints(modifier = modifier) {
                    // Unbounded when the scroll view is itself content-sized
                    // (no h-* and nothing constraining it). `heightIn(min =
                    // Dp.Infinity)` would be catastrophic, so fall through to
                    // the normal path — there is no viewport to fill against.
                    val viewport = maxHeight.takeIf { it.value.isFinite() && it.value > 0f }
                    LazyColumn(
                        state = listState,
                        verticalArrangement = Arrangement.spacedBy(gap),
                    ) {
                        items(node.children, key = { it.id }) { child ->
                            val layout = child.layout
                            if (viewport != null && layout?.heightMode == SizeMode.FILL) {
                                // The minimum goes on the CHILD's own modifier,
                                // not on a wrapper. A Box RELAXES min
                                // constraints for its children (only
                                // `matchParentSize` opts back in), so wrapping
                                // made the Box viewport-tall while the column
                                // inside it kept hugging — the original bug,
                                // one layer down.
                                //
                                // Compose enforces min constraints, so a column
                                // measured at minHeight = viewport IS viewport
                                // tall, and its own Arrangement.Center then has
                                // slack to distribute.
                                //
                                // Width is reproduced here because
                                // `overrideModifier` replaces NodeView's own
                                // sizing block wholesale. Same pattern as
                                // StackRenderer above.
                                var childMod: Modifier = Modifier.heightIn(min = viewport)
                                when (layout.widthMode) {
                                    SizeMode.FILL -> childMod = childMod.fillMaxWidth()
                                    SizeMode.FIXED -> if (layout.width > 0f) {
                                        childMod = childMod.width(layout.width.dp)
                                    }
                                    SizeMode.PERCENT -> if (layout.width > 0f) {
                                        childMod = childMod.fillMaxWidth(
                                            (layout.width / 100f).coerceIn(0f, 1f)
                                        )
                                    }
                                }
                                NodeView(node = child, overrideModifier = childMod)
                            } else {
                                NodeView(node = child)
                            }
                        }
                    }
                }
            } else {
                LazyColumn(
                    modifier = modifier,
                    state = listState,
                    verticalArrangement = Arrangement.spacedBy(gap),
                ) {
                    items(node.children, key = { it.id }) { child ->
                        NodeView(node = child)
                    }
                }
            }
        }
    }
}
