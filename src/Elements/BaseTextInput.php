<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Icon\IconResolver;
use Native\Mobile\Icon\IosSymbol;

/**
 * Shared base for the text input variants (`outlined-text-input`,
 * `filled-text-input`).
 *
 * API shape follows Model 3 — NO per-instance color / font overrides. All
 * colors, corner radii, and typography come from the theme. For fully custom
 * input styling, drop to `<pressable>` wrapping a plain HTML-like form.
 *
 * Allowed per-instance:
 *   - `value`, `placeholder`, `label`, `supporting`  (content)
 *   - `disabled`, `readOnly`, `error`, `loading`     (state)
 *   - `keyboard`, `secure`, `maxLength`, `multiline`, `maxLines`, `minLines` (behavior)
 *   - `prefix`, `suffix`, `leading-icon`, `trailing-icon` (decorations)
 *   - `size`                                          (sm | md | lg)
 *   - `a11y-label`, `a11y-hint`                       (accessibility)
 *   - `@change`, `@submit`, `@selectionChange`        (callbacks)
 *
 * `@selectionChange` reports caret / selection movement: the handler is
 * called with `(string $text, int $selectionStart, int $selectionEnd)`,
 * offsets in Unicode code points (start === end for a bare caret). Events
 * are coalesced on the native side — 150ms by default, tunable per input
 * via `selection-debounce-ms` / `->selectionDebounceMs()`. Never emitted
 * for `secure` inputs (the callback is not serialized, and the renderers
 * refuse to emit as well).
 *
 * Subclasses (`OutlinedTextInput`, `FilledTextInput`) only override `$type`
 * so native renderers can dispatch to the right Material3 / SwiftUI primitive.
 */
abstract class BaseTextInput extends Element
{
    /** @var array<string, mixed> */
    protected array $inputProps = [];

    protected ?string $changeCallback = null;

    protected ?string $submitCallback = null;

    protected ?string $selectionChangeCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        // Content
        if (isset($attrs['value'])) {
            $this->value($attrs['value']);
        }
        if (isset($attrs['placeholder'])) {
            $this->placeholder($attrs['placeholder']);
        }
        if (isset($attrs['label'])) {
            $this->label($attrs['label']);
        }
        if (isset($attrs['supporting'])) {
            $this->supporting($attrs['supporting']);
        }

        // State
        if (! empty($attrs['disabled'])) {
            $this->disabled();
        }
        if (! empty($attrs['readOnly']) || ! empty($attrs['read-only'])) {
            $this->readOnly();
        }
        if (! empty($attrs['error']) || ! empty($attrs['isError']) || ! empty($attrs['is-error'])) {
            $this->error();
        }
        if (! empty($attrs['loading'])) {
            $this->loading();
        }

        // Behavior
        if (isset($attrs['keyboard'])) {
            $this->keyboard($attrs['keyboard']);
        }
        if (! empty($attrs['secure'])) {
            $this->secure();
        }
        if (isset($attrs['maxLength']) || isset($attrs['max-length'])) {
            $this->maxLength((int) ($attrs['maxLength'] ?? $attrs['max-length']));
        }
        if (! empty($attrs['multiline'])) {
            $this->multiline();
        }
        if (! empty($attrs['keepFocusOnSubmit']) || ! empty($attrs['keep-focus-on-submit']) || ! empty($attrs['keep-focus'])) {
            $this->keepFocusOnSubmit();
        }
        if (isset($attrs['maxLines']) || isset($attrs['max-lines'])) {
            $this->maxLines((int) ($attrs['maxLines'] ?? $attrs['max-lines']));
        }
        if (isset($attrs['minLines']) || isset($attrs['min-lines'])) {
            $this->minLines((int) ($attrs['minLines'] ?? $attrs['min-lines']));
        }

        // Decorations
        if (isset($attrs['prefix'])) {
            $this->prefix($attrs['prefix']);
        }
        if (isset($attrs['suffix'])) {
            $this->suffix($attrs['suffix']);
        }
        // Platform icon overrides follow the core/Button convention: the
        // platform prefixes the shared attribute name (`ios-leading-icon` /
        // `android-trailing-icon`), mirroring `icon` → `ios-icon` and
        // `icon-trailing` → `ios-icon-trailing` on Button.
        $leadingIcon = $attrs['leading-icon'] ?? $attrs['leadingIcon'] ?? null;
        $leadingIconIos = $attrs['ios-leading-icon'] ?? $attrs['iosLeadingIcon'] ?? null;
        $leadingIconAndroid = $attrs['android-leading-icon'] ?? $attrs['androidLeadingIcon'] ?? null;

        if ($leadingIcon !== null || $leadingIconIos !== null || $leadingIconAndroid !== null) {
            $this->leadingIcon($leadingIcon, $leadingIconIos, $leadingIconAndroid);
        }

