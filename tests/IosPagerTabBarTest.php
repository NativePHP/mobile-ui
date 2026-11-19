<?php

it('runs a horizontal pager under a bar at the bottom of the screen and at its sides', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('EdgeInsets(top: 0, leading: geo.safeAreaInsets.leading, bottom: geo.safeAreaInsets.bottom, trailing: geo.safeAreaInsets.trailing)')
        ->toContain('CGSize(width: geo.size.width + insets.leading + insets.trailing, height: geo.size.height + insets.bottom)')
        ->toContain('.ignoresSafeArea(.container, edges: horizontal ? [.bottom, .horizontal] : [])');
});

it('gives the bar insets back to the page content as safe area', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)->toMatch('/\.safeAreaPadding\(insets\)\s*\.frame\(width: size\.width, height: size\.height\)\s*\.clipped\(\)/');
});

it('pages a horizontal pager by its own width and clips its sides beside a sideways bar', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('let length = horizontal ? geometry.bounds.width : visible.height')
        ->toContain('.clipShape(PagerSideClip(horizontal: horizontal))')
        ->toContain('.clipShape(PagerSideClip(horizontal: true))');
});

it('runs lists and scroll views under a bar at their sides and hands its inset back as safe area', function () {
    $ios = dirname(__DIR__).'/resources/ios/';

    expect(file_get_contents($ios.'NativeUIScrollViewRenderer.swift'))
        ->toMatch('/\.safeAreaPadding\(\.leading, insets\.leading\)\s*\.safeAreaPadding\(\.trailing, insets\.trailing\)\s*\.ignoresSafeArea\(\.container, edges: \.horizontal\)/');

    foreach (['NativeUIScrollViewRenderer.swift', 'NativeUIListRenderer.swift', 'NativeUIVirtualListRenderer.swift', 'NativeUIPagerRenderer.swift'] as $file) {
        expect(file_get_contents($ios.$file))->toContain('.modifier(NativeUIScrollEdgeExtension())');
    }
});
