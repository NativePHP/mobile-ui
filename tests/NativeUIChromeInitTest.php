<?php

test('registers the Android drawer host with navigation bar slot reservation', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/NativeUIChromeInit.kt');
    $matched = preg_match(
        '/NativeRootHostRegistry\.register\(\s*"native-ui\.drawer",(?<arguments>[^)]*)\)/s',
        $source,
        $registration,
    );

    expect($matched)->toBe(1)
        ->and($registration['arguments'])
        ->toMatch('/consumes\s*=\s*"native_drawer"/')
        ->toMatch('/reservesNavigationBarSlot\s*=\s*true/');
});
