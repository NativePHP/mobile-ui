<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Image;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\ListItem;
use Native\Mobile\UI\Elements\Pager;

$ios = dirname(__DIR__).'/resources/ios';

it('loads every remote image through NativeUIRemoteImage', function () use ($ios) {
    $uses = 0;
    foreach (glob($ios.'/*.swift') as $file) {
        $uses += preg_match_all('/\bAsyncImage\(url:/', file_get_contents($file));
    }

    // No plain AsyncImage: it uses the small shared URLCache and decodes at full size.
    expect($uses)->toBe(0)
        ->and(file_get_contents($ios.'/NativeUIImageSource.swift'))->toContain('NativeUIRemoteImage(url: url, revalidate: revalidate) { phase in')
        ->and(file_get_contents($ios.'/NativeUISimpleRenderers.swift'))->toContain('NativeUIRemoteImage(url: url, fullSize: fit == .none, revalidate: node.props.revalidatesRemoteImages) { phase in')
        ->and(file_get_contents($ios.'/NativeUIPagerRenderer.swift'))->toContain('NativeUIRemoteImage(url: url, revalidate: revalidatesPlaceholders) { phase in');
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

it('keeps no decoded remote images in memory beyond what each view shows', function () use ($ios) {
    $source = file_get_contents($ios.'/NativeUIImageSource.swift');
    $remote = substr($source, strpos($source, 'enum NativeUIRemoteImageCache'));

    expect($remote)
        ->not->toContain('NSCache')
        ->not->toContain('totalCostLimit');
});

it('empties the URLCache memory tier on a memory warning and in the background', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('UIApplication.didReceiveMemoryWarningNotification,')
        ->toContain('UIApplication.didEnterBackgroundNotification,')
        ->toContain('urlCache.memoryCapacity = 0');
});

it('reads revalidate the same way for every element that shows remote images', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('var revalidatesRemoteImages: Bool {')
        ->toContain('getBool("revalidate") || ["true", "1"].contains(getString("revalidate"))')
        ->and(file_get_contents(dirname(__DIR__).'/src/NativeUIServiceProvider.php'))
        ->toContain("NativeElementCollector::captureAttribute('revalidate', 'revalidate');");
});

it('passes revalidate from a list item to its avatar and thumbnail', function () use ($ios) {
    $source = file_get_contents($ios.'/NativeUIListItemRenderer.swift');

    expect($source)
        ->toContain('NativeUIRowImage(src: value, revalidate: node.props.revalidatesRemoteImages) {')
        ->toContain('NativeUIRowImage(src: value, contentMode: imageFit == "contain" ? .fit : .fill, revalidate: node.props.revalidatesRemoteImages) {')
        ->and(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('init(src: String, contentMode: ContentMode = .fill, revalidate: Bool = false, @ViewBuilder placeholder: @escaping () -> Placeholder) {');
});

it('passes revalidate from a pager to its placeholder images', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIPagerRenderer.swift'))
        ->toContain('revalidatesPlaceholders: p.revalidatesRemoteImages,')
        ->toContain('NativeUIRemoteImage(url: url, revalidate: revalidatesPlaceholders) { phase in');
});

/**
 * The tree Blade would build for one element, with mobile-ui's capture of
 * `revalidate` registered.
 */
function revalidateProps(string $type, string $class, array $attrs): array
{
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register($type, $class);
    NativeElementCollector::captureAttribute('revalidate', 'revalidate');

    try {
        NativeElementCollector::leaf($type, $attrs);

        return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];
    } finally {
        NativeElementCollector::stopCapturingAttributes();
        NativeElementCollector::reset();
        ElementRegistry::reset();
    }
}

it('carries revalidate onto the image node as a prop', function () {
    $props = revalidateProps('image', Image::class, ['src' => 'https://example.com/a.jpg', 'revalidate' => true]);

    expect($props['revalidate'])->toBeTrue()
        ->and($props['src'])->toBe('https://example.com/a.jpg')
        ->and(revalidateProps('image', Image::class, ['src' => 'https://example.com/a.jpg']))->not->toHaveKey('revalidate');
});

it('carries revalidate onto a list item and a pager as a prop', function () {
    $item = revalidateProps('list_item', ListItem::class, ['headline' => 'Ada', 'leadingAvatar' => 'https://example.com/ada.jpg', 'revalidate' => true]);
    $pager = revalidateProps('pager', Pager::class, ['placeholders' => ['https://example.com/1.jpg'], 'revalidate' => 'true']);

    expect($item['revalidate'])->toBeTrue()
        ->and($item['leading_value'])->toBe('https://example.com/ada.jpg')
        ->and($pager['revalidate'])->toBe('true')
        ->and($pager['placeholders'])->toBe(['https://example.com/1.jpg'])
        ->and(ListItem::make('Ada')->leadingAvatar('https://example.com/ada.jpg')->setProp('revalidate', true)->toArray(new CallbackRegistry)['props']['revalidate'])->toBeTrue();
});

it('thumbnails with ImageIO only when the source is well over the drawn size', function () use ($ios) {
    expect(file_get_contents($ios.'/NativeUIImageSource.swift'))
        ->toContain('if fill < 1 / 1.5 {')
        ->toContain('kCGImageSourceCreateThumbnailFromImageAlways: true')
        ->toContain('kCGImageSourceShouldCacheImmediately: true')
        ->toContain('CGImageSourceCreateThumbnailAtIndex(source, 0, options)');
});

it('leaves a full-size remote decode in ImageIO\'s purgeable cache', function () use ($ios) {
    $source = file_get_contents($ios.'/NativeUIImageSource.swift');
    $decode = substr($source, strpos($source, 'func decodeImage('), 4000);

    expect($decode)
        ->toContain('guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {')
        ->toContain('kCGImageSourceShouldCache: true,')
        ->not->toContain('preparingForDisplay()');
});

it('tries a failed download again after a delay, but not a cancelled one', function () use ($ios) {
    $source = file_get_contents($ios.'/NativeUIImageSource.swift');

    expect($source)
        ->toContain('private static var retryDelays: [Duration] { [.milliseconds(500), .milliseconds(1500)] }')
        ->toContain('try? await Task.sleep(for: Self.retryDelays[failures])')
        ->not->toContain('content(.empty).task { attempt += 1 }');
});
