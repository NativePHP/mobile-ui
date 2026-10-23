<?php

test('keeps the Android bottom sheet composed until hiding it has slid it away', function () {
    $rendererPath = dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt';

    expect($rendererPath)->toBeFile();

    $renderer = file_get_contents($rendererPath);

    expect($renderer)
        ->toBeString()
        ->not->toMatch('/if \(!visible\) return/')
        ->toMatch('/LaunchedEffect\(visible\) \{.*?sheetState\.hide\(\)\s*shown = false/s')
        ->toMatch('/if \(!shown\) return/');
});