        $trailingIcon = $attrs['trailing-icon'] ?? $attrs['trailingIcon'] ?? null;
        $trailingIconIos = $attrs['ios-trailing-icon'] ?? $attrs['iosTrailingIcon'] ?? null;
        $trailingIconAndroid = $attrs['android-trailing-icon'] ?? $attrs['androidTrailingIcon'] ?? null;

        if ($trailingIcon !== null || $trailingIconIos !== null || $trailingIconAndroid !== null) {
            $this->trailingIcon($trailingIcon, $trailingIconIos, $trailingIconAndroid);
        }

        // Size + a11y
        if (isset($attrs['size'])) {
            $this->size($attrs['size']);
        }
        // Custom font by name — the token is a font file (minus extension)
        // bundled from the app's resources/fonts/ by the copy_assets hook.
        if (isset($attrs['font'])) {
            $this->font($attrs['font']);
        }
        // Line height (leading) — meaningful for multiline inputs. `line_height`
        // is a multiplier of font size; `line_height_px` an absolute override.
        $lineHeight = $attrs['line-height'] ?? $attrs['lineHeight'] ?? null;
        if ($lineHeight !== null) {
            $this->inputProps['line_height'] = (float) $lineHeight;
        }
        $lineHeightPx = $attrs['line-height-px'] ?? $attrs['lineHeightPx'] ?? null;
        if ($lineHeightPx !== null) {
            $this->inputProps['line_height_px'] = (float) $lineHeightPx;
        }
        $this->applyA11yAttributes($attrs);

