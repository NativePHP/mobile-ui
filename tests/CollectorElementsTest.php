<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Column;
use Native\Mobile\Edge\Elements\Row;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\Accordion;
use Native\Mobile\UI\Elements\AccordionContent;
use Native\Mobile\UI\Elements\AccordionHeader;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\BottomSheet;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\Checkbox;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;
use Native\Mobile\UI\Elements\ProgressBar;
use Native\Mobile\UI\Elements\Radio;
use Native\Mobile\UI\Elements\RadioGroup;
use Native\Mobile\UI\Elements\SheetPane;
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
    ElementRegistry::register('text', Text::class);
    ElementRegistry::register('button', Button::class);
    ElementRegistry::register('bare_text_input', BareTextInput::class);
    ElementRegistry::register('outlined_text_input', OutlinedTextInput::class);
    ElementRegistry::register('filled_text_input', FilledTextInput::class);
    ElementRegistry::register('toggle', Toggle::class);
    ElementRegistry::register('sheet_pane', SheetPane::class);
    ElementRegistry::register('bottom_sheet', BottomSheet::class);
    ElementRegistry::register('checkbox', Checkbox::class);
    ElementRegistry::register('progress_bar', ProgressBar::class);
    ElementRegistry::register('radio_group', RadioGroup::class);
    ElementRegistry::register('radio', Radio::class);
    ElementRegistry::register('accordion', Accordion::class);
    ElementRegistry::register('accordion_header', AccordionHeader::class);
    ElementRegistry::register('accordion_content', AccordionContent::class);
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

