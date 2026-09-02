package com.nativephp.plugins.native_ui.ui

import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 linear progress indicator. Determinate when `value` supplied;
 * indeterminate (animated wave) otherwise. Theme-tinted (Model 3).
 */
object ProgressBarRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val indeterminate = p.getBool("indeterminate")
        val a11yLabel = p.getString("a11y_label")

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light

        val overrideArgb = p.getColor("color", 0)
        val trackOverride = p.getColor("track_color", 0)
        val tint  = if (overrideArgb != 0)  Color(overrideArgb)  else theme.primary
        val track = if (trackOverride != 0) Color(trackOverride) else theme.surfaceVariant

        val barModifier = modifier
            .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m }

        if (indeterminate) {
            LinearProgressIndicator(
                modifier = barModifier,
                color = tint,
                trackColor = track,
            )
        } else {
            LinearProgressIndicator(
                progress = { p.getFloat("value").coerceIn(0f, 1f) },
                modifier = barModifier,
                color = tint,
                trackColor = track,
            )
        }
    }
}
