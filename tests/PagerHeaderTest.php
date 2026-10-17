<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Column;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\Pager;
use Native\Mobile\UI\Elements\PagerHeader;
use Native\Mobile\UI\Elements\PagerOverlay;

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('pager', Pager::class);
    ElementRegistry::register('pager_header', PagerHeader::class);
    ElementRegistry::register('pager_overlay', PagerOverlay::class);
    ElementRegistry::register('column', Column::class);
    ElementRegistry::register('text', Text::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function swiftSource(string $file): string
{
    return file_get_contents(dirname(__DIR__).'/resources/ios/'.$file);
}

function kotlinSource(string $file): string
{
    return file_get_contents(dirname(__DIR__).'/resources/android/'.$file);
}

it('sends the header and the overlay beside the pages, and counts only the pages', function () {
    NativeElementCollector::open('pager', ['horizontal' => true, 'tabs' => ['Posts', 'Replies']]);
    NativeElementCollector::open('pager_header', []);
    NativeElementCollector::open('text', ['text' => 'Ada']);
    NativeElementCollector::close();
    NativeElementCollector::close();
    NativeElementCollector::open('column', []);
    NativeElementCollector::close();
    NativeElementCollector::open('column', []);
    NativeElementCollector::close();
    NativeElementCollector::open('pager_overlay', []);
    NativeElementCollector::close();
    NativeElementCollector::close();

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect(array_column($tree['children'], 'type'))->toBe(['pager_header', 'column', 'column', 'pager_overlay'])
        ->and($tree['props']['count'])->toBe(2)
        ->and($tree['children'][0]['props'] ?? [])->toBe([])
        ->and($tree['children'][0]['children'][0]['type'])->toBe('text');
});

it('builds the same pager fluently', function () {
    $tree = Pager::make(
        PagerHeader::make(Text::make('Ada')),
        Column::make(Text::make('Posts')),
        Column::make(Text::make('Replies')),
        PagerOverlay::make(Text::make('3 new posts')),
    )->horizontal()->tabs(['Posts', 'Replies'])->toArray(new CallbackRegistry);

    expect($tree['props']['count'])->toBe(2)
        ->and(array_column($tree['children'], 'type'))->toBe(['pager_header', 'column', 'column', 'pager_overlay']);
});

it('registers the header and the overlay for the pager to draw', function () {
    $components = collect(json_decode(file_get_contents(dirname(__DIR__).'/nativephp.json'), true)['components'])->keyBy('type');

    foreach (['pager_header' => 'PagerHeader', 'pager_overlay' => 'PagerOverlay'] as $type => $class) {
        expect($components[$type])->toMatchArray([
            'element' => "Native\\Mobile\\UI\\Elements\\{$class}",
            'blade' => "Native\\Mobile\\UI\\Components\\{$class}",
            'android_renderer' => 'com.nativephp.plugins.native_ui.ui.EmptyRenderer',
            'ios_renderer' => 'NativeUIEmptyRenderer',
            'self_closing' => false,
        ]);
    }
});

it('keeps the header and the overlay out of the pages on both platforms', function () {
    expect(swiftSource('NativeUIPagerRenderer.swift'))
        ->toContain('let pages = node.children.filter { $0.type != "pager_header" && $0.type != "pager_overlay" }')
        ->toContain('header: horizontal ? node.children.first { $0.type == "pager_header" } : nil');

    expect(kotlinSource('PagerRenderer.kt'))
        ->toContain('node.children.filter { it.type != "pager_header" && it.type != "pager_overlay" }')
        ->toContain('val header = if (horizontal) node.children.firstOrNull { it.type == "pager_header" } else null');
});

it("draws the header as a page list's first row and pins the tabs under it", function () {
    expect(swiftSource('NativeUIListRenderer.swift'))
        ->toContain('@Environment(\.nativeUIPagerHeader) private var pagerHeader')
        ->toMatch('/NativeUIPagerHeaderRow\(header: pagerHeader\)[\s\S]*?Section \{[\s\S]*?\} header: \{[\s\S]*?NativeUIPagerHeaderStrip\(header: pagerHeader\)/')
        ->toContain('.environment(\.nativeUIPagerHeader, nil)');

    expect(kotlinSource('ListRenderer.kt'))
        ->toContain('val pagerHeader = if (horizontal) null else LocalPagerHeader.current')
        ->toMatch('/item\(key = PAGER_HEADER_KEY\) \{ PagerHeaderRow\(pagerHeader\) \}\s*if \(pagerHeader.hasTabs\) \{\s*stickyHeader\(key = PAGER_TABS_KEY\)/');
});

it('holds the header still while the pager swipes', function () {
    expect(swiftSource('NativeUIPagerRenderer.swift'))
        ->toContain('(progress.value - CGFloat(page)) * scroll.pageWidth')
        ->toContain('content.offset(x: header.stationaryOffset)');

    expect(kotlinSource('PagerRenderer.kt'))
        ->toContain('translationX = (header.pagerState.currentPage + header.pagerState.currentPageOffsetFraction - header.page) * size.width');
});

it('keeps the pages level while any of the header shows, and lets each keep its place once it has gone', function () {
    expect(swiftSource('NativeUIPagerRenderer.swift'))
        ->toContain('let target = shown < headerHeight ? shown : max(own, headerHeight)');

    expect(kotlinSource('PagerRenderer.kt'))
        ->toContain('val target = if (collapse < height) collapse else maxOf(own, height)');
});
