<?php

/**
 * Coil's default cache strategy already serves whatever is on disk, so a
 * plain image URL is immutable on Android as on iOS. `revalidate` gives the
 * request a network fetcher that follows Cache-Control.
 */
$android = dirname(__DIR__).'/resources/android';

it('fetches revalidate images on Android with a cache-control strategy and no memory cache', function () use ($android) {
    $helper = file_get_contents($android.'/NativeUIRemoteImage.kt');

    expect($helper)
        ->toContain('getBool("revalidate") || getString("revalidate") in setOf("true", "1")')
        ->toContain('fetcherFactory(revalidatingNetworkFetcher)')
        ->toContain('memoryCachePolicy(CachePolicy.DISABLED)')
        ->toContain('cacheStrategy = { CacheControlCacheStrategy() },')
        ->and(file_get_contents($android.'/ImageRenderer.kt'))->toContain('nuiImageModel(model, context, revalidate, wholeImage)')
        ->and(substr_count(file_get_contents($android.'/ListItemRenderer.kt'), 'nuiImageModel(nuiResolveImageSrc(effectiveValue, context), context, revalidate)'))->toBe(2)
        ->and(file_get_contents($android.'/PagerRenderer.kt'))->toContain('nuiImageModel(imageUrl, context, revalidate)')
        ->and(json_decode(file_get_contents(dirname(__DIR__).'/nativephp.json'), true)['android']['dependencies']['implementation'])
        ->toContain('io.coil-kt.coil3:coil-network-cache-control:3.1.0');
});
