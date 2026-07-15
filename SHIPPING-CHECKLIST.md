# NativeUI — Shipping Checklist

Audit list for taking nativephp/mobile-ui from unreleased to ship-ready. Verified on iOS **and** Android in `~/Herd/native`. Docs are kept in sync as we go at `~/Herd/nativephp/resources/views/docs/mobile/3/edge-components/`.

**Phasing**: Layout first → Buttons & pressables → Inputs → Feedback → Lists → Overlays → Tabs → Misc. Cross-cutting items (§0) get checked as they come up; not gated to a phase.

Legend: `[ ]` todo · `[~]` partial · `[x]` shipped · `[!]` blocker

Per-component template (every component is checked against this):

```
- [ ] PHP/Blade API ergonomic (slot vs prop, named ctor, fluent methods)
- [ ] applyAttributes() covers kebab + camel variants
- [ ] Tailwind classes behave as web devs expect (padding/margin/w/h/bg/text/rounded/border/opacity/dark:/ios:/android:)
- [ ] Theme tokens honored — no hardcoded colors
- [ ] Variants render correctly (where applicable)
- [ ] Sizes render correctly (where applicable)
- [ ] Disabled state visible + non-interactive
- [ ] Loading state (where applicable)
- [ ] a11y-label + a11y-hint plumbed
- [ ] @press / @change / etc. fire on iOS + Android
- [ ] Dark mode visual passes
- [ ] iOS renderer matches Android renderer (visual + behavior parity)
- [ ] Demo page in ~/Herd/native covers golden path + edges
- [ ] Docs page at ~/Herd/nativephp/.../edge-components/<name>.md reflects current API
```

---

## 0. Cross-cutting (do as they come up)

### 0.1 TailwindParser coverage (`mobile-air/src/Edge/TailwindParser.php`)

Web devs reach for these without thinking. Each should resolve to a sensible native prop or be explicitly documented as unsupported.

- [ ] `space-y-*` / `space-x-*` — children-gap shim (likely just routes to `gap-*` on row/column)
- [ ] `divide-x-*` / `divide-y-*` — inter-child borders
- [ ] `min-w-*` / `max-w-*` / `min-h-*` / `max-h-*`
- [ ] `aspect-square` / `aspect-video` / `aspect-[w/h]`
- [ ] `overflow-hidden` / `overflow-visible` / `overflow-scroll`
- [ ] `truncate` (single-line ellipsis on text)
- [ ] `line-clamp-1..6` (multi-line ellipsis on text)
- [ ] `leading-*` (line height: `none`, `tight`, `snug`, `normal`, `relaxed`, `loose`, numeric)
- [ ] `tracking-*` (letter spacing)
- [ ] `uppercase` / `lowercase` / `capitalize` / `normal-case`
- [ ] `italic` / `not-italic`
- [ ] `underline` / `line-through` / `no-underline`
- [ ] `text-left` / `text-center` / `text-right` (alignment, not color)
- [ ] `z-*` (z-index)
- [ ] `inset-*` / `inset-x-*` / `inset-y-*` (shorthand for top/right/bottom/left)
- [ ] `hidden` (collapse from layout)
- [ ] `font-[Inter]` / `font-[SF Pro]` — custom family via arbitrary
- [ ] Confirm `text-xs`/`-sm`/`-base`/`-md`/`-lg`/`-xl`/`-2xl`/`-3xl`/`-4xl`/`-5xl`/`-6xl` all map
- [ ] Confirm fractional widths (`w-1/2`, `w-1/3`, `w-2/3`, `w-1/4`, `w-3/4`, `w-1/5`…) all parse
- [ ] `flex-row` / `flex-col` / `flex-wrap` / `flex-nowrap` — decide: class-driven or element-driven only
- [ ] `transition` / `duration-*` / `ease-*` — decide: support, or document as "use animation API"
- [ ] Document the supported subset (and the explicit no-ops) in plugin README + docs

### 0.2 Theme / dark mode
- [ ] Verify `bg-theme-*`, `text-theme-*`, `border-theme-*` resolve every token in `config/native-ui.php`
- [ ] Verify `dark:` companion is emitted and respected at draw time (auto-derive when `dark` block partial)
- [ ] `Theme::merge([...])` from a service-provider boot wins over published config
- [ ] All built-in components read colors from theme tokens — no hardcoded hex hiding in renderers

