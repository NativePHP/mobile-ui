package com.nativephp.plugins.native_ui.ui

import android.content.Context
import android.graphics.Bitmap
import androidx.test.core.app.ApplicationProvider
import coil3.ImageLoader
import coil3.asImage
import coil3.decode.DecodeResult
import coil3.decode.Decoder
import coil3.disk.DiskCache
import coil3.fetch.SourceFetchResult
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.request.Options
import coil3.request.SuccessResult
import com.nativephp.mobile.ui.nativerender.GenericProps
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import okio.Path.Companion.toOkioPath
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * Plain images keep whatever Coil has on disk, however old; `revalidate`
 * images follow Cache-Control. Real OkHttp against a local server, with
 * Coil's disk cache and no memory cache, so every load reaches the fetcher.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RemoteImageRevalidateTest {
    @get:Rule val folder = TemporaryFolder()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val requests = ConcurrentHashMap<String, AtomicInteger>()
    private val conditional = ConcurrentHashMap<String, AtomicInteger>()
    private val server = MockWebServer()
    private lateinit var loader: ImageLoader

    @Before fun start() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.requestUrl!!.encodedPath
                requests.getOrPut(path) { AtomicInteger() }.incrementAndGet()
                val etag = if (path.startsWith("/etag")) "\"v1\"" else null
                if (etag != null && request.getHeader("If-None-Match") == etag) {
                    conditional.getOrPut(path) { AtomicInteger() }.incrementAndGet()

                    return MockResponse().setResponseCode(304).setHeader("ETag", etag)
                }

                return MockResponse()
                    .setHeader("Content-Type", "image/png")
                    .setHeader("Cache-Control", if (path.startsWith("/fresh")) "public, max-age=60" else "public, max-age=0")
                    .apply { etag?.let { setHeader("ETag", it) } }
                    .setBody(Buffer().write(byteArrayOf(1, 2, 3, 4)))
            }
        }
        server.start()
        loader = ImageLoader.Builder(context)
            .memoryCache(null)
            .diskCache { DiskCache.Builder().directory(folder.root.toOkioPath()).build() }
            .components { add(BytesOnlyDecoder()) }
            .build()
    }

    @After fun stop() {
        loader.shutdown()
        server.shutdown()
    }

    private fun url(path: String) = server.url(path).toString()

    private fun load(path: String, revalidate: Boolean) = runBlocking {
        val model = nuiImageModel(url(path), context, revalidate)
        val request = model as? ImageRequest ?: ImageRequest.Builder(context).data(model).build()
        val result = loader.execute(request)
        assertTrue("$path: $result", result is SuccessResult)
    }

    private fun count(path: String) = requests[path]?.get() ?: 0

    @Test fun aPlainImageIsServedFromDiskAfterItExpires() {
        load("/stale.png", revalidate = false)
        load("/stale.png", revalidate = false)
        load("/stale.png", revalidate = false)

        assertEquals(1, count("/stale.png"))
    }

    @Test fun aRevalidateImageIsFetchedAgainOnceItExpires() {
        load("/stale.png", revalidate = true)
        load("/stale.png", revalidate = true)
        load("/stale.png", revalidate = false)

        assertEquals(2, count("/stale.png"))
    }

    @Test fun aRevalidateImageIsServedFromDiskWhileFresh() {
        load("/fresh.png", revalidate = true)
        load("/fresh.png", revalidate = true)

        assertEquals(1, count("/fresh.png"))
    }

    @Test fun aRevalidateImageAsksWithItsETagOnceItExpires() {
        load("/etag.png", revalidate = false)
        load("/etag.png", revalidate = true)

        assertEquals(2, count("/etag.png"))
        assertEquals(1, conditional["/etag.png"]?.get() ?: 0)
    }

    @Test fun onlyRemoteRevalidateImagesGetTheirOwnRequest() {
        val remote = nuiImageModel("https://example.com/a.jpg", context, revalidate = true) as ImageRequest

        assertEquals(CachePolicy.DISABLED, remote.memoryCachePolicy)
        assertEquals(revalidatingNetworkFetcher, remote.fetcherFactory?.first)
        assertEquals("https://example.com/a.jpg", nuiImageModel("https://example.com/a.jpg", context, revalidate = false))
        assertEquals("/data/user/0/app/public/a.jpg", nuiImageModel("/data/user/0/app/public/a.jpg", context, revalidate = true))
    }

    @Test fun revalidateIsReadFromABareOrQuotedAttribute() {
        assertTrue(GenericProps(mapOf("revalidate" to true)).revalidatesRemoteImages())
        assertTrue(GenericProps(mapOf("revalidate" to "true")).revalidatesRemoteImages())
        assertEquals(false, GenericProps(mapOf("revalidate" to "false")).revalidatesRemoteImages())
        assertEquals(false, GenericProps().revalidatesRemoteImages())
    }
}

/** Reads the bytes and hands back a 1x1 bitmap; only the fetch matters here. */
private class BytesOnlyDecoder : Decoder.Factory {
    override fun create(result: SourceFetchResult, options: Options, imageLoader: ImageLoader) = object : Decoder {
        override suspend fun decode(): DecodeResult {
            result.source.source().readByteArray()
            return DecodeResult(Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888).asImage(), isSampled = false)
        }
    }
}
