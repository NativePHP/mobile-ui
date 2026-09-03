<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

it('serializes autofocus on every variant', function (string $inputClass) {
    $input = new $inputClass;
    $input->applyAttributes(['autofocus' => true]);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['autofocus'])->toBeTrue();
})->with([
    'bare' => [BareTextInput::class],
    'filled' => [FilledTextInput::class],
    'outlined' => [OutlinedTextInput::class],
]);

it('is absent when not requested', function () {
    $input = new BareTextInput;

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props)->not->toHaveKey('autofocus');
});

it('is absent when the bound expression is false', function () {
    $input = new BareTextInput;
    $input->applyAttributes(['autofocus' => false]);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props)->not->toHaveKey('autofocus');
});
