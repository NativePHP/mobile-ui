<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

/**
 * Typography wire props on native-ui elements:
 *  - `font` attribute / `->font()` → `font_name` (a resources/fonts/ file
 *    token the native renderers resolve; falls back to the theme's
 *    `font-family` default, then the system font).
 *  - `leading-*` classes → `line_height` (multiplier) / `line_height_px`
 *    (absolute), parsed by core's TailwindParser into lineHeight attrs.
 *
 * Core `text` element coverage lives in mobile-air (TextSelectionAndRunsTest);
 * these pin the same contract on the native-ui button + text inputs.
 */
function nuiProps(object $el): array
{
    return $el->toArray(new CallbackRegistry)['props'];
}

// ── Button ──────────────────────────────────────────────────────────────────

it('serializes the font attribute on a button', function () {
    $button = Button::make('Save');
    $button->applyAttributes(['font' => 'Inter-Bold']);

    expect(nuiProps($button)['font_name'])->toBe('Inter-Bold');
});

it('exposes a fluent font() on button', function () {
    expect(nuiProps(Button::make('Go')->font('Lobster-Regular'))['font_name'])
        ->toBe('Lobster-Regular');
});

it('serializes line height attrs on a button', function () {
    $button = Button::make('Save');
    $button->applyAttributes(['lineHeight' => 1.5, 'lineHeightPx' => 24]);

    $props = nuiProps($button);
    expect($props['line_height'])->toBe(1.5);
    expect($props['line_height_px'])->toBe(24.0);
});

// ── Text inputs (shared BaseTextInput) ──────────────────────────────────────

it('serializes the font attribute on both input variants', function () {
    foreach ([OutlinedTextInput::class, FilledTextInput::class] as $class) {
        $input = $class::make();
        $input->applyAttributes(['font' => 'Inter-Regular']);

        expect(nuiProps($input)['font_name'])->toBe('Inter-Regular');
    }
});

it('exposes a fluent font() on inputs', function () {
    expect(nuiProps(OutlinedTextInput::make()->font('Inter-Regular'))['font_name'])
        ->toBe('Inter-Regular');
});

it('serializes line height attrs on inputs', function () {
    $input = OutlinedTextInput::make();
    $input->applyAttributes(['lineHeight' => 1.625]);

    expect(nuiProps($input)['line_height'])->toBe(1.625);
});

it('omits typography props when unset', function () {
    $props = nuiProps(Button::make('Plain'));

    expect($props)->not->toHaveKey('font_name');
    expect($props)->not->toHaveKey('line_height');
    expect($props)->not->toHaveKey('line_height_px');
});
