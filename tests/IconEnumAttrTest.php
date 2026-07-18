<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Icon\IosSymbol;
use Native\Mobile\Platform;
use Native\Mobile\UI\Elements\Icon;

/**
 * `<icon :ios="Ios::House" :android="Android::Home"/>` — platform enum
 * overrides as blade attributes, same shape as the programmatic
 * `Icon::make(ios: …, android: …)`. Fixture enums are inline (distinct
 * names from HasPlatformIconTest's — Pest loads all test files into one
 * process) so the test doesn't depend on a generated `App\Icons\*` catalog.
 */
enum IconAttrIos: string implements IosSymbol
{
    case House = 'house.fill';
}

enum IconAttrAndroid: string implements AndroidSymbol
{
    public function variant(): string
    {
        return 'filled';
    }

    case Home = 'home';
}

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('icon', Icon::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    Platform::set(null);
});

it('resolves :ios enum attribute on ios', function () {
    Platform::set('ios');

    NativeElementCollector::leaf('icon', [
        'ios' => IconAttrIos::House,
        'android' => IconAttrAndroid::Home,
        'size' => 36,
    ]);
    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['name'])->toBe('house.fill');
});

it('resolves :android enum attribute on android', function () {
    Platform::set('android');

    NativeElementCollector::leaf('icon', [
        'ios' => IconAttrIos::House,
        'android' => IconAttrAndroid::Home,
    ]);
    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['name'])->toBe('home');
    expect($tree['props']['material_variant'])->toBe('filled');
});
