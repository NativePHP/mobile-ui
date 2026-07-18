package com.nativephp.plugins.native_ui.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient
import android.webkit.CookieManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.nativephp.mobile.bridge.LaravelEnvironment
import com.nativephp.mobile.bridge.PHPBridge
import com.nativephp.mobile.network.WebViewManager
import com.nativephp.mobile.ui.MainActivity
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode

/**
 * Locked-down WebView primitive.
 *
 * Defaults are paranoid by design: JS off, no DOM storage, no file access,
 * no JS bridge to the host, no new windows, mixed content blocked, cookies
 * non-persistent (cleared on attach). Hosts opt back into individual
 * capabilities via attributes (`javascript`, `dom-storage`) on the Blade
 * tag.
 *
 * Top-frame navigations fire `on_navigated(url)` once committed. External
 * schemes (mailto, tel, intent, …) and target=_blank attempts are denied.
 *
 * The `php` attribute swaps the sandbox for the app's own enriched Laravel
 * webview (see [PhpWebView]): pages served per-request by the embedded PHP
 * runtime, with the full JS bridge and the process-wide cookie session.
 */
object WebviewRenderer {

    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        if (node.props.getBool("php", false)) {
            PhpWebView(node, modifier)
            return
        }

        // Snapshot of the values we care about. `remember(key)` rebuilds
        // the WebView only when src/html actually change — avoids
        // recreating the surface on every recomposition (which would
        // reset scroll position and flicker).
        val src = node.props.getString("src", "")
        val html = node.props.getString("html", "")
        val jsEnabled = node.props.getBool("javascript", false)
        val domStorage = node.props.getBool("dom_storage", false)
        val onNavigatedCb = node.props.getCallbackId("on_navigated")
        val nodeId = node.id

        // Single content signature drives WebView reload decisions. We
        // don't include callback ids — those only affect dispatch, not
        // displayed content.
        val contentKey = remember(src, html, jsEnabled, domStorage) {
            "$src$html$jsEnabled$domStorage"
        }

        AndroidView(
            modifier = modifier,
            factory = { ctx ->
                @SuppressLint("SetJavaScriptEnabled")
                val webView = WebView(ctx).apply {
                    applyLockdownSettings(settings, jsEnabled = jsEnabled, domStorage = domStorage)

                    // No persistent cookies. CookieManager is process-
                    // wide, so clearing here also wipes cookies a sibling
                    // webview tried to set — acceptable while everything
                    // is locked down by default.
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)

                    webViewClient = LockdownClient(onNavigatedCb, nodeId)
                    webChromeClient = NoPopupChromeClient()

                    setBackgroundColor(0)
                }

                webView.loadContent(src, html)
                webView
            },
            update = { webView ->
                applyLockdownSettings(
                    webView.settings,
                    jsEnabled = jsEnabled,
                    domStorage = domStorage
                )
                (webView.webViewClient as? LockdownClient)?.let {
                    it.navigatedCallbackId = onNavigatedCb
                    it.nodeId = nodeId
                }
                if (webView.tag != contentKey) {
                    webView.tag = contentKey
                    webView.loadContent(src, html)
                }
            },
            onRelease = { webView ->
                webView.stopLoading()
                webView.webViewClient = WebViewClient()
                webView.webChromeClient = null
                webView.destroy()
            }
        )
    }
}

/**
 * Enriched-mode webview: an independent WebView wired exactly like the app's
 * main Laravel webview. [WebViewManager.setup] provides the full stack —
 * settings, cookie manager, the request-intercepting client that answers
 * `http://127.0.0.1` from the embedded PHP runtime, the POST-capture JS
 * interface, and the `window.Native` injection.
 *
 * Two integration hazards are handled here:
 * - `setup()` claims the process-wide [WebViewManager.shared] slot, which
 *   belongs to the app's root webview. It is restored immediately after.
 * - The stock client's `onPageStarted` drops out of native-UI mode
 *   (`isActive = false`) on every page load. Correct for the root webview;
 *   fatal for one embedded *inside* the native tree — it would unmount this
 *   very renderer. [PhpEmbedClient] delegates to the stock client (keeping
 *   the POST-inspector script injection it performs) and re-asserts
 *   native-UI mode afterwards.
 *
 * `src` is an app route path in this mode; anything not starting with `/`
 * (including empty) falls back to the app's configured start URL.
 */
@Composable
private fun PhpWebView(node: NativeUINode, modifier: Modifier) {
    val src = node.props.getString("src", "")
    val onNavigatedCb = node.props.getCallbackId("on_navigated")
    val nodeId = node.id

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val activity = (ctx as? MainActivity) ?: MainActivity.instance
                ?: return@factory WebView(ctx) // no shell activity — bare view, nothing to serve

            val webView = WebView(activity)
            val previousShared = WebViewManager.shared
            WebViewManager(activity, webView, PHPBridge(activity)).setup()
            WebViewManager.shared = previousShared

            webView.webViewClient = PhpEmbedClient(webView.webViewClient, onNavigatedCb, nodeId)

            val path = phpPath(src, activity)
            webView.tag = path
            webView.loadUrl("http://127.0.0.1$path")
            webView
        },
        update = { webView ->
            (webView.webViewClient as? PhpEmbedClient)?.let {
                it.navigatedCallbackId = onNavigatedCb
                it.nodeId = nodeId
            }
            val activity = (webView.context as? MainActivity) ?: MainActivity.instance
            if (activity != null) {
                val path = phpPath(src, activity)
                if (webView.tag != path) {
                    webView.tag = path
                    webView.loadUrl("http://127.0.0.1$path")
                }
            }
        },
        onRelease = { webView ->
            webView.stopLoading()
            webView.webViewClient = WebViewClient()
            webView.webChromeClient = null
            webView.destroy()
        }
    )
}

