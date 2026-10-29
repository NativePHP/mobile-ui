<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\NativeTagPrecompiler;
use Native\Mobile\UI\Elements\EmojiPicker;

/**
 * `<native:emoji-picker>` raises the platform's emoji chooser while
 * `visible` is true. Picks reach PHP as a select-change on `on_change`,
 * and a person closing it as a sheet dismiss on `on_dismiss`, which both
 * renderers fire.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('emoji_picker', EmojiPicker::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function emojiPickerTree(string $blade, array $vars = []): array
{
    $wasActive = NativeTagPrecompiler::setActive(true);

    try {
        $php = (new NativeTagPrecompiler)($blade);
    } finally {
        NativeTagPrecompiler::setActive($wasActive);
    }

    (function (array $vars) use ($php) {
        extract($vars);
        eval('?>'.$php);
    })($vars);

    $registry = new CallbackRegistry;

    return ['tree' => NativeElementCollector::collect()->toArray($registry), 'registry' => $registry];
}

it('wires visible, the done label and both handlers from a Blade tag', function () {
    ['tree' => $tree, 'registry' => $registry] = emojiPickerTree(
        '<native:emoji-picker :visible="$open" done-label="Fertig" @change="react({{ $id }})" @dismiss="closePicker" />',
        ['open' => true, 'id' => 7],
    );

    expect($tree['type'])->toBe('emoji_picker')
        ->and($tree['props']['visible'])->toBeTrue()
        ->and($tree['props']['done_label'])->toBe('Fertig')
        ->and($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'react', 'args' => [7]])
        ->and($registry->resolve($tree['props']['on_dismiss']))->toBe(['method' => 'closePicker', 'args' => []]);
});

it('sends visible false while closed, so the renderers put the picker away', function () {
    ['tree' => $tree] = emojiPickerTree('<native:emoji-picker :visible="$open" @change="react" />', ['open' => false]);

    expect($tree['props']['visible'])->toBeFalse()
        ->and($tree['props'])->not->toHaveKey('on_dismiss');
});

it('builds the same props fluently', function () {
    $registry = new CallbackRegistry;

    $props = EmojiPicker::make()->visible()->onChange('react')->onDismiss('closePicker')->toArray($registry)['props'];

    expect($props['visible'])->toBeTrue()
        ->and($registry->resolve($props['on_change'])['method'])->toBe('react')
        ->and($registry->resolve($props['on_dismiss'])['method'])->toBe('closePicker');
});

it('ships a renderer for each platform and the Jetpack picker on Android', function () {
    $root = dirname(__DIR__);
    $manifest = json_decode(file_get_contents($root.'/nativephp.json'), true);
    $component = collect($manifest['components'])->firstWhere('type', 'emoji_picker');

    expect($component['self_closing'])->toBeTrue()
        ->and($root.'/resources/ios/'.$component['ios_renderer'].'.swift')->toBeFile()
        ->and($root.'/resources/android/'.class_basename(str_replace('.', '\\', $component['android_renderer'])).'.kt')->toBeFile()
        ->and($manifest['android']['dependencies']['implementation'])->toContain('androidx.emoji2:emoji2-emojipicker:1.7.0');
});

// The picker brings Guava in at runtime only, which turns CameraX's listenablefuture into Guava's
// empty stub on the compile classpath. Without Guava there too, plugins that call
// ProcessCameraProvider.getInstance() can't see ListenableFuture and stop compiling.
it('keeps Guava on the Android compile classpath alongside the picker', function () {
    $manifest = json_decode(file_get_contents(dirname(__DIR__).'/nativephp.json'), true);

    expect($manifest['android']['dependencies']['implementation'])->toContain('com.google.guava:guava:32.0.1-android');
});
