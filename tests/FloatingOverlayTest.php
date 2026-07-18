<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\UI\Builders\FloatingOverlay as FloatingOverlayBuilder;
use Native\Mobile\UI\Concerns\InteractsWithFloatingOverlay;
use Native\Mobile\UI\Elements\Chip;
use Native\Mobile\UI\Elements\FloatingOverlay;
use Native\Mobile\UI\NativeUIServiceProvider;

/**
 * The floating-overlay layout hook: a content-agnostic pill/banner that floats
 * over the content (and the tab bar) rather than insetting it. Covers the
 * builder surface (returned from `NativeLayout::floatingOverlay()`) and the
 * `floating_overlay` sentinel the chrome contributor emits from it.
 */

it('defaults the builder to a bottom overlay with no explicit offset', function () {
    $builder = FloatingOverlayBuilder::make(Chip::make('3 servers nearby'));

    expect($builder->getAlignment())->toBe('bottom');
    expect($builder->getOffset())->toBeNull();
});

it('carries alignment, offset and content through the builder', function () {
    $content = Chip::make('Now playing');
    $builder = FloatingOverlayBuilder::make($content)->top()->offset(88);

    expect($builder->getAlignment())->toBe('top');
    expect($builder->getOffset())->toBe(88);
    expect($builder->getContent())->toBe($content);
});

it('serializes the sentinel element props', function () {
    $overlay = FloatingOverlay::make();
    $overlay->applyAttributes(['alignment' => 'top', 'offset' => 88]);

    $props = $overlay->toArray(new CallbackRegistry)['props'];

    expect($props['alignment'])->toBe('top');
    expect($props['offset'])->toBe(88);
});

it('defaults sentinel alignment to bottom and omits an unset offset', function () {
    $overlay = FloatingOverlay::make();
    $overlay->applyAttributes(['offset' => null]);

    $props = $overlay->toArray(new CallbackRegistry)['props'];

    expect($props['alignment'])->toBe('bottom');
    expect($props)->not->toHaveKey('offset');
});

it('clamps an unknown alignment to bottom', function () {
    $overlay = FloatingOverlay::make();
    $overlay->applyAttributes(['alignment' => 'sideways']);

    $props = $overlay->toArray(new CallbackRegistry)['props'];

    expect($props['alignment'])->toBe('bottom');
});

/**
 * The contributor's per-screen opt-out accepts BOTH spellings: the
 * InteractsWithFloatingOverlay trait (method form) and a bare
 * `protected bool $hidesFloatingOverlay = true;` property — the latter
 * matching core's `$hidesTabBar` / `$hidesNavBar` shorthand.
 */
it('reads the opt-out flag from the trait method form', function () {
    $screen = new class extends NativeComponent
    {
        use InteractsWithFloatingOverlay;

        public function __construct()
        {
            $this->hidesFloatingOverlay = true;
        }
    };

    expect(NativeUIServiceProvider::screenHides($screen, 'hidesFloatingOverlay'))->toBeTrue();
});

it('reads the opt-out flag from a bare property without the trait', function () {
    $screen = new class extends NativeComponent
    {
        protected bool $hidesFloatingOverlay = true;
    };

    expect(NativeUIServiceProvider::screenHides($screen, 'hidesFloatingOverlay'))->toBeTrue();
});

it('defaults the opt-out flag to false when the screen declares neither', function () {
    $screen = new class extends NativeComponent {};

    expect(NativeUIServiceProvider::screenHides($screen, 'hidesFloatingOverlay'))->toBeFalse();
    expect(NativeUIServiceProvider::screenHides($screen, 'hidesDrawer'))->toBeFalse();
});
