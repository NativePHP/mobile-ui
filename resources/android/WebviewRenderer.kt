package com.nativephp.plugins.native_ui.ui

import android.annotation.SuppressLint
import android.content.res.Configuration
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.nativephp.mobile.bridge.LaravelEnvironment
import com.nativephp.mobile.bridge.PHPBridge
import com.nativephp.mobile.bridge.WebviewPHPRuntime
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
            modifier = modifier.clipToBounds(),
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
 * `embedded = true` keeps the stock client out of app-level state: its page
 * loads never drop the app out of native-UI mode, so the native tree this
 * renderer lives in stays mounted. [PhpEmbedClient] delegates to the stock
 * client for everything, keeping the POST-inspector script injection it
 * performs.
 *
 * Mobile releases from before the shell stopped doing so have `setup()`
 * claim the process-wide [WebViewManager.shared] slot even when embedded.
 * That slot belongs to the app's root webview, so it is saved and restored
 * around the call. On a release that leaves the slot alone the restore
 * changes nothing; drop it once the minimum supported mobile version is one
 * of those.
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
        modifier = modifier.clipToBounds(),
        factory = { ctx ->
            val activity = (ctx as? MainActivity) ?: MainActivity.instance
            if (activity == null) {
                // No shell activity — bare view, nothing to serve
                WebView(ctx)
            } else {
                val webView = WebView(activity)

                // Transparent until Chromium's first paint — a fresh WebView
                // surface otherwise renders opaque black over the window for
                // a beat (the "black flash"), hiding the native siblings.
                webView.setBackgroundColor(android.graphics.Color.TRANSPARENT)

                // Dedicated PHP context for this webview — phpExecutor is parked
                // in the native screen's event loop and can never serve our
                // requests. Released via PhpEmbedClient in onRelease.
                val bridge = PHPBridge(activity)
                val phpRuntime = WebviewPHPRuntime(bridge)
                bridge.dedicatedWebviewRuntime = phpRuntime

                // Mobile releases without the shell fix claim
                // WebViewManager.shared here even for an embedded webview;
                // put the root webview's back.
                val previousShared = WebViewManager.shared
                WebViewManager(activity, webView, bridge, embedded = true).setup()
                WebViewManager.shared = previousShared

                val safeArea = if (node.props.getBool("fullscreen", false)) PhpWebViewSafeArea(webView) else null
                webView.webViewClient = PhpEmbedClient(webView.webViewClient, onNavigatedCb, nodeId, phpRuntime, safeArea)
                safeArea?.let { area ->
                    // Rotation and window resizes change the insets.
                    webView.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
                        if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) {
                            area.inject()
                        }
                    }
                }

                val path = phpPath(src, activity)
                webView.tag = path
                webView.loadUrl("http://127.0.0.1$path")
                webView
            }
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
            // Stop this webview's dedicated PHP thread the moment the
            // webview leaves the view hierarchy.
            (webView.webViewClient as? PhpEmbedClient)?.phpRuntime?.release()
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
    var nodeId: Int,
    val phpRuntime: WebviewPHPRuntime? = null,
    private val safeArea: PhpWebViewSafeArea? = null
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
        // The stock client skips the switch to web mode for an embedded
        // webview, so the native tree around this one stays mounted.
        inner.onPageStarted(view, url, favicon)
        safeArea?.inject(force = true)
    }

    override fun onPageFinished(view: WebView, url: String?) {
        inner.onPageFinished(view, url)
        safeArea?.inject(force = true)
    }

    override fun onPageCommitVisible(view: WebView?, url: String?) {
        inner.onPageCommitVisible(view, url)
        // Surface-geometry nudge: a WebView created mid-composition can
        // paint its layer at a stale offset until the next layout pass.
        view?.requestLayout()
        val resolved = url.orEmpty()
        if (navigatedCallbackId != 0 && resolved.isNotEmpty()) {
            NativeUIBridge.sendTextChangeEvent(navigatedCallbackId, nodeId, resolved)
        }
    }
}

