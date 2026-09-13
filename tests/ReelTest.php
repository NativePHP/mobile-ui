<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Column;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Concerns\HasReelPage;
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

it('applies windowed reel props and registers the page callback', function () {
    NativeElementCollector::open('reel', [
        'count' => 500,
        'page' => 41,
        'from' => 40,
        'to' => 42,
        'has-more' => true,
        'placeholders' => ['https://x/a.jpg', null, 'https://x/c.jpg'],
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
        ->and($tree['props']['has_more'])->toBeTrue()
        ->and($tree['props']['placeholders'])->toBe(['https://x/a.jpg', '', 'https://x/c.jpg'])
        ->and($tree['props'])->not->toHaveKey('horizontal');

    $cb = $tree['props']['on_page_change'];
    expect($registry->resolve($cb))->toBe(['method' => 'setReelPage', 'args' => []])
        ->and($registry->kind($cb))->toBeNull();
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
        ->and($tree['props'])->not->toHaveKey('has_more')
        ->and($tree['children'])->toHaveCount(3);
});

it('clamps negative count and page to zero', function () {
    $tree = Reel::make()->count(-4)->page(-1)->toArray(new CallbackRegistry);

    expect($tree['props']['count'])->toBe(0)
        ->and($tree['props']['page'])->toBe(0);
});

it('tracks the settled page, the loaded count and when a feed needs its next batch', function () {
    $host = new class
    {
        use HasReelPage;
    };

    // Nothing loaded yet: window is page ±1, unclamped.
    expect($host->reelPage)->toBe(0)
        ->and($host->reelWindowFrom())->toBe(0)
        ->and($host->reelWindowTo())->toBe(1)
        ->and($host->reelNeedsMore())->toBeTrue();

    $host->extendReel(10);
    expect($host->reelLoaded)->toBe(10)
        ->and($host->reelHasMore)->toBeTrue()
        ->and($host->reelNeedsMore())->toBeFalse();

    // Window clamps to what is loaded.
    $host->setReelPage(9);
    expect($host->reelWindowFrom())->toBe(8)
        ->and($host->reelWindowTo())->toBe(9);

    // Within three of the end → fetch ahead; the threshold is tunable.
    $host->setReelPage(7);
    expect($host->reelNeedsMore())->toBeTrue()
        ->and($host->reelNeedsMore(1))->toBeFalse();

    // On the loading tail (index === loaded) it always needs more.
    $host->setReelPage(10);
    expect($host->reelNeedsMore(0))->toBeTrue();

    // Last batch: nothing more to fetch, whatever the page.
    $host->extendReel(4, hasMore: false);
    expect($host->reelLoaded)->toBe(14)
        ->and($host->reelNeedsMore())->toBeFalse();

    $host->setReelPage(-4);
    expect($host->reelPage)->toBe(0);
});
