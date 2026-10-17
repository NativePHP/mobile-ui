<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\JumpBridge;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Theme;

/**
 * A button variant that names a theme colour token draws in that token,
 * with its `on-` token for the label, in both shades.
 */
beforeEach(function () {
    JumpBridge::instance()->mute();
    Theme::reset();
    Theme::load([
        'light' => [
            'primary' => '#3B6FE0',
            'on-primary' => '#FFFFFF',
            'secondary' => '#EEF0F2',
            'brand' => '#0C8599',
            'on-brand' => '#FFFFFF',
            'mono' => '#121417',
        ],
        'dark' => [
            'primary' => '#7AA2F7',
            'on-primary' => '#111112',
            'brand' => '#3BC9DB',
            'on-brand' => '#111112',
            'mono' => '#121417',
        ],
    ]);
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('button', Button::class);
});

afterEach(function () {
    Theme::reset();
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('sends a token variant with its light and dark colours', function () {
    $props = Button::make('Follow')->variant('brand')->toArray(new CallbackRegistry)['props'];

    expect($props)
        ->toMatchArray([
            'variant' => 'brand',
            'tint' => '#0C8599',
            'dark_tint' => '#3BC9DB',
            'on_tint' => '#FFFFFF',
            'dark_on_tint' => '#111112',
        ]);
});

it('takes a token variant from Blade', function () {
    NativeElementCollector::leaf('button', ['label' => 'Follow', 'variant' => 'brand']);

    $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

    expect($props['tint'])->toBe('#0C8599')
        ->and($props['on_tint'])->toBe('#FFFFFF');
});

it('labels a token without an on- token in on-primary', function () {
    $props = Button::make('Go')->variant('mono')->toArray(new CallbackRegistry)['props'];

    expect($props)
        ->toMatchArray(['tint' => '#121417', 'on_tint' => '#FFFFFF', 'dark_on_tint' => '#111112'])
        ->not->toHaveKey('dark_tint');
});

it('leaves the built-in variants to the renderers', function (string $variant) {
    $props = Button::make('Go')->variant($variant)->toArray(new CallbackRegistry)['props'];

    expect($props)->not->toHaveKeys(['tint', 'dark_tint', 'on_tint', 'dark_on_tint']);
})->with(Button::Variants);

it('sends no colours for a name the theme does not have', function () {
    $props = Button::make('Go')->variant('nope')->toArray(new CallbackRegistry)['props'];

    expect($props)->not->toHaveKeys(['tint', 'on_tint']);
});

it('drops the colours when the variant changes back to a built-in one', function () {
    $props = Button::make('Go')->variant('brand')->variant('secondary')->toArray(new CallbackRegistry)['props'];

    expect($props['variant'])->toBe('secondary')
        ->and($props)->not->toHaveKeys(['tint', 'dark_tint', 'on_tint', 'dark_on_tint']);
});

it('draws the sent colours in place of primary on both platforms', function () {
    $ios = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIButtonRenderer.swift');
    $android = file_get_contents(dirname(__DIR__).'/resources/android/ButtonRenderer.kt');

    expect($ios)
        ->toContain('guard p.has("tint") else { return nil }')
        ->toContain('.tint(enabled ? (token?.tint ?? theme.primary) : theme.surfaceVariant)')
        ->toContain('.foregroundStyle(enabled ? (token?.onTint ?? theme.onPrimary) : theme.onSurfaceVariant)')
        ->toContain('default:            return token?.tint ?? theme.primary')
        ->toContain('default:            return token?.onTint ?? theme.onPrimary');

    expect($android)
        ->toContain('val tint = tokenColor("tint", theme.primary)')
        ->toContain('containerColor = tint,')
        ->toContain('contentColor = onTint,');
});
