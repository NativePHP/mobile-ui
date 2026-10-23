<?php

/**
 * While a finger is on the iOS slider, a re-render must not move the thumb:
 * the renderer ignores server values until the finger lifts.
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
