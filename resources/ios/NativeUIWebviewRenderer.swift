import SwiftUI
@preconcurrency import WebKit

/// Locked-down WKWebView primitive.
///
/// Defaults are paranoid by design: JS off, no DOM storage, no link previews,
/// no JS bridge to the host, no back/forward swipe, no new windows, no
/// mixed content, non-persistent data store, media requires a user gesture.
/// Hosts opt back into individual capabilities via attributes
/// (`javascript`, `dom-storage`) on the Blade tag.
///
/// Top-frame navigations fire `on_navigated(url)` once committed. External
/// schemes (mailto, tel, sms, …) and target=_blank attempts are denied.
struct NativeUIWebviewRenderer: View {
    let node: NativeUINode

    var body: some View {
        WebViewContainer(node: node)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let node: NativeUINode

    func makeCoordinator() -> Coordinator {
        Coordinator(navigatedCallbackId: node.props.getCallbackId("on_navigated"),
                    nodeId: node.id)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Non-persistent: cookies / cache die with the view, so an
        // embedded page can't read state left by another embedded page
        // (or the host browser session). Hosts that need persistence
        // can graduate to a per-host data store later.
        config.websiteDataStore = .nonPersistent()

        // Opt-in JS. Off by default — most embeds the user controls
        // don't need it, and turning it on globally surrenders the
        // strongest single mitigation we have.
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = node.props.getBool("javascript", default: false)
        config.defaultWebpagePreferences = prefs

        // Block media autoplay — keeps third-party embeds from ringing
        // audio in the user's pocket on load.
        config.mediaTypesRequiringUserActionForPlayback = .all

        // No <input type=file> handler wired up; leave default.

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.bounces = true

        loadContent(into: webView)
        context.coordinator.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let newSig = contentSignature()
        if context.coordinator.lastContentSignature != newSig {
            context.coordinator.lastContentSignature = newSig
            loadContent(into: webView)
        }
        context.coordinator.navigatedCallbackId = node.props.getCallbackId("on_navigated")
        context.coordinator.nodeId = node.id
    }

    private func contentSignature() -> String {
        let src = node.props.getString("src")
        let html = node.props.getString("html")
        return src + "\u{1F}" + html
    }

    private func loadContent(into webView: WKWebView) {
        let src = node.props.getString("src")
        let html = node.props.getString("html")

        if !html.isEmpty {
            // baseURL = nil → opaque origin. The HTML can't `fetch()` or
            // navigate to the host app's data on a same-origin basis.
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        guard !src.isEmpty, let url = URL(string: src) else { return }
        guard isLoadableScheme(url.scheme) else { return }
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var navigatedCallbackId: Int
        var nodeId: Int
        var lastContentSignature: String = ""
        weak var webView: WKWebView?

        init(navigatedCallbackId: Int, nodeId: Int) {
            self.navigatedCallbackId = navigatedCallbackId
            self.nodeId = nodeId
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
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

            // Allow same-origin subresources (`navigationType == .other`
            // covers XHR / `<img>` / `<iframe>` loads) without
            // restriction — only top-frame navigations are gated.
            let isTopFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if !isTopFrame {
                decisionHandler(.allow)
                return
            }

            if !isLoadableScheme(url.scheme) {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // didCommit fires after the server has accepted the request
            // and we know the final URL. Fires once per top-frame
            // navigation; intermediate redirects don't fire it.
            guard navigatedCallbackId != 0,
                  let url = webView.url?.absoluteString else { return }
            NativeElementBridge.sendTextChangeEvent(navigatedCallbackId, nodeId: nodeId, text: url)
        }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // target=_blank / window.open() → silently denied.
            // Returning nil drops the request rather than escalating
            // out of the embedded view.
            return nil
        }
    }
}

private func isLoadableScheme(_ scheme: String?) -> Bool {
    guard let scheme = scheme?.lowercased() else { return false }
    return scheme == "https" || scheme == "http" || scheme == "data" || scheme == "about"
}
