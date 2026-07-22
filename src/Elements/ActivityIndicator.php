<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\UI\Concerns\ResolvesColorValues;

/**
 * Circular activity indicator (spinner). Always indeterminate — use
 * `<progress-bar :value="..."/>` for determinate progress.
 *
 * Model 3: `theme.primary` tint. No per-instance color overrides.
 * Size: sm | md (default) | lg.
 */
class ActivityIndicator extends Element
{
    use ResolvesColorValues;

    protected string $type = 'activity_indicator';

    /** @var array<string, mixed> */
    protected array $indicatorProps = [];

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['size'])) {
            $this->size($attrs['size']);
        }
        if (isset($attrs['color'])) {
            $this->color((string) $attrs['color']);
        }

        $this->applyA11yAttributes($attrs);
    }

    /**
     * Optional color override. Primitives like spinners sometimes need to
     * match their container (e.g. a light spinner on a dark image overlay)
     * and the Model 3 rule yields ergonomics here. Leave unset for the
     * theme-driven default (`theme.primary`).
     */
    public function color(string $hex): static
    {
        $this->indicatorProps['color'] = $this->resolveColorValue($hex);

        return $this;
    }

    /** Accepts "sm" | "md" | "lg" or legacy ints (1=large, 2=small). */
    public function size(string|int $size): static
    {
        $this->indicatorProps['size'] = match ($size) {
            'lg', 'large', 1 => 'lg',
            'sm', 'small', 2 => 'sm',
            default => 'md',
        };

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->indicatorProps;
    }
}
