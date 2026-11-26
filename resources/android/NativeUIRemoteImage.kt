package com.nativephp.plugins.native_ui.ui

import android.content.Context
import coil3.annotation.ExperimentalCoilApi
import coil3.network.cachecontrol.CacheControlCacheStrategy
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import com.nativephp.mobile.ui.nativerender.GenericProps

/**
 * `revalidate` on an element that shows remote images: `<native:image>`, a
 * list item's avatar or thumbnail, a pager's placeholders. A bare Blade
 * attribute arrives as `true`, a quoted one as a string.
 */
internal fun GenericProps.revalidatesRemoteImages(): Boolean =
    getBool("revalidate") || getString("revalidate") in setOf("true", "1")

/**
 * What to hand Coil for a `src` that [nuiResolveImageSrc] has resolved.
 *
 * Coil's default cache strategy serves anything in its disk cache without
 * asking the server, so an image URL is treated as immutable, the same as
 * on iOS. `revalidate` asks for strict HTTP caching instead, for a URL that
 * is reused for changing content: the request gets a network fetcher with
 * Coil's [CacheControlCacheStrategy], so a stale disk entry is revalidated
 * or downloaded again, and it skips the memory cache, which never looks at
 * HTTP. Local files ignore it.
 *
 * Without `revalidate` or [configure] this is the plain string, as before.
 */
internal fun nuiImageModel(
    src: String,
    context: Context,
    revalidate: Boolean,
    configure: (ImageRequest.Builder.() -> Unit)? = null,
): Any {
    val strict = revalidate && (src.startsWith("https://") || src.startsWith("http://"))
    if (!strict && configure == null) {
        return src
    }

    return ImageRequest.Builder(context).data(src).apply {
        configure?.invoke(this)
        if (strict) {
            fetcherFactory(revalidatingNetworkFetcher)
            memoryCachePolicy(CachePolicy.DISABLED)
        }
    }.build()
}

/**
 * The network fetcher for every `revalidate` image, so they share one
 * OkHttp client, made on first use. The disk cache is still the image
 * loader's, shared with every other image: an entry keeps its response
 * headers whichever strategy wrote it, and those are what this one reads.
 */
@OptIn(ExperimentalCoilApi::class)
internal val revalidatingNetworkFetcher = OkHttpNetworkFetcherFactory(
    cacheStrategy = { CacheControlCacheStrategy() },
)
