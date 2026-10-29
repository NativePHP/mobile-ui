<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

function selectionProps(string $inputClass, array $attrs): array
{
    $input = new $inputClass;
    $input->applyAttributes($attrs);

    return $input->getResolvedProps(new CallbackRegistry);
}

it('is absent unless asked for, so PHP never moves a caret by default', function (string $inputClass) {
    $props = selectionProps($inputClass, ['value' => 'Hello']);

    expect($props)->not->toHaveKey('selection_start')
        ->and($props)->not->toHaveKey('selection_end');
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
]);

it('places a caret from a number', function (string $inputClass) {
    $props = selectionProps($inputClass, ['selection' => 7]);

    expect($props['selection_start'])->toBe(7)
        ->and($props['selection_end'])->toBe(7);
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
]);

it('selects a range from a pair', function () {
    $props = selectionProps(BareTextInput::class, ['selection' => [3, 9]]);

    expect($props['selection_start'])->toBe(3)
        ->and($props['selection_end'])->toBe(9);
});

it('still declares the field when the caret is null, so iOS never rebuilds it between renders', function (mixed $nothing) {
    $props = selectionProps(BareTextInput::class, ['selection' => $nothing]);

    expect($props['selection_start'])->toBe(-1)
        ->and($props['selection_end'])->toBe(-1);
})->with([
    'null' => null,
    'empty string' => '',
    'empty pair' => [[]],
]);

it('keeps the range in order and off negative offsets', function () {
    expect(BareTextInput::make()->selection(-4)->getResolvedProps(new CallbackRegistry))
        ->toMatchArray(['selection_start' => 0, 'selection_end' => 0])
        ->and(BareTextInput::make()->selection(9, 3)->getResolvedProps(new CallbackRegistry))
        ->toMatchArray(['selection_start' => 9, 'selection_end' => 9]);
});

it('takes Blade numbers that arrive as strings', function () {
    expect(selectionProps(OutlinedTextInput::class, ['selection' => '12']))
        ->toMatchArray(['selection_start' => 12, 'selection_end' => 12]);
});

it('is settable fluently, and back to nothing to place', function () {
    expect(OutlinedTextInput::make()->selection(2, 5)->getResolvedProps(new CallbackRegistry))
        ->toMatchArray(['selection_start' => 2, 'selection_end' => 5])
        ->and(OutlinedTextInput::make()->selection(2)->selection(null)->getResolvedProps(new CallbackRegistry))
        ->toMatchArray(['selection_start' => -1, 'selection_end' => -1]);
});

it('never places a caret in a secure field', function () {
    $props = selectionProps(OutlinedTextInput::class, ['secure' => true, 'selection' => 3]);

    expect($props)->not->toHaveKey('selection_start')
        ->and($props)->not->toHaveKey('selection_end');
});

it('places the caret in every Android variant when PHP pushes a value', function (string $file) {
    $source = file_get_contents(dirname(__DIR__)."/resources/android/{$file}");

    expect($source)
        ->toContain('val pushed = TextFieldValue(props.serverValue, props.pushedSelection(props.serverValue))')
        ->not->toContain('val pushed = TextFieldValue(props.serverValue, TextRange(props.serverValue.length))');
})->with([
    'OutlinedTextInputRenderer.kt',
    'FilledTextInputRenderer.kt',
    'BareTextInputRenderer.kt',
]);

it('binds the iOS selection whenever PHP can place it, and places it on a push', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)
        ->toContain('let selectionBound = selectionEnabled || placesSelection')
        ->toContain('if selectionBound {
                                TextEditor(text: $text, selection: $selection)')
        ->toContain('if selectionBound {
                    TextField(placeholder, text: $text, selection: $selection, prompt: prompt)')
        ->toContain('placed = placeSelection(start: placedStart, end: placedEnd, in: newServerValue)');
});

it('reports the caret before a press elsewhere on iOS, as Android does', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)->toMatch('/KeyboardFocusPolicy\.fieldFocused\(focusToken, keepsFocus: keepFocus\) \{.*?flushSelection\(cb: onSelectionCb\).*?flushPending\(onChangeCb: onChangeCb\)/s');
});
