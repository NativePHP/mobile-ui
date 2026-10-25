<?php

/**
 * While a finger is on a slider, a re-render must not move the thumb: the
 * renderers ignore server values until the finger lifts (iOS) or the drag
 * ends (Android).
 */
function iosSliderRenderer(): string
{
    $rendererPath = dirname(__DIR__).'/resources/ios/NativeUISliderRenderer.swift';

    expect($rendererPath)->toBeFile();

    return file_get_contents($rendererPath);
}

test('the iOS slider knows when a finger is on it', function () {
    expect(iosSliderRenderer())
        ->toMatch('/@State private var isEditing: Bool = false/')
        ->toMatch('/private func handleEditingChanged\(_ editing: Bool[^)]*\) \{.*?isEditing = editing.*?guard !editing else \{ return \}/s');
});

test('the iOS slider ignores server values during a drag', function () {
    expect(iosSliderRenderer())
        ->toMatch('/\.onChange\(of: serverValue\) \{ _, newServerValue in\s*(?:\/\/[^\n]*\n\s*)*guard !isEditing else \{ return \}/');
});

test('the iOS slider applies server values again if it goes away mid-drag', function () {
    expect(iosSliderRenderer())
        ->toMatch('/\.onDisappear \{\s*(?:\/\/[^\n]*\n\s*)*isEditing = false\s*\}/');
});

function androidSliderRenderer(): string
{
    $rendererPath = dirname(__DIR__).'/resources/android/SliderRenderer.kt';

    expect($rendererPath)->toBeFile();

    return file_get_contents($rendererPath);
}

test('the Android slider knows when a finger drags it', function () {
    expect(androidSliderRenderer())
        ->toMatch('/val isDragged by interactionSource\.collectIsDraggedAsState\(\)/')
        ->toMatch('/\n {8}Slider\(.*?\n {12}interactionSource = interactionSource,\n {8}\)/s');
});

test('the Android slider ignores server values during a drag', function () {
    expect(androidSliderRenderer())
        ->toMatch('/LaunchedEffect\(serverValue\) \{\s*(?:\/\/[^\n]*\n\s*)*if \(isDragged\) return@LaunchedEffect/');
});
