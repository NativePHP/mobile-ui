package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import com.nativephp.mobile.ui.nativerender.LocalTopBarColor
import com.nativephp.mobile.ui.nativerender.LocalTopTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.MaterialIcon
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 PrimaryTabRow — horizontal tab strip with an indicator under the
 * active tab. Echo-prevention (plan K), theme-sourced colors (Model 3).
 */
object TabRowRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getInt("value")
        val onChangeCb  = p.getCallbackId("on_change")
        val a11yLabel   = p.getString("a11y_label")

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        val tabs = node.children.filter { it.type == "tab" }
        if (tabs.isEmpty()) return

        var selectedIndex by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                selectedIndex = serverValue
                lastSentValue = serverValue
            }
        }

        val rowModifier = modifier
            .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m }

        Column(modifier = rowModifier) {
            // mirror the iOS strip — transparent
            // background (the page shows through), content-sized tabs on a
            // horizontally scrollable row so labels never wrap, hairline in
            // theme.outline underneath. The fixed PrimaryTabRow split the
            // width evenly and wrapped four Dutch labels onto two lines.
            PrimaryScrollableTabRow(
                selectedTabIndex = selectedIndex.coerceIn(0, tabs.size - 1),
                // a strip sitting directly under the
                // nav bar is chrome — it paints in the bar's colour (see
                // LocalTopTabRow); inline strips stay transparent.
                containerColor = if (node === LocalTopTabRow.current) (LocalTopBarColor.current ?: Color.Transparent) else Color.Transparent,
                contentColor = theme.primary,
                edgePadding = 0.dp,
                divider = { HorizontalDivider(color = theme.outline) },
            ) {
                tabs.forEachIndexed { index, tabNode ->
                    val tabLabel = tabNode.props.getString("label")
                    val tabIcon  = tabNode.props.getString("icon")
                    // Explicit a11y_label wins; otherwise fall back to the
                    // tab's label prop so icon-only tabs are never unlabeled.
                    val tabA11y  = tabNode.props.getString("a11y_label").ifEmpty { tabLabel }
                    val isSelected = index == selectedIndex

                    Tab(
                        selected = isSelected,
                        onClick = {
                            selectedIndex = index
                            lastSentValue = index
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendTabChangeEvent(onChangeCb, node.id, index)
                            }
                        },
                        modifier = if (tabA11y.isNotEmpty()) {
                            Modifier.semantics { contentDescription = tabA11y }
                        } else Modifier,
                        text = if (tabLabel.isNotEmpty()) ({ Text(tabLabel, fontFamily = nuiDefaultFontFamily(), maxLines = 1, softWrap = false, overflow = TextOverflow.Clip) }) else null,
                        icon = if (tabIcon.isNotEmpty()) {
                            { MaterialIcon(name = tabIcon, contentDescription = null, size = 24.dp) }
                        } else null,
                        selectedContentColor = theme.primary,
                        unselectedContentColor = theme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
