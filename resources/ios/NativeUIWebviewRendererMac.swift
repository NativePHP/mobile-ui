#if os(macOS)
import AppKit
import SwiftUI
@preconcurrency import WebKit

// MARK: - `webview` on macOS
//
// The iOS renderer (NativeUIWebviewRenderer.swift, next to this file) is a
// `UIViewRepresentable` and reaches into the iOS shell's own webview types for
// its `php` mode, so it cannot be contributed here — which is why `webview` was
// the one component of this package with no macOS renderer at all, and why every
// webview demo drew a blank column.
//
// This is the same element, same props, same events, built on `WKWebView`
// through `NSViewRepresentable`. Only the two files' plumbing differs; the
// posture below is copied deliberately, line for line, from the iOS container so
// that a page embedded in a Mac app is sandboxed exactly as tightly as the same
// markup is on a phone.
//
// ## `php` mode
//
// The enriched form, where the webview is served by the app's own embedded PHP
// runtime over the `php://` scheme, sharing the app's Laravel session. It works
// here now, on the same principle as iOS: the element runtime's thread is parked
// inside `nativephp_element_wait_event()` for the app's whole life and can never
// answer a page request, so the webview gets an interpreter of its own on a
// thread of its own. The two shell types that do it are `WebviewPHPRuntime` (the
// interpreter) and `WebviewSchemeHandler` (the routing), and the long comments
// on both are where the reasoning lives.
//
// What this does not have, and iOS does, is the `window.Native` bridge inside
// the page — that is a mobile shell type with no desktop counterpart yet. A page
// that checks for `window.Native` will find nothing.

/// Locked-down `WKWebView` primitive.
///
/// Defaults are paranoid by design: JS off, non-persistent data store, no link
/// previews, no back/forward swipe, no new windows, media requires a user
/// gesture. Hosts opt back into individual capabilities via attributes
/// (`javascript`) on the Blade tag.
///
/// Top-frame navigations fire `on_navigated(url)` once committed. External
/// schemes (mailto, tel, …) and `target=_blank` attempts are denied.
struct NativeUIWebviewRenderer: View {
    let node: NativeUINode

    var body: some View {
        let content = Group {
            if node.props.getBool("php", default: false) {
                MacPHPWebViewContainer(node: node)
            } else {
                MacWebViewContainer(node: node)
            }
        }

        if node.props.getBool("fullscreen", default: false) {
            // Same meaning as on iOS: the element already arrives with fill
            // layout from PHP, and this lets it reach behind the window's safe
            // area — which on a Mac is the strip the traffic lights sit in.
            content.ignoresSafeArea(.container, edges: .all)
        } else {
            content
        }
    }
}

/// Enriched-mode container: the app's own Laravel, in a webview.
///
/// Every request the page makes — the page itself, its stylesheets, its
/// `fetch()` calls — is answered by `WebviewSchemeHandler` out of an interpreter
/// this view owns, and stops existing when the view does. Two `php` webviews on
/// screen are two interpreters; neither is the element runtime, and neither can
/// block it.
///
/// `src` is an app route path (`/dashboard`), not a URL. Anything that doesn't
/// start with `/` is treated as the app root, which is the same rule iOS uses.
private struct MacPHPWebViewContainer: NSViewRepresentable {
    let node: NativeUINode

