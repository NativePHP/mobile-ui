<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\Icon;
use Native\Mobile\UI\Elements\ListItem;
use Native\Mobile\UI\Elements\Tab;
use Native\Mobile\UI\Elements\TabRow;
use Native\Mobile\UI\Elements\Toggle;

/**
 * Accessibility props (`HasA11y` trait + ListItem's trailing label):
 * the fluent API and both Blade attribute spellings must land on the
 * serialized node as `a11y_label` / `a11y_hint` — the wire keys the
 * native renderers map to accessibilityLabel/Hint (iOS) and
 * contentDescription (Android).
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('button', Button::class);
    ElementRegistry::register('toggle', Toggle::class);
    ElementRegistry::register('icon', Icon::class);
    ElementRegistry::register('tab', Tab::class);
    ElementRegistry::register('tab_row', TabRow::class);
    ElementRegistry::register('list_item', ListItem::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

it('serializes fluent a11y props on a button', function () {
    $tree = Button::make('Save')
        ->a11yLabel('Save changes')
        ->a11yHint('Saves the current document')
        ->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('button');
    expect($tree['props']['label'])->toBe('Save');
    expect($tree['props']['a11y_label'])->toBe('Save changes');
    expect($tree['props']['a11y_hint'])->toBe('Saves the current document');
});

it('serializes fluent a11y props on a toggle', function () {
    $tree = Toggle::make()
        ->value(true)
        ->a11yLabel('Notifications')
        ->a11yHint('Toggles push notifications')
        ->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('toggle');
    expect($tree['props']['value'])->toBeTrue();
    expect($tree['props']['a11y_label'])->toBe('Notifications');
    expect($tree['props']['a11y_hint'])->toBe('Toggles push notifications');
});

it('serializes fluent a11y props on an icon', function () {
    // Icons are decorative (silent to screen readers) by default; giving
    // one a label makes it announced.
    $tree = Icon::make('trash')
        ->a11yLabel('Delete')
        ->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('icon');
    expect($tree['props']['a11y_label'])->toBe('Delete');
});

it('serializes fluent a11y props on a tab through the tab row tree', function () {
    // Tabs serialize via the normal node path as children of the row, so
    // the trait's extraProps must survive full-tree serialization.
    $tree = TabRow::make(
        Tab::make('Home')->a11yLabel('Home tab')->a11yHint('Shows the home feed'),
        Tab::make('Search'),
    )->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('tab_row');
    expect($tree['children'])->toHaveCount(2);
    expect($tree['children'][0]['props']['label'])->toBe('Home');
    expect($tree['children'][0]['props']['a11y_label'])->toBe('Home tab');
    expect($tree['children'][0]['props']['a11y_hint'])->toBe('Shows the home feed');
    expect($tree['children'][1]['props'])->not->toHaveKey('a11y_label');
});

it('serializes fluent a11y props on a list item', function () {
    $tree = ListItem::make('Inbox')
        ->a11yLabel('Inbox, 3 unread')
        ->a11yHint('Opens the inbox')
        ->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('list_item');
    expect($tree['props']['headline'])->toBe('Inbox');
    expect($tree['props']['a11y_label'])->toBe('Inbox, 3 unread');
    expect($tree['props']['a11y_hint'])->toBe('Opens the inbox');
});

it('hydrates kebab-case a11y attributes from blade', function () {
    NativeElementCollector::leaf('button', [
        'label' => 'Save',
        'a11y-label' => 'Save changes',
        'a11y-hint' => 'Saves the current document',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['a11y_label'])->toBe('Save changes');
    expect($tree['props']['a11y_hint'])->toBe('Saves the current document');
});

it('hydrates camelCase a11y attributes from blade', function () {
    NativeElementCollector::leaf('toggle', [
        'value' => false,
        'a11yLabel' => 'Dark mode',
        'a11yHint' => 'Switches the app theme',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['props']['a11y_label'])->toBe('Dark mode');
    expect($tree['props']['a11y_hint'])->toBe('Switches the app theme');
});

it('hydrates a11y attributes on elements that previously had none', function () {
    NativeElementCollector::leaf('icon', [
        'name' => 'trash',
        'a11y-label' => 'Delete',
    ]);

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('icon');
    expect($tree['props']['a11y_label'])->toBe('Delete');
});

it('serializes the trailing a11y label on a list item', function () {
    $tree = ListItem::make('Song title')
        ->trailingIconButton('ellipsis')
        ->trailingA11yLabel('More options')
        ->toArray(new CallbackRegistry);

    expect($tree['props']['trailing_type'])->toBe('icon_button');
    expect($tree['props']['trailing_value'])->toBe('ellipsis');
    expect($tree['props']['trailing_a11y_label'])->toBe('More options');
});

it('hydrates the trailing a11y label from both blade spellings', function () {
    NativeElementCollector::leaf('list_item', [
        'headline' => 'Song title',
        'trailingIconButton' => 'ellipsis',
        'trailing-a11y-label' => 'More options',
    ]);

    $kebab = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    NativeElementCollector::reset();
    NativeElementCollector::leaf('list_item', [
        'headline' => 'Song title',
        'trailingIconButton' => 'ellipsis',
        'trailingA11yLabel' => 'More options',
    ]);

    $camel = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($kebab['props']['trailing_a11y_label'])->toBe('More options');
    expect($camel['props']['trailing_a11y_label'])->toBe('More options');
});
