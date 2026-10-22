<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\ListItem;
use Native\Mobile\UI\Elements\ListPlaceholder;
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
    ElementRegistry::register('list_placeholder', ListPlaceholder::class);
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

it('paints rows with a row colour', function () {
    $tree = collectList(['row-color' => '#FFFFFF']);

    expect($tree['props']['row_color'])->toBe('#FFFFFF');
});

it('accepts the camelCase rowColor spelling and the fluent builder', function () {
    expect(collectList(['rowColor' => '#FFF8EE'])['props']['row_color'])->toBe('#FFF8EE')
        ->and(NativeList::make()->rowColor('#123456')->toArray(new CallbackRegistry)['props']['row_color'])->toBe('#123456');
});

it('leaves rows clear without a row colour', function () {
    expect(collectList(['row-color' => ''])['props'] ?? [])->not->toHaveKey('row_color');
});

it('exposes transparent on the fluent builder', function () {
    $list = NativeList::make()->transparent();

    expect($list->toArray(new CallbackRegistry)['props']['transparent'])->toBeTrue();

    $opaque = NativeList::make()->transparent(false);

    expect($opaque->toArray(new CallbackRegistry)['props']['transparent'])->toBeFalse();
});

it('serializes the end reached buffer from attributes', function () {
    $tree = collectList(['end-reached-buffer' => 5]);

    expect($tree['props']['end_reached_buffer'])->toBe(5);
});

it('accepts the end reached buffer on the fluent builder', function () {
    $list = NativeList::make()->endReachedBuffer(5);

    expect($list->toArray(new CallbackRegistry)['props']['end_reached_buffer'])->toBe(5);
});

it('clamps a negative end reached buffer to one', function () {
    $list = NativeList::make()->endReachedBuffer(-1);

    expect($list->toArray(new CallbackRegistry)['props']['end_reached_buffer'])->toBe(1);
});

it('reports the visible range as two positions, the way the virtual list reports its window', function () {
    $registry = new CallbackRegistry;
    NativeElementCollector::open('list', ['on-visible-range' => 'showRows', 'visible-range-step' => 20]);
    NativeElementCollector::close();

    $props = NativeElementCollector::collect()->toArray($registry)['props'];

    expect($registry->resolve($props['on_visible_range'])['method'])->toBe('showRows')
        ->and($registry->kind($props['on_visible_range']))->toBe('virtual_window')
        ->and($props['visible_range_step'])->toBe(20);
});

it('leaves the visible range out of a list that does not ask for it', function () {
    $props = NativeList::make()->toArray(new CallbackRegistry)['props'] ?? [];

    expect($props)->not->toHaveKey('on_visible_range')
        ->and($props)->not->toHaveKey('visible_range_step');
});

it('clamps the visible range step to one row', function () {
    $list = NativeList::make()->onVisibleRange('showRows')->visibleRangeStep(0);

    expect($list->toArray(new CallbackRegistry)['props']['visible_range_step'])->toBe(1);
});

it('gives a placeholder the node id of the row whose key it carries', function () {
    $row = fn () => NativeList::make(Text::make('Hello')->key('commit-1'))->key('log');
    $placeholder = fn () => NativeList::make(ListPlaceholder::make()->key('commit-1'))->key('log');

    $rowNode = $row()->toArray(new CallbackRegistry)['children'][0];
    $placeholderNode = $placeholder()->toArray(new CallbackRegistry)['children'][0];

    expect($placeholderNode['type'])->toBe('list_placeholder')
        ->and($placeholderNode['id'])->toBe($rowNode['id'])
        ->and($placeholderNode)->not->toHaveKey('children');
});

it('serializes a placeholder estimated height from attributes', function () {
    NativeElementCollector::open('list', []);
    NativeElementCollector::leaf('list_placeholder', ['estimated-height' => 120]);
    NativeElementCollector::close();

    $placeholder = NativeElementCollector::collect()->toArray(new CallbackRegistry)['children'][0];

    expect($placeholder['props']['estimated_height'])->toBe(120.0);
});
