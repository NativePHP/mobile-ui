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

test('sizes an iOS fit sheet to the height its content measures', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/case "fit":\s*detents\.insert\(fitDetent\)/')
        ->toMatch('/height\.map \{ \.height\(\$0\) \}/')
        ->toMatch('/\.fixedSize\(horizontal: false, vertical: fits\)\s*'
            .'\.onGeometryChange\(for: CGFloat\.self\) \{ \$0\.size\.height \} action: \{ height in\s*'
            .'if fits, height > 0 \{ fitHeight = height \}/s');
});

test('keeps an iOS fit sheet on its fit detent when the content height changes', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/\.presentationDetents\(detents, selection: selection\)/')
        ->toMatch('/\.onChange\(of: fitHeight\) \{ old, _ in\s*'
            .'if selectedDetent == Self\.fitDetent\(for: old\) \{ selectedDetent = fitDetent \}/s');
});
