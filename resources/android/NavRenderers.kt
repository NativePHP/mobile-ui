package com.nativephp.plugins.native_ui.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.R
import com.nativephp.mobile.ui.getIconName
import com.nativephp.mobile.ui.nativerender.LocalSafeAreaBottom
import com.nativephp.mobile.ui.nativerender.LocalSafeAreaTop
import com.nativephp.mobile.ui.nativerender.NativeElementBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import kotlinx.coroutines.launch

object TopBarRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val props = node.props
        val title = props.getString("title", "")
        val subtitle = props.getString("subtitle", "")
        val showNavIcon = props.getBool("show_navigation_icon", true)

        // Honor explicit text_color / background_color from NavBar builder;
        // fall back to system dark-theme heuristic only when nothing is set.
        val isDark = isSystemInDarkTheme()
        val textArgb = props.getColor("text_color", 0)
        val textColor = if (textArgb != 0) Color(textArgb) else if (isDark) Color.White else Color.Black
        val bgArgb = props.getColor("background_color", 0)
        val backgroundColor = if (bgArgb != 0) Color(bgArgb) else Color.Transparent
        val elevation = props.getFloat("elevation").dp

        // The wrapper releases the top safe-area to this bar (when paired
        // with a TabBar via `wrapWithChrome`'s safeAreaTop/Bottom split).
        // We apply the status-bar / notch inset internally so the bar's
        // bg reaches the screen edge and the title sits below the notch.
        val safeAreaTop = LocalSafeAreaTop.current.dp
        val iconFont = remember { FontFamily(Font(R.font.material_icons)) }

        Row(
            modifier = modifier
                .fillMaxWidth()
                .shadow(elevation)
                .background(backgroundColor)
                .padding(top = safeAreaTop)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (showNavIcon) {
                // Back chevron — fires a system-back event into the PHP event
                // queue. The runloop catches type 8 (EventType.systemBack) and
                // calls onBackPressed → back(), popping the navigation stack.
                // Same path the device hardware back button uses.
                // minimumInteractiveComponentSize grows the tap target to
                // 48dp (glyph stays 24sp); the smaller end padding keeps the
                // title gap roughly where it was (~12dp slack + 4dp).
                Text(
                    text = getIconName("arrow_back"),
                    fontFamily = iconFont,
                    fontSize = 24.sp,
                    color = textColor,
                    modifier = Modifier
                        .padding(end = 4.dp)
                        .minimumInteractiveComponentSize()
                        .clickable(role = Role.Button) {
                            NativeElementBridge.sendSystemBackEvent()
                        }
                        .semantics { contentDescription = "Back" }
                )
            }
            // Title + optional subtitle stacked
            Column(modifier = Modifier.weight(1f)) {
                Text(text = title, fontFamily = nuiNodeFontFamily(node.props.getString("font_name")), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = textColor)
                if (subtitle.isNotEmpty()) {
                    Text(text = subtitle, fontFamily = nuiNodeFontFamily(node.props.getString("font_name")), fontSize = 12.sp, color = textColor.copy(alpha = 0.7f))
                }
            }
            val actions = node.children.filter { it.type == "top_bar_action" }
            val context = LocalContext.current
            for (action in actions.take(3)) {
                val icon = action.props.getString("icon", "more_vert")
                val url = action.props.getString("url")
                val actionLabel = action.props.getString("label")
                Text(
                    text = getIconName(icon), fontFamily = iconFont, fontSize = 24.sp, color = textColor,
                    modifier = Modifier
                        .minimumInteractiveComponentSize()
                        .clickable(role = Role.Button) {
                            if (url.isNotEmpty()) {
                                try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (_: Exception) {}
                            } else if (action.onPress != 0) {
                                NativeElementBridge.sendPressEvent(action.onPress, action.id)
                            }
                        }
                        .let { m ->
                            if (actionLabel.isNotEmpty()) m.semantics { contentDescription = actionLabel } else m
                        }
                )
            }
        }
    }
}

object BottomNavRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val items = node.children.filter { it.type == "bottom_nav_item" }
        if (items.isEmpty()) return
        val iconFont = remember { FontFamily(Font(R.font.material_icons)) }

        // Bar-level props (from `TabBar::activeColor()` / `TabBar::dark()` /
        // `TabBar::labelVisibility()`).
        val activeArgb = node.props.getColor("active_color", 0)
        val activeColor = if (activeArgb != 0) Color(activeArgb) else Color(0xFF1976D2)
        val isDark = node.props.getBool("dark")
        // Explicit `textColor()` from the TabBar builder wins for inactive
        // items; falls back to the gray defaults picked by `dark()`.
        val textColorArgb = node.props.getColor("text_color", 0)
        val inactiveColor = when {
            textColorArgb != 0 -> Color(textColorArgb)
            isDark              -> Color(0xFFB3B3B3)
            else                -> Color(0xFF757575)
        }
        // Explicit `backgroundColor()` from the TabBar builder wins; falls
        // back to the `dark()` default (dark surface) or transparent.
        val bgArgb = node.props.getColor("background_color", 0)
        val barBackground = when {
            bgArgb != 0 -> Color(bgArgb)
            isDark      -> Color(0xFF1E1E1E)
            else        -> Color.Transparent
        }
        val labelVisibility = node.props.getString("label_visibility", "labeled")

        // The wrapper releases the bottom safe-area to this bar (via
        // `wrapWithChrome`'s safeAreaTop/Bottom split). Apply the
        // home-indicator / gesture inset internally so the bar's bg
        // reaches the screen edge and the icons sit above the gesture.
        val safeAreaBottom = LocalSafeAreaBottom.current.dp

        Row(
            modifier = modifier
                .fillMaxWidth()
                .background(barBackground)
                .padding(top = 8.dp, bottom = 8.dp + safeAreaBottom),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (item in items) {
                val label = item.props.getString("label", "")
                val icon = item.props.getString("icon", "circle")
                val active = item.props.getBool("active")
                val badge = item.props.getString("badge", "")
                val news = item.props.getBool("news")
                val itemColor = if (active) activeColor else inactiveColor
                val showLabel = when (labelVisibility) {
                    "unlabeled" -> false
                    "selected"  -> active
                    else        -> true
                }

                Column(
                    // selectable(role = Tab) lets TalkBack announce
                    // "selected"/position; the min height guarantees a
                    // >=48dp touch target. When label_visibility hides the
                    // visible label, expose it as the contentDescription so
                    // icon-only tabs aren't unlabeled.
                    modifier = Modifier.weight(1f)
                        .defaultMinSize(minHeight = 48.dp)
                        .selectable(
                            selected = active,
                            role = Role.Tab,
                            onClick = { if (item.onPress != 0) NativeElementBridge.sendPressEvent(item.onPress, item.id) },
                        )
                        .padding(vertical = 8.dp)
                        .let { m ->
                            if (!showLabel && label.isNotEmpty()) m.semantics { contentDescription = label } else m
                        },
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Box wraps the icon at center; badge / news dot anchored
                    // to the icon's TopEnd corner via `.align(TopEnd)`.
                    Box(contentAlignment = Alignment.Center) {
                        Text(text = getIconName(icon), fontFamily = iconFont, fontSize = 24.sp, color = itemColor, textAlign = TextAlign.Center)
                        if (badge.isNotEmpty()) {
                            Box(
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .offset(x = 10.dp, y = (-6).dp)
                                    .defaultMinSize(minWidth = 16.dp, minHeight = 16.dp)
                                    .clip(CircleShape)
                                    .background(Color.Red)
                                    .padding(horizontal = 4.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = badge,
                                    fontFamily = nuiNodeFontFamily(node.props.getString("font_name")),
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                    textAlign = TextAlign.Center
                                )
                            }
                        } else if (news) {
                            Box(
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .offset(x = 4.dp, y = (-2).dp)
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .background(Color.Red)
                            )
                        }
                    }
                    if (showLabel && label.isNotEmpty()) {
                        Text(text = label, fontFamily = nuiNodeFontFamily(node.props.getString("font_name")), fontSize = 12.sp, color = itemColor, textAlign = TextAlign.Center)
                    }
                }
            }
        }
    }
}

object SideNavRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        // No-op: the Edge-bridge drawer host (NativeEdgeDrawerState) was
        // removed with the v3 Edge chrome system. A hoisted side_nav node
        // currently has no drawer host on Android — layout drawers go
        // through HasLayoutDrawer / the native_drawer root host instead.
        // This renderer stays registered so a side_nav in the wire tree
        // renders nothing rather than crashing renderer dispatch.
    }
}

object EmptyRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {}
}