// NOTE ON WHAT THIS COVERS: the assertion is that an element handed a
// `_selectionChange` attr ends up with a `text_selection`-kinded callback. It
// does NOT prove the core's collector routes `_selectionChange` →
// `onSelectionChange()`, because `BaseTextInput::applyAttributes` self-wires
// the same attr. Against the core this repo's CI builds against (which has the
// precompiler half but not the collector half) the self-wire is what makes
// this pass. Both paths are intentional; the collector path is covered by the
// companion core PR's own suite.
it('gives a _selectionChange attr a text_selection-kinded callback', function (string $type) {
    NativeElementCollector::leaf($type, [
        'value' => 'hello',
        '_selectionChange' => 'onCaretMove',
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe($type);
    expect($tree['props']['on_selection_change'])->toBeInt();
    expect($registry->resolve($tree['props']['on_selection_change']))->toBe(['method' => 'onCaretMove', 'args' => []]);
    // The kind tag drives NativeComponent::dispatch's TEXT_CHANGE payload
    // decode — (text, selectionStart, selectionEnd) handler args.
    expect($registry->kind($tree['props']['on_selection_change']))->toBe('text_selection');
})->with(['bare_text_input', 'outlined_text_input', 'filled_text_input']);

it('serializes selection-debounce-ms only when set', function () {
    NativeElementCollector::leaf('outlined_text_input', [
        '_selectionChange' => 'onCaretMove',
        'selection-debounce-ms' => 120,
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['selection_debounce_ms'])->toBe(120);

    // Absent attr → absent prop: the default window lives in the renderers,
    // never serialized from PHP.
    NativeElementCollector::reset();
    NativeElementCollector::leaf('outlined_text_input', [
        '_selectionChange' => 'onCaretMove',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props'])->not->toHaveKey('selection_debounce_ms');
});

it('accepts the camelCase selectionDebounceMs attribute', function () {
    NativeElementCollector::leaf('filled_text_input', [
        'selectionDebounceMs' => '75',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['selection_debounce_ms'])->toBe(75);
});

it('never serializes a selection callback for a secure input', function (string $type) {
    // Privacy invariant, enforced at the source rather than restated in every
    // renderer: a secure field must not ship caret offsets, so the callback id
    // is never registered and the native side has nothing to emit against.
    NativeElementCollector::leaf($type, [
        'secure' => true,
        '_selectionChange' => 'onCaretMove',
        'selection-debounce-ms' => 120,
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props'])->not->toHaveKey('on_selection_change');
    // The other callbacks on a secure field are untouched.
    expect($tree['props']['secure'])->toBeTrue();
})->with(['bare_text_input', 'outlined_text_input', 'filled_text_input']);

it('suppresses the selection callback for a secure input via the fluent API', function () {
    $registry = new CallbackRegistry;
    $props = OutlinedTextInput::make()
        ->onSelectionChange('trackCaret')
        ->secure()
        ->toArray($registry)['props'];

    expect($props)->not->toHaveKey('on_selection_change');
});

it('still serializes the selection callback when secure is explicitly false', function () {
    $registry = new CallbackRegistry;
    $props = OutlinedTextInput::make()
        ->onSelectionChange('trackCaret')
        ->secure(false)
        ->toArray($registry)['props'];

    expect($props['on_selection_change'])->toBeInt();
    expect($registry->kind($props['on_selection_change']))->toBe('text_selection');
});

it('registers selection change via the fluent API', function () {
    $registry = new CallbackRegistry;
    $props = OutlinedTextInput::make()
        ->onSelectionChange('trackCaret')
        ->selectionDebounceMs(200)
        ->toArray($registry)['props'];

    expect($props['on_selection_change'])->toBeInt();
    expect($registry->resolve($props['on_selection_change']))->toBe(['method' => 'trackCaret', 'args' => []]);
    expect($registry->kind($props['on_selection_change']))->toBe('text_selection');
    expect($props['selection_debounce_ms'])->toBe(200);
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

it('applies accordion props and keeps header and content as distinct slots', function () {
    NativeElementCollector::open('accordion', ['expanded' => true, '_change' => 'onToggleSection']);
    NativeElementCollector::open('accordion_header', []);
    NativeElementCollector::leaf('text', ['text' => 'Specifications']);
    NativeElementCollector::close();
    NativeElementCollector::open('accordion_content', []);
    NativeElementCollector::leaf('text', ['text' => 'Weight — 1.24 kg']);
    NativeElementCollector::close();
    NativeElementCollector::close();

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('accordion');
    expect($tree['props']['expanded'])->toBeTrue();
    expect($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'onToggleSection', 'args' => []]);

    // Both renderers pick their slot by child type, so the two must stay
    // separate typed children rather than being flattened into one list.
    expect($tree['children'])->toHaveCount(2);
    expect($tree['children'][0]['type'])->toBe('accordion_header');
    expect($tree['children'][0]['children'][0]['props']['text'])->toBe('Specifications');
    expect($tree['children'][1]['type'])->toBe('accordion_content');
    expect($tree['children'][1]['children'][0]['props']['text'])->toBe('Weight — 1.24 kg');
});

it('defaults an accordion to collapsed with no change callback', function () {
    NativeElementCollector::open('accordion', []);
    NativeElementCollector::open('accordion_header', []);
    NativeElementCollector::leaf('text', ['text' => 'Care instructions']);
    NativeElementCollector::close();
    NativeElementCollector::close();

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    // An untouched accordion carries no props at all — the renderers read
    // `expanded` as false and `on_change` as callback id 0.
    $props = $tree['props'] ?? [];

    expect($props)->not->toHaveKey('on_change');
    expect($props['expanded'] ?? false)->toBeFalse();
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
    $programmatic = Column::make(
        Text::make('Count: 5')->fontSize(32)->fontWeight(7)->color('#1a1a2e'),
        Row::make(
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

it('applies sheet pane props with kebab attributes and registers the change callback', function () {
    NativeElementCollector::leaf('sheet_pane', [
        'detents' => '180,520',
        'detent' => '520',
        'corner-radius' => '32',
        'inset-x' => '12',
        'inset-bottom' => '16',
        '_change' => 'onDetentChange',
    ]);

    $registry = new CallbackRegistry;
    $tree = NativeElementCollector::collect()->toArray($registry);

    expect($tree['type'])->toBe('sheet_pane');
    expect($tree['props']['detents'])->toBe('180,520');
    expect($tree['props']['detent'])->toBe(520.0);
    expect($tree['props']['corner_radius'])->toBe(32.0);
    expect($tree['props']['inset_x'])->toBe(12.0);
    expect($tree['props']['inset_bottom'])->toBe(16.0);
    expect($registry->resolve($tree['props']['on_change']))->toBe(['method' => 'onDetentChange', 'args' => []]);
});

it('accepts camelCase sheet pane attributes', function () {
    NativeElementCollector::leaf('sheet_pane', [
        'cornerRadius' => '28',
        'insetX' => '4',
        'insetBottom' => '6',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['corner_radius'])->toBe(28.0);
    expect($tree['props']['inset_x'])->toBe(4.0);
    expect($tree['props']['inset_bottom'])->toBe(6.0);
});

it('falls back to the sheet pane defaults when attributes are absent', function () {
    NativeElementCollector::leaf('sheet_pane', []);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['detents'])->toBe('200,560,780');
    expect($tree['props']['corner_radius'])->toBe(44.0);
    expect($tree['props']['inset_x'])->toBe(8.0);
    expect($tree['props']['inset_bottom'])->toBe(8.0);
});

it('applies the permanent and background-interaction sheet props', function () {
    NativeElementCollector::leaf('bottom_sheet', [
        'visible' => true,
        'permanent' => true,
        'background-interaction' => true,
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('bottom_sheet');
    expect($tree['props']['permanent'])->toBeTrue();
    expect($tree['props']['background_interaction'])->toBeTrue();
});

it('parses string booleans on the new sheet props via filter_var', function () {
    NativeElementCollector::leaf('bottom_sheet', [
        'permanent' => 'false',
        'backgroundInteraction' => 'false',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['permanent'])->toBeFalse();
    expect($tree['props']['background_interaction'])->toBeFalse();
});
