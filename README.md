# NativeUI Plugin for NativePHP Mobile

A NativePHP Mobile plugin

## Installation

```bash
composer require nativephp/mobile-ui
```

## Usage

```php
use Native\Mobile\UI\Facades\NativeUI;

// Execute functionality
$result = NativeUI::execute(['option1' => 'value']);

// Get status
$status = NativeUI::getStatus();
```

## Listening for Events

```php
use Livewire\Attributes\On;

#[On('native:Native\Mobile\UI\Events\NativeUICompleted')]
public function handleNativeUICompleted($result, $id = null)
{
    // Handle the event
}
```

## Theming & Colors

Theme tokens live in `config/native-ui.php` (publish with
`php artisan vendor:publish --tag=native-ui-config`). Every authored color —
theme tokens, element color props, and arbitrary-value classes — accepts the
same grammar:

```php
'light' => [
    'primary'   => 'violet-600',      // Tailwind palette name
    'secondary' => 'fuchsia-500/70',  // opacity modifier → tonal fill
    'surface'   => '#F8FAFC',         // plain hex (#RGB / #RRGGBB)
    'accent'    => '#00AAA680',       // CSS alpha hex (#RRGGBBAA)
],
```

Alpha hex is authored in CSS `#RRGGBBAA` order; the framework converts to the
native wire format. Dark mode is auto-derived from `light` (alpha preserved)
unless a `dark` block overrides specific tokens.

Disabled controls draw from the `surface-variant` (fill) and
`on-surface-variant` (label) tokens on both platforms — adjust those two
tokens to tune disabled contrast app-wide.

`outlined-text-input` draws a transparent box by default (Material 3's
outlined container), so on a colored screen the field reads as part of the
page rather than as a field. Declare the optional `input-fill` / `on-input`
pair to give it a body of its own — `input-fill` paints the box, `on-input`
recolors everything inside it (typed text, placeholder, icons,
prefix/suffix). Leave them unset and nothing changes.

Icons accept platform enum overrides in Blade, matching the fluent API:

```blade
<native:icon :ios="Ios::House" :android="Android::Home" :size="24" />
```

## Accessibility

Every element accepts a screen-reader label and an optional hint, via Blade
attributes (`a11y-label` / `a11y-hint`, or the camelCase spellings
`a11yLabel` / `a11yHint`) or the fluent API (`->a11yLabel()` / `->a11yHint()`).
The label maps to `accessibilityLabel` on iOS and `contentDescription` on
Android; the hint maps to `accessibilityHint` on iOS and is appended to the
content description on Android.

```blade
<native:button icon="trash" a11y-label="Delete draft" a11y-hint="Deletes the draft permanently" @press="deleteDraft" />
```

```php
use Native\Mobile\UI\Elements\Button;

Button::make()
    ->icon('plus')
    ->a11yLabel('Add item')
    ->a11yHint('Adds a new item to the list')
    ->onPress('addItem');
```

Always set `a11y-label` on icon-only buttons, chips, and tabs — without
visible text there is nothing for VoiceOver / TalkBack to announce. Icons are
decorative (silent to screen readers) unless given an `a11y-label`. List items
with a trailing icon button take `trailing-a11y-label` (fluent:
`->trailingA11yLabel()`) to label that button separately from the row.

## Caret & Selection Reporting

> **Requires** `nativephp/mobile` 4.0+, which ships the `text_selection`
> callback kind — already enforced by this package's composer constraint.

The text inputs (`<native:bare-text-input>`, `<native:outlined-text-input>`,
`<native:filled-text-input>`) can report caret position and text selection back
to PHP via `@selectionChange`. The handler receives the current text plus the
selection range:

```php
public function onCaretMove(string $text, int $selectionStart, int $selectionEnd)
{
    // $selectionStart === $selectionEnd when the caret is a plain cursor;
    // they differ when a range of text is selected.
}
```

Offsets are **Unicode code points** into the text (not UTF-16 units or bytes),
so emoji and other astral characters count as one — safe to feed straight into
`mb_substr(..., encoding: 'UTF-8')`.

```blade
<native:outlined-text-input
    label="Message"
    @selectionChange="onCaretMove"
    selection-debounce-ms="100"
/>
```

```php
use Native\Mobile\UI\Elements\OutlinedTextInput;

OutlinedTextInput::make()
    ->label('Message')
    ->onSelectionChange('onCaretMove')
    ->selectionDebounceMs(100);
```

Events are coalesced on the native side — by default at most one every **150ms**
while the caret moves (the trailing position always fires). Tune the window per
input with `selection-debounce-ms` / `selectionDebounceMs` (fluent:
`->selectionDebounceMs()`); when unset, nothing is serialized and the renderer
default applies. A value of `0` (or less) also means "use the default"; positive
values are floored at one frame (16ms).

