<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Components\StickyHeader as StickyHeaderComponent;
use Native\Mobile\UI\Elements\NativeList;
use Native\Mobile\UI\Elements\StickyHeader;

/**
 * `native:sticky-header`: a list row that pins to the top of the list once it
 * reaches it, while the rows after it scroll underneath.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('text', Text::class);
    ElementRegistry::register('list', NativeList::class);
    ElementRegistry::register('sticky_header', StickyHeader::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('collects a sticky header and what it holds as a row of the list', function () {
    NativeElementCollector::open('list', []);
    NativeElementCollector::leaf('text', ['text' => 'Above']);
    NativeElementCollector::open('sticky_header', ['class' => 'w-full bg-white py-3', 'a11y-label' => 'New posts']);
    NativeElementCollector::leaf('text', ['text' => '3 new posts']);
    NativeElementCollector::close();
    NativeElementCollector::leaf('text', ['text' => 'Below']);
    NativeElementCollector::close();

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);
    $header = $tree['children'][1];

    expect(array_column($tree['children'], 'type'))->toBe(['text', 'sticky_header', 'text'])
        ->and($header['children'])->toHaveCount(1)
        ->and($header['layout'])->toMatchArray(['width' => 'fill', 'padding' => [12, 0, 12, 0]])
        ->and($header['style']['bg_color'])->toBe('#FFFFFF')
        ->and($header['props']['a11y_label'])->toBe('New posts');
});

it('takes hidden, so a header can wait in its place until there is something to show', function () {
    NativeElementCollector::open('list', []);
    NativeElementCollector::open('sticky_header', ['class' => 'hidden']);
    NativeElementCollector::close();
    NativeElementCollector::close();

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['children'][0]['type'])->toBe('sticky_header')
        ->and($tree['children'][0]['layout']['display'])->toBe(1);
});

it('builds a sticky header with the fluent API', function () {
    $header = StickyHeader::make(Text::make('3 new posts'))->toArray(new CallbackRegistry);

    expect($header['type'])->toBe('sticky_header')
        ->and($header['children'])->toHaveCount(1);
});

it('lays a sticky header out as a column on both platforms', function () {
    $manifest = json_decode(file_get_contents(dirname(__DIR__).'/nativephp.json'), true);
    $component = collect($manifest['components'])->firstWhere('type', 'sticky_header');

    expect($component)->toMatchArray([
        'element' => StickyHeader::class,
        'blade' => StickyHeaderComponent::class,
        'android_renderer' => 'com.nativephp.plugins.native_ui.ui.ColumnRenderer',
        'ios_renderer' => 'NativeUIColumnRenderer',
        'self_closing' => false,
    ]);
});

it('pins a sticky header on iOS as the header of a plain list section holding the rows after it', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIListRenderer.swift');

    expect($source)
        ->toContain('let hasStickyHeaders = !hasSections && children.contains { $0.type == "sticky_header" }')
        ->toContain('stickyHeaderView(group.header)')
        ->toContain('.environment(\.defaultMinListHeaderHeight, 0)')
        ->toContain('.listSectionSpacing(0)')
        ->toMatch('/if header\.layout\?\.display != Display\.none \{\s*NodeView\(node: header\)/');
});

it('pins a sticky header on Android as a sticky LazyColumn item', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ListRenderer.kt');

    expect($source)->toContain('} else if (child.type == "sticky_header" && !hasSections) {')
        ->toContain('stickyHeader(key = child.id) { NodeView(node = child) }');
});
