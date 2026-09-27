<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\ListItem;

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('list_item', ListItem::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function lineThroughProps(array $attrs): array
{
    NativeElementCollector::leaf('list_item', ['headline' => 'Buy milk'] + $attrs);

    return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'] ?? [];
}

it('leaves the headline undecorated by default', function () {
    expect(lineThroughProps([]))->not->toHaveKey('headline_line_through');
});

it('strikes through the headline from either Blade spelling', function (string $attr) {
    expect(lineThroughProps([$attr => true])['headline_line_through'])->toBeTrue();
})->with(['headline-line-through', 'headlineLineThrough']);

it('follows a bound value so done and not-done rows share one tag', function (mixed $value, bool $expected) {
    expect(lineThroughProps(['headline-line-through' => $value])['headline_line_through'])->toBe($expected);
})->with([
    [true, true],
    [false, false],
    ['true', true],
    ['false', false],
    [1, true],
    [0, false],
]);

it('exposes a fluent builder', function () {
    $props = ListItem::make('Buy milk')->headlineLineThrough()->toArray(new CallbackRegistry)['props'];

    expect($props['headline_line_through'])->toBeTrue();
});