private fun phpPath(src: String, context: android.content.Context): String =
    if (src.startsWith("/")) src else LaravelEnvironment.getStartURL(context)

private class PhpEmbedClient(
    private val inner: WebViewClient,
    var navigatedCallbackId: Int,
    var nodeId: Int
) : WebViewClient() {

    override fun shouldInterceptRequest(
        view: WebView,
        request: WebResourceRequest
    ): WebResourceResponse? = inner.shouldInterceptRequest(view, request)

    override fun shouldOverrideUrlLoading(
        view: WebView,
        request: WebResourceRequest
    ): Boolean = inner.shouldOverrideUrlLoading(view, request)

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        inner.onPageStarted(view, url, favicon)
        // The delegate call above just flipped the app to web mode; undo it —
        // this webview renders inside the native tree, which must stay mounted.
        NativeUIBridge.isActive.value = true
    }

    override fun onPageFinished(view: WebView, url: String?) {
        inner.onPageFinished(view, url)
    }

    override fun onPageCommitVisible(view: WebView?, url: String?) {
        inner.onPageCommitVisible(view, url)
        val resolved = url.orEmpty()
        if (navigatedCallbackId != 0 && resolved.isNotEmpty()) {
            NativeUIBridge.sendTextChangeEvent(navigatedCallbackId, nodeId, resolved)
        }
    }
}

private fun WebView.loadContent(src: String, html: String) {
    if (html.isNotEmpty()) {
        // null baseURL → opaque origin. Embedded HTML can't issue
        // same-origin requests against the host app's URLs.
        loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
        return
    }
    if (src.isEmpty()) return
    if (!isLoadableScheme(src)) return
    loadUrl(src)
}

private fun applyLockdownSettings(
    settings: WebSettings,
    jsEnabled: Boolean,
    domStorage: Boolean
) {
    settings.javaScriptEnabled = jsEnabled
    settings.domStorageEnabled = domStorage
    settings.allowFileAccess = false
    settings.allowContentAccess = false
    @Suppress("DEPRECATION")
    settings.allowFileAccessFromFileURLs = false
    @Suppress("DEPRECATION")
    settings.allowUniversalAccessFromFileURLs = false
    settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
    settings.javaScriptCanOpenWindowsAutomatically = false
    settings.setSupportMultipleWindows(false)
    settings.mediaPlaybackRequiresUserGesture = true
    settings.setGeolocationEnabled(false)
    settings.databaseEnabled = false
    settings.cacheMode = WebSettings.LOAD_NO_CACHE
}

private class LockdownClient(
    var navigatedCallbackId: Int,
    var nodeId: Int
) : WebViewClient() {

    override fun shouldOverrideUrlLoading(
        view: WebView,
        request: WebResourceRequest
    ): Boolean {
        val url: Uri = request.url ?: return true
        if (!request.isForMainFrame) {
            return false
        }
        if (!isLoadableScheme(url.scheme)) {
            // Drop external-scheme top-frame navigation (mailto, tel,
            // intent, …). Returning `true` cancels the load instead of
            // dispatching it to the system handler.
            return true
        }
        return false
    }

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        // onPageStarted fires before the server has responded; we
        // prefer onPageCommitVisible / onPageFinished. Override left
        // empty so the default behavior doesn't proxy through.
    }

    override fun onPageCommitVisible(view: WebView?, url: String?) {
        // Most reliable "the user is now looking at this URL" hook on
        // Android. Mirrors iOS's `didCommit`.
        val resolved = url.orEmpty()
        if (navigatedCallbackId != 0 && resolved.isNotEmpty()) {
            NativeUIBridge.sendTextChangeEvent(navigatedCallbackId, nodeId, resolved)
        }
    }
}

private class NoPopupChromeClient : WebChromeClient() {
    override fun onCreateWindow(
        view: WebView,
        isDialog: Boolean,
        isUserGesture: Boolean,
        resultMsg: android.os.Message?
    ): Boolean {
        // target=_blank / window.open() → denied. Returning false drops
        // the new-window request silently.
        return false
    }
}

private fun isLoadableScheme(scheme: String?): Boolean {
    if (scheme.isNullOrEmpty()) return false
    val s = scheme.lowercase()
    return s == "https" || s == "http" || s == "data" || s == "about"
}

private fun isLoadableScheme(url: String): Boolean {
    val parsed = Uri.parse(url)
    return isLoadableScheme(parsed.scheme)
}
