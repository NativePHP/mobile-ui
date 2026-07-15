<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Icon\IconResolver;
use Native\Mobile\Icon\IosSymbol;
use Native\Mobile\UI\Concerns\ResolvesColorValues;

class Icon extends Element
{
    use ResolvesColorValues;

    protected string $type = 'icon';

    protected array $iconProps = [];

    private ?string $shared = null;
    private IosSymbol|string|null $iosOverride = null;
    private AndroidSymbol|string|null $androidOverride = null;

    public static function make(string $name = ''): static
    {
        $el = new static;

        if ($name !== '') {
            $el->name($name);
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['name']))  { $this->name($attrs['name']); }
        if (isset($attrs['size']))  { $this->size((float) $attrs['size']); }
        if (isset($attrs['color'])) { $this->color($attrs['color']); }

        // Platform enum overrides — `<icon :ios="Ios::House" :android="Android::Home"/>`
        // — same shape as the programmatic `Icon::make(ios: …, android: …)`.
        $ios = $attrs['ios'] ?? null;
        $android = $attrs['android'] ?? null;
        if ($ios !== null || $android !== null) {
            $this->name(ios: $ios, android: $android);
        }

        // Optional dark-mode override hex. Renderers pick this when the
        // system colorScheme is dark; otherwise they use `color`.
        if (isset($attrs['dark-color']) || isset($attrs['darkColor'])) {
            $this->darkColor($attrs['dark-color'] ?? $attrs['darkColor']);
        }

        // Icons are decorative (silent to screen readers) unless given a label.
        $this->applyA11yAttributes($attrs);
    }

    /**
     * Set the icon. Mirrors the `(name, ios, android)` shape used by
     * `HasPlatformIcon`-bearing builders — the Icon element doesn't mix
     * in the trait directly because its public setter is `name()`
     * (matching the `<icon name="…">` blade attr) rather than
     * `icon()`.
     *
     *   <icon name="home" />
     *   Icon::make()->name(ios: Ios::House, android: Android::Home)
     */
    public function name(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        if ($name !== null)    { $this->shared = $name; }
        if ($ios !== null)     { $this->iosOverride = $ios; }
        if ($android !== null) { $this->androidOverride = $android; }

        return $this;
    }

    public function size(float $size): static
    {
        $this->iconProps['size'] = $size;

        return $this;
    }

    public function color(string $color): static
    {
        $this->iconProps['color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function darkColor(string $color): static
    {
        $this->iconProps['dark_color'] = $this->resolveColorValue($color);

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->iconProps;

        $resolved = IconResolver::resolve($this->shared, $this->iosOverride, $this->androidOverride);
        if ($resolved['icon'] !== null) {
            $props['name'] = $resolved['icon'];
            if ($resolved['variant'] !== null) {
                $props['material_variant'] = $resolved['variant'];
            }
        }

        return $props;
    }
}
