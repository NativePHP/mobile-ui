<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

function autofocusProps(string $inputClass, array $attrs): array
{
    $input = new $inputClass;
    $input->applyAttributes($attrs);

    return $input->getResolvedProps(new CallbackRegistry);
}

it('is absent unless asked for, so no field grabs the keyboard by default', function (string $inputClass) {
    expect(autofocusProps($inputClass, ['label' => 'Name'])['autofocus'] ?? null)->toBeNull();
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
]);

it('resolves the autofocus attribute in both spellings', function (string $inputClass, string $attribute) {
    expect(autofocusProps($inputClass, [$attribute => true])['autofocus'])->toBeTrue();
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
])->with([
    'autofocus',
    'auto-focus',
]);

it('ignores a falsy attribute rather than focusing on it', function () {
    // `autofocus="{{ $condition }}"` renders an empty string when the
    // condition is false, which must not read as opt-in.
    expect(autofocusProps(OutlinedTextInput::class, ['autofocus' => ''])['autofocus'] ?? null)->toBeNull()
        ->and(autofocusProps(OutlinedTextInput::class, ['autofocus' => false])['autofocus'] ?? null)->toBeNull();
});

it('is settable fluently', function () {
    $props = OutlinedTextInput::make()->autofocus()->getResolvedProps(new CallbackRegistry);

    expect($props['autofocus'])->toBeTrue();
});

it('can be turned back off fluently', function () {
    $props = OutlinedTextInput::make()->autofocus()->autofocus(false)->getResolvedProps(new CallbackRegistry);

    expect($props['autofocus'])->toBeFalse();
});
