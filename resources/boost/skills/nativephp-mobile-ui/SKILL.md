---
name: nativephp-mobile-ui
description: "Element reference for nativephp/mobile-ui, the plugin that renders every NativePHP EDGE element. Activate when writing or changing a NativePHP screen's Blade view: layout (column, row, stack, scroll-view), text, button, the text inputs (outlined-text-input, filled-text-input, bare-text-input), list and list-item (leading/trailing slots, swipe actions, trailing icon buttons), icon, top-bar, toggle, checkbox, select, and their events and native:model binding."
---

# nativephp/mobile-ui elements

Every `<native:*>` tag is drawn by this plugin, as SwiftUI on iOS and Jetpack Compose on Android. The plugin must be
registered in `plugins()` in `app/Providers/NativeServiceProvider.php` (`php artisan native:plugin:register
nativephp/mobile-ui`). The `native:` prefix is optional (`<column>` works), but use it.

## Events

`@press` (alias `@tap`), `@longPress`, `@doubleTap`, `@change`, `@submit`, `@refresh`, `@endReached`. The value is a
public method name or `method(arg, ...)` with JSON arguments: `select('abc')`, `remove({{ $id }})`. The element's
own value is appended after your arguments: the text for `@submit` and `@change` on text inputs, a bool for
checkboxes and switches. Any element takes `@press`, including rows and columns. A misspelled event attribute is
dropped without an error.

## Elements

| Element | Props that matter |
|---|---|
| `column`, `row`, `stack`, `scroll-view`, `spacer`, `divider`, `pressable` | Tailwind `class`: `w-full h-full flex-1 gap-N p-N px-N items-center justify-between rounded-lg bg-theme-*` |
| `text` (slot is the text) | `class` (`text-lg font-bold line-through underline text-theme-on-surface`), `font` |
| `button` | label as slot or `label`; `variant` primary\|secondary\|destructive\|success\|ghost; `size` sm\|md\|lg; `icon`, `icon-trailing`, `ios-icon`, `android-icon`, `disabled`, `loading`, `a11y-label` |
| `outlined-text-input`, `filled-text-input`, `bare-text-input` | `native:model`, `placeholder`, `label`, `@submit`, `@change`, `keyboard` (text\|number\|decimal\|email\|phone\|url\|password), `secure`, `revealable`, `multiline`, `max-length`, `autofocus`, `leading-icon`, `trailing-icon`, `error`, `supporting` |
| `list` | `separator`, `plain`, `horizontal`, `on-refresh`, `on-end-reached`. Children: `list-item` or any element |
| `list-item` | see below |
| `icon` | `name` (`star.fill`, `trash`, `plus`), or per platform `ios="checkmark.circle.fill" android="check_circle"`, `:size="20"`, `class="text-theme-primary"` |
| `top-bar` | `title`, `subtitle`, `back`. Put it at the top level of the view |
| also | `toggle`, `checkbox`, `slider`, `select`, `radio-group`, `chip`, `badge`, `date-picker`, `modal`, `bottom-sheet`, `tab-row`, `progress-bar`, `activity-indicator` |

There is no `text-input` element. It throws "Unknown native element type: text_input".

## Text inputs

```blade
<native:outlined-text-input class="flex-1" placeholder="New note" ref="title-input"
    native:model.debounce.300ms="title" @submit="save" />
```

- Use `native:model.debounce.300ms` (`.debounce` alone is 300ms) or `.blur`. The default live mode syncs every
  keystroke and echoes the value back into the field, which drops or reorders characters under fast typing.
- Take the text from `@submit` too. The handler gets it as its last argument, so a button tapped inside the
  debounce window can't save a stale value:

```php
public function save(?string $submitted = null): void
{
    $title = trim($submitted ?? $this->title);
    // ...
    $this->title = '';   // clears the field on the next render
}
```

- `keep-focus-on-submit` only works on iOS.

## List items

Props are written camelCase, exactly as below. Use `:prop` for PHP values.

- Text: `headline`, `supporting`, `overline`, `headlineColor`.
- Leading slot, pick one: `leadingIcon`, `leadingCheckbox`, `leadingRadio`, `leadingMonogram`, `leadingAvatar`,
  `leadingImage`. Changes go to `on-leading-change`.
- Trailing slot, pick one: `trailingIcon`, `trailingText`, `trailingCheckbox`, `trailingSwitch`,
  `trailingIconButton`. Changes go to `on-trailing-change`; the icon button's press goes to `on-trailing-press`.
- Swipe: `:trailing-actions` and `:leading-actions` take arrays of `method`, `label`, `icon` (or `ios` and
  `android`), `tint`, `role` (`destructive` makes it red). `on-swipe-delete` is the single-action shortcut.
- `@press` on the row, `disabled`, `native:key` for a stable identity.

```blade
<native:list class="w-full flex-1" separator>
    @foreach ($notes as $note)
        <native:list-item native:key="note-{{ $note->id }}"
            :headline="$note->title"
            :supporting="$note->pinned ? 'Pinned' : ''"
            :leadingCheckbox="$note->pinned" on-leading-change="pin({{ $note->id }})"
            trailingIconButton="trash" trailing-a11y-label="Delete" on-trailing-press="remove({{ $note->id }})"
            :trailing-actions="[['method' => 'remove('.$note->id.')', 'label' => 'Delete', 'icon' => 'trash', 'role' => 'destructive']]" />
    @endforeach
</native:list>
```

Swipe actions only work on list items that are direct children of `<native:list>`.

A list item can't strike through or restyle its headline. For that, build the row yourself inside a
`scroll-view`:

```blade
<native:scroll-view class="w-full flex-1">
    <native:column class="w-full">
        @foreach ($notes as $note)
            <native:row class="w-full items-center gap-3 px-4 py-3" @press="archive({{ $note->id }})">
                <native:icon :name="$note->archived ? 'checkmark.circle.fill' : 'circle'" :size="22" class="text-theme-primary" />
                <native:text class="flex-1 {{ $note->archived ? 'line-through text-theme-on-surface-variant' : 'text-theme-on-surface' }}">{{ $note->title }}</native:text>
                <native:button variant="ghost" size="sm" icon="trash" a11y-label="Delete" @press="remove({{ $note->id }})" />
            </native:row>
        @endforeach
    </native:column>
</native:scroll-view>
```

## Layout

- `<native:top-bar>` gives a native navigation bar and handles the safe area. A screen can also return its title
  from `navTitle(): string`.
- Add `safe-area` only to screens with no top bar, bottom nav or layout.
- Colours come from theme tokens (`bg-theme-*`, `text-theme-*`, `border-theme-*` with `primary`, `on-primary`,
  `surface`, `on-surface`, `surface-variant`, `on-surface-variant`, `background`, `outline`), which switch for dark
  mode on their own.

## In tests

Node types in `Native::test(...)->tree()` and `assertElement()` are snake_case: `list_item`,
`outlined_text_input`. A list item's checkbox state is `props.leading_checked`. `assertSee()` finds headlines and
swipe action labels. `press('remove(5)')` fires whatever callback was registered for that expression.
