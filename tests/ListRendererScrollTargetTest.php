<?php

/**
 * Source contract of the Android list renderer's half of the bottom-tab
 * reselect scroll seam: while a list declares a `scroll_target` its
 * LazyList state is registered in core's NativeScrollTargetRegistry for
 * the lifetime of the composition. Pure source assertions in the
 * ModalRendererTest style — the plugin ships no JVM test environment;
 * the Kotlin compiles in the generated app (registry included by the
 * core patch).
 */
test('registers the list state with the scroll target registry for the composition lifetime', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ListRenderer.kt');

    expect($source)
        ->toContain('import com.nativephp.mobile.ui.nativerender.NativeScrollTargetRegistry');

    // The DisposableEffect block, mirroring the contract documented on
    // NativeScrollTargetRegistry: exact top (index 0 AND zero pixel
    // offset), native scroll to item 0, unregister on dispose with the
    // composition's own owner token, and the live availability predicate
    // the registry's get() consults at tap time and settle-gate time.
    $effect = '/DisposableEffect\(key, state, page, active\) \{\s*'
        .'if \(active\) \{\s*'
        .'NativeScrollTargetRegistry\.register\(\s*'
        .'key = key,\s*'
        .'owner = owner,\s*'
        .'isAtTop = \{ state\.firstVisibleItemIndex == 0 && state\.firstVisibleItemScrollOffset == 0 \},\s*'
        .'scrollToTop = \{ state\.animateScrollToItem\(0\) \},\s*'
        .'isAvailable = \{ page\?\.isAvailable\(\) \?: true \},\s*'
        .'\)\s*'
        .'\}\s*'
        .'onDispose \{ NativeScrollTargetRegistry\.unregister\(key, owner\) \}\s*'
        .'\}/s';

    // A fresh owner token per composition, so a stale onDispose from a
    // superseded composition can never unregister the newer entry (the
    // registry matches by identity); keying the effect on the state
    // re-registers when rememberLazyListState produces a new one, so no
    // entry ever points at a disposed state.
    expect(preg_match($effect, $source))->toBe(1)
        ->and(preg_match('/val owner = remember \{ Any\(\) \}/', $source))->toBe(1);
});

test('registers only while a scroll target key is declared', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ListRenderer.kt');

    // Default lists (no prop) register nothing: same props, same
    // behavior as before the seam existed.
    expect(preg_match('/node\.props\.getString\("scroll_target", ""\)/', $source))->toBe(1)
        ->and(preg_match('/isNotEmpty\(\)\) \{\s*ListScrollTarget\(/', $source))->toBe(1);
});

test('waits for the pager page it is on to be the one showing', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ListRenderer.kt');

    // A pager keeps the pages beside the one showing composed, so every
    // composed page's list would otherwise answer the same reselect while
    // PHP is still a round trip behind the swipe. The list reads the page
    // context it is on and only publishes while that page is the one the
    // pager is settled on.
    expect($source)
        ->toContain('ListScrollTarget(scrollTarget, scrollState, LocalPagerPage.current)')
        ->toContain('val active = page?.isAvailable() ?: true');

    // `active` is observed in composition (the pager's page flips restart
    // the effect) and keys it alongside key, state and page. `page` keys it
    // too, so the registered predicate never keeps reading a context from
    // a pager that has been replaced.
    expect(preg_match('/DisposableEffect\(key, state, page, active\) \{/', $source))->toBe(1);
});

test('re-registers a fresh entry when a page goes away and returns', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ListRenderer.kt');

    // The registration sits inside `if (active)` and the effect is keyed
    // on it, so a page leaving the one showing disposes its entry and the
    // page coming back registers a new one. Each register() call builds a
    // fresh Entry, so the core settle gate — which compares the entry it
    // tapped with the one live after the scroll — cannot match a scroll
    // that started before the page went away and fire late into the page
    // that came back. Between the flip and this effect applying, the live
    // predicate is already filtering, closing that frame or two.
    expect(preg_match('/if \(active\) \{\s*NativeScrollTargetRegistry\.register\(/s', $source))->toBe(1)
        ->and(preg_match('/DisposableEffect\(key, state, page, active\) \{/', $source))->toBe(1);
});