### 0.3 Platform variants
- [ ] `ios:` / `android:` resolve per platform, drop silently on the other
- [ ] Compose with `dark:` in both orders: `ios:dark:bg-…`, `dark:ios:bg-…`

### 0.4 Glass / Liquid Glass
- [ ] `glass`, `glass:prominent`, `glass:interactive`, `glass:clear`, and combinations render on iOS 26+, fall back cleanly on iOS 18-25, degrade to tonal surface on Compose
- [ ] Unknown modifiers (`glass:thicc`) silently ignored, base flag still applies
- [ ] Works as a child of card, listitem, button (not just root)

### 0.5 Safe area
- [ ] `safe-area` / `safe-area-top` / `safe-area-bottom` work on every screen primitive (Screen, ScrollView, Stack)
- [ ] Document interaction with TabRow / nav chrome

### 0.6 Accessibility
- [ ] Every interactive component accepts `a11y-label` + `a11y-hint`
- [ ] `disabled` state announced to screen readers
- [ ] Form labels programmatically associated with inputs
- [ ] Dynamic Type / system font scaling honored
- [ ] Focus order logical for screen-reader swipe

### 0.7 Form binding (no Livewire — pure Blade + wire bridge)
- [ ] State-binding pattern works on every input (Bare/Filled/Outlined TextInput, Toggle, Checkbox, Radio/RadioGroup, Select, Slider)
- [ ] Two-way updates without re-mount flicker
- [ ] Per-field `error` prop or convention
- [ ] Form-level submit flow demo

### 0.8 Callbacks / events
- [ ] `@press`, `@change`, `@submit`, `@open`, `@close` consistently named
- [ ] Callbacks survive hot-reload
- [ ] Long-press / double-tap / swipe API documented (`<gesture-area>`)

### 0.9 Icon system
- [ ] `IconResolver` resolves `name=` cross-platform
- [ ] `ios:` / `android:` explicit overrides land on the right platform
- [ ] `php artisan native-ui:generate-icons` runs clean
- [ ] Icon variants (filled/outlined/rounded/sharp) plumb through to Compose
- [ ] SF Symbols rendering variants (multicolor, hierarchical, palette) — supported or explicitly not

### 0.10 Tooling / docs
- [ ] `resources/boost/guidelines/core.blade.php` — currently scaffold describing a fictional `NativeUI::execute()` facade. Rewrite for the real component library.
- [ ] README.md — same scaffold problem. Rewrite with real Quick Start + component index + theme override snippet.
- [ ] `php artisan vendor:publish --tag=native-ui-config` produces a clean config
- [ ] `tests/` — add per-component prop-emission tests at minimum
- [ ] CI runs tests on PR
- [ ] Version handshake with `struct_layout_version` post-release

### 0.11 Bench / perf
- [ ] NativeVirtualList / NativeList smooth with 10k items
- [ ] FrameTracker steady during Spotify/Twitter demos
- [ ] PHP→wire emission cost for big screens sub-frame

---

## 1. Layout & containers (Phase 1 — start here)

Engine primitives live in `mobile-air/src/Edge/Elements/` (not the plugin), but every demo composes them. Plugin components like `Screen` and `Card` belong in this phase too.

### 1.1 `<row>`  (engine)
- [ ] Template items
- [ ] `gap-*` between children
- [ ] `items-*` cross-axis alignment
- [ ] `justify-*` main-axis alignment
- [ ] Child `flex-1` distributes leftover space
- [ ] Wrap behavior (or document: no wrap, use grid)
- [ ] Docs: `mobile/3/edge-components/row.md`

### 1.2 `<column>`  (engine)
- [ ] Template items
- [ ] Same gap / align / justify / flex-1 coverage
- [ ] Docs: `column.md`

### 1.3 `<stack>`  (engine)
- [ ] Template items
- [ ] Z-stacks children, last-wins on top
- [ ] `items-*` / `justify-*` position the whole stack within itself
- [ ] Children with `absolute` + `top/left/right/bottom-*` position freely
- [ ] iOS centering fix verified (see memory: `feedback_stack_in_flex_cell`)
- [ ] Docs: `stack.md`

### 1.4 `<scroll-view>`  (engine)
- [ ] Template items
- [ ] `axis=` vertical / horizontal / both
- [ ] Content sizing respects intrinsic height
- [ ] Snap behavior (per-page, per-item)
- [ ] `:bounces` (iOS) / overscroll (Android)
- [ ] Keyboard avoidance when focused input is below the fold
- [ ] Inside `safe-area` screens — no double padding
- [ ] Docs: `scroll-view.md`

