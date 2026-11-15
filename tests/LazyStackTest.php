<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Components\LazyStack as LazyStackComponent;
use Native\Mobile\UI\Elements\LazyStack;

/**
 * `native:lazy-stack`: a vertical scroll of keyed children drawn lazily.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('text', Text::class);
    ElementRegistry::register('lazy_stack', LazyStack::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('collects its children in order, with gap and padding from classes', function () {
    NativeElementCollector::open('lazy_stack', ['class' => 'w-full flex-1 gap-2 p-4 bg-white']);
    NativeElementCollector::leaf('text', ['text' => 'One']);
    NativeElementCollector::leaf('text', ['text' => 'Two']);
    NativeElementCollector::close();

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('lazy_stack')
        ->and(array_column($tree['children'], 'type'))->toBe(['text', 'text'])
        ->and($tree['layout'])->toMatchArray(['gap' => 8.0, 'padding' => 16.0])
        ->and($tree['style']['bg_color'])->toBe('#FFFFFF');
});

it('takes content padding the way CSS padding takes values', function (mixed $value, array $expected) {
    NativeElementCollector::open('lazy_stack', ['content-padding' => $value]);
    NativeElementCollector::close();

    $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

    expect([
        $props['content_padding_top'], $props['content_padding_right'],
        $props['content_padding_bottom'], $props['content_padding_left'],
    ])->toBe($expected);
})->with([
    'one value' => [16, [16.0, 16.0, 16.0, 16.0]],
    'two values' => ['8 16', [8.0, 16.0, 8.0, 16.0]],
    'three values' => ['8 16 24', [8.0, 16.0, 24.0, 16.0]],
    'four values' => ['1 2 3 4', [1.0, 2.0, 3.0, 4.0]],
]);

it('sends no props it was not given', function () {
    $stack = LazyStack::make(Text::make('One'))->toArray(new CallbackRegistry);

    expect($stack['type'])->toBe('lazy_stack')
        ->and($stack['children'])->toHaveCount(1)
        ->and($stack['props'] ?? [])->not->toHaveKey('content_padding_top');
});

it('hides the scroll indicator when asked', function () {
    NativeElementCollector::open('lazy_stack', ['shows-indicators' => false]);
    NativeElementCollector::close();

    $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

    expect($props['shows_indicators'])->toBeFalse();
});

it('registers its own renderer on iOS and Android', function () {
    $manifest = json_decode(file_get_contents(dirname(__DIR__).'/nativephp.json'), true);
    $component = collect($manifest['components'])->firstWhere('type', 'lazy_stack');

    expect($component)->toMatchArray([
        'element' => LazyStack::class,
        'blade' => LazyStackComponent::class,
        'android_renderer' => 'com.nativephp.plugins.native_ui.ui.LazyStackRenderer',
        'ios_renderer' => 'NativeUILazyStackRenderer',
        'self_closing' => false,
    ]);
});