/**
 * `MainActivity.injectSafeAreaInsets` for a fullscreen php webview. The shell
 * only injects into the root webview, so pages here get no `--inset-*` at all.
 *
 * The insets come from this webview's own window. Script evaluated from a page
 * callback can land after the page has rendered, so the same script also runs
 * at document start of every later page, like the shell's request body shim.
 */
private class PhpWebViewSafeArea(private val webView: WebView) {
    private var injected: Insets? = null
    private var startScript: ScriptHandler? = null

    /** `force` re-injects unchanged insets, for a page that's loading. */
    fun inject(force: Boolean = false) {
        val insets = ViewCompat.getRootWindowInsets(webView)
            ?.getInsets(WindowInsetsCompat.Type.systemBars()) ?: return
        val changed = insets != injected
        if (!changed && !force) return
        injected = insets

        val js = script(insets)
        if (changed && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            startScript?.remove()
            startScript = WebViewCompat.addDocumentStartJavaScript(webView, js, setOf("http://127.0.0.1"))
        }
        webView.evaluateJavascript(js, null)
    }

    private fun script(insets: Insets): String {
        val density = webView.resources.displayMetrics.density
        val leftPx = (insets.left / density).toInt()
        val topPx = (insets.top / density).toInt()
        val rightPx = (insets.right / density).toInt()
        val bottomPx = (insets.bottom / density).toInt()
        val isPortrait = webView.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT

        return """
        (function() {
            function injectSafeAreaStyles() {
                const existingStyle = document.getElementById('nativephp-safe-area-style');
                if (existingStyle) {
                    existingStyle.remove();
                }

                const style = document.createElement('style');
                style.id = 'nativephp-safe-area-style';
                style.setAttribute('data-nativephp-persist', 'true');
                style.textContent = ':root { --inset-top: ${topPx}px; --inset-right: ${rightPx}px; --inset-bottom: ${bottomPx}px; --inset-left: ${leftPx}px; } .nativephp-safe-area { ${if (isPortrait) "padding-top: var(--inset-top); padding-bottom: var(--inset-bottom);" else "padding-right: var(--inset-right); padding-left: var(--inset-left);"} }';

                if (!document.head) {
                    const head = document.createElement('head');
                    if (document.documentElement) {
                        document.documentElement.insertBefore(head, document.documentElement.firstChild);
                    }
                }

                if (document.head) {
                    if (document.head.firstChild) {
                        document.head.insertBefore(style, document.head.firstChild);
                    } else {
                        document.head.appendChild(style);
                    }
                }

                if (document.documentElement) {
                    document.documentElement.style.setProperty('--inset-top', '${topPx}px');
                    document.documentElement.style.setProperty('--inset-right', '${rightPx}px');
                    document.documentElement.style.setProperty('--inset-bottom', '${bottomPx}px');
                    document.documentElement.style.setProperty('--inset-left', '${leftPx}px');

                    document.documentElement.classList.remove('portrait', 'landscape');
                    document.documentElement.classList.add('${if (isPortrait) "portrait" else "landscape"}');
                }
            }

            injectSafeAreaStyles();

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', injectSafeAreaStyles);
            }

            document.addEventListener('livewire:navigated', injectSafeAreaStyles);
        })();
        """
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
    if (!isLoadableUrl(src)) return
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
    // Deprecated in API 33 — the Web SQL Database API it gates was removed from
    // WebView entirely. Suppressed rather than deleted: `minSdk` is 26, and on
    // an older device carrying an older WebView the setting still does
    // something, so dropping it would quietly weaken the lockdown on exactly
    // the devices that need it most. Same reasoning as the two suppressions
    // above.
    @Suppress("DEPRECATION")
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

private fun isLoadableUrl(url: String): Boolean {
    val parsed = Uri.parse(url)
    return isLoadableScheme(parsed.scheme)
}
