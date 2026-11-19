<?php

/**
 * Source regressions for the tab strip's supported transparent background.
 * Kotlin compilation remains a separate Android build gate.
 */
test('does not import unavailable core tab chrome locals', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/TabRowRenderer.kt');

    expect($source)->not->toContain('LocalTopBarColor', 'LocalTopTabRow');
});

test('keeps the tab strip transparent without an optional core chrome hook', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/TabRowRenderer.kt');

    expect($source)->toContain('containerColor = Color.Transparent,');
});