### 1.5 `<refreshable>`  (engine)
- [ ] Template items
- [ ] `@refresh` callback fires on pull-to-refresh
- [ ] Refreshing state programmatic (start/stop from PHP)
- [ ] Works inside both NativeList and ScrollView
- [ ] Docs: add page (none currently in mobile/3)

### 1.6 `<gesture-area>`  (engine)
- [ ] Template items
- [ ] `@press`, long-press, double-tap, drag callbacks
- [ ] SharedValue integration (see memory: `project_animation_phase_summary`)
- [ ] Compose translateX/translateY in px not dp (see memory: `feedback_compose_dp_px`)
- [ ] Docs: add page

### 1.7 `<lazy-grid>`  (engine)
- [ ] Template items
- [ ] Column count
- [ ] Item template
- [ ] PHP→wire O(N) cost — see memory: `project_lazy_grid_datasource` (template+items+bindings refactor)
- [ ] Docs: add page

### 1.8 `<spacer>` / `<divider>` (engine)
- [ ] Template items (visual primitives)
- [ ] Divider color follows theme
- [ ] Docs: `spacer.md`, `divider.md`

### 1.9 ~~Screen~~ — REMOVED

Screen was deleted in Phase 1. Page wrappers are now plain Laravel layouts. The plugin ships a default scaffold:

```bash
php artisan vendor:publish --tag=native-ui-layouts
```

Drops `resources/views/components/layouts/app.blade.php` into the app. Devs edit freely; ship multiple archetypes (`layouts/feed.blade.php`, `layouts/detail.blade.php`) by copying.

Usage:

```blade
<x-layouts.app safe-area="top" scrollable>
    <column class="p-5 gap-4">
        ...page content...
    </column>
</x-layouts.app>
```

Rationale: Screen was anemic (zero useful props), 48/49 demo files routed around it, and chrome (title/back/nav) already lives in the route-group nav layouts. A Laravel layout component carries the page-body concerns (safe area, scroll, background) in a way web devs already know. Per-screen status-bar style is a separate concern — see [[swiftui_renderer_learnings]] for the deferred view-level implementation.

Future work: when status-bar style lands, model it as a self-closing leaf element (`<status-bar style="light" />`) so it composes without coupling to the layout.

### 1.10 ~~Card~~ — REMOVED

Card was deleted in Phase 1. The recommended pattern is a styled column:

```blade
{{-- filled --}}
<column class="w-full p-4 gap-1 bg-theme-surface-variant rounded-2xl"> ... </column>

{{-- outlined --}}
<column class="w-full p-4 gap-1 bg-theme-surface rounded-2xl border border-theme-outline"> ... </column>

{{-- elevated --}}
<column class="w-full p-4 gap-1 bg-theme-surface rounded-2xl shadow"> ... </column>

{{-- tappable --}}
<pressable @press="…"> <column class="..."> ... </column> </pressable>
```

Rationale: a Card component fights the "Tailwind classes only" principle (memory `feedback_tailwind_only`) by adding lockdown semantics that surprise web devs. The column pattern is what RN ecosystems (NativeWind, gluestack) use anyway.

---

## 2. Buttons & pressables (Phase 2)

### 2.1 Button  (plugin)
- [ ] Template items
- [ ] Variants: primary/secondary/destructive/ghost
- [ ] Sizes: sm/md/lg
- [ ] Loading state replaces label, preserves width
- [ ] Leading + trailing icons
- [ ] Slot OR `label=` prop both work
- [ ] `:menu` dropdown opens on press, shadows @press
- [ ] `w-full` works (see memory: `feedback_swiftui_button_fill_width`)
- [ ] Model-3 enforcement: per-instance bg/border/radius/shadow stripped — document loudly
- [ ] Docs: `button.md`

### 2.2 ButtonGroup  (plugin)
- [ ] Template items
- [ ] Segmented control behavior
- [ ] Single-select vs multi-select
- [ ] Disabled individual buttons
- [ ] Equal-width children
- [ ] Docs: `button-group.md`

### 2.3 `<pressable>`  (engine)
- [ ] Template items
- [ ] When-to-use-over-Button doc
- [ ] Press feedback (opacity / scale) configurable
- [ ] Disabled prop
- [ ] Docs: `pressable.md`

