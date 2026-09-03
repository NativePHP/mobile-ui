package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.argbToComposeColor

object ImageRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val src = p.getString("src")
        val fit = p.getInt("fit")
        val alt = p.getString("alt")
        val tintArgb = p.getColor("tint_color", 0)
        val radius = node.style?.borderRadius ?: 0f

        val context = LocalContext.current
        val model = remember(src, context) { nuiResolveImageSrc(src, context) }

        // Images need explicit clip for rounded corners (nodeStyle doesn't clip globally)
        val imgModifier = if (radius > 0f) {
            modifier.clip(RoundedCornerShape(radius.dp))
        } else modifier

        if (src.isNotEmpty()) {
            AsyncImage(
                model = model,
                // `alt` marks the image as meaningful; without it the image
                // stays decorative (silent for TalkBack).
                contentDescription = alt.ifEmpty { null },
                modifier = imgModifier,
                contentScale = resolveContentScale(fit),
                colorFilter = if (tintArgb != 0) {
                    ColorFilter.tint(argbToComposeColor(tintArgb))
                } else null
            )
        }
    }
}

private fun resolveContentScale(fit: Int): ContentScale {
    return when (fit) {
        0 -> ContentScale.None
        1 -> ContentScale.Fit
        2 -> ContentScale.Crop
        3 -> ContentScale.FillBounds
        4 -> ContentScale.Fit
        else -> ContentScale.Fit
    }
}
