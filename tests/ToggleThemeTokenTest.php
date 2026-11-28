<?php

/**
 * A switch that is on draws its track in the optional `toggle` theme token,
 * and in `primary` when the app does not declare it.
 */
it('tints the iOS switch with toggle, falling back to primary', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIToggleRenderer.swift');
    $theme = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITheme.swift');

    expect($renderer)->toContain('.tint(theme.toggle ?? theme.primary)');
    expect($theme)
        ->toMatch('/let toggle: Color\?/')
        ->toMatch('/toggle:\s+nil,/')
        ->toMatch('/toggle:\s+optionalHex\(map\["toggle"\],\s+fallback: fallbackTo\.toggle\)/');
});

it('draws the checked Android switch track in toggle, falling back to primary', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/ToggleRenderer.kt');
    $theme = file_get_contents(dirname(__DIR__).'/resources/android/NativeUITheme.kt');

    expect($renderer)
        ->toContain('val onTrack = theme.toggle ?: theme.primary')
        ->toContain('checkedTrackColor = onTrack,')
        ->toContain('checkedBorderColor = onTrack,');
    expect($theme)
        ->toMatch('/val toggle:\s+Color\?,/')
        ->toMatch('/toggle\s+= null,/')
        ->toMatch('/toggle\s+= optionalColor\(map\["toggle"\],\s+fb\.toggle\)/');
});
