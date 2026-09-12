<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Column;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\Reel;

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('reel', Reel::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('applies windowed reel props and registers the page callback with the reel_page kind', function () {
    NativeElementCollector::open('reel', [
        'count' => 500,
        'page' => 41,
        'from' => 40,
        'to' => 42,
        'on-page-change' => 'setReelPage',
    ]);
    NativeElementCollector::open('column', []);
    NativeElementCollector::close();
    NativeElementCollector::close();

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('reel')
        ->and($tree['props']['count'])->toBe(500)
        ->and($tree['props']['page'])->toBe(41)
        ->and($tree['props']['window_from'])->toBe(40)
        ->and($tree['props']['window_to'])->toBe(42)
        ->and($tree['props'])->not->toHaveKey('horizontal');

    $cb = $tree['props']['on_page_change'];
    expect($registry->resolve($cb))->toBe(['method' => 'setReelPage', 'args' => []])
        ->and($registry->kind($cb))->toBe('reel_page');
});

it('defaults count to the inline page count and forwards horizontal', function () {
    $tree = Reel::make(
        Column::make(Text::make('one')),
        Column::make(Text::make('two')),
        Column::make(Text::make('three')),
    )->horizontal()->toArray(new CallbackRegistry);

    expect($tree['props']['count'])->toBe(3)
        ->and($tree['props']['horizontal'])->toBeTrue()
        ->and($tree['props'])->not->toHaveKey('on_page_change')
        ->and($tree['children'])->toHaveCount(3);
});

it('clamps negative count and page to zero', function () {
    $tree = Reel::make()->count(-4)->page(-1)->toArray(new CallbackRegistry);

    expect($tree['props']['count'])->toBe(0)
        ->and($tree['props']['page'])->toBe(0);
});
