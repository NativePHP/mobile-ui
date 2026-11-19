<?php

test('applies the status bar inset before padding the Android modal close button', function () {
    $rendererPath = dirname(__DIR__).'/resources/android/ModalRenderer.kt';

    expect($rendererPath)->toBeFile();

    $renderer = file_get_contents($rendererPath);
    $closeButtonModifierPattern = '/if \(dismissible\) \{\s*Row\(\s*modifier = Modifier\s*'
        .'\.fillMaxWidth\(\)\s*'
        .'\.statusBarsPadding\(\)\s*'
        .'\.padding\(8\.dp\),/s';

    expect($renderer)
        ->toBeString()
        ->toMatch($closeButtonModifierPattern);
});

test('copies the status bar appearance of the activity to the Android modal window', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/ModalRenderer.kt');

    expect($renderer)
        ->toBeString()
        ->toMatch('/\(dialogView\.parent as\? DialogWindowProvider\)\?\.window/')
        ->toMatch('/val screenWindow = MainActivity\.instance\?\.window/')
        ->toMatch('/WindowCompat\.getInsetsController\(dialogWindow, dialogView\)\.isAppearanceLightStatusBars =\s*'
            .'WindowCompat\.getInsetsController\(screenWindow, screenWindow\.decorView\)\.isAppearanceLightStatusBars/');
});

test('sends no dismissal to PHP when PHP closes the iOS modal', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIModalRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/\.fullScreenCover\(isPresented: \.constant\(visible\)\) \{/')
        ->not->toMatch('/onDismiss: \{/')
        ->toMatch('/Button\(action: fireDismiss\)/');
});
