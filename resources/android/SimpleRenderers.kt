package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.argbToComposeColor
import com.nativephp.plugins.native_ui.NativeUITheme

object SpacerRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        Spacer(modifier = modifier)
    }
}

object DividerRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val isDark = isSystemInDarkTheme()
        // `border-*` colours the rule (`dark:border-*` in dark mode). Without
        // one, a `bg-*` colour is the rule: the node modifier already paints
        // the background (and its `dark:bg-*` variant) under the divider, so
        // the line stays transparent instead of covering it.
        // Neither → the theme's hairline (`outline-variant`), which dims in
        // dark mode like iOS's separator. The vendor's fixed #E0E0E0 drew a
        // white line on dark surfaces.
        val darkBorder = if (isDark) node.props.getColor("dark_border_color", 0) else 0
        val borderArgb = if (darkBorder != 0) darkBorder else (node.style?.borderColor ?: 0)
        val darkBg = if (isDark) node.props.getColor("dark_bg_color", 0) else 0
        val hasBackground = darkBg != 0 || (node.style?.bgColor ?: 0) != 0
        val theme = if (isDark) NativeUITheme.dark else NativeUITheme.light
        val color = when {
            borderArgb != 0 -> argbToComposeColor(borderArgb)
            hasBackground -> Color.Transparent
            else -> theme.outlineVariant
        }
        HorizontalDivider(modifier = modifier, color = color)
    }
}

object RectRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        Box(modifier = modifier)
    }
}

object CircleRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        Box(modifier = modifier)
    }
}

object LineRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val borderArgb = node.style?.borderColor ?: 0
        val color = if (borderArgb != 0) argbToComposeColor(borderArgb) else Color(0xFFE0E0E0)
        val strokeWidth = node.style?.borderWidth ?: 1f

        Canvas(modifier = modifier.fillMaxWidth().height(strokeWidth.dp)) {
            drawLine(
                color = color,
                start = Offset(0f, size.height / 2),
                end = Offset(size.width, size.height / 2),
                strokeWidth = strokeWidth
            )
        }
    }
}
