package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 circular activity indicator (spinner). Theme-tinted (Model 3).
 */
object ActivityIndicatorRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val size = p.getString("size", "md")
        val a11yLabel = p.getString("a11y_label")

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light

        // Optional override — primitives like spinners sometimes need to
        // match their container. When unset, fall through to theme.primary.
        val overrideArgb = p.getColor("color", 0)
        val tint = if (overrideArgb != 0) Color(overrideArgb) else theme.primary

        val sizeDp = when (size) {
            "lg" -> 48.dp
            "sm" -> 20.dp
            else -> 32.dp
        }

        // Always announce something ("Loading" fallback) and mark the node a
        // polite live region so TalkBack reports the spinner appearing.
        val indicatorModifier = modifier
            .size(sizeDp)
            .semantics {
                contentDescription = a11yLabel.ifEmpty { "Loading" }
                liveRegion = LiveRegionMode.Polite
            }

        CircularProgressIndicator(
            modifier = indicatorModifier,
            color = tint,
        )
    }
}
