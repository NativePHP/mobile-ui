<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Image;
use Native\Mobile\Edge\NativeElementCollector;

$ios = dirname(__DIR__).'/resources/ios';

it('loads every remote image through NativeUIRemoteImage', function () use ($ios) {
    $uses = 0;
    foreach (glob($ios.'/*.swift') as $file) {
        $uses += preg_match_all('/\bAsyncImage\(url:/', file_get_contents($file));
    }

    // No plain AsyncImage: it uses the small shared URLCache and decodes at full size.
    expect($uses)->toBe(0)
        ->and(file_get_contents($ios.'/NativeUIImageSource.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in')
        ->and(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))->toContain('NativeUIRemoteImage(url: url, fullSize: fit == .none, revalidate: revalidates) { phase in')
        ->and(file_get_contents($ios.'/NativeUIPagerRenderer.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in');
});

it('downloads through its own session with a small memory tier and a disk cache', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('private static let memoryCapacity = 2 * 1024 * 1024')
        ->toContain('URLCache(memoryCapacity: memoryCapacity, diskCapacity: 50 * 1024 * 1024, directory: directory)')
        ->toContain('configuration.requestCachePolicy = .useProtocolCachePolicy')
        ->toContain('try await session.data(for: request)');
});

it('reuses a cached response however old it is, unless the image revalidates', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('if !key.revalidate, let cached = urlCache.cachedResponse(for: request) {')
        ->toContain('(200..<300).contains(http.statusCode)')
        ->toContain('urlCache.removeCachedResponse(for: request)');
});

it('shares one download per URL and cancels it only when nobody is waiting', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('@MainActor private static var downloads: [DownloadKey: Download] = [:]')
        ->toContain('try? await Task.sleep(for: .milliseconds(300))')
        ->toContain('guard self.waiters.isEmpty, !self.finished else {')
        ->toContain('self.task?.cancel()');
});

it('keeps only a small cache of decoded remote images', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('private static let decodedCapacity = 4 * 1024 * 1024')
        ->toContain('cache.totalCostLimit = decodedCapacity')
        ->toContain('if entry.cost <= decodedCapacity / 2 {')
        ->toContain('decoded.setObject(entry, forKey: url as NSURL, cost: entry.cost)');
});

it('empties the decoded cache and the URLCache memory tier on a memory warning and in the background', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('decoded.removeAllObjects()')
        ->toContain('UIApplication.didReceiveMemoryWarningNotification,')
        ->toContain('UIApplication.didEnterBackgroundNotification,')
        ->toContain('urlCache.memoryCapacity = 0');
});

it('passes revalidate from the image element to the remote image', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))
        ->toContain('return p.getBool("revalidate") || ["true", "1"].contains(p.getString("revalidate"))')
        ->and(file_get_contents(dirname(__DIR__).'/src/NativeUIServiceProvider.php'))
        ->toContain("NativeElementCollector::captureAttribute('revalidate', 'revalidate');");
});

it('carries revalidate onto the image node as a prop', function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('image', Image::class);
    NativeElementCollector::captureAttribute('revalidate', 'revalidate');

    try {
        NativeElementCollector::leaf('image', ['src' => 'https://example.com/a.jpg', 'revalidate' => true]);
        $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

        expect($props['revalidate'])->toBeTrue()
            ->and($props['src'])->toBe('https://example.com/a.jpg');

        NativeElementCollector::reset();
        NativeElementCollector::leaf('image', ['src' => 'https://example.com/a.jpg']);
        $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

        expect($props)->not->toHaveKey('revalidate');
    } finally {
        NativeElementCollector::stopCapturingAttributes();
        NativeElementCollector::reset();
        ElementRegistry::reset();
    }
});

it('thumbnails with ImageIO only when the source is well over the drawn size', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('if fill < 1 / 1.5 {')
        ->toContain('kCGImageSourceCreateThumbnailFromImageAlways: true')
        ->toContain('kCGImageSourceShouldCacheImmediately: true')
        ->toContain('CGImageSourceCreateThumbnailAtIndex(source, 0, options)');
});

it('tries a failed download again after a delay, but not a cancelled one', function () use ($ios) {
    $source = file_get_contents($ios.'/NativeUIImageSource.swift');

    expect($source)
        ->toContain('private static var retryDelays: [Duration] { [.milliseconds(500), .milliseconds(1500)] }')
        ->toContain('try? await Task.sleep(for: Self.retryDelays[failures])')
        ->not->toContain('content(.empty).task { attempt += 1 }');
});
