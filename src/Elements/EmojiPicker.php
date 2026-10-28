<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Emoji picker — the platform's own emoji chooser, shown while `visible` is
 * true. Draws nothing in place.
 *
 * iOS has no public emoji picker view, so it raises the system emoji
 * keyboard (with its search, categories, recents and skin tones) on a hidden
 * field, with a Done bar above it. Android shows Jetpack's
 * `EmojiPickerView` (androidx.emoji2) in a bottom sheet: categories, recents,
 * and skin-tone and gender variants on a long press.
 *
 * `@change` receives each picked emoji as a string. The picker stays up
 * until PHP sets `visible` false, so close it in that handler for a one-off
 * pick, or leave it up to pick several. `@dismiss` fires when the person
 * closes it themselves (Done, a tap outside, a swipe down, back).
 *
 * The emoji arrives exactly as the platform hands it over: it can carry a
 * skin-tone modifier, a variation selector, or be a ZWJ sequence newer than
 * whatever your server accepts. Check it before you store or send it.
 */
class EmojiPicker extends Element
{
    protected string $type = 'emoji_picker';

    /** @var array<string, mixed> */
    protected array $pickerProps = [];

    protected ?string $changeCallback = null;

    protected ?string $dismissCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['visible'])) {
            $this->visible(filter_var($attrs['visible'], FILTER_VALIDATE_BOOLEAN));
        }
        foreach (['done-label', 'doneLabel'] as $key) {
            if (isset($attrs[$key])) {
                $this->doneLabel((string) $attrs[$key]);
            }
        }

        $this->applyA11yAttributes($attrs);
    }

    public function visible(bool $value = true): static
    {
        $this->pickerProps['visible'] = $value;

        return $this;
    }

    /**
     * The button on the bar above the iOS emoji keyboard that closes it
     * ("Done" when unset). Android closes its sheet with a swipe or back.
     */
    public function doneLabel(string $label): static
    {
        $this->pickerProps['done_label'] = $label;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    public function onDismiss(string $method): static
    {
        $this->dismissCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->pickerProps;

        if ($this->changeCallback !== null) {
            $props['on_change'] = $registry->register($this->changeCallback);
        }
        if ($this->dismissCallback !== null) {
            $props['on_dismiss'] = $registry->register($this->dismissCallback);
        }

        return $props;
    }

    // ── Model 3 enforcement ──────────────────────────────────────────────────

    public function getStyle(): array
    {
        return [];
    }
}