### 2.4 Chip  (plugin)
- [ ] Template items
- [ ] Variants: filter / input / suggestion / assist (Material 3)
- [ ] Selected state
- [ ] Deletable (trailing X)
- [ ] Leading icon / avatar
- [ ] Tap callback
- [ ] Docs: `chip.md`

---

## 3. Inputs (Phase 3)

### 3.1 BareTextInput  (plugin)
- [ ] Template items
- [ ] keyboardType (text/number/email/url/phone/decimal)
- [ ] secureTextEntry
- [ ] returnKeyType + onSubmit
- [ ] autoCorrect / autoCapitalize / spellCheck
- [ ] maxLength
- [ ] selectionColor / cursorColor
- [ ] multiline + autoGrow
- [ ] Docs: `text-input.md` (covers all three?)

### 3.2 FilledTextInput  (plugin)
- [ ] Template items
- [ ] Floating label
- [ ] Leading/trailing icon slots
- [ ] Helper text + error text
- [ ] Counter with maxLength
- [ ] Inherits BareTextInput keyboard/secure/etc.
- [ ] Docs: covered in `text-input.md`?

### 3.3 OutlinedTextInput  (plugin)
- [ ] Template items
- [ ] Same coverage, outlined visual
- [ ] Focus ring follows theme

### 3.4 Toggle  (plugin)
- [ ] Template items
- [ ] Label slot
- [ ] Disabled
- [ ] @change
- [ ] Docs: `toggle.md`

### 3.5 Checkbox  (plugin)
- [ ] Template items
- [ ] Label slot + label prop
- [ ] Indeterminate state (Compose native; iOS custom)
- [ ] Group behavior (array binding)
- [ ] Docs: `checkbox.md`

### 3.6 Radio  (plugin)
- [ ] Template items
- [ ] Bound to RadioGroup parent

### 3.7 RadioGroup  (plugin)
- [ ] Template items
- [ ] `value` two-way binding (wire:model)
- [ ] Horizontal vs vertical layout
- [ ] @change
- [ ] Docs: `radio-group.md`

### 3.8 Select  (plugin)
- [ ] Template items
- [ ] Options shape (label/value pairs)
- [ ] iOS native picker / menu; Android dropdown
- [ ] Disabled options
- [ ] Search inside long lists (or document cutoff)
- [ ] Docs: `select.md`

### 3.9 Slider  (plugin)
- [ ] Template items
- [ ] Min / max / step
- [ ] Two-way binding
- [ ] @change vs @end-change (live vs commit)
- [ ] Range slider (two thumbs) — supported or future
- [ ] Docs: `slider.md`

---

## 4. Feedback (Phase 4)

### 4.1 ActivityIndicator  (plugin)
- [ ] Template items
- [ ] Sizes sm/md/lg
- [ ] Color customization (theme + arbitrary)
- [ ] Docs: `activity-indicator.md`

### 4.2 ProgressBar  (plugin)
- [ ] Template items
- [ ] Determinate (0..1) vs indeterminate
- [ ] Track + fill from theme
- [ ] Height override
- [ ] Docs: `progress-bar.md`

### 4.3 Badge  (plugin)
- [ ] Template items
- [ ] Variants
- [ ] Numeric vs dot vs text content
- [ ] Position on parent (top-right pattern) — this component's job or a layout pattern?
- [ ] Docs: `badge.md`

---

## 5. Lists & carousels (Phase 5)

### 5.1 ListItem  (plugin) — 595 LoC, scrutinize
- [ ] Template items
- [ ] Leading slot (avatar / icon)
- [ ] Title + subtitle + supportingText
- [ ] Trailing slot
- [ ] Swipe actions (iOS swipe-to-delete; Compose `SwipeToDismiss`)
- [ ] Variants dense / standard / two-line / three-line
- [ ] Disabled
- [ ] Chevron for navigable items?
- [ ] Docs: covered by `list.md`?

### 5.2 NativeList  (plugin)
- [ ] Template items
- [ ] Section headers / footers
- [ ] Separators toggle
- [ ] Pull-to-refresh integration
- [ ] Inset grouped vs plain
- [ ] Docs: `list.md`

