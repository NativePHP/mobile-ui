<?php

function sheetPaneRenderer(string $path): string
{
    return file_get_contents(dirname(__DIR__).'/resources/'.$path);
}

test('measures an iOS fit pane at its content\'s ideal height, capped at the screen', function () {
    expect(sheetPaneRenderer('ios/NativeUISheetPaneRenderer.swift'))
        ->toBeString()
        ->toMatch('/case "fit": fits = true/')
        ->toMatch('/\.fixedSize\(horizontal: false, vertical: config\.fits\)\s*'
            .'\.onGeometryChange\(for: CGFloat\.self\) \{ \$0\.size\.height \} action: \{ height in\s*'
            .'if config\.fits, height > 0 \{ fitHeight = height \}/s')
        ->toMatch('/let fit = fitHeight\.map \{ min\(\$0, geo\.size\.height - insetBottom\) \}/');
});

test('keeps the iOS pane content pinned to the top of the tallest detent', function () {
    expect(sheetPaneRenderer('ios/NativeUISheetPaneRenderer.swift'))
        ->toBeString()
        ->toMatch('/let revealHeight = heights\.map\(\\\\\.height\)\.max\(\) \?\? 0/')
        ->toMatch('/\.frame\(width: paneWidth, height: revealHeight, alignment: \.top\)\s*'
            .'\.frame\(width: paneWidth, height: model\.height, alignment: \.top\)/s');
});

test('reports and follows the iOS fit detent', function () {
    expect(sheetPaneRenderer('ios/NativeUISheetPaneRenderer.swift'))
        ->toBeString()
        ->toMatch('/case \.fit: "fit"/')
        ->toMatch('/\.onChange\(of: fit\) \{ _, newValue in\s*model\.follow\(fit: newValue\)/s')
        ->toMatch('/func follow\(fit: CGFloat\?\) \{\s*guard appliedDetent == \.fit/s');
});

test('measures an Android fit pane at its content\'s natural height, capped at the screen', function () {
    expect(sheetPaneRenderer('android/SheetPaneRenderer.kt'))
        ->toBeString()
        ->toMatch('/"fit" -> fits = true/')
        ->toMatch('/\.wrapContentHeight\(align = Alignment\.Top, unbounded = true\)\s*\.onSizeChanged \{/s')
        ->toMatch('/val fit = fitHeight\?\.let \{ min\(it, maxHeight\.value - insetBottom\) \}/');
});

test('reports and follows the Android fit detent', function () {
    expect(sheetPaneRenderer('android/SheetPaneRenderer.kt'))
        ->toBeString()
        ->toMatch('/Detent\.Fit -> "fit"/')
        ->toMatch('/LaunchedEffect\(fit\) \{\s*if \(appliedDetent\.value == Detent\.Fit && !dragging/s');
});
