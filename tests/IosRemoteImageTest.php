<?php

$ios = dirname(__DIR__).'/resources/ios';

it('loads every remote image through NativeUIRemoteImage', function () use ($ios) {
    $uses = 0;
    foreach (glob($ios.'/*.swift') as $file) {
        $uses += preg_match_all('/\bAsyncImage\(url:/', file_get_contents($file));
    }

    // No plain AsyncImage: it uses the small shared URLCache and decodes at full size.
    expect($uses)->toBe(0)
        ->and(file_get_contents($ios.'/NativeUIImageSource.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in')
        ->and(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))->toContain('NativeUIRemoteImage(url: url, fullSize: fit == .none) { phase in')
        ->and(file_get_contents($ios.'/NativeUIPagerRenderer.swift'))->toContain('NativeUIRemoteImage(url: url) { phase in');
});

it('downloads through its own session with a sized URLCache that follows HTTP caching', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024, directory: directory)')
        ->toContain('configuration.requestCachePolicy = .useProtocolCachePolicy')
        ->toContain('try await session.data(from: url)');
});

it('shares one download per URL and cancels it only when nobody is waiting', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('@MainActor private static var downloads: [URL: Download] = [:]')
        ->toContain('guard self.waiters.isEmpty, !self.finished else {')
        ->toContain('self.task?.cancel()');
});

it('keeps decoded remote images in a cost-limited cache keyed by URL and pixel size', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('private static let cache: NSCache<NSString, Entry>')
        ->toContain('"\(url.absoluteString)#\(Int(size.width))x\(Int(size.height))" as NSString')
        ->toContain('cache.setObject(entry, forKey: cacheKey(url, size), cost: entry.cost)')
        ->toContain('cache.totalCostLimit = 16 * 1024 * 1024');
});

it('empties decoded remote images on a memory warning and in the background', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('UIApplication.didReceiveMemoryWarningNotification,')
        ->toContain('UIApplication.didEnterBackgroundNotification,')
        ->toContain('cache.removeAllObjects()');
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
