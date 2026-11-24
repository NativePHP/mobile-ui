<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

it('fills its height when a multiline field is h-full or fill', function (string $inputClass, string $how) {
    $input = (new $inputClass)->multiline();
    $how === 'fill' ? $input->fill() : $input->fillHeight();

    expect($input->getResolvedProps(new CallbackRegistry)['fills_height'] ?? null)->toBeTrue();
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
])->with(['h-full' => 'fillHeight', 'fill' => 'fill']);

it('stays as tall as its lines by default, with flex-1, or with only a width', function () {
    expect(BareTextInput::make()->multiline()->getResolvedProps(new CallbackRegistry))->not->toHaveKey('fills_height')
        ->and(BareTextInput::make()->multiline()->flexGrow(1)->getResolvedProps(new CallbackRegistry))->not->toHaveKey('fills_height')
        ->and(BareTextInput::make()->multiline()->fillWidth()->getResolvedProps(new CallbackRegistry))->not->toHaveKey('fills_height');
});

it('leaves a single-line field alone', function () {
    expect(BareTextInput::make()->fillHeight()->getResolvedProps(new CallbackRegistry))->not->toHaveKey('fills_height');
});

it('fills from the h-full class', function () {
    $input = new BareTextInput;
    $input->applyAttributes(['multiline' => true]);
    NativeElementCollector::applyLayout($input, TailwindParser::parse('w-full h-full'));

    expect($input->getResolvedProps(new CallbackRegistry)['fills_height'] ?? null)->toBeTrue();
});

it('fills on iOS by taking the height it is given, never less than min-lines', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)
        ->toContain('let fillsHeight   = multiline && p.getBool("fills_height")')
        ->toContain('content.frame(minHeight: minHeight, maxHeight: .infinity, alignment: .top)')
        ->toContain('content.frame(height: height)');
});

it('fills on Android without the max-lines cap', function (string $file) {
    $source = file_get_contents(dirname(__DIR__)."/resources/android/{$file}");

    expect($source)
        ->toContain('if (props.fillsHeight) Modifier.fillMaxHeight() else Modifier')
        ->toContain('maxLines = props.effectiveMaxLines');
})->with(['BareTextInputRenderer.kt', 'OutlinedTextInputRenderer.kt', 'FilledTextInputRenderer.kt']);
