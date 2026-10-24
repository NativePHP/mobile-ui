<?php

$ios = dirname(__DIR__).'/resources/ios';

it('loads every remote image through the retrying cache, not AsyncImage', function () use ($ios) {
    foreach (glob($ios.'/*.swift') as $file) {
        expect(preg_match('/^\s*AsyncImage\(/m', file_get_contents($file)))->toBe(0, basename($file).' still uses AsyncImage');
    }

    expect(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))->toContain('NativeUIRemoteImage(url: url)')
        ->and(file_get_contents($ios.'/NativeUIImageSource.swift'))->toContain('NativeUIRemoteImage(url: url)')
        ->and(file_get_contents($ios.'/NativeUIPagerRenderer.swift'))->toContain('NativeUIRemoteImage(url: url)');
});

it('keeps a download going when the view that asked for it is recreated', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('let task = loads[url] ?? start(url)')
        ->toContain('Task.detached(priority: .userInitiated)');
});

it('tries a download again only when it might work next time', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('private static let retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]')
        ->toContain('http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500 ? .transient : .permanent');
});

it('shows a spinner while loading and nothing once it has failed', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))
        ->toContain('} placeholder: { failed in');
});
