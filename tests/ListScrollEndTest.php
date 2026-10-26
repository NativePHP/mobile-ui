<?php

it('reports a scroll end on iOS once the list is idle after moving', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIListRenderer.swift');

    expect($source)
        ->toContain('.modifier(ListScrollPhaseModifier(tracker: onScrollEndCb != 0 ? visibleRange : nil))')
        ->toMatch('/if phase\.isScrolling \{\s*moved = true/')
        ->toMatch('/\} else if phase == \.idle, moved \{\s*moved = false\s*scrollEnded\(\)/');
});

it('drops a visible range report still to come on iOS when a scroll ends', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIListRenderer.swift');

    expect($source)
        ->toMatch('/private func scrollEnded\(\) \{\s*guard scrollEndCallbackId != 0 else \{ return \}\s*pending\?\.cancel\(\)/')
        ->toContain('guard callbackId != 0, pending == nil, pendingEnd == nil');
});

it('reports a scroll end on Android once the list stops after moving', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ListRenderer.kt');

    expect($source)
        ->toContain('snapshotFlow { scrollState.isScrollInProgress }')
        ->toMatch('/if \(scrolling\) \{\s*moved = true\s*return@collect\s*\}\s*if \(!moved\) return@collect/')
        ->toContain('if (latest == reported.range) return@collect');
});