### 5.3 NativeVirtualList  (plugin)
- [ ] Template items
- [ ] Recycler reuses cells (10k items)
- [ ] Item key prop
- [ ] Variable item heights
- [ ] On-end-reached callback
- [ ] Scroll-to-index
- [ ] Ergonomics vs NativeList — unified or distinct
- [ ] Docs: add page

### 5.4 Carousel  (plugin)
- [ ] Template items
- [ ] Auto-advance interval
- [ ] Indicator dots
- [ ] Snap behavior
- [ ] Item width override
- [ ] @change index
- [ ] Docs: `carousel.md`

---

## 6. Overlays (Phase 6)

### 6.1 Modal  (plugin)
- [ ] Template items
- [ ] Backdrop tap dismiss (configurable)
- [ ] Full-screen vs centered card
- [ ] @open / @close
- [ ] Keyboard avoidance
- [ ] Docs: `modal.md`

### 6.2 BottomSheet  (plugin)
- [ ] Template items
- [ ] Detents (small/medium/large/custom)
- [ ] Dismissible by drag / backdrop tap
- [ ] @open / @close
- [ ] Scrollable content inside doesn't fight drag handle
- [ ] Keyboard avoidance with inputs
- [ ] iOS 26 search-tab activation issue (see memory: `swiftui_tab_role_search_activation`)
- [ ] Docs: `bottom-sheet.md`

---

## 7. Tabs (Phase 7)

### 7.1 Tab  (plugin)
- [ ] Template items
- [ ] Receives selected state from TabRow parent
- [ ] Docs: covered by `tab-row.md`?

### 7.2 TabRow  (plugin)
- [ ] Template items
- [ ] Top tabs vs scrollable tabs
- [ ] @change event
- [ ] Difference vs Native tabs chrome (TabsLayout / NativeTabsLayout) documented
- [ ] Docs: `tab-row.md`

---

## 8. Misc (Phase 8)

### 8.1 Icon  (plugin)
- [ ] Template items
- [ ] `name=` resolves via IconResolver
- [ ] `ios=` / `android=` overrides
- [ ] `size=` numeric points/dp
- [ ] `color=` arbitrary + `text-theme-*` propagates from parent
- [ ] Variant prop (filled/outlined/rounded/sharp)
- [ ] Docs: `icon.md` / `icons.md`

### 8.2 `<text>`  (engine)
- [ ] All Tailwind text classes (size, weight, color, leading, tracking, transform, decoration, alignment, truncate, line-clamp)
- [ ] Selectable
- [ ] Accessibility traits (heading, emphasis)
- [ ] Docs: `text.md`

### 8.3 `<image>`  (engine)
- [ ] fit modes (cover/contain/fill/scaleDown/none)
- [ ] placeholder
- [ ] error fallback
- [ ] async loading
- [ ] local asset references
- [ ] Docs: `image.md`

### 8.4 `<canvas>` / `<shapes>`  (engine)
- [ ] Template items
- [ ] Skia integration
- [ ] Docs: `canvas.md`, `shapes.md`

---

## 9. Demo coverage (~/Herd/native)

Current `resources/views/native/explore/`:
- [x] buttons, cards, forms, icons, layout, menus, sheets, typography

Add or finish:
- [ ] `explore/inputs.blade.php` — bare / filled / outlined side by side
- [ ] `explore/selection.blade.php` — toggle, checkbox, radio, radiogroup, select, slider
- [ ] `explore/feedback.blade.php` — activity-indicator, progress-bar, badge, chip
- [ ] `explore/overlays.blade.php` — modal, bottom-sheet, carousel
- [ ] `explore/lists.blade.php` — listitem, native-list, native-virtual-list (+ 10k bench)
- [ ] `explore/tabs.blade.php` — tab + tab-row (in-screen, not chrome)
- [ ] `explore/theme.blade.php` — swatch grid of every token, light + dark side by side
- [ ] `explore/tailwind.blade.php` — visual matrix of supported classes (web devs use as reference)

---

## 10. Release gates

- [ ] All §1–§8 components green on iOS device + Android device (not just simulator)
- [ ] All §0 cross-cutting items checked
- [ ] README + boost guidelines rewritten
- [ ] All docs pages in `mobile/3/edge-components/` reflect current API
- [ ] CHANGELOG drafted
- [ ] `composer.json` constraints sane
- [ ] Bench numbers captured (FrameTracker + PerfFunctions) for marquee demos
- [ ] Memory updated: archive `project_yoga_removal`, `project_compose_migration`, etc., as shipped
