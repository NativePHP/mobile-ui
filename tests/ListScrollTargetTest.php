<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\NativeList;

/**
 * `scroll-target` / `scrollTarget()` — the key a list publishes itself
 * under for the Android bottom-tab reselect scroll seam. A
 * `Tab::onReselect($method, $key)` naming the same key scrolls this list
 * back to its top when its tab is re-tapped while the list is scrolled,
 * or fires $method when it already sits at exact top. Serialized as a
 * plain `scroll_target` string prop (the registry key, not a callback
 * id) and omitted entirely when not configured.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('text', Text::class);
    ElementRegistry::register('list', NativeList::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('leaves the scroll target off a list that does not declare one', function () {
    $fluent = NativeList::make()->toArray(new CallbackRegistry)['props'] ?? [];

    NativeElementCollector::open('list', ['separator' => true, 'on-refresh' => 'reload']);
    NativeElementCollector::close();
    $fromAttrs = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'] ?? [];

    expect($fluent)->not->toHaveKey('scroll_target')
        ->and($fromAttrs)->not->toHaveKey('scroll_target');
});

it('serializes the scroll target from attributes', function () {
    NativeElementCollector::open('list', ['scroll-target' => 'log-feed-following']);
    NativeElementCollector::close();

    $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

    expect($props['scroll_target'])->toBe('log-feed-following');
});

it('accepts the scroll target attribute in its camelCase spelling', function () {
    NativeElementCollector::open('list', ['scrollTarget' => 'log-feed-trending']);
    NativeElementCollector::close();

    $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

    expect($props['scroll_target'])->toBe('log-feed-trending');
});

it('exposes the scroll target on the fluent builder', function () {
    $list = NativeList::make()->scrollTarget('log-feed-latest');

    expect($list->toArray(new CallbackRegistry)['props']['scroll_target'])->toBe('log-feed-latest');
});
