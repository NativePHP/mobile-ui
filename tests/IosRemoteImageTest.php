<?php

$ios = dirname(__DIR__).'/resources/ios';

it('loads every remote image through NativeUIRemoteImage', function () use ($ios) {
    $uses = 0;
    foreach (glob($ios.'/*.swift') as $file) {
        $uses += preg_match_all('/\bAsyncImage\(url:/', file_get_contents($file));
    }

    // The one AsyncImage left is the one inside NativeUIRemoteImage.
    expect($uses)->toBe(1)
        ->and(file_get_contents($ios.'/NativeUIImageSource.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in')
        ->and(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in')
        ->and(file_get_contents($ios.'/NativeUIPagerRenderer.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in');
});

it('tries a failed download again with a new AsyncImage', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('private static var retryDelays: [Duration] { [.milliseconds(500), .milliseconds(1500)] }')
        ->toContain('.id(attempt)');
});

it('starts a cancelled download again without counting it as a failure', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('if Self.isCancellation(error) {')
        ->toContain('content(.empty).task { attempt += 1 }');
});

it('lets an image that ran out of tries load again when it next comes on screen', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('content(phase).onDisappear { failures = 0 }');
});
