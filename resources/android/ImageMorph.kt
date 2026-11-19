package com.nativephp.plugins.native_ui.ui

import android.content.res.Resources
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.roundToInt

/**
 * Where each image with a `ref` is drawn, so a modal can grow a picture out
 * of one (`morph-from`) and into another (`morph-to`) as it opens, and back
 * as it closes (see ModalRenderer). The Android half of iOS's
 * NativeUIImageMorph.
 *
 * An image registers once it has loaded. Where it's drawn is worked out
 * when it's asked for, from its layout coordinates, so it takes in the
 * transforms around it (a zoom, a drag) as they are at that moment: the
 * rect its pixels cover on screen, which is the fitted rect for
 * `fit="contain"` and the frame for the fits that fill it. A copy drawn
 * cropped across a rect moving between two of these matches both ends.
 */
object NativeUIImageMorph {
    /** Where an image's pixels are on screen, in px, and the picture. */
    class Drawn(val rect: Rect, val image: ImageBitmap, val radiusDp: Float)

    /** What an image tells the registry about itself. */
    class Source {
        var coordinates: LayoutCoordinates? = null
        var image: ImageBitmap? = null
        /** Width over height of the loaded image. */
        var aspect: Float = 0f
        var contain: Boolean = false
        var radiusDp: Float = 0f
    }

    private val sources = HashMap<String, Source>()

    /** Refs whose images draw nothing while a copy of them is in flight. */
    private val hidden = mutableStateMapOf<String, Boolean>()

    fun register(ref: String, source: Source) {
        if (ref.isNotEmpty()) sources[ref] = source
    }

    fun forget(ref: String, source: Source) {
        if (sources[ref] === source) sources.remove(ref)
    }

    fun isHidden(ref: String): Boolean = ref.isNotEmpty() && hidden[ref] == true

    fun hide(vararg refs: String) {
        refs.filter { it.isNotEmpty() }.forEach { hidden[it] = true }
    }

    fun show(vararg refs: String) {
        refs.forEach { hidden.remove(it) }
    }

    /** Where `ref` is drawn, if it has loaded and any of it is on screen. */
    fun onScreen(ref: String): Drawn? {
        if (ref.isEmpty()) return null
        val source = sources[ref] ?: return null
        val coordinates = source.coordinates?.takeIf { it.isAttached } ?: return null
        val image = source.image ?: return null
        val size = coordinates.size
        if (size.width <= 0 || size.height <= 0) return null
        var local = Rect(0f, 0f, size.width.toFloat(), size.height.toFloat())
        if (source.contain && source.aspect > 0f) {
            local = if (local.width / local.height > source.aspect) {
                val width = local.height * source.aspect
                Rect(Offset((local.width - width) / 2f, 0f), androidx.compose.ui.geometry.Size(width, local.height))
            } else {
                val height = local.width / source.aspect
                Rect(Offset(0f, (local.height - height) / 2f), androidx.compose.ui.geometry.Size(local.width, height))
            }
        }
        val topLeft = coordinates.localToScreen(local.topLeft)
        val bottomRight = coordinates.localToScreen(local.bottomRight)
        val rect = Rect(topLeft, bottomRight)
        if (rect.isEmpty) return null
        val metrics = Resources.getSystem().displayMetrics
        val screen = Rect(0f, 0f, metrics.widthPixels.toFloat(), metrics.heightPixels.toFloat())
        if (!rect.overlaps(screen)) return null
        // rounded-full sends a huge radius; past half the shorter side it's a
        // circle anyway, and a copy that shrinks from one should start
        // rounding off straight away.
        val radius = minOf(source.radiusDp, minOf(rect.width, rect.height) / 2f / metrics.density)
        return Drawn(rect, image, radius)
    }

    /** Where `ref` is drawn, waiting a frame at a time up to [timeoutMillis] for it to load. */
    suspend fun awaitOnScreen(ref: String, timeoutMillis: Long): Drawn? {
        if (ref.isEmpty()) return null
        return withTimeoutOrNull(timeoutMillis) {
            var drawn = onScreen(ref)
            while (drawn == null) {
                withFrameNanos { }
                drawn = onScreen(ref)
            }
            drawn
        }
    }
}

/** A picture on its way between two drawn rects. */
class NativeUIImageFlight(val from: NativeUIImageMorph.Drawn, val to: NativeUIImageMorph.Drawn)

/**
 * Draws a flight [progress] of the way along, laid over a box whose top
 * left is at [origin] on screen.
 */
@Composable
fun NativeUIImageFlightView(flight: NativeUIImageFlight, progress: Float, origin: Offset) {
    val density = LocalDensity.current
    val rect = lerp(flight.from.rect, flight.to.rect, progress)
    val radius = lerp(flight.from.radiusDp, flight.to.radiusDp, progress)
    Image(
        bitmap = flight.to.image.takeIf { it.width >= flight.from.image.width } ?: flight.from.image,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = Modifier
            .offset { IntOffset((rect.left - origin.x).roundToInt(), (rect.top - origin.y).roundToInt()) }
            .size(with(density) { rect.width.toDp() }, with(density) { rect.height.toDp() })
            .clip(RoundedCornerShape(radius.dp)),
    )
}
