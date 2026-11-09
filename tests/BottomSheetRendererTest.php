<?php

test('leaves the iOS grabber to the system, so only a resizable sheet shows one', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/\.presentationDragIndicator\(\.automatic\)/')
        ->not->toContain('.presentationDragIndicator(.visible)');
});

test('keeps the Android bottom sheet composed until hiding it has slid it away', function () {
    $rendererPath = dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt';

    expect($rendererPath)->toBeFile();

    $renderer = file_get_contents($rendererPath);

    expect($renderer)
        ->toBeString()
        ->not->toMatch('/if \(!visible\) return/')
        ->toMatch('/LaunchedEffect\(visible\) \{.*?sheetState\.hide\(\).*?shown = false/s')
        ->toMatch('/if \(!shown\) return/');
});

test('takes an Android bottom sheet away even when hiding it is cancelled', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt');

    expect($renderer)
        ->toBeString()
        ->toMatch('/try \{\s*if \(!permanent\) sheetState\.hide\(\)\s*\} finally \{\s*shown = false\s*\}/');
});

test('keeps the detents an Android bottom sheet opened with while it closes', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt');

    expect($renderer)
        ->toBeString()
        ->toMatch('/var detentsStr by remember \{ mutableStateOf\(requestedDetents\) \}\s*if \(visible\) detentsStr = requestedDetents/')
        ->not->toMatch('/val detentsStr = p\.getString/');
});

test('wraps an Android fit sheet around its content, opened in full', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt');

    expect($renderer)
        ->toBeString()
        ->toMatch('/val skipPartial = fits \|\| !hasPartialDetent\(detentsStr\)/')
        ->toMatch('/Column\(modifier = if \(fits\) sheetModifier else sheetModifier\.fillMaxHeight\(\)\)/')
        ->toMatch('/private fun hasDetent\(str: String, detent: String\): Boolean/');
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
