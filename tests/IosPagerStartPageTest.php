<?php

it('puts the start page in place in the first layout', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('.defaultScrollAnchor(startAnchor, for: .initialOffset)')
        ->toContain('let fraction = count > 1 ? CGFloat(requestedPage) / CGFloat(count - 1) : 0');
});

it('reports no page before the pager has a size', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('.onScrollGeometryChange(for: Int?.self)')
        ->toContain('guard length > 0, count > 0 else { return nil }')
        ->toContain('guard let page else { return }');
});
