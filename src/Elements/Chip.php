<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Concerns\HasPlatformIcon;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Chip — compact selectable tag. Bool selected state, optional leading icon
 * + label.
 *
 * Model 3: colors from theme tokens (primary for active, outline for inactive).
 * Honors `native:model` like other stateful components.
 */
class Chip extends Element
{
    use HasPlatformIcon;

    protected string $type = 'chip';

    /** @var array<string, mixed> */
    protected array $chipProps = [];

    protected ?string $changeCallback = null;

    public static function make(string $label = ''): static
    {
        $el = new static;
        if ($label !== '') {
            $el->chipProps['label'] = $label;
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        // Default to capsule radius so the outer wrapper's bg paint and
        // ClipRadiusModifier align with the chip's rounded shape (otherwise
        // `bg-*` colors leak out at the corners). User `rounded-*` classes
        // still override via applyStyle.
        $this->borderRadius(9999);

        if (isset($attrs['label'])) {
            $this->label($attrs['label']);
        }
        // `selected` is the bound value; accept both `selected` and `value`.
        if (isset($attrs['selected'])) {
            $this->selected((bool) $attrs['selected']);
        }
        if (isset($attrs['value'])) {
            $this->selected((bool) $attrs['value']);
        }
        if (isset($attrs['icon'])) {
            $this->icon($attrs['icon']);
        }
        if (! empty($attrs['disabled'])) {
            $this->disabled();
        }

        $this->applyA11yAttributes($attrs);

        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode($attrs['sync-mode'] ?? $attrs['syncMode']);
        }
    }

    public function label(string $label): static
    {
        $this->chipProps['label'] = $label;

        return $this;
    }

    public function selected(bool $selected = true): static
    {
        // Stored under `value` so native:model binding works uniformly with
        // other stateful components (they all read `props.value`).
        $this->chipProps['value'] = $selected;

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->chipProps['disabled'] = $value;

        return $this;
    }

    public function syncMode(string $mode): static
    {
        $this->chipProps['sync_mode'] = $mode;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->chipProps;

        if (($icon = $this->resolvedIcon()) !== null) {
            $props['icon'] = $icon;
            if (($variant = $this->resolvedMaterialVariant()) !== null) {
                $props['material_variant'] = $variant;
            }
        }

        if ($this->changeCallback !== null) {
            $props['on_change'] = $registry->register($this->changeCallback);
        }

        return $props;
    }

    // ── Model 3 enforcement ──────────────────────────────────────────────────

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