        // Sync mode + debounce (from `native:model` expansion, or set manually).
        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode($attrs['sync-mode'] ?? $attrs['syncMode']);
        }
        if (isset($attrs['debounce-ms']) || isset($attrs['debounceMs'])) {
            $this->debounceMs((int) ($attrs['debounce-ms'] ?? $attrs['debounceMs']));
        }

        // Selection-change coalescing window. Only serialized when set —
        // renderers fall back to 50ms when the prop is absent.
        if (isset($attrs['selection-debounce-ms']) || isset($attrs['selectionDebounceMs'])) {
            $this->selectionDebounceMs((int) ($attrs['selection-debounce-ms'] ?? $attrs['selectionDebounceMs']));
        }

        // `@selectionChange` → `_selectionChange` (precompiler rewrite).
        //
        // On a core that ships the companion change this is redundant: the
        // collector's applyCallbacks already routes `_selectionChange` to
        // `onSelectionChange()` (`method_exists`-gated). It is NOT a fallback
        // for cores that predate that change — those don't rewrite the
        // `@selectionChange` directive either, so `_selectionChange` can never
        // reach us. What it does buy is decoupling: the element works against
        // a core that has the precompiler half without the collector half,
        // which is exactly the configuration this repo's CI builds against.
        // Double-wiring is harmless — both paths set the same property to the
        // same expression.
        if (isset($attrs['_selectionChange'])) {
            $this->onSelectionChange($attrs['_selectionChange']);
        }
    }

    // ── Content ──────────────────────────────────────────────────────────────

    public function value(string $text): static
    {
        $this->inputProps['value'] = $text;

        return $this;
    }

    public function placeholder(string $text): static
    {
        $this->inputProps['placeholder'] = $text;

        return $this;
    }

    public function label(string $text): static
    {
        $this->inputProps['label'] = $text;

        return $this;
    }

    public function supporting(string $text): static
    {
        $this->inputProps['supporting'] = $text;

        return $this;
    }

    // ── State ────────────────────────────────────────────────────────────────

    public function disabled(bool $value = true): static
    {
        $this->inputProps['disabled'] = $value;

        return $this;
    }

    public function readOnly(bool $value = true): static
    {
        $this->inputProps['read_only'] = $value;

        return $this;
    }

    public function error(bool $value = true): static
    {
        $this->inputProps['is_error'] = $value;

        return $this;
    }

    public function loading(bool $value = true): static
    {
        $this->inputProps['loading'] = $value;

        return $this;
    }

    // ── Behavior ─────────────────────────────────────────────────────────────

    /** Keyboard hint — "text" (default) | "number" | "email" | "phone" | "url" | "decimal" | "password" */
    public function keyboard(string|int $type): static
    {
        $this->inputProps['keyboard'] = $type;

        return $this;
    }

    public function secure(bool $value = true): static
    {
        $this->inputProps['secure'] = $value;

        return $this;
    }

    public function maxLength(int $length): static
    {
        $this->inputProps['max_length'] = $length;

        return $this;
    }

    /**
     * Multiline: the return/enter key always inserts a line break on both
     * platforms (never submits), so `@submit` is not reachable from the
     * keyboard — pair the field with a send/save button instead.
     */
    public function multiline(bool $value = true): static
    {
        $this->inputProps['multiline'] = $value;

        return $this;
    }

    /**
     * Keep the keyboard up after the field is submitted (return key /
     * `@submit`). Without this SwiftUI resigns first responder on return,
     * dismissing the keyboard — the chat "send and keep typing" pattern
     * wants the opposite. Blade: `keep-focus-on-submit` (or `keep-focus`).
     */
    public function keepFocusOnSubmit(bool $value = true): static
    {
        $this->inputProps['keep_focus_on_submit'] = $value;

        return $this;
    }

    public function maxLines(int $lines): static
    {
        $this->inputProps['max_lines'] = $lines;

        return $this;
    }

    public function minLines(int $lines): static
    {
        $this->inputProps['min_lines'] = $lines;

        return $this;
    }

    // ── Decorations ──────────────────────────────────────────────────────────

    public function prefix(string $text): static
    {
        $this->inputProps['prefix'] = $text;

        return $this;
    }

    public function suffix(string $text): static
    {
        $this->inputProps['suffix'] = $text;

        return $this;
    }

    public function leadingIcon(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->inputProps['leading_icon'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->inputProps['leading_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

    public function trailingIcon(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->inputProps['trailing_icon'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->inputProps['trailing_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

    // ── Size ─────────────────────────────────────────────────────────────────

    /** sm | md | lg. Default: md. */
    public function size(string $value): static
    {
        $this->inputProps['size'] = $value;

        return $this;
    }

    /**
     * Render the typed text in a custom font. The name is a font file bundled
     * from the app's resources/fonts/ (e.g. `Inter` for `Inter.ttf`).
     */
    public function font(string $name): static
    {
        $this->inputProps['font_name'] = $name;

        return $this;
    }

    // ── Sync mode ────────────────────────────────────────────────────────────

    /**
     * How the native side should dispatch change events back to PHP.
     *
     *   'live'     — every keystroke (default, matches `wire:model.live`)
     *   'blur'     — only when the field loses focus / user submits
     *   'debounce' — after `debounce_ms` of inactivity
     *
     * Typically set indirectly via `native:model.live` / `.blur` / `.debounce.Xms`
     * in Blade — the precompiler translates those into this prop.
     */
    public function syncMode(string $mode): static
    {
        $this->inputProps['sync_mode'] = $mode;

        return $this;
    }

    public function debounceMs(int $ms): static
    {
        $this->inputProps['debounce_ms'] = $ms;

        return $this;
    }

    /**
     * Coalescing window for `@selectionChange` events, in milliseconds.
     * When unset the renderers default to 150ms — the prop is only
     * serialized when explicitly configured.
     *
     * Values of 0 or less mean "use the renderer default"; positive values
     * are floored at one frame (16ms) natively, since every emission costs a
     * bridge frame plus a full component re-render. Blade:
     * `selection-debounce-ms` (or `selectionDebounceMs`).
     */
    public function selectionDebounceMs(int $ms): static
    {
        $this->inputProps['selection_debounce_ms'] = $ms;

        return $this;
    }

    // ── Callbacks ────────────────────────────────────────────────────────────

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    public function onSubmit(string $method): static
    {
        $this->submitCallback = $method;

        return $this;
    }

    /**
     * Caret / selection reporting. The handler is invoked as
     * `method(string $text, int $selectionStart, int $selectionEnd)` —
     * offsets in Unicode code points, `start === end` for a plain caret.
     * Coalesced natively (150ms default; see `selectionDebounceMs()`).
     *
     * Never emitted for `secure` inputs: the callback is not serialized at
     * all when `secure()` is set, and both renderers additionally refuse to
     * emit. Note that each event carries the FULL current text, independent
     * of the `native:model` sync mode.
     *
     * Blade: `@selectionChange="method"`.
     */
    public function onSelectionChange(string $method): static
    {
        $this->selectionChangeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->inputProps;

        if ($this->changeCallback !== null) {
            $props['on_change'] = $registry->register($this->changeCallback);
        }
        if ($this->submitCallback !== null) {
            $props['on_submit'] = $registry->register($this->submitCallback);
        }
        // Selection reporting is suppressed for `secure` inputs at the SOURCE,
        // not just in the renderers. Both renderers also refuse to emit, but
        // that leaves a privacy-relevant invariant restated in every renderer —
        // including any future one. Never serializing the callback id means a
        // secure field cannot leak caret offsets no matter what the native side
        // does with the prop.
        if ($this->selectionChangeCallback !== null && empty($this->inputProps['secure'])) {
            // 'text_selection' kind tells NativeComponent::dispatch to decode
            // the event's TEXT_CHANGE payload ("{start},{end}\x1F{text}") and
            // call the handler with (text, selectionStart, selectionEnd).
            $props['on_selection_change'] = $registry->register($this->selectionChangeCallback, 'text_selection');
        }

        return $props;
    }

    // ── Model 3 enforcement ──────────────────────────────────────────────────
    //
    // Text inputs control their own visuals via variant + theme tokens.
    // Per-instance style overrides (bg, border, radius, shadow, opacity,
    // elevation) and internal padding are intentionally ignored. This
    // prevents the collector's applyStyle() from painting a wrapper around
    // the native input.

    public function getStyle(): array
    {
        return [];
    }

    public function getLayout(): array
    {
        $layout = parent::getLayout();
        unset($layout['padding']);

        return $layout;
    }
}
