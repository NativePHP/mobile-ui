<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Toggle — binary on/off switch. Renders as a SwiftUI `Toggle` on iOS and an
 * M3 `Switch` (with optional label row) on Android.
 *
 * Model 3: no per-instance color overrides. Active track / thumb colors come
 * from `theme.primary` / `theme.on-primary`. For custom visuals, drop to
 * `<pressable>` with a custom drawing.
 *
 * Honors `native:model`. `sync_mode` is accepted for API consistency with
 * the other stateful components, though for a discrete control the distinction
 * between live / debounce / blur matters less than it does for sliders or
 * text inputs — every tap is a discrete event.
 */
class Toggle extends Element
{

    protected string $type = 'toggle';

    /** @var array<string, mixed> */
    protected array $toggleProps = [];

    protected ?string $changeCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['label']))    { $this->label($attrs['label']); }
        if (isset($attrs['value']))    { $this->value((bool) $attrs['value']); }
        if (! empty($attrs['disabled'])) { $this->disabled(); }

        $this->applyA11yAttributes($attrs);

        // Sync mode + debounce, normally populated by the `native:model`
        // directive expansion.
        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode($attrs['sync-mode'] ?? $attrs['syncMode']);
        }
        if (isset($attrs['debounce-ms']) || isset($attrs['debounceMs'])) {
            $this->debounceMs((int) ($attrs['debounce-ms'] ?? $attrs['debounceMs']));
        }
    }

    public function label(string $text): static
    {
        $this->toggleProps['label'] = $text;

        return $this;
    }

    public function value(bool $checked): static
    {
        $this->toggleProps['value'] = $checked;

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->toggleProps['disabled'] = $value;

        return $this;
    }

    public function syncMode(string $mode): static
    {
        $this->toggleProps['sync_mode'] = $mode;

        return $this;
    }

    public function debounceMs(int $ms): static
    {
        $this->toggleProps['debounce_ms'] = $ms;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->toggleProps;

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
