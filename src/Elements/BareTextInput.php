<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\UI\Concerns\ResolvesColorValues;

/**
 * Chromeless text input — a SwiftUI `TextField` (iOS) / Compose
 * `BasicTextField` (Android) with no outline, no label, no fill, no
 * Material 3 styling. Just the typing affordance.
 *
 * Intended for places where the surrounding container provides the
 * visual chrome — chat input pills, search bars, inline editors, etc.
 * Pair with a `<row class="glass rounded-full">` wrapper to get
 * the iMessage / WhatsApp pill aesthetic.
 *
 * Inherits all behaviour (value sync via `native:model`, echo
 * prevention, sync_mode, secure / multiline, keyboard type, submit,
 * disabled / readOnly) from `BaseTextInput`. Variant differences are
 * purely visual.
 */
class BareTextInput extends BaseTextInput
{
    use ResolvesColorValues;

    protected string $type = 'bare_text_input';

    /**
     * Bare variant accepts a per-instance text color in addition to the
     * shared base attributes. Outlined / filled variants stay Model 3
     * (theme-only) — but the bare variant is *for* custom chrome, so
     * letting callers also pick the contrast color avoids the white-on-
     * white footgun when their wrapper overrides the bg (e.g.
     * `android:dark:bg-white`).
     *
     * Source can be either:
     *   - explicit attribute:  `color="#334155"` / `color="slate-700"`
     *   - tailwind class on the input: `class="text-slate-700"`
     *     (the parser produces `attrs['color']` which we pick up here)
     *
     * Dark mode override: `class="text-slate-700 dark:text-slate-300"`
     * — the collector's `buildDarkProps` already maps `dark.color` to
     * the `dark_color` prop, which the renderers also honor.
     *
     * `placeholder-color` (+ `dark-placeholder-color`) styles the
     * placeholder text independently of `color` — there's no `placeholder-*`
     * Tailwind class parsed by the collector, so unlike `color` the dark
     * companion is a plain sibling attribute (same shape as `Icon`'s
     * `dark-color`) rather than a `dark:` class variant:
     *   - `placeholder-color="#94a3b8"` / `placeholder-color="slate-400"`
     *   - `dark-placeholder-color="slate-500"`
     */
    public function applyAttributes(array $attrs): void
    {
        parent::applyAttributes($attrs);

        if (isset($attrs['color'])) {
            $this->color($attrs['color']);
        }

        if (isset($attrs['placeholder-color']) || isset($attrs['placeholderColor'])) {
            $this->placeholderColor($attrs['placeholder-color'] ?? $attrs['placeholderColor']);
        }

        if (isset($attrs['dark-placeholder-color']) || isset($attrs['darkPlaceholderColor'])) {
            $this->darkPlaceholderColor($attrs['dark-placeholder-color'] ?? $attrs['darkPlaceholderColor']);
        }
    }

    public function color(string $color): static
    {
        // Use the same prop name (`color`) as `<text>` so the
        // collector's `buildDarkProps` automatically maps `dark.color`
        // to `dark_color` for free — `class="text-slate-700 dark:text-slate-300"`
        // gives a working light/dark pair without any custom plumbing.
        $this->inputProps['color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function placeholderColor(string $color): static
    {
        $this->inputProps['placeholder_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function darkPlaceholderColor(string $color): static
    {
        $this->inputProps['dark_placeholder_color'] = $this->resolveColorValue($color);

        return $this;
    }

    /**
     * Lift the Model 3 style lockout that `BaseTextInput` enforces for
     * the outlined / filled variants. The bare variant is explicitly
     * "chromeless, caller supplies the chrome" — so element-level styles
     * (`bg`, `borderRadius`, `borderWidth`/`borderColor`, `opacity`,
     * `elevation`, `glass`) and padding all flow through normally,
     * letting callers style the input directly:
     *
     *   <bare-text-input
     *       class="flex-1 glass rounded-full px-4 py-2 dark:text-slate-700"
     *       placeholder="Message" native:model="draft" />
     *
     * No wrapping `<row>` needed.
     */
    public function getStyle(): array
    {
        return array_merge($this->styleDefaults(), $this->style);
    }

    public function getLayout(): array
    {
        return array_merge($this->layoutDefaults(), $this->layout);
    }
}
