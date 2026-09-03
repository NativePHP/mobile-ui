<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\ListItem;

/**
 * The opt-in trailing-slot props of `native:list-item`: `trailingTextStyle`
 * and `trailingAlign`. Both are absent from the wire unless authored, so
 * existing rows keep Material's defaults.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('list_item', ListItem::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function collectListItem(array $attrs): array
{
    NativeElementCollector::leaf('list_item', ['headline' => 'Alice won', 'trailingText' => '48'] + $attrs);

    return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];
}

it('sends no trailing style or alignment unless authored', function () {
    $props = collectListItem([]);

    expect($props)->not->toHaveKey('trailing_text_style')
        ->and($props)->not->toHaveKey('trailing_align')
        ->and($props['trailing_type'])->toBe('text');
});

it('sends trailingTextStyle and trailingAlign as wire props', function () {
    $props = collectListItem(['trailingTextStyle' => 'headline', 'trailingAlign' => 'center']);

    expect($props['trailing_text_style'])->toBe('headline')
        ->and($props['trailing_align'])->toBe('center');
});

it('exposes the same props through the fluent builders', function () {
    $item = ListItem::make()->trailingText('48')->trailingTextStyle('headline')->trailingAlign('center');

    $props = $item->toArray(new CallbackRegistry)['props'];

    expect($props['trailing_text_style'])->toBe('headline')
        ->and($props['trailing_align'])->toBe('center');
});

it('rejects unknown values', function () {
    expect(fn () => ListItem::make()->trailingTextStyle('huge'))->toThrow(InvalidArgumentException::class)
        ->and(fn () => ListItem::make()->trailingAlign('bottom'))->toThrow(InvalidArgumentException::class);
});
