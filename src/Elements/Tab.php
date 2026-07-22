<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Concerns\HasPlatformIcon;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Tab — child of `<tab-row>`. Declares a label + optional leading icon.
 * Selection state is owned by the parent row (see [TabRow]).
 */
class Tab extends Element
{
    use HasPlatformIcon;

    protected string $type = 'tab';

    /** @var array<string, mixed> */
    protected array $tabProps = [];

    public static function make(string $label = ''): static
    {
        $el = new static;
        if ($label !== '') {
            $el->tabProps['label'] = $label;
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['label'])) {
            $this->tabProps['label'] = $attrs['label'];
        }
        if (isset($attrs['icon'])) {
            $this->icon($attrs['icon']);
        }

        $this->applyA11yAttributes($attrs);
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->tabProps;
        if (($icon = $this->resolvedIcon()) !== null) {
            $props['icon'] = $icon;
            if (($variant = $this->resolvedMaterialVariant()) !== null) {
                $props['material_variant'] = $variant;
            }
        }

        return $props;
    }

    // ── Model 3 enforcement ──────────────────────────────────────────────────

    public function getStyle(): array
    {
        return [];
    }
}
