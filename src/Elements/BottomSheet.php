<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Bottom sheet — dismissible panel that slides up from the bottom. Visibility
 * driven by `visible`; `@dismiss` fires on drag-down or tap-outside.
 *
 * Model 3: container colors from theme. No per-instance `backgroundColor`
 * override — wrap content in `<column class="bg-...">` if a
 * non-standard surface is truly needed, but prefer the theme.
 */
class BottomSheet extends Element
{
    protected string $type = 'bottom_sheet';

    /** @var array<string, mixed> */
    protected array $sheetProps = [];

    protected ?string $dismissCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['visible'])) {
            $this->visible((bool) $attrs['visible']);
        }
        if (isset($attrs['detents'])) {
            $this->detents($attrs['detents']);
        }
        if (isset($attrs['permanent'])) {
            $this->permanent(filter_var($attrs['permanent'], FILTER_VALIDATE_BOOLEAN));
        }
        foreach (['background-interaction', 'backgroundInteraction'] as $key) {
            if (isset($attrs[$key])) {
                $this->backgroundInteraction(filter_var($attrs[$key], FILTER_VALIDATE_BOOLEAN));
            }
        }

        $this->applyA11yAttributes($attrs);
    }

    public function visible(bool $value = true): static
    {
        $this->sheetProps['visible'] = $value;

        return $this;
    }

    /**
     * Set allowed sheet heights.
     * Accepts: "small", "medium", "large", "full", or comma-separated
     * ("medium,large"). Also accepts a numeric fraction (0.0–1.0) for a
     * custom height (e.g. "0.4" for 40% of screen).
     */
    public function detents(string $detents): static
    {
        $this->sheetProps['detents'] = $detents;

        return $this;
    }

    /**
     * A permanent sheet can't be swiped away — drag only snaps between
     * detents, and Android's back press won't dismiss it either. Pair
     * with `backgroundInteraction()` on iOS so the content behind stays
     * usable (see that method for the Android caveat).
     */
    public function permanent(bool $value = true): static
    {
        $this->sheetProps['permanent'] = $value;

        return $this;
    }

    /**
     * Keep the view behind the sheet interactive (no dim, touches pass
     * through) — the HIG "sheet with interaction behind" pattern.
     *
     * iOS-only: Android's Material ModalBottomSheet is a modal window, so
     * the scrim always intercepts background touches. For a Maps-style
     * always-on panel over a live background on both platforms, use
     * `<native:sheet-pane>` instead.
     */
    public function backgroundInteraction(bool $value = true): static
    {
        $this->sheetProps['background_interaction'] = $value;

        return $this;
    }

    public function onDismiss(string $method): static
    {
        $this->dismissCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->sheetProps;

        if ($this->dismissCallback !== null) {
            $props['on_dismiss'] = $registry->register($this->dismissCallback);
        }

        return $props;
    }
}
