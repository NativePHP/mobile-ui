package com.nativephp.plugins.native_ui.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.ScaleFactor
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.size.SizeResolver
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.argbToComposeColor
import com.nativephp.mobile.ui.nativerender.nodeShape
import kotlin.math.roundToInt

object ImageRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val src = p.getString("src")
        // No `fit` prop means no `object-*` class. Default to contain so
        // an unclassed image scales into its frame like iOS does, instead
        // of ContentScale.None painting the bitmap at intrinsic size and
        // center-cropping it to the frame.
        val fit = p.getInt("fit", ImageFit.CONTAIN)
        val alt = p.getString("alt")
        val tintArgb = p.getColor("tint_color", 0)
        val radius = node.style?.borderRadius ?: 0f

        val context = LocalContext.current
        val model = remember(src, context) { nuiResolveImageSrc(src, context) }

        // `none` draws the whole bitmap at its own size, so ask Coil for all
        // of it. Coil does that by itself for ContentScale.None but not for
        // the density-scaled ContentScale used here, and would otherwise
        // decode a big image down to the frame first.
        val request = remember(model, context, fit) {
            if (fit == ImageFit.NONE) {
                ImageRequest.Builder(context).data(model).size(SizeResolver.ORIGINAL).build()
            } else {
                model
            }
        }
        val density = LocalDensity.current.density
        val contentScale = remember(fit, density) { resolveContentScale(fit, density) }

        // Width over height of the loaded image, 0 until it's known.
        var aspectRatio by remember { mutableFloatStateOf(0f) }

        // Images need an explicit clip for rounded corners (nodeStyle doesn't
        // clip globally). `nodeShape` is the same resolver containers use, so
        // per-corner radii (`rounded-3xl rounded-br-none`, `rounded-t-2xl`)
        // clip an image exactly like a column with the same classes. Those
        // ride the props bag as `radius_tl` etc. with no uniform radius to
        // fall back on, which is why they count as "has a radius" here.
        val sizedModifier = modifier.sizeFromAspectRatio { aspectRatio }
        val imgModifier = if (radius > 0f || p.has("radius_tl")) {
            sizedModifier.clip(nodeShape(radius, p))
        } else sizedModifier

        if (src.isNotEmpty()) {
            AsyncImage(
                model = request,
                // `alt` marks the image as meaningful; without it the image
                // stays decorative (silent for TalkBack).
                contentDescription = alt.ifEmpty { null },
                modifier = imgModifier,
                contentScale = contentScale,
                colorFilter = if (tintArgb != 0) {
                    ColorFilter.tint(argbToComposeColor(tintArgb))
                } else null,
                onSuccess = { state ->
                    val size = state.painter.intrinsicSize
                    if (size.width > 0f && size.height > 0f) {
                        aspectRatio = size.width / size.height
                    }
                }
            )
        }
    }
}

/** Wire values of the `fit` prop, matching PHP's `ImageFit` enum. */
private object ImageFit {
    const val NONE = 0
    const val CONTAIN = 1
    const val COVER = 2
    const val FILL = 3
}

private fun resolveContentScale(fit: Int, density: Float): ContentScale {
    return when (fit) {
        ImageFit.NONE -> NaturalSize(density)
        ImageFit.COVER -> ContentScale.Crop
        ImageFit.FILL -> ContentScale.FillBounds
        else -> ContentScale.Fit
    }
}

/**
 * Draws the image at its own size with one image pixel per dp, the way iOS
 * draws a plain file one pixel per point. ContentScale.None maps one image
 * pixel to one screen pixel, so the same file came out two to three times
 * smaller than on iOS.
 */
private data class NaturalSize(val density: Float) : ContentScale {
    override fun computeScaleFactor(srcSize: Size, dstSize: Size) = ScaleFactor(density, density)
}

/**
 * Gives an image that has a fixed size on one axis and no bound on the other
 * the size its aspect ratio calls for, like an HTML <img> and iOS do.
 * `w-full` with no height in a list or scroll view is the usual case: Coil
 * only scales into the frame when both axes are bounded, so it fell back to
 * the bitmap's pixel size and left the image small in a wide box.
 */
private fun Modifier.sizeFromAspectRatio(aspectRatio: () -> Float): Modifier =
    layout { measurable, constraints ->
        val ratio = aspectRatio()
        val sized = when {
            ratio <= 0f -> constraints
            constraints.hasFixedWidth && !constraints.hasBoundedHeight -> {
                val width = constraints.maxWidth
                Constraints.fixed(width, constraints.constrainHeight((width / ratio).roundToInt()))
            }
            constraints.hasFixedHeight && !constraints.hasBoundedWidth -> {
                val height = constraints.maxHeight
                Constraints.fixed(constraints.constrainWidth((height * ratio).roundToInt()), height)
            }
            else -> constraints
        }
        val placeable = measurable.measure(sized)
        layout(placeable.width, placeable.height) {
            placeable.place(0, 0)
        }
    }
