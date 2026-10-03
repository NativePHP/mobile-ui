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
