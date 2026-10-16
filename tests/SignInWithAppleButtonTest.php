<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\NativeTagPrecompiler;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\SignInWithAppleButton;

/**
 * Apple's Sign in with Apple button. The renderers draw the system button
 * from `label` / `button_style` / `corner_radius` and only fire `on_press`;
 * the app runs the sign-in itself.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('sign_in_with_apple_button', SignInWithAppleButton::class);
    ElementRegistry::register('button', Button::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function appleButtonTree(string $blade, CallbackRegistry $registry): array
{
    $wasActive = NativeTagPrecompiler::setActive(true);

    try {
        $php = (new NativeTagPrecompiler)($blade);
    } finally {
        NativeTagPrecompiler::setActive($wasActive);
    }

    eval('?>'.$php);

    return NativeElementCollector::collect()->toArray($registry);
}

it('sends the label, style, corner radius and press handler from a Blade tag', function () {
    $registry = new CallbackRegistry;
    $tree = appleButtonTree(
        '<native:sign-in-with-apple-button label="continue" button-style="white-outline" corner-radius="8" @press="signInWithApple" />',
        $registry,
    );

    expect($tree['type'])->toBe('sign_in_with_apple_button')
        ->and($tree['props'])->toMatchArray([
            'label' => 'continue',
            'button_style' => 'white_outline',
            'corner_radius' => 8.0,
        ])
        ->and($registry->resolve($tree['props']['on_press']))->toBe(['method' => 'signInWithApple', 'args' => []]);
});

it('keeps the press handler off the node so core adds no second tap gesture', function () {
    $tree = appleButtonTree('<native:sign-in-with-apple-button @press="signInWithApple" />', new CallbackRegistry);

    expect($tree)->not->toHaveKey('on_press')
        ->and($tree['props'])->toHaveKey('on_press');
});

it('leaves the defaults to the renderer', function () {
    $tree = appleButtonTree('<native:sign-in-with-apple-button />', new CallbackRegistry);

    expect($tree['props'] ?? [])->toBe([]);
});

it('accepts each label', function (string $label, string $wire) {
    $tree = appleButtonTree("<native:sign-in-with-apple-button label=\"{$label}\" />", new CallbackRegistry);

    expect($tree['props']['label'])->toBe($wire);
})->with([
    ['sign-in', 'sign_in'],
    ['continue', 'continue'],
    ['sign-up', 'sign_up'],
    ['sign_up', 'sign_up'],
    ['signUp', 'sign_up'],
]);

it('accepts each style', function (string $style, string $wire) {
    $tree = appleButtonTree("<native:sign-in-with-apple-button button-style=\"{$style}\" />", new CallbackRegistry);

    expect($tree['props']['button_style'])->toBe($wire);
})->with([
    ['auto', 'auto'],
    ['black', 'black'],
    ['white', 'white'],
    ['white-outline', 'white_outline'],
    ['whiteOutline', 'white_outline'],
]);

it('rejects a label Apple has no title for', function () {
    SignInWithAppleButton::make()->label('Sign in with Apple');
})->throws(InvalidArgumentException::class, 'SignInWithAppleButton `label` must be one of [sign-in, continue, sign-up], got [Sign in with Apple].');

it('rejects an unknown style', function () {
    SignInWithAppleButton::make()->buttonStyle('red');
})->throws(InvalidArgumentException::class, 'SignInWithAppleButton `button-style` must be one of [auto, black, white, white-outline], got [red].');

it('takes the corner radius from a rounded class, with the attribute winning', function () {
    $fromClass = appleButtonTree('<native:sign-in-with-apple-button class="rounded-xl" />', new CallbackRegistry);
    NativeElementCollector::reset();
    $both = appleButtonTree('<native:sign-in-with-apple-button class="rounded-xl" corner-radius="4" />', new CallbackRegistry);

    expect($fromClass['props']['corner_radius'])->toBe(12.0)
        ->and($both['props']['corner_radius'])->toBe(4.0);
});

it('sizes through the layout and drops colours and padding', function () {
    $tree = appleButtonTree('<native:sign-in-with-apple-button class="w-full h-12 p-4 bg-red-500" />', new CallbackRegistry);

    expect($tree['layout'])->toMatchArray(['width' => 'fill', 'height' => 48.0])
        ->and($tree['layout'])->not->toHaveKey('padding')
        ->and($tree['style'] ?? [])->toBe([]);
});

it('can be disabled', function () {
    $tree = appleButtonTree('<native:sign-in-with-apple-button :disabled="true" />', new CallbackRegistry);

    expect($tree['props']['disabled'])->toBeTrue();
});

it('keeps children as the Android fallback', function () {
    $tree = appleButtonTree(
        '<native:sign-in-with-apple-button @press="signInWithApple"><native:button @press="signInWithApple">Sign in with Apple</native:button></native:sign-in-with-apple-button>',
        new CallbackRegistry,
    );

    expect($tree['children'])->toHaveCount(1)
        ->and($tree['children'][0]['type'])->toBe('button')
        ->and($tree['children'][0]['props']['label'])->toBe('Sign in with Apple');
});

it('builds the same props fluently', function () {
    $registry = new CallbackRegistry;
    $props = SignInWithAppleButton::make()
        ->label('sign-up')
        ->buttonStyle('black')
        ->cornerRadius(22)
        ->onPress('signUpWithApple')
        ->toArray($registry)['props'];

    expect($props)->toMatchArray(['label' => 'sign_up', 'button_style' => 'black', 'corner_radius' => 22.0])
        ->and($registry->resolve($props['on_press']))->toBe(['method' => 'signUpWithApple', 'args' => []]);
});

it('is registered in the manifest as a container element', function () {
    $manifest = json_decode(file_get_contents(dirname(__DIR__).'/nativephp.json'), true);
    $component = collect($manifest['components'])->firstWhere('type', 'sign_in_with_apple_button');

    expect($component)->toMatchArray([
        'element' => SignInWithAppleButton::class,
        'blade' => Native\Mobile\UI\Components\SignInWithAppleButton::class,
        'android_renderer' => 'com.nativephp.plugins.native_ui.ui.SignInWithAppleButtonRenderer',
        'ios_renderer' => 'NativeUISignInWithAppleButtonRenderer',
        'self_closing' => false,
    ])
        ->and(dirname(__DIR__).'/resources/ios/NativeUISignInWithAppleButtonRenderer.swift')->toBeFile()
        ->and(dirname(__DIR__).'/resources/android/SignInWithAppleButtonRenderer.kt')->toBeFile();
});
