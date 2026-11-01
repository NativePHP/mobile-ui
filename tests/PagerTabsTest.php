<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\JumpBridge;
use Native\Mobile\UI\Elements\Pager;
use Native\Mobile\UI\Theme;

beforeEach(function () {
    JumpBridge::instance()->mute();
    Theme::reset();
    TailwindParser::clearCache();
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('pager', Pager::class);
});

afterEach(function () {
    Theme::reset();
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function pagerTabProps(array $attrs, ?CallbackRegistry $registry = null): array
{
    NativeElementCollector::open('pager', $attrs);
    NativeElementCollector::close();

    return NativeElementCollector::collect()->toArray($registry ?? new CallbackRegistry)['props'];
}

it('sends the tab labels, their a11y labels and the reselect callback', function () {
    $registry = new CallbackRegistry;

    $props = pagerTabProps([
        'horizontal' => true,
        'tabs' => ['Following', ['label' => 'Latest', 'a11y-label' => 'Latest, 3 new'], 'Trending'],
        'tabs-scrollable' => true,
        'on-tab-reselect' => 'scrollToTop',
    ], $registry);

    expect($props['tabs'])->toBe(['Following', 'Latest', 'Trending'])
        ->and($props['tab_a11y_labels'])->toBe(['', 'Latest, 3 new', ''])
        ->and($props['tabs_scrollable'])->toBeTrue()
        ->and($registry->resolve($props['on_tab_reselect']))->toBe(['method' => 'scrollToTop', 'args' => []]);
});

it('leaves out a11y labels when no tab has one', function () {
    $props = pagerTabProps(['tabs' => ['All', 'Replies']]);

    expect($props['tabs'])->toBe(['All', 'Replies'])
        ->and($props)->not->toHaveKey('tab_a11y_labels')
        ->and($props)->not->toHaveKey('tabs_scrollable')
        ->and($props)->not->toHaveKey('on_tab_reselect');
});

it('sends no tab props without tabs', function () {
    $props = pagerTabProps(['horizontal' => true, 'count' => 3]);

    expect(array_filter(array_keys($props), fn (string $key): bool => str_contains($key, 'tab')))->toBe([]);
});

it('resolves tab colours, sending both shades of a theme token', function () {
    Theme::load([
        'light' => ['ink' => '#121417', 'ink-muted' => '#5b616b', 'hairline' => '#e1e4e8'],
        'dark' => ['ink' => '#ececec', 'ink-muted' => '#a1a1a6', 'hairline' => '#2a2a2d'],
    ]);

    $props = pagerTabProps([
        'tabs' => ['A', 'B'],
        'tab-active-color' => 'theme-ink',
        'tab-color' => 'theme-ink-muted',
        'tab-divider-color' => 'transparent',
        'tab-indicator-color' => 'blue-600',
    ]);

    expect($props['tab_active_color'])->toBe('#121417')
        ->and($props['dark_tab_active_color'])->toBe('#ECECEC')
        ->and($props['tab_color'])->toBe('#5B616B')
        ->and($props['dark_tab_color'])->toBe('#A1A1A6')
        ->and($props['tab_divider_color'])->toBe('#00000000')
        ->and($props)->not->toHaveKey('dark_tab_divider_color')
        ->and($props['tab_indicator_color'])->toBe('#2563EB');
});

it('leaves an unknown theme token to the native default', function () {
    $props = pagerTabProps(['tabs' => ['A'], 'tab-active-color' => 'theme-nope']);

    expect($props)->not->toHaveKey('tab_active_color')
        ->and($props)->not->toHaveKey('dark_tab_active_color');
});

it('sends the tab font, sizes and padding', function () {
    $props = pagerTabProps([
        'tabs' => ['A'],
        'tab-font' => 'semibold',
        'tab-font-size' => '15',
        'tab-indicator-height' => 3,
        'tab-padding-x' => 12,
        'tab-padding-top' => 14,
        'tab-padding-bottom' => 11,
        'tab-edge-padding' => -2,
    ]);

    expect($props['tab_font'])->toBe('semibold')
        ->and($props['tab_font_size'])->toBe(15.0)
        ->and($props['tab_indicator_height'])->toBe(3.0)
        ->and($props['tab_padding_x'])->toBe(12.0)
        ->and($props['tab_padding_top'])->toBe(14.0)
        ->and($props['tab_padding_bottom'])->toBe(11.0)
        ->and($props['tab_edge_padding'])->toBe(0.0);
});

it('builds the same tabs fluently', function () {
    $registry = new CallbackRegistry;

    $props = Pager::make()
        ->horizontal()
        ->tabs(['Following', 'Latest'])
        ->tabsScrollable()
        ->onTabReselect('scrollToTop')
        ->tabActiveColor('red-300')
        ->tabFont('semibold')
        ->tabPadding(top: 10)
        ->toArray($registry)['props'];

    expect($props['tabs'])->toBe(['Following', 'Latest'])
        ->and($props['tabs_scrollable'])->toBeTrue()
        ->and($registry->resolve($props['on_tab_reselect'])['method'])->toBe('scrollToTop')
        ->and($props['tab_active_color'])->toBe('#FCA5A5')
        ->and($props['tab_font'])->toBe('semibold')
        ->and($props['tab_padding_top'])->toBe(10.0)
        ->and($props)->not->toHaveKey('tab_padding_x');
});

it('drives the iOS tab row from the pager position, not PHP', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        // The unrounded position, written every frame into an observable only the row reads.
        ->toContain('.onScrollGeometryChange(for: CGFloat?.self)')
        ->toContain('progress.value = value')
        ->toContain('@Observable')
        // Highlight: the nearest page. Indicator: between the labels either side.
        ->toContain('Int(progress.value.rounded())')
        ->toContain('let from = Int(position.rounded(.down))')
        ->toContain('a.minX + (b.minX - a.minX) * t')
        // A scrollable row follows the indicator.
        ->toContain('rowPosition.scrollTo(x:')
        ->toContain('.accessibilityAddTraits(.isTabBar)');
});

it('scrolls the iOS pager on a tab tap and sends a reselect to PHP', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toMatch('/if index == leading, abs\(progress\.value - CGFloat\(index\)\) < 0\.01 \{\s*if let cb = tabs\?\.reselectCbId, cb != 0 \{\s*NativeElementBridge\.sendTabChangeEvent\(cb, nodeId: nodeId, index: index\)/')
        ->toContain('withAnimation { position = index }');
});

