<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\DatePicker;

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::register('date_picker', DatePicker::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

/**
 * Serialize a fluent element straight to its props bag.
 *
 * `toArray()` omits the `props` key entirely when an element carries none,
 * so a bare `DatePicker::make()` has no key to read — coalesce to an empty
 * bag rather than tripping the return type.
 */
function pickerProps(DatePicker $picker, ?CallbackRegistry $registry = null): array
{
    return $picker->toArray($registry ?? new CallbackRegistry)['props'] ?? [];
}

/** Serialize a Blade-style attribute bag through the collector. */
function pickerPropsFromAttrs(array $attrs): array
{
    NativeElementCollector::reset();
    NativeElementCollector::leaf('date_picker', $attrs);

    return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'] ?? [];
}

// ── The wire contract ────────────────────────────────────────────────────────

it('serializes each mode to its ISO wall-clock shape', function (string $mode, string $input, string $expected) {
    $props = pickerProps(DatePicker::make()->mode($mode)->value($input));

    expect($props['value'])->toBe($expected);
})->with([
    'date keeps the calendar date' => ['date', '2026-07-25', '2026-07-25'],
    'time is 24-hour on the wire' => ['time', '14:30', '14:30'],
    'datetime joins with T' => ['datetime', '2026-07-25T14:30', '2026-07-25T14:30'],
]);

it('truncates a fuller value to the precision the mode needs', function (string $mode, string $expected) {
    // A datetime column driving a date-only picker must not force the caller
    // to reformat first.
    $props = pickerProps(DatePicker::make()->mode($mode)->value('2026-07-25T14:30:59Z'));

    expect($props['value'])->toBe($expected);
})->with([
    ['date', '2026-07-25'],
    ['time', '14:30'],
    ['datetime', '2026-07-25T14:30'],
]);

it('normalizes against the mode set later in the chain', function () {
    // `mode()` after `value()` still decides the wire shape — normalization
    // is deferred to serialization for exactly this reason.
    $props = pickerProps(DatePicker::make()->value('2026-07-25T14:30')->mode('time'));

    expect($props['value'])->toBe('14:30');
});

it('accepts any DateTimeInterface', function () {
    $props = pickerProps(
        DatePicker::make()->mode('datetime')->value(new DateTimeImmutable('2026-07-25 14:30:00'))
    );

    expect($props['value'])->toBe('2026-07-25T14:30');
});

it('reads a bare wall-clock string without picking up a host offset', function () {
    // Parsed against UTC, so a CI box in America/New_York can't shift "14:30".
    $original = date_default_timezone_get();
    date_default_timezone_set('America/New_York');

    try {
        $props = pickerProps(DatePicker::make()->mode('time')->value('14:30'));
        expect($props['value'])->toBe('14:30');
    } finally {
        date_default_timezone_set($original);
    }
});

it('treats an empty value as "no selection" rather than dropping the prop', function () {
    $props = pickerProps(DatePicker::make()->value(''));

    expect($props)->toHaveKey('value');
    expect($props['value'])->toBe('');
});

it('leaves value unserialized when never set', function () {
    expect(pickerProps(DatePicker::make()))->not->toHaveKey('value');
});

it('rejects a value it cannot parse', function () {
    DatePicker::make()->value('not-a-date')->toArray(new CallbackRegistry);
})->throws(InvalidArgumentException::class, 'not-a-date');

// ── Bounds ───────────────────────────────────────────────────────────────────

it('normalizes min and max to the same shape as value', function () {
    $props = pickerProps(
        DatePicker::make()
            ->mode('date')
            ->min('2026-01-01T00:00:00Z')
            ->max(new DateTimeImmutable('2026-12-31 23:59:59'))
    );

    expect($props['min'])->toBe('2026-01-01');
    expect($props['max'])->toBe('2026-12-31');
});

it('omits bounds that were never set', function () {
    $props = pickerProps(DatePicker::make()->mode('date')->value('2026-07-25'));

    expect($props)->not->toHaveKey('min');
    expect($props)->not->toHaveKey('max');
});

// ── Modes, display, hour format ──────────────────────────────────────────────

it('defaults to date mode by leaving the prop unset', function () {
    // The renderers default to `date`; PHP only serializes an explicit mode.
    expect(pickerProps(DatePicker::make()))->not->toHaveKey('mode');
});

it('accepts every documented mode', function (string $mode) {
    expect(pickerProps(DatePicker::make()->mode($mode))['mode'])->toBe($mode);
})->with(DatePicker::MODES);

it('accepts every documented picker style', function (string $style) {
    expect(pickerProps(DatePicker::make()->pickerStyle($style))['picker_style'])->toBe($style);
})->with(DatePicker::PICKER_STYLES);

it('accepts every documented hour format', function (string $format) {
    expect(pickerProps(DatePicker::make()->hourFormat($format))['hour_format'])->toBe($format);
})->with(DatePicker::HOUR_FORMATS);

it('rejects an unknown mode', function () {
    DatePicker::make()->mode('century');
})->throws(InvalidArgumentException::class, 'mode');

it('rejects an unknown picker style', function () {
    DatePicker::make()->pickerStyle('carousel');
})->throws(InvalidArgumentException::class, 'picker-style');

it('keeps pickerStyle clear of the base element layout display', function () {
    // `Element::display(int)` is flex/layout display — a different axis.
    // Setting one must not disturb the other.
    $props = pickerProps(DatePicker::make()->pickerStyle('inline'));

    expect($props['picker_style'])->toBe('inline');
    expect($props)->not->toHaveKey('display');
});

it('rejects an unknown hour format', function () {
    DatePicker::make()->hourFormat('36');
})->throws(InvalidArgumentException::class, 'hour-format');

// ── Internationalization ─────────────────────────────────────────────────────

it('passes a valid IANA timezone through', function () {
    expect(pickerProps(DatePicker::make()->timezone('Europe/London'))['timezone'])
        ->toBe('Europe/London');
});

it('rejects a timezone that is not a real IANA identifier', function () {
    DatePicker::make()->timezone('Mars/Olympus_Mons');
})->throws(InvalidArgumentException::class, 'timezone');

it('does not let the timezone shift the wire value', function () {
    // The contract is wall-clock: `timezone` names the calendar the user
    // picks in, it never rewrites the string.
    $utc = pickerProps(DatePicker::make()->mode('datetime')->value('2026-07-25T14:30'));
    $tokyo = pickerProps(
        DatePicker::make()->mode('datetime')->timezone('Asia/Tokyo')->value('2026-07-25T14:30')
    );

    expect($tokyo['value'])->toBe($utc['value'])->toBe('2026-07-25T14:30');
});

it('passes the display locale through untouched', function () {
    expect(pickerProps(DatePicker::make()->locale('de-DE'))['locale'])->toBe('de-DE');
});

it('keeps the locale from affecting the wire value', function () {
    $props = pickerProps(DatePicker::make()->mode('date')->locale('ja-JP')->value('2026-07-25'));

    expect($props['value'])->toBe('2026-07-25');
});

// ── Clearing ─────────────────────────────────────────────────────────────────

it('serializes a clearable picker with the label of its X', function () {
    $props = pickerProps(DatePicker::make()->clearable()->clearLabel('Remove date'));

    expect($props['clearable'])->toBeTrue();
    expect($props['clear_label'])->toBe('Remove date');
});

it('leaves a picker without an X unless it asks for one', function () {
    expect(pickerProps(DatePicker::make()))->not->toHaveKeys(['clearable', 'clear_label']);
});

// ── Blade attributes ─────────────────────────────────────────────────────────

it('applies kebab-case attributes from Blade', function () {
    $props = pickerPropsFromAttrs([
        'mode' => 'datetime',
        'value' => '2026-07-25T09:00',
        'min' => '2026-07-01T00:00',
        'max' => '2026-07-31T23:59',
        'picker-style' => 'inline',
        'timezone' => 'Europe/Berlin',
        'locale' => 'de-DE',
        'hour-format' => '24',
        'confirm-label' => 'Übernehmen',
        'cancel-label' => 'Abbrechen',
        'clearable' => true,
        'clear-label' => 'Löschen',
        'title' => 'Termin wählen',
        'label' => 'Termin',
        'placeholder' => 'Datum wählen',
        'disabled' => true,
    ]);

    expect($props['mode'])->toBe('datetime');
    expect($props['value'])->toBe('2026-07-25T09:00');
    expect($props['min'])->toBe('2026-07-01T00:00');
    expect($props['max'])->toBe('2026-07-31T23:59');
    expect($props['picker_style'])->toBe('inline');
    expect($props['timezone'])->toBe('Europe/Berlin');
    expect($props['locale'])->toBe('de-DE');
    expect($props['hour_format'])->toBe('24');
    expect($props['confirm_label'])->toBe('Übernehmen');
    expect($props['cancel_label'])->toBe('Abbrechen');
    expect($props['clearable'])->toBeTrue();
    expect($props['clear_label'])->toBe('Löschen');
    expect($props['title'])->toBe('Termin wählen');
    expect($props['label'])->toBe('Termin');
    expect($props['placeholder'])->toBe('Datum wählen');
    expect($props['disabled'])->toBeTrue();
});

it('accepts camelCase variants of the hyphenated attributes', function () {
    $props = pickerPropsFromAttrs([
        'hourFormat' => '12',
        'confirmLabel' => 'Done',
        'cancelLabel' => 'Dismiss',
        'clearLabel' => 'Remove date',
    ]);

    expect($props['hour_format'])->toBe('12');
    expect($props['confirm_label'])->toBe('Done');
    expect($props['cancel_label'])->toBe('Dismiss');
    expect($props['clear_label'])->toBe('Remove date');
});

// ── Accessibility ────────────────────────────────────────────────────────────

it('plumbs a11y label and hint through Blade attributes', function () {
    $props = pickerPropsFromAttrs([
        'a11y-label' => 'Appointment date',
        'a11y-hint' => 'Opens a calendar',
    ]);

    expect($props['a11y_label'])->toBe('Appointment date');
    expect($props['a11y_hint'])->toBe('Opens a calendar');
});

// ── Callbacks ────────────────────────────────────────────────────────────────

it('registers the change callback', function () {
    $registry = new CallbackRegistry;
    $props = pickerProps(DatePicker::make()->onChange('dateChosen'), $registry);

    expect($props['on_change'])->toBeInt();
    expect($registry->resolve($props['on_change']))->toBe(['method' => 'dateChosen', 'args' => []]);
});

it('wires _change from the Blade directive through the collector', function () {
    NativeElementCollector::reset();
    NativeElementCollector::leaf('date_picker', ['_change' => 'dateChosen']);

    $registry = new CallbackRegistry;
    $props = NativeElementCollector::collect()->toArray($registry)['props'];

    expect($registry->resolve($props['on_change']))->toBe(['method' => 'dateChosen', 'args' => []]);
});

it('omits the callback when no handler is attached', function () {
    expect(pickerProps(DatePicker::make()))->not->toHaveKey('on_change');
});

// ── Model 3 enforcement ──────────────────────────────────────────────────────

it('drops per-instance styling like the other Model 3 elements', function () {
    expect(DatePicker::make()->getStyle())->toBe([]);
    expect(DatePicker::make()->getLayout())->not->toHaveKey('padding');
});

// ── Sync mode ────────────────────────────────────────────────────────────────

it('accepts the live sync mode without serializing anything', function () {
    // `native:model` expands to sync-mode="live"; a picker is always live.
    $props = pickerPropsFromAttrs(['sync-mode' => 'live', 'value' => '2026-07-25']);

    expect($props)->not->toHaveKey('sync_mode');
    expect($props['value'])->toBe('2026-07-25');
});

it('rejects deferred sync modes rather than ignoring them', function (string $mode) {
    // `native:model.blur` / `.debounce` have nothing to defer on a control
    // that commits discretely — silently accepting them would mislead.
    DatePicker::make()->syncMode($mode);
})->with(['blur', 'debounce'])->throws(InvalidArgumentException::class);

it('rejects a deferred sync mode arriving from a Blade directive', function () {
    pickerPropsFromAttrs(['sync-mode' => 'blur']);
})->throws(InvalidArgumentException::class);

// ── Bounds that no platform can enforce ─────────────────────────────────────

it('refuses min/max on a time picker', function (string $bound) {
    // Neither SwiftUI nor Material 3 can bound a time-of-day range.
    DatePicker::make()->mode('time')->{$bound}('09:00')->toArray(new CallbackRegistry);
})->with(['min', 'max'])->throws(InvalidArgumentException::class, 'mode="time"');

it('still allows bounds on date and datetime pickers', function (string $mode, string $bound) {
    $props = pickerProps(DatePicker::make()->mode($mode)->min($bound));

    expect($props['min'])->toBe($bound);
})->with([
    ['date', '2026-07-01'],
    ['datetime', '2026-07-01T00:00'],
]);
