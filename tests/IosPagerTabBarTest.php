<?php

it('runs a horizontal pager under a bar at the bottom of the screen', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('let bottomInset = horizontal ? geo.safeAreaInsets.bottom : 0')
        ->toContain('height: geo.size.height + bottomInset')
        ->toContain('.ignoresSafeArea(.container, edges: horizontal ? .bottom : [])');
});

it('gives the bar inset back to the page content as safe area', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)->toMatch('/\.safeAreaPadding\(\.bottom, bottomInset\)\s*\.frame\(width: size\.width, height: size\.height\)\s*\.clipped\(\)/');
});
