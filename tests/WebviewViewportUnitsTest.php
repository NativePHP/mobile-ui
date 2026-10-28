<?php

it('gives Android webviews with a fixed height MATCH_PARENT height so viewport units are not 0', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/WebviewRenderer.kt');

    expect($source)
        ->toContain('val height = if (constraints.hasFixedHeight) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT')
        ->toContain('webView.layoutParams = ViewGroup.LayoutParams(params?.width ?: ViewGroup.LayoutParams.WRAP_CONTENT, height)');
});

it('applies the viewport height to both the sandboxed and the php webview on Android', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/WebviewRenderer.kt');

    expect(substr_count($source, 'modifier = modifier.clipToBounds().viewportHeight(webViewRef)'))->toBe(2);
});
