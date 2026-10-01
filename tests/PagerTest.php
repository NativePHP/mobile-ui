<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Column;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Concerns\HasPagerWindow;
use Native\Mobile\UI\Elements\Pager;

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('pager', Pager::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('applies windowed pager props and registers the page callback', function () {
    NativeElementCollector::open('pager', [
        'count' => 500,
        'page' => 41,
        'from' => 40,
        'to' => 42,
        'has-more' => true,
        'placeholders' => ['https://x/a.jpg', null, 'https://x/c.jpg'],
        'on-page-change' => 'setPagerPage',
    ]);
    NativeElementCollector::open('column', []);
    NativeElementCollector::close();
    NativeElementCollector::close();

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('pager')
        ->and($tree['props']['count'])->toBe(500)
        ->and($tree['props']['page'])->toBe(41)
        ->and($tree['props']['window_from'])->toBe(40)
        ->and($tree['props']['window_to'])->toBe(42)
        ->and($tree['props']['has_more'])->toBeTrue()
        ->and($tree['props']['placeholders'])->toBe(['https://x/a.jpg', '', 'https://x/c.jpg'])
        ->and($tree['props'])->not->toHaveKey('horizontal');

    $cb = $tree['props']['on_page_change'];
    expect($registry->resolve($cb))->toBe(['method' => 'setPagerPage', 'args' => []])
        ->and($registry->kind($cb))->toBeNull();
});

it('defaults count to the inline page count and forwards horizontal', function () {
    $tree = Pager::make(
        Column::make(Text::make('one')),
        Column::make(Text::make('two')),
        Column::make(Text::make('three')),
    )->horizontal()->toArray(new CallbackRegistry);

    expect($tree['props']['count'])->toBe(3)
        ->and($tree['props']['horizontal'])->toBeTrue()
        ->and($tree['props'])->not->toHaveKey('on_page_change')
        ->and($tree['props'])->not->toHaveKey('has_more')
        ->and($tree['children'])->toHaveCount(3);
});

it('clamps negative count and page to zero', function () {
    $tree = Pager::make()->count(-4)->page(-1)->toArray(new CallbackRegistry);

    expect($tree['props']['count'])->toBe(0)
        ->and($tree['props']['page'])->toBe(0);
});

it('tracks the settled page, the loaded count and when a feed needs its next batch', function () {
    $host = new class
    {
        use HasPagerWindow;
    };

    // Nothing loaded yet: window is page ±2, unclamped.
    expect($host->pagerPage)->toBe(0)
        ->and($host->pagerWindowFrom())->toBe(0)
        ->and($host->pagerWindowTo())->toBe(2)
        ->and($host->pagerNeedsMore())->toBeTrue();

    $host->extendPager(10);
    expect($host->pagerLoaded)->toBe(10)
        ->and($host->pagerHasMore)->toBeTrue()
        ->and($host->pagerNeedsMore())->toBeFalse();

    // Window clamps to what is loaded.
    $host->setPagerPage(9);
    expect($host->pagerWindowFrom())->toBe(7)
        ->and($host->pagerWindowTo())->toBe(9);

    // Within three of the end → fetch ahead; the threshold is tunable.
    $host->setPagerPage(7);
    expect($host->pagerNeedsMore())->toBeTrue()
        ->and($host->pagerNeedsMore(1))->toBeFalse();

    // On the loading tail (index === loaded) it always needs more.
    $host->setPagerPage(10);
    expect($host->pagerNeedsMore(0))->toBeTrue();

    // Last batch: nothing more to fetch, whatever the page.
    $host->extendPager(4, hasMore: false);
    expect($host->pagerLoaded)->toBe(14)
        ->and($host->pagerNeedsMore())->toBeFalse();

    $host->setPagerPage(-4);
    expect($host->pagerPage)->toBe(0);
});
