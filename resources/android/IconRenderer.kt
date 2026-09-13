package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

object IconRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val name = p.getString("name")
        val a11yLabel = p.getString("a11y_label")
        // default 0 (unset) → theme onSurface,
        // so an icon without an explicit colour follows dark mode.
        val lightArgb = p.getColor("color", 0)
        val darkArgb  = p.getColor("dark_color", 0)
        val isDark = isSystemInDarkTheme()
        val effectiveArgb = if (isDark && darkArgb != 0) darkArgb else lightArgb
        val theme = if (isDark) NativeUITheme.dark else NativeUITheme.light

        com.nativephp.mobile.ui.MaterialIcon(
            name = name,
            // Only announce an explicit a11y label — the raw machine icon
            // name ("chevron_right") is noise, so decorative icons stay
            // silent for TalkBack.
            contentDescription = a11yLabel.ifEmpty { null },
            modifier = modifier.then(applyClickModifier(node)),
            size = p.getFloat("size", 24f).dp,
            tint = if (effectiveArgb != 0) Color(effectiveArgb) else theme.onSurface,
        )
    }

    private fun applyClickModifier(node: NativeUINode): Modifier {
        return if (node.onPress != 0) {
            // Button role + a >=48dp touch target for tappable icons. The
            // glyph keeps its visual size; only the hit area grows.
            Modifier
                .minimumInteractiveComponentSize()
                .clickable(role = Role.Button) {
                    NativeUIBridge.sendPressEvent(node.onPress, node.id)
                }
        } else {
            Modifier
        }
    }
}
