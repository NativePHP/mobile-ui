<?php

test('draws the iOS X only beside a picked compact date', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIDatePickerRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toContain('let clearable   = p.getBool("clearable")')
        ->toMatch('/if clearable && hasSelection && display == "compact" && !disabled \{\s*HStack\(spacing: 8\) \{\s*styledPicker\s*Button \{\s*clear\(onChangeCb: onChangeCb\)/')
        ->toMatch('/Image\(systemName: "xmark\.circle\.fill"\).*?\.accessibilityLabel\(clearLabel\)/s');
});

test('clears an iOS picker to the empty wire value', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIDatePickerRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/private func clear\(onChangeCb: Int\) \{\s*hasSelection = false\s*selected = Date\(\)\s*lastSentValue = ""\s*'
            .'if onChangeCb != 0 \{\s*NativeElementBridge\.sendSelectChangeEvent\(onChangeCb, nodeId: node\.id, value: ""\)/');
});
