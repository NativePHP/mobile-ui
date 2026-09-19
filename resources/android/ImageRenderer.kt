package com.nativephp.plugins.native_ui.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil3.compose.AsyncImage
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.argbToComposeColor
import com.nativephp.mobile.ui.nativerender.nodeShape

object ImageRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val src = p.getString("src")
        // No `fit` prop means no `object-*` class. Default to Fit (1) so
        // an unclassed image scales into its frame like iOS does, instead
        // of ContentScale.None painting the bitmap at intrinsic size and
        // center-cropping it to the frame.
        val fit = p.getInt("fit", 1)
        val alt = p.getString("alt")
        val tintArgb = p.getColor("tint_color", 0)
        val radius = node.style?.borderRadius ?: 0f

        val context = LocalContext.current
        val model = remember(src, context) { nuiResolveImageSrc(src, context) }

        // Images need an explicit clip for rounded corners (nodeStyle doesn't
        // clip globally). `nodeShape` is the same resolver containers use, so
        // per-corner radii (`rounded-3xl rounded-br-none`, `rounded-t-2xl`)
        // clip an image exactly like a column with the same classes. Those
        // ride the props bag as `radius_tl` etc. with no uniform radius to
        // fall back on, which is why they count as "has a radius" here.
        val imgModifier = if (radius > 0f || p.has("radius_tl")) {
            modifier.clip(nodeShape(radius, p))
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