    /// Shared so that two `php` webviews are one browsing context as far as
    /// caching goes. Non-persistent because the state that actually matters —
    /// the session — lives in `WebviewCookieJar` on the native side; WebKit
    /// gives a custom scheme no cookie handling and no local storage anyway.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    func makeCoordinator() -> Coordinator {
        Coordinator(navigatedCallbackId: node.props.getCallbackId("on_navigated"),
                    nodeId: node.id)
    }

    /// The interpreter goes when the view goes. A `php` webview costs a thread
    /// and a booted Laravel; leaving one running behind a screen the user
    /// navigated away from is a leak with a heartbeat.
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.runtime?.release()
        coordinator.runtime = nil
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore

        // On, and not an opt-in like the sandboxed container's. This is the
        // app's own markup being rendered by the app's own runtime; a Blade view
        // that can't run its own script is not the thing the developer asked
        // for.
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        guard let runtime = WebviewPHPRuntime() else {
            // No bootstrap in the bundle — nothing can serve this. Return an
            // empty webview showing why, rather than a blank rectangle.
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.loadHTMLString(Self.unavailableHTML, baseURL: nil)
            return webView
        }

        context.coordinator.runtime = runtime
        config.setURLSchemeHandler(WebviewSchemeHandler(runtime: runtime),
                                   forURLScheme: WebviewSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false

        let path = startPath()
        context.coordinator.lastPath = path
        load(path, into: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let path = startPath()

        if context.coordinator.lastPath != path {
            context.coordinator.lastPath = path
            load(path, into: webView)
        }

        context.coordinator.navigatedCallbackId = node.props.getCallbackId("on_navigated")
        context.coordinator.nodeId = node.id
    }

    private func startPath() -> String {
        let src = node.props.getString("src")

        return src.hasPrefix("/") ? src : "/"
    }

    private func load(_ path: String, into webView: WKWebView) {
        let base = "\(WebviewSchemeHandler.scheme)://\(WebviewSchemeHandler.host)"

        guard let url = URL(string: base + path) else {
            NSLog("NativeUIWebviewRenderer: php mode — unloadable path '\(path)'")
            return
        }

        webView.load(URLRequest(url: url))
    }

    private static let unavailableHTML = """
    <!doctype html><meta charset="utf-8">
    <body style="font:13px -apple-system,system-ui;padding:24px;color:#444">
    <p><strong>This webview has no PHP runtime.</strong></p>
    <p>The shell could not find <code>Resources/php/webview.php</code> in the app bundle,
    so there is nothing to serve <code>php://</code> requests with.</p>
    </body>
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var navigatedCallbackId: Int
        var nodeId: Int
        var lastPath: String = ""
        var runtime: WebviewPHPRuntime?

        init(navigatedCallbackId: Int, nodeId: Int) {
            self.navigatedCallbackId = navigatedCallbackId
            self.nodeId = nodeId
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let isTopFrame = navigationAction.targetFrame?.isMainFrame ?? true

            guard isTopFrame else {
                decisionHandler(.allow)
                return
            }

            switch url.scheme?.lowercased() {
            case WebviewSchemeHandler.scheme, "about", "data":
                decisionHandler(.allow)
            default:
                // A link out of the app goes to the user's browser, where a
                // link out of an app belongs. Same rule the classic webview
                // has always followed.
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard navigatedCallbackId != 0,
                  let url = webView.url?.absoluteString else { return }

            NativeElementBridge.sendTextChangeEvent(navigatedCallbackId, nodeId: nodeId, text: url)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("NativeUIWebviewRenderer: php mode — provisional load failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("NativeUIWebviewRenderer: php mode — load failed: \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("NativeUIWebviewRenderer: php mode — content process terminated, reloading")
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}

private struct MacWebViewContainer: NSViewRepresentable {
    let node: NativeUINode

    func makeCoordinator() -> Coordinator {
        Coordinator(navigatedCallbackId: node.props.getCallbackId("on_navigated"),
                    nodeId: node.id)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Non-persistent: cookies / cache die with the view, so an embedded
        // page can't read state left by another embedded page (or by the user's
        // browser session).
        config.websiteDataStore = .nonPersistent()

        // Opt-in JS. Off by default — most embeds don't need it, and turning it
        // on globally surrenders the strongest single mitigation there is.
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = node.props.getBool("javascript", default: false)
        config.defaultWebpagePreferences = prefs

        // Block media autoplay, so a third-party embed can't start making noise
        // the moment the screen appears.
        config.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        // Deliberately NOT made transparent, unlike the iOS container. AppKit's
        // WKWebView draws its own background by default, and leaving it that way
        // is right here: a Mac window has a light window background behind the
        // element, so a transparent webview over a page with no background of
        // its own reads as a rendering failure rather than as a design.

        loadContent(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let signature = contentSignature()

        if context.coordinator.lastContentSignature != signature {
            context.coordinator.lastContentSignature = signature
            loadContent(into: webView)
        }

        context.coordinator.navigatedCallbackId = node.props.getCallbackId("on_navigated")
        context.coordinator.nodeId = node.id
    }

    /// What the webview is showing, as one comparable value.
    ///
    /// `updateNSView` runs on every published frame — sixty a second on a
    /// polling screen — and reloading a page each time would make the webview
    /// permanently blank. So the content is only re-loaded when the thing being
    /// shown actually changed.
    private func contentSignature() -> String {
        node.props.getString("src") + "\u{1F}" + node.props.getString("html")
    }

    private func loadContent(into webView: WKWebView) {
        let html = node.props.getString("html")

        if !html.isEmpty {
            // baseURL = nil → opaque origin. The HTML can't `fetch()` or
            // navigate to the host app's data on a same-origin basis.
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        let src = node.props.getString("src")

        guard !src.isEmpty,
              let url = URL(string: src),
              nuiIsLoadableWebviewScheme(url.scheme) else { return }

        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var navigatedCallbackId: Int
        var nodeId: Int
        var lastContentSignature: String = ""

        init(navigatedCallbackId: Int, nodeId: Int) {
            self.navigatedCallbackId = navigatedCallbackId
            self.nodeId = nodeId
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // Only top-frame navigations are gated; subresource loads (XHR,
            // `<img>`, `<iframe>`) go through untouched.
            let isTopFrame = navigationAction.targetFrame?.isMainFrame ?? true

            guard isTopFrame else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(nuiIsLoadableWebviewScheme(url.scheme) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // didCommit fires once the server has accepted the request and the
            // final URL is known — once per top-frame navigation, not for the
            // redirects on the way.
            guard navigatedCallbackId != 0,
                  let url = webView.url?.absoluteString else { return }

            NativeElementBridge.sendTextChangeEvent(navigatedCallbackId, nodeId: nodeId, text: url)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("NativeUIWebviewRenderer: provisional load failed — \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("NativeUIWebviewRenderer: content process terminated — reloading")
            webView.reload()
        }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // `target=_blank` / `window.open()` — dropped rather than escalated
            // out of the embedded view into a new window.
            nil
        }
    }
}

private func nuiIsLoadableWebviewScheme(_ scheme: String?) -> Bool {
    guard let scheme = scheme?.lowercased() else { return false }

    return scheme == "https" || scheme == "http" || scheme == "data" || scheme == "about"
}
#endif
