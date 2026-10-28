<?php

it('injects the safe-area insets into a fullscreen php webview on iOS', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIWebviewRenderer.swift');

    expect($source)
        ->toContain('injectsSafeAreaInsets: node.props.getBool("fullscreen", default: false)')
        ->toContain('guard injectsSafeAreaInsets, let window = webView.window else { return }')
        ->toContain("document.documentElement.style.setProperty('--inset-top', '\\(insets.top)px');");
});

it('re-injects on iOS after each navigation and when the window width changes', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIWebviewRenderer.swift');

    expect($source)
        ->toContain('@Environment(\.windowWidth) private var windowWidth')
        ->toContain("if context.coordinator.lastWindowWidth != windowWidth {\n            context.coordinator.lastWindowWidth = windowWidth\n            context.coordinator.injectSafeAreaInsets(webView)")
        ->toContain("func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {\n            injectSafeAreaInsets(webView)");
});

it('runs the iOS insets script at document start without dropping the other user scripts', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIWebviewRenderer.swift');

    expect($source)
        ->toContain('WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)')
        ->toContain('let otherScripts = controller.userScripts.filter { $0 !== insetsScript }')
        ->toContain('otherScripts.forEach(controller.addUserScript)');
});

it('injects the safe-area insets into a fullscreen php webview on Android', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/WebviewRenderer.kt');

    expect($source)
        ->toContain('val safeArea = if (node.props.getBool("fullscreen", false)) PhpWebViewSafeArea(webView) else null')
        ->toContain('ViewCompat.getRootWindowInsets(webView)')
        ->toContain("document.documentElement.style.setProperty('--inset-top', '\${topPx}px');");
});

it('re-injects on Android on page loads, size changes and at document start', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/WebviewRenderer.kt');

    expect($source)
        ->toContain("inner.onPageStarted(view, url, favicon)\n        safeArea?.inject(force = true)")
        ->toContain('webView.addOnLayoutChangeListener')
        ->toContain('startScript?.remove()')
        ->toContain('WebViewCompat.addDocumentStartJavaScript(webView, js, setOf("http://127.0.0.1"))');
});
