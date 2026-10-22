<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Divider;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;

/**
 * The divider renderers (NativeUIDividerRenderer / DividerRenderer) colour
 * the rule from these wire keys: `style.border_color` with
 * `props.dark_border_color`, else `style.bg_color` with
 * `props.dark_bg_color`, else the platform separator. These pin that the
 * classes an author writes on `<native:divider>` reach those keys.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('divider', Divider::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function collectDivider(string $class): array
{
    NativeElementCollector::leaf('divider', ['class' => $class]);

    return NativeElementCollector::collect()->toArray(new CallbackRegistry);
}

it('carries a background colour and its dark variant', function () {
    $node = collectDivider('bg-red-500 dark:bg-blue-500');

    expect($node['style']['bg_color'])->toBe('#EF4444');
    expect($node['props']['dark_bg_color'])->toBe('#3B82F6');
});

it('carries a border colour and its dark variant', function () {
    $node = collectDivider('border border-[#FF0000] dark:border-[#00FF00]');

    expect($node['style']['border_color'])->toBe('#FF0000');
    expect($node['props']['dark_border_color'])->toBe('#00FF00');
});

it('sends no colour for a plain divider, so the platform separator draws', function () {
    $node = collectDivider('');

    expect($node)->not->toHaveKey('style');
    expect($node['props'] ?? [])->not->toHaveKey('dark_bg_color');
    expect($node['props'] ?? [])->not->toHaveKey('dark_border_color');
});