it('drives the Android tab row from the pager position, not PHP', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    expect($source)
        ->toContain('pagerState.currentPage + pagerState.currentPageOffsetFraction')
        ->toContain('val active = pagerState.currentPage.coerceIn(0, last)')
        ->toContain('.drawBehind {')
        ->toContain('role = Role.Tab')
        ->toContain('scope.launch { pagerState.animateScrollToPage(index) }')
        ->toContain('NativeElementBridge.sendTabChangeEvent(tabs.reselectCbId, node.id, index)')
        ->toContain('scrollState.scrollTo(');
});

it('sends a pill indicator on a track, with both shades of a theme track colour', function () {
    Theme::load([
        'light' => ['groove' => '#f2f2f2', 'rim' => '#e5e5e5'],
        'dark' => ['groove' => '#1c1c1e', 'rim' => '#2c2c2e'],
    ]);

    $props = pagerTabProps([
        'tabs' => ['Cart', 'Ongoing', 'History'],
        'tab-indicator-style' => 'pill',
        'tab-track-color' => 'theme-groove',
        'tab-track-border-color' => 'theme-rim',
        'tab-track-border-width' => 1.5,
        'tab-track-padding' => 4,
    ]);

    expect($props['tab_indicator_style'])->toBe('pill')
        ->and($props['tab_track_color'])->toBe('#F2F2F2')
        ->and($props['dark_tab_track_color'])->toBe('#1C1C1E')
        ->and($props['tab_track_border_color'])->toBe('#E5E5E5')
        ->and($props['dark_tab_track_border_color'])->toBe('#2C2C2E')
        ->and($props['tab_track_border_width'])->toBe(1.5)
        ->and($props['tab_track_padding'])->toBe(4.0);
});

it('builds a pill indicator on a track fluently', function () {
    $props = Pager::make()
        ->tabs(['A', 'B'])
        ->tabIndicatorStyle('pill')
        ->tabTrackColor('gray-100')
        ->tabTrackBorderColor('gray-200')
        ->tabTrackBorderWidth(-1)
        ->tabTrackPadding(-1)
        ->toArray(new CallbackRegistry)['props'];

    expect($props['tab_indicator_style'])->toBe('pill')
        ->and($props['tab_track_color'])->toBe('#F3F4F6')
        ->and($props['tab_track_border_color'])->toBe('#E5E7EB')
        ->and($props['tab_track_border_width'])->toBe(0.0)
        ->and($props['tab_track_padding'])->toBe(0.0);
});

it('rejects an indicator style it cannot draw', function () {
    pagerTabProps(['tabs' => ['A'], 'tab-indicator-style' => 'dot']);
})->throws(InvalidArgumentException::class, "pager tab-indicator-style must be 'underline' or 'pill', got 'dot'");

it('draws the pill and track behind the tab labels on iOS, and the underline over them', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('self.pill = p.getString("tab_indicator_style") == "pill"')
        ->toMatch('/\.background\(alignment: \.topLeading\) \{\s*ZStack\(alignment: \.topLeading\) \{\s*if tabs\.hasTrack/')
        ->toContain('if tabs.pill, let frame = pillFrame')
        ->toContain('.strokeBorder(resolve(tabs.trackBorderColor, fallback: .clear), lineWidth: tabs.trackBorderWidth)')
        ->toContain('if !tabs.pill, let frame = indicatorFrame')
        // The pill fills each tab, so it slides between whole tabs, not labels.
        ->toContain('action: { tabFrames[index] = $0 }')
        ->toContain('fallback: tabs.pill ? theme.onPrimary : theme.onSurface');
});

it('draws the pill and track behind the tab labels on Android', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    expect($source)
        ->toContain('val pill = p.getString("tab_indicator_style") == "pill"')
        ->toContain('if (tabs.trackColor.isSet) {')
        ->toContain('style = Stroke(width = width)')
        ->toContain('val bounds = pill() ?: return@drawBehind')
        ->toContain('tabBounds[index] = Rect(origin, Size(it.size.width.toFloat(), it.size.height.toFloat()))')
        ->toContain('if (tabs.pill) theme.onPrimary else theme.onSurface');
});
