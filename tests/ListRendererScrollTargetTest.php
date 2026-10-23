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
    // composition's own owner token.
    $effect = '/DisposableEffect\(key, state\) \{\s*'
        .'NativeScrollTargetRegistry\.register\(\s*'
        .'key = key,\s*'
        .'owner = owner,\s*'
        .'isAtTop = \{ state\.firstVisibleItemIndex == 0 && state\.firstVisibleItemScrollOffset == 0 \},\s*'
        .'scrollToTop = \{ state\.animateScrollToItem\(0\) \},\s*'
        .'\)\s*'
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
