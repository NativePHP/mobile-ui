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
// ## What is not here
//
// `php` mode — the enriched form, where the webview is served by the app's own
// embedded PHP runtime over the `php://` scheme with a shared Laravel session and
// the `window.Native` bridge. On iOS that is four shell-owned types
// (`WebviewPHPRuntime`, `PHPSchemeHandler`, `WebView`, `SharedWebView`), one of
// which spins up a dedicated interpreter thread per webview. The desktop shell
// has no equivalent yet: its single embedded runtime is parked in the surface
// coordinator's event loop and cannot answer a scheme handler's requests while it
// is waiting there.
//
// So `php` mode says so, on the screen, rather than loading nothing and leaving
// the developer to guess whether the attribute is wrong or the page is blank.

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
                UnsupportedPHPWebview()
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

/// What `php` mode draws here, until the desktop shell can serve `php://`.
///
/// A message rather than an empty rectangle. The failure this replaces is the
/// worst kind: the element lays out correctly, so the screen looks finished and
/// simply has nothing in the frame, and there is no way to tell that from a page
/// that returned a blank body.
private struct UnsupportedPHPWebview: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("`php` mode is iOS-only for now")
                .font(.system(size: 13, weight: .semibold))
            Text("A `php` webview is served by the app's own embedded runtime over php://.\nThe desktop shell has one runtime and it is busy rendering this window.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            NSLog("NativeUIWebviewRenderer: `php` mode is not implemented on macOS — the element rendered an explanatory panel instead.")
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
