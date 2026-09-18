<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\UI\Builders\BackgroundLayer as BackgroundLayerBuilder;
use Native\Mobile\UI\Concerns\InteractsWithBackgroundLayer;
use Native\Mobile\UI\Elements\BackgroundLayer;
use Native\Mobile\UI\Elements\Chip;
use Native\Mobile\UI\NativeUIServiceProvider;

/**
 * The background-layer layout hook: persistent content rendered beneath
 * every screen under the layout (a map, a video, a canvas). Covers the
 * builder surface (returned from `NativeLayout::backgroundLayer()`) and
 * the `background_layer` sentinel the chrome contributor emits from it.
 * Mirrors FloatingOverlayTest.
 */
it('carries content through the builder', function () {
    $content = Chip::make('Map layer');
    $builder = BackgroundLayerBuilder::make($content);

    expect($builder->getContent())->toBe($content);
});

it('serializes the sentinel with its child beneath it', function () {
    $sentinel = BackgroundLayer::make();
    $sentinel->addChild(Chip::make('Map layer'));

    $tree = $sentinel->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('background_layer');
    expect($tree['children'])->toHaveCount(1);
    expect($tree['children'][0]['type'])->toBe('chip');
});

/**
 * The contributor's per-screen opt-out accepts BOTH spellings: the
 * InteractsWithBackgroundLayer trait (method form) and a bare
 * `protected bool $hidesBackgroundLayer = true;` property — the latter
 * matching core's `$hidesTabBar` / `$hidesNavBar` shorthand.
 */
it('reads the background-layer opt-out from the trait method form', function () {
    $screen = new class extends NativeComponent
    {
        use InteractsWithBackgroundLayer;

        public function __construct()
        {
            $this->hidesBackgroundLayer = true;
        }
    };

    expect(NativeUIServiceProvider::screenHides($screen, 'hidesBackgroundLayer'))->toBeTrue();
});

it('reads the background-layer opt-out from a bare property without the trait', function () {
    $screen = new class extends NativeComponent
    {
        protected bool $hidesBackgroundLayer = true;
    };

    expect(NativeUIServiceProvider::screenHides($screen, 'hidesBackgroundLayer'))->toBeTrue();
});

it('defaults the background-layer opt-out to false when the screen declares neither', function () {
    $screen = new class extends NativeComponent {};

    expect(NativeUIServiceProvider::screenHides($screen, 'hidesBackgroundLayer'))->toBeFalse();
});

it('the trait override hook defaults to null so the layout wins', function () {
    $screen = new class extends NativeComponent
    {
        use InteractsWithBackgroundLayer;
    };

    expect($screen->backgroundLayerOverride())->toBeNull();
});
