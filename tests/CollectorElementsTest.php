<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\Checkbox;
use Native\Mobile\UI\Elements\ProgressBar;
use Native\Mobile\UI\Elements\Radio;
use Native\Mobile\UI\Elements\RadioGroup;
use Native\Mobile\UI\Elements\Toggle;

/**
 * Attribute → wire-prop behavior of this plugin's elements, driven
 * through core's NativeElementCollector exactly as compiled Blade
 * drives them. Moved here from nativephp/mobile so the tests live
 * with the elements they cover.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('text', \Native\Mobile\Edge\Elements\Text::class);
    ElementRegistry::register('button', Button::class);
    ElementRegistry::register('bare_text_input', BareTextInput::class);
    ElementRegistry::register('toggle', Toggle::class);
    ElementRegistry::register('checkbox', Checkbox::class);
    ElementRegistry::register('progress_bar', ProgressBar::class);
    ElementRegistry::register('radio_group', RadioGroup::class);
    ElementRegistry::register('radio', Radio::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('applies button props', function () {
    NativeElementCollector::leaf('button', [
        'label' => 'Save changes',
        'variant' => 'primary',
        'size' => 'lg',
        'disabled' => true,
        '_press' => 'save',
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('button');
    expect($tree['props']['label'])->toBe('Save changes');
    expect($tree['props']['variant'])->toBe('primary');
    expect($tree['props']['size'])->toBe('lg');
    expect($tree['props']['disabled'])->toBeTrue();
    expect($tree['props']['on_press'])->toBeInt();
    expect($registry->resolve($tree['props']['on_press']))->toBe(['method' => 'save', 'args' => []]);
});

it('enforces theme-only button styling (Model 3)', function () {
    // Per-instance visual overrides are intentionally ignored: all button
    // visuals come from the theme via `variant`. Only layout-positioning
    // props pass through.
    NativeElementCollector::leaf('button', [
        'label' => 'Sign In',
        'class' => 'bg-blue-500 text-white rounded-lg',
        '_press' => 'login',
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('button');
    expect($tree['props']['label'])->toBe('Sign In');
    expect($tree['props'])->not->toHaveKey('color');
    expect($tree['props'])->not->toHaveKey('label_color');
    expect($tree)->not->toHaveKey('style');
    expect($registry->resolve($tree['props']['on_press']))->toBe(['method' => 'login', 'args' => []]);
});

it('applies bare text input props and callbacks', function () {
    NativeElementCollector::leaf('bare_text_input', [
        'value' => 'current text',
        'placeholder' => 'Enter text...',
        '_change' => 'onTextChange',
        '_submit' => 'onTextSubmit',
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('bare_text_input');
    expect($tree['props']['value'])->toBe('current text');
    expect($tree['props']['placeholder'])->toBe('Enter text...');
    expect($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'onTextChange', 'args' => []]);
    expect($registry->resolve($tree['props']['on_submit']))->toBe(['method' => 'onTextSubmit', 'args' => []]);
});

it('applies toggle props', function () {
    NativeElementCollector::leaf('toggle', [
        'value' => true,
        'label' => 'Notifications',
        'disabled' => true,
        '_change' => 'onToggle',
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('toggle');
    expect($tree['props']['value'])->toBeTrue();
    expect($tree['props']['label'])->toBe('Notifications');
    expect($tree['props']['disabled'])->toBeTrue();
    expect($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'onToggle', 'args' => []]);
});

it('applies checkbox props', function () {
    NativeElementCollector::leaf('checkbox', [
        'value' => true,
        'label' => 'Accept terms',
        '_change' => 'onAccept',
        'disabled' => false,
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('checkbox');
    expect($tree['props']['value'])->toBeTrue();
    expect($tree['props']['label'])->toBe('Accept terms');
    expect($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'onAccept', 'args' => []]);
});

it('applies checkbox disabled state', function () {
    NativeElementCollector::leaf('checkbox', [
        'value' => false,
        'disabled' => true,
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('checkbox');
    expect($tree['props']['value'])->toBeFalse();
    expect($tree['props']['disabled'])->toBeTrue();
});

it('applies progress bar props', function () {
    NativeElementCollector::leaf('progress_bar', ['value' => 0.75]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('progress_bar');
    expect($tree['props']['value'])->toBe(0.75);
});

it('applies radio group and radio props', function () {
    NativeElementCollector::open('radio_group', ['value' => 'opt2', '_change' => 'onSelect']);
    NativeElementCollector::leaf('radio', ['radioValue' => 'opt1', 'label' => 'Option 1']);
    NativeElementCollector::leaf('radio', ['radioValue' => 'opt2', 'label' => 'Option 2']);
    NativeElementCollector::leaf('radio', ['radioValue' => 'opt3', 'label' => 'Option 3', 'disabled' => true]);
    NativeElementCollector::close();

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('radio_group');
    expect($tree['props']['value'])->toBe('opt2');
    expect($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'onSelect', 'args' => []]);
    expect($tree['children'])->toHaveCount(3);
    expect($tree['children'][0]['props']['value'])->toBe('opt1');
    expect($tree['children'][0]['props']['label'])->toBe('Option 1');
    expect($tree['children'][2]['props']['disabled'])->toBeTrue();
});

it('produces identical tree to programmatic API', function () {
    // Build via collector (simulates Blade rendering)
    NativeElementCollector::open('column', ['fill' => true, 'center' => true]);
    NativeElementCollector::leaf('text', ['text' => 'Count: 5', 'fontSize' => '32', 'fontWeight' => '7', 'color' => '#1a1a2e']);
    NativeElementCollector::open('row', ['gap' => '16']);
    NativeElementCollector::leaf('button', ['label' => '-', '_press' => 'decrement']);
    NativeElementCollector::leaf('button', ['label' => '+', '_press' => 'increment']);
    NativeElementCollector::close(); // row
    NativeElementCollector::close(); // column

    $collectorRegistry = new CallbackRegistry;
    $collectorTree = NativeElementCollector::collect()->toArray($collectorRegistry);

    // Build via programmatic API
    $programmatic = \Native\Mobile\Edge\Elements\Column::make(
        \Native\Mobile\Edge\Elements\Text::make('Count: 5')->fontSize(32)->fontWeight(7)->color('#1a1a2e'),
        \Native\Mobile\Edge\Elements\Row::make(
            Button::make('-')->onPress('decrement'),
            Button::make('+')->onPress('increment'),
        )->gap(16),
    )->fill()->center();

    $programmaticRegistry = new CallbackRegistry;
    $programmaticTree = $programmatic->toArray($programmaticRegistry);

    // Trees should be structurally identical
    expect($collectorTree['type'])->toBe($programmaticTree['type']);
    expect($collectorTree['layout'])->toBe($programmaticTree['layout']);

    expect($collectorTree['children'])->toHaveCount(2);
    expect($programmaticTree['children'])->toHaveCount(2);

    // Text element
    expect($collectorTree['children'][0]['type'])->toBe($programmaticTree['children'][0]['type']);
    expect($collectorTree['children'][0]['props'])->toBe($programmaticTree['children'][0]['props']);

    // Row
    expect($collectorTree['children'][1]['type'])->toBe($programmaticTree['children'][1]['type']);
    expect($collectorTree['children'][1]['layout'])->toBe($programmaticTree['children'][1]['layout']);

    // Buttons in row
    $collectorButtons = $collectorTree['children'][1]['children'];
    $programmaticButtons = $programmaticTree['children'][1]['children'];
    expect($collectorButtons)->toHaveCount(2);

    expect($collectorButtons[0]['props']['label'])->toBe($programmaticButtons[0]['props']['label']);
    expect($collectorButtons[1]['props']['label'])->toBe($programmaticButtons[1]['props']['label']);

    // Callback method names resolve identically
    expect($collectorRegistry->resolve($collectorButtons[0]['props']['on_press']))->toBe(['method' => 'decrement', 'args' => []]);
    expect($collectorRegistry->resolve($collectorButtons[1]['props']['on_press']))->toBe(['method' => 'increment', 'args' => []]);
    expect($programmaticRegistry->resolve($programmaticButtons[0]['props']['on_press']))->toBe(['method' => 'decrement', 'args' => []]);
    expect($programmaticRegistry->resolve($programmaticButtons[1]['props']['on_press']))->toBe(['method' => 'increment', 'args' => []]);
});
