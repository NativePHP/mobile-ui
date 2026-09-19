<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

it('serializes a valid submit label on every variant', function (string $inputClass) {
    $input = new $inputClass;
    $input->applyAttributes(['submit-label' => 'next']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['submit_label'])->toBe('next');
})->with([
    'bare' => [BareTextInput::class],
    'filled' => [FilledTextInput::class],
    'outlined' => [OutlinedTextInput::class],
]);

it('accepts every documented label value', function (string $label) {
    $input = new OutlinedTextInput;
    $input->applyAttributes(['submit-label' => $label]);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['submit_label'])->toBe($label);
})->with(['next', 'done', 'go', 'search', 'send', 'return']);

it('accepts the camelCase attribute spelling', function () {
    $input = new FilledTextInput;
    $input->applyAttributes(['submitLabel' => 'send']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['submit_label'])->toBe('send');
});

it('normalizes case and surrounding whitespace', function () {
    $input = new OutlinedTextInput;
    $input->submitLabel(' Next ');

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props['submit_label'])->toBe('next');
});

it('does not serialize the prop when unset', function () {
    $input = new OutlinedTextInput;
    $input->applyAttributes(['placeholder' => 'Name']);

    $props = $input->getResolvedProps(new CallbackRegistry);

    expect($props)->not->toHaveKey('submit_label');
});

it('rejects an unknown submit label', function () {
    (new OutlinedTextInput)->submitLabel('confirm');
})->throws(InvalidArgumentException::class, 'Unknown submit-label `confirm`');