> **Every event carries the full current text**, and every event costs a bridge
> frame plus a full component re-render. That is independent of the
> `native:model` sync mode: pairing `@selectionChange` with `native:model.blur`
> or `.debounce` still ships the field contents to PHP on the selection
> cadence, not the model cadence. Budget the debounce window accordingly.

`@selectionChange` is never emitted for `secure` inputs. The callback is not
serialized at all when `secure` is set, and both renderers additionally refuse
to emit — so caret telemetry can't leak password-field context.

### Contract details

- **Programmatic value pushes.** When PHP pushes a new `value` onto the input,
  the field is replaced wholesale and the caret drops at the end. Both platforms
  report that immediately as a single `(text, length, length)` event, bypassing
  the debounce. A handler that rewrites the bound model will therefore see one
  follow-up event.
- **Discontiguous selections** (multi-range, iOS) are reported as a single span
  from the lowest start to the highest end — the reported range covers the gaps,
  so `mb_substr($text, $start, $end - $start)` includes text the user did not
  select.
- **`read-only` inputs** report selection on Android (which keeps them focusable
  for copy) but not on iOS (where read-only implies disabled, so the field never
  focuses).

A typical use is typeahead / mention triggers, where `@change` alone can't tell
you *where* the user is typing:

```php
public function onCaretMove(string $text, int $start, int $end)
{
    // Look backwards from the caret for an "@mention" trigger.
    $before = mb_substr($text, 0, $start, 'UTF-8');

    if (preg_match('/@(\w*)$/u', $before, $m)) {
        $this->showMentionSuggestions($m[1]);
    } else {
        $this->hideMentionSuggestions();
    }
}
```

## Date & Time Pickers

`<native:date-picker>` wraps SwiftUI's `DatePicker` and Material 3's
`DatePicker` / `TimePicker` behind one API.

```blade
<native:date-picker
    label="Appointment"
    mode="datetime"
    native:model="appointmentAt"
    min="2026-01-01"
    max="2026-12-31"
    timezone="Europe/Berlin"
    locale="de-DE"
    @change="appointmentChanged"
/>
```

```php
use Native\Mobile\UI\Elements\DatePicker;

DatePicker::make()
    ->label('Appointment')
    ->mode('datetime')
    ->value($this->appointmentAt)   // string or any DateTimeInterface
    ->min('2026-01-01')
    ->timezone('Europe/Berlin')
    ->locale('de-DE')
    ->onChange('appointmentChanged');
```

### The value contract

Values cross the bridge as **wall-clock ISO 8601 strings with no offset**,
shaped by `mode`:

| mode | wire value | example |
|---|---|---|
| `date` (default) | `Y-m-d` | `2026-07-25` |
| `time` | `H:i`, always 24-hour | `14:30` |
| `datetime` | `Y-m-d\TH:i` | `2026-07-25T14:30` |

No UTC conversion ever crosses the bridge. That is deliberate: it is what
keeps the classic off-by-one-day bug out of the element. Android's
`DatePickerState` reports UTC-midnight epoch millis and SwiftUI's `DatePicker`
binds an instant, so each renderer converts on its own side against one
agreed calendar — neither ever ships an instant.

`value`, `min`, and `max` accept an ISO string *or* any `DateTimeInterface`
(Carbon included), and a value finer than the mode needs is truncated — so a
`datetime` column can drive a date-only picker without reformatting:

```php
->mode('date')->value('2026-07-25T14:30:59Z')   // serializes as 2026-07-25
```

An empty string clears the selection; an unparseable one throws.

### Timezones and internationalization

`timezone` takes an IANA identifier and names **the calendar the picker
operates in** — what "today" means for an empty picker, and on iOS the
calendar used to convert between the bound instant and the wall-clock string.
It does *not* shift the wire value. Set it when your app pins a business
timezone instead of following the device; leave it unset to follow the device.

`locale` takes a BCP-47 tag and drives **display only** — month and weekday
names, weekday order, and the default clock convention. It never changes the
wire value, and the wire formatter is pinned to a Gregorian POSIX calendar so
a Buddhist- or Japanese-era locale can't leak a non-Gregorian year onto the
bridge.

`hour-format` (`auto` | `12` | `24`) overrides the clock convention. `auto`
resolves from the locale on **both** platforms — Android asks
`getBestDateTimePattern(locale, "jm")` rather than reading the device's
24-hour system setting, so the same `locale` gives the same result either
side.

### Display styles

`picker-style` picks the presentation, mapped to the nearest native idiom.
(It is not called `display` — that name is already flex/layout display on every
element.)

| `picker-style` | iOS | Android |
|---|---|---|
| `compact` (default) | `.compact` — tap to popover | trigger field + modal dialog |
| `inline` | `.graphical` — embedded calendar | embedded picker |
| `wheel` | `.wheel` — drum | **no drum in Material**; falls back to embedded |

