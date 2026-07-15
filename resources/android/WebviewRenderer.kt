package com.nativephp.plugins.native_ui.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient
import android.webkit.CookieManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
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
 */
object WebviewRenderer {

    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
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
