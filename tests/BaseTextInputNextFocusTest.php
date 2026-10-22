<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

it('serializes next-focus on every variant', function (string $inputClass) {
    $input = new $inputClass;
    $input->applyAttributes(['next-focus' => 'email']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['next_focus'])->toBe('email');
})->with([
    'bare' => [BareTextInput::class],
    'filled' => [FilledTextInput::class],
    'outlined' => [OutlinedTextInput::class],
]);

it('accepts the camelCase attribute spelling', function () {
    $input = new FilledTextInput;
    $input->applyAttributes(['nextFocus' => 'pin']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['next_focus'])->toBe('pin');
});

it('treats an empty ref as unset', function () {
    $input = new OutlinedTextInput;
    $input->applyAttributes(['next-focus' => '  ']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props)->not->toHaveKey('next_focus');
});

it('trims the target ref', function () {
    $input = new OutlinedTextInput;
    $input->nextFocus(' email ');

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['next_focus'])->toBe('email');
});

it('surfaces the element ref as the focus_ref prop', function () {
    $input = new OutlinedTextInput;
    $input->ref('email');
    $input->applyAttributes(['placeholder' => 'Email']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['focus_ref'])->toBe('email');
});

it('does not serialize focus_ref without a ref', function () {
    $input = new OutlinedTextInput;
    $input->applyAttributes(['placeholder' => 'Email']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props)->not->toHaveKey('focus_ref');
});