### Platform notes

- `title`, `confirm-label`, and `cancel-label` are **Android only** — iOS
  commits on selection and has no dialog chrome to label. They are still
  user-visible strings, so pass translated values: `->confirmLabel(__('Done'))`.
- On iOS with `picker-style="compact"` and no value, a placeholder trigger stands
  in until first tap, because SwiftUI's compact picker always renders a
  concrete date and has no empty state.
- With `picker-style="inline"` and no initial value, neither platform commits the
  seeded "today" — you get a change event only once the user actually picks.
- `a11y-label` / `a11y-hint` are plumbed on both platforms; the current
  selection is additionally announced as the control's accessibility value.
- **`min` / `max` are rejected for `mode="time"`.** Neither platform can
  enforce a time-of-day range — SwiftUI's `in:` bounds an absolute instant, and
  Material 3's `TimePicker` has no bounds API — so passing them throws rather
  than silently doing nothing. Validate the chosen time in your component.
- **`picker-style="inline"` falls back to compact for `mode="time"` on iOS.**
  SwiftUI's `.graphical` style is date-only. Android embeds the time picker as
  asked.
- **Sync-mode modifiers are rejected.** A picker commits discretely, so
  `native:model.blur` / `native:model.debounce.300ms` have nothing to defer;
  they throw. Use plain `native:model`.

### Testing

The plugin registers picker vocabulary on the test harness, so screens read in
picker terms rather than raw select-change plumbing:

```php
Native::visit('/booking')
    ->pickDate('startsOn', '2026-12-24')
    ->pickTime('opensAt', new DateTimeImmutable('18:05'))
    ->pickDateTime('appointment', '2027-03-01T07:45')
    ->clearPicker('deadline')
    ->assertPicker('Starts', 'date')
    ->assertPickerValue('Starts', '2026-12-24')
    ->assertPickerEmpty('Deadline');
```

The `pick*` macros take an ISO string *or* any `DateTimeInterface` and
normalize to the wire shape for that mode before dispatching, so a test using
a Carbon instance or a full timestamp still sends exactly what the renderer
would. `assertPicker*` match on the picker's `label`.

Macros register only under a test runner, and only on a core whose
`TestableComponent` is macroable — the same `method_exists` gate the camera
plugin uses for its `FakeBridge` macros.

## Testing

Theme normalization and config write-back are pure PHP — no device, emulator,
or bridge round-trip required. `Theme::load()` / `Theme::merge()` resolve
authored color tokens (Tailwind names, `red-300/20` opacity modifiers, CSS
`#RRGGBBAA` alpha hex) to wire-format hex, auto-derive a dark block, and mirror
the effective set into `config('native-ui.theme.…')`. You can assert every step
of that in a unit test:

```php
use Illuminate\Config\Repository;
use Illuminate\Container\Container;
use Native\Mobile\UI\Theme;

it('normalizes tokens and mirrors them into config', function () {
    Container::getInstance()->instance('config', new Repository);

    try {
        Theme::load([
            'light' => ['primary' => 'red-300', 'accent' => '#8B5CF680'],
            'dark'  => ['primary' => 'red-800'],
        ]);

        // Normalized tokens are readable via Theme::get('mode.token'):
        expect(Theme::get('light.primary'))->toBe('#FCA5A5');   // palette name
        expect(Theme::get('light.accent'))->toBe('#808B5CF6');  // CSS alpha → wire ARGB

        // …and mirrored back so core's theme() helper reads wire-format hex:
        expect(config('native-ui.theme.light.primary'))->toBe('#FCA5A5');
        expect(config('native-ui.theme.dark.primary'))->toBe('#991B1B');
    } finally {
        Container::setInstance(null);
    }
});
```

Element color and typography props share the same grammar and serialize the
same way. Elements expose `toArray(new CallbackRegistry)` (via
`NativeElementCollector`), so you can assert what lands on the wire:

```php
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\Button;

it('serializes typography props on an element', function () {
    $props = Button::make('Save')->font('Inter-Bold')->toArray(new CallbackRegistry)['props'];

    expect($props['font_name'])->toBe('Inter-Bold');
});
```

### Keeping `Theme::pushToNative()` off the wire

`Theme::load()` / `merge()` fire a `NativeUI.Theme.Set` bridge call on every
change. In a full Laravel test app, `pushToNative()`'s `runningUnitTests()`
guard suppresses it. In **plain Pest** (no booted app), that guard can't trip,
so mute the bridge in `beforeEach()` — the same pattern the plugin's own tests
use — and `reset()` between tests:

```php
use Native\Mobile\JumpBridge;
use Native\Mobile\UI\Theme;

beforeEach(function () {
    JumpBridge::instance()->mute();
    Theme::reset();
});

afterEach(fn () => Theme::reset());
```

## License

MIT