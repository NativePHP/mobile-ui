<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Popover — a small bubble that floats beside whatever this element is laid
 * over, while `visible` is true. Its children are the bubble's content.
 *
 * The element itself draws nothing and takes no touches: it marks the spot
 * the bubble points at. Lay it over the view it belongs to, usually in a
 * stack with `class="absolute top-0 bottom-0 left-0 right-0"`.
 *
 * The bubble opens above that spot (`placement="top"`, the default) or below
 * it (`placement="bottom"`), and takes the other side when there isn't room.
 * iOS draws a system popover with its arrow; Android a raised Material
 * surface in a popup. A tap outside it, or back on Android, fires
 * `@dismiss`; PHP setting `visible` false never does.
 *
 * Model 3: the bubble's colour comes from `theme.surface`.
 */
class Popover extends Element
{
    protected string $type = 'popover';

    /** @var array<string, mixed> */
    protected array $popoverProps = [];

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
        if (isset($attrs['placement'])) {
            $this->placement((string) $attrs['placement']);
        }

        $this->applyA11yAttributes($attrs);
    }

    public function visible(bool $value = true): static
    {
        $this->popoverProps['visible'] = $value;

        return $this;
    }

    /**
     * The side the bubble prefers: `top` (default) or `bottom`.
     */
    public function placement(string $placement): static
    {
        if (! in_array($placement, ['top', 'bottom'], true)) {
            throw new \InvalidArgumentException("A popover's placement is top or bottom, not [{$placement}].");
        }

        $this->popoverProps['placement'] = $placement;

        return $this;
    }

    public function onDismiss(string $method): static
    {
        $this->dismissCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->popoverProps;

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
