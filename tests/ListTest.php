<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\ListItem;
use Native\Mobile\UI\Elements\ListSection;
use Native\Mobile\UI\Elements\NativeList;

/**
 * Attribute → wire-prop behaviour of `native:list`, driven through core's
 * NativeElementCollector exactly as compiled Blade drives it.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('text', Text::class);
    ElementRegistry::register('list', NativeList::class);
    ElementRegistry::register('list_section', ListSection::class);
    ElementRegistry::register('list_item', ListItem::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function collectList(array $attrs): array
{
    NativeElementCollector::open('list', $attrs);
    NativeElementCollector::open('list_section', ['header' => 'Today']);
    NativeElementCollector::leaf('list_item', ['headline' => 'Alice won']);
    NativeElementCollector::close();
    NativeElementCollector::close();

    return NativeElementCollector::collect()->toArray(new CallbackRegistry);
}

it('leaves the platform scroll background alone by default', function () {
    $tree = collectList([]);

    expect($tree['type'])->toBe('list')
        ->and($tree['props'] ?? [])->not->toHaveKey('transparent')
        ->and($tree['props'] ?? [])->not->toHaveKey('plain')
        ->and($tree['children'][0]['type'])->toBe('list_section');
});

it('marks a list transparent so the screen background shows through', function () {
    $tree = collectList(['transparent' => true]);

    expect($tree['props']['transparent'])->toBeTrue();
});

it('accepts the list style switches together', function () {
    $tree = collectList(['transparent' => true, 'plain' => true, 'separator' => true]);

    expect($tree['props']['transparent'])->toBeTrue()
        ->and($tree['props']['plain'])->toBeTrue()
        ->and($tree['props']['separator'])->toBeTrue();
});

it('exposes transparent on the fluent builder', function () {
    $list = NativeList::make()->transparent();

    expect($list->toArray(new CallbackRegistry)['props']['transparent'])->toBeTrue();

    $opaque = NativeList::make()->transparent(false);

    expect($opaque->toArray(new CallbackRegistry)['props']['transparent'])->toBeFalse();
});
