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

## License

MIT