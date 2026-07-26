package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Badge — small count or text marker. Variant picks which theme pair to use.
 */
object BadgeRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val count   = p.getInt("count")
        val label   = p.getString("label")
        val variant = p.getString("variant", "destructive")
        val a11yLabel = p.getString("a11y_label")

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        val (bg, fg) = when (variant) {
            "primary" -> theme.primary     to theme.onPrimary
            "accent"  -> theme.accent      to theme.onAccent
            "success" -> theme.success     to theme.onSuccess
            else      -> theme.destructive to theme.onDestructive // "destructive"
        }

        val text = if (label.isNotEmpty()) label
                   else if (count > 99) "99+"
                   else count.toString()

        val boxModifier = modifier
            .defaultMinSize(minWidth = 20.dp, minHeight = 20.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m }

        Box(modifier = boxModifier, contentAlignment = Alignment.Center) {
            Text(
                text = text,
                fontFamily = nuiDefaultFontFamily(),
                color = fg,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
