<?php

it('uses the app-local appearance state in Android renderers', function () {
    $renderers = glob(__DIR__.'/../resources/android/*Renderer.kt');

    expect($renderers)->not->toBeFalse()->not->toBeEmpty();

    foreach ($renderers as $renderer) {
        $source = file_get_contents($renderer);

        if (str_contains($source, 'NativeUITheme.dark')) {
            expect($source)
                ->not->toContain('isSystemInDarkTheme()')
                ->toContain('NativeAppearanceState.isDark()');
        }
    }
});
