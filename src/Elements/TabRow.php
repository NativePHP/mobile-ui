<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * TabRow — horizontal segmented selector. Holds `<tab>` children; the
 * row owns the selected-index state.
 *
 * Accepts `native:model="activeTab"` where `$activeTab` is an int property.
 */
class TabRow extends Element
{

    protected string $type = 'tab_row';

    /** @var array<string, mixed> */
    protected array $tabRowProps = [];

    protected ?string $changeCallback = null;

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        // Accept `value` (from native:model expansion) and `selectedIndex`
        // (from the fluent API / legacy shape) as aliases.
        if (isset($attrs['value']))         { $this->selectedIndex((int) $attrs['value']); }
        if (isset($attrs['selectedIndex'])) { $this->selectedIndex((int) $attrs['selectedIndex']); }
        if (isset($attrs['selected-index'])){ $this->selectedIndex((int) $attrs['selected-index']); }

        $this->applyA11yAttributes($attrs);

        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode($attrs['sync-mode'] ?? $attrs['syncMode']);
        }
    }

    public function selectedIndex(int $index): static
    {
        // Stored under `value` so native:model → `__syncProperty` writes
        // through the same key every other stateful component uses.
        $this->tabRowProps['value'] = $index;

        return $this;
    }

    public function syncMode(string $mode): static
    {
        $this->tabRowProps['sync_mode'] = $mode;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->tabRowProps;

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
