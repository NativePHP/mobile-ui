<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * ButtonGroup — segmented single-choice selector. Options are a flat array of
 * strings; the group owns the selected-index state.
 *
 * Accepts `native:model="planTier"` where `$planTier` is an int property.
 *
 * Model 3: active/inactive colors from theme tokens. No per-instance color
 * override.
 */
class ButtonGroup extends Element
{
    protected string $type = 'button_group';

    /** @var array<string, mixed> */
    protected array $buttonGroupProps = [];

    protected ?string $changeCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['options'])) {
            $this->options((array) $attrs['options']);
        }
        if (isset($attrs['value'])) {
            $this->selectedIndex((int) $attrs['value']);
        }
        if (isset($attrs['selectedIndex'])) {
            $this->selectedIndex((int) $attrs['selectedIndex']);
        }
        if (isset($attrs['selected-index'])) {
            $this->selectedIndex((int) $attrs['selected-index']);
        }
        if (! empty($attrs['disabled'])) {
            $this->disabled();
        }

        $this->applyA11yAttributes($attrs);

        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode($attrs['sync-mode'] ?? $attrs['syncMode']);
        }
    }

    /** @param array<int|string, string> $options */
    public function options(array $options): static
    {
        $this->buttonGroupProps['options'] = array_values(array_map('strval', $options));

        return $this;
    }

    public function selectedIndex(int $index): static
    {
        $this->buttonGroupProps['value'] = $index;

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->buttonGroupProps['disabled'] = $value;

        return $this;
    }

    public function syncMode(string $mode): static
    {
        $this->buttonGroupProps['sync_mode'] = $mode;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->buttonGroupProps;

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
}
