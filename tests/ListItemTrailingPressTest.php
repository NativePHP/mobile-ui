<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\NativeTagPrecompiler;
use Native\Mobile\UI\Elements\ListItem;

/**
 * A trailing icon button's press handler set from Blade has to reach the
 * wire as `on_trailing_press`, which both renderers already fire.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('list_item', ListItem::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function trailingPressTree(array $attrs, CallbackRegistry $registry): array
{
    NativeElementCollector::leaf('list_item', ['headline' => 'Buy milk', 'trailingIconButton' => 'trash'] + $attrs);

    return NativeElementCollector::collect()->toArray($registry);
}

it('registers the trailing press handler from each Blade spelling', function (string $attr) {
    $registry = new CallbackRegistry;
    $tree = trailingPressTree([$attr => 'deleteTodo(7)'], $registry);

    expect($tree['props']['trailing_type'])->toBe('icon_button')
        ->and($tree['props']['on_trailing_press'])->toBeInt()
        ->and($registry->resolve($tree['props']['on_trailing_press']))
        ->toBe(['method' => 'deleteTodo', 'args' => [7]]);
})->with(['on-trailing-press', 'onTrailingPress']);

it('compiles on-trailing-press with a bound argument from a Blade tag', function () {
    $wasActive = NativeTagPrecompiler::setActive(true);

    try {
        $php = (new NativeTagPrecompiler)(
            '<native:list-item headline="Buy milk" trailingIconButton="trash" on-trailing-press="deleteTodo({{ $id }})" />'
        );
    } finally {
        NativeTagPrecompiler::setActive($wasActive);
    }

    (function (int $id) use ($php) {
        eval('?>'.$php);
    })(7);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($registry->resolve($tree['props']['on_trailing_press']))
        ->toBe(['method' => 'deleteTodo', 'args' => [7]]);
});

it('sends no trailing press callback when none is set', function () {
    $tree = trailingPressTree([], new CallbackRegistry);

    expect($tree['props'])->not->toHaveKey('on_trailing_press');
});

it('keeps the fluent onTrailingPress builder working', function () {
    $registry = new CallbackRegistry;
    $props = ListItem::make('Buy milk')->trailingIconButton('trash')->onTrailingPress('deleteTodo')
        ->toArray($registry)['props'];

    expect($registry->resolve($props['on_trailing_press']))->toBe(['method' => 'deleteTodo', 'args' => []]);
});
