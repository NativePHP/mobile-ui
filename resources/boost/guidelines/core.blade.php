## nativephp/mobile-ui

Native UI components for NativePHP Mobile. Every element renders as a real
platform primitive — Material3 on Android, SwiftUI on iOS — not a webview
widget. Elements are declared in Blade with `<native:*>` tags or built
programmatically with the fluent `Native\Mobile\UI\Elements\*` API; both
paths serialize to the same wire tree.

### Core rules

- Visual styling is theme-driven ("Model 3"): buttons, inputs, toggles, and
  other controls take their colors, radii, and typography from the theme
  (`Native\Mobile\UI\Theme`). Use semantic props like `variant="primary"`
  instead of per-instance colors — per-instance visual overrides on these
  controls are intentionally ignored.
- Bind state with `native:model="property"` (works on toggle, checkbox, chip,
  slider, select, radio-group, button-group, tab-row, and the text inputs).
  Use `.live` / `.blur` / `.debounce.Xms` modifiers to control sync frequency.
- Wire callbacks with event attributes (`@press`, `@change`, `@submit`,
  `@dismiss`) pointing at public methods on the component.

@verbatim
<code-snippet name="Declaring native elements in Blade" lang="blade">
<native:column class="gap-4 p-4">
    <native:outlined-text-input label="Email" native:model.blur="email" />
    <native:toggle label="Notifications" native:model="notify" />
    <native:button variant="primary" @press="save">Save</native:button>
</native:column>
</code-snippet>
@endverbatim

### Theming & colors

- Everywhere a color is authored — theme tokens in `config/native-ui.php`,
  element color props (`->color()`, `headline-color`, badge `color`, swipe
  `tint`), and arbitrary-value classes (`bg-[#…]`) — the same grammar applies:
  - Tailwind palette names: `red-300`, `orange-800`
  - Special names: `white`, `black`, `transparent`
  - CSS hex: `#F00`, `#B91C1C`, and with alpha `#8B5CF680` (#RRGGBBAA order)
  - Opacity modifiers on any of the above: `red-300/20`, `#8B5CF6/50`
- Alpha-bearing hex is always authored in CSS `#RRGGBBAA` order; PHP converts
  to the native wire order — never hand-author Android-style `#AARRGGBB`.
- Dark mode: theme tokens carry a `dark` block (auto-derived when omitted),
  and `bg-theme-*` / `text-theme-*` / `border-theme-*` classes emit both
  modes automatically. This works for Blade-declared AND programmatically
  built elements (`Element->class()`).
- Disabled controls use the `surface-variant` (fill) + `on-surface-variant`
  (label) tokens on both platforms — tune disabled contrast by adjusting
  those two tokens, not per-component.
- Buttons render their variant token solid; for a softer tonal fill set
  opacity on the token itself (e.g. `'secondary' => 'fuchsia-500/70'`).
- `<native:icon>` accepts platform enum overrides as attributes —
  `:ios="Ios::House"` / `:android="Android::Home"` — matching the
  programmatic `Icon::make(ios: …, android: …)`.

@verbatim
<code-snippet name="Theme tokens accept the full color grammar" lang="php">
// config/native-ui.php
'light' => [
    'primary'   => 'violet-600',      // tailwind palette name
    'secondary' => 'fuchsia-500/70',  // with opacity → tonal fills
    'surface'   => '#F8FAFC',         // plain hex
    'accent'    => '#00AAA680',       // CSS alpha hex (#RRGGBBAA)
],
</code-snippet>
@endverbatim

### Typography

- **Custom fonts.** Drop `.ttf`/`.otf`/`.ttc` files into the app's
  `resources/fonts/` and reference one by its filename (minus extension) with
  the `font` attribute: `font="Inter-Bold"` for `resources/fonts/Inter-Bold.ttf`.
  Works on `<native:text>`, `<native:button>`, and the text inputs; also fluent
  as `->font('Inter-Bold')`. The build's `copy_assets` hook bundles the files
  (iOS registers them by PostScript name, Android loads from `assets/fonts/`);
  an unresolved name falls back to the system font. Font size/weight still come
  from `text-*` / `font-*` classes and the theme.
- **Downloading fonts.** `php artisan native:font Lobster` (or `"Rock Salt"`,
  multiple families, `--weights=400,700`, `--italic`) downloads Google Fonts
  into `resources/fonts/` with ready-to-use token names — no API key.
- **App-wide default font.** Set the theme's `font-family` token in
  `config/native-ui.php` to a bundled token (e.g. `'Inter-Regular'`) to apply
  it everywhere; per-element `font` attributes and `font-serif`/`font-mono`
  classes still win. `native:font --default` sets it for you.
- **Line height (leading).** `leading-none|tight|snug|normal|relaxed|loose`
  (unitless multipliers of the font size), plus arbitrary `leading-[1.4]`
  (multiplier) and `leading-[24px]` (absolute). Applies to `<native:text>` and
  the text inputs; button labels are single-line so it has no visible effect
  there. Only affects multi-line text. iOS caveat: SwiftUI's `Text` only exposes
  additive line spacing, so *increasing* leading (`relaxed`/`loose`, or a large
  `leading-[…px]`) is exact, but tightening below the font's natural line height
  (`none`/`tight`) is limited — measured against the actual font, so custom
  fonts aren't over-spaced. Android is exact both ways.

@verbatim
<code-snippet name="Custom font + line height" lang="blade">
<native:text font="Inter-Bold" class="text-2xl">Heading</native:text>
<native:text class="text-base leading-relaxed">
    A comfortably-spaced paragraph that wraps across several lines.
</native:text>
</code-snippet>
@endverbatim

### Accessibility

Screen-reader support rides on two props that every element accepts:
`a11y-label` (what VoiceOver / TalkBack announces; maps to
`accessibilityLabel` on iOS and `contentDescription` on Android) and
`a11y-hint` (supplementary usage guidance, read after the label; maps to
`accessibilityHint` on iOS and is appended to the content description on
Android). Both are also available fluently as `->a11yLabel()` / `->a11yHint()`.

- ALWAYS set `a11y-label` on icon-only buttons, chips, and tabs — with no
  visible text there is nothing for the screen reader to announce.
- Icons are decorative by default: an `<native:icon>` without `a11y-label` is
  silent to screen readers. Give it a label only when the icon itself carries
  meaning.
- Use `alt` on `<native:image>` for meaningful images; omit it for purely
  decorative ones.
- Use `a11y-hint` sparingly, for supplementary guidance the label doesn't
  cover ("Double-tap to reorder"). Never repeat the label in the hint.
- List items with a trailing icon button take `trailing-a11y-label` to label
  that button separately from the row.
- Text scales with the user's system font size on both platforms
  automatically — don't hardcode layouts that break at larger type sizes.

@verbatim
<code-snippet name="Accessible icon-only controls" lang="blade">
<native:button icon="trash" a11y-label="Delete draft" a11y-hint="Deletes the draft permanently" @press="deleteDraft" />
<native:icon name="checkmark.seal" a11y-label="Verified" />
<native:list-item headline="Team meeting" trailingIconButton="ellipsis" trailing-a11y-label="More options" />
</code-snippet>
@endverbatim

@verbatim
<code-snippet name="Fluent a11y API" lang="php">
use Native\Mobile\UI\Elements\Button;

Button::make()
    ->icon('plus')
    ->a11yLabel('Add item')
    ->a11yHint('Adds a new item to the list')
    ->onPress('addItem');
</code-snippet>
@endverbatim
