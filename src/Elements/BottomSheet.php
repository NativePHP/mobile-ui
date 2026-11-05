<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Bottom sheet — dismissible panel that slides up from the bottom. Visibility
 * driven by `visible`; `@dismiss` fires on drag-down or tap-outside.
 *
 * A `title` draws the sheet the way each platform designs its own. iOS
 * puts the content in a navigation stack whose inline bar carries the
 * title and the system's close button (Apple's HIG, Sheets); the close
 * button reports `@dismiss` like a swipe-down. Android shows the title as
 * Material heading text under the drag handle, with no close button:
 * Material's sheet closes on a swipe down, a tap outside or back.
 *
 *   <native:bottom-sheet :visible="$open" title="Filters" @dismiss="close">
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
        if (isset($attrs['title'])) {
            $this->title((string) $attrs['title']);
        }
        foreach (['close-label', 'closeLabel'] as $key) {
            if (isset($attrs[$key])) {
                $this->closeLabel((string) $attrs[$key]);
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
     *
     * "fit" makes the sheet exactly as tall as its content, measured on
     * the device and capped at "large". On iOS it combines with the
     * others ("fit,large" opens at the content's height and drags up to
     * large). Android's sheet only has a fixed half-screen partial stop,
     * so there a fit sheet opens at its content's height and ignores the
     * other detents listed beside it.
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

    /**
     * The sheet's title. iOS shows it in the sheet's own navigation bar,
     * beside the system's close button (left out on a `permanent` sheet);
     * Android shows it as heading text under the drag handle. An empty
     * title leaves the sheet untitled.
     */
    public function title(string $title): static
    {
        $this->sheetProps['title'] = $title;

        return $this;
    }

    /**
     * What VoiceOver reads for the close button of a titled iOS sheet. The
     * system's own label when unset; pass your app's translation of
     * "Close" if the system's language may differ from your app's.
     */
    public function closeLabel(string $label): static
    {
        $this->sheetProps['close_label'] = $label;

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
