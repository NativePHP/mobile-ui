<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Slider — continuous (or stepped) value selection.
 *
 * Model 3: no per-instance color/track overrides. Colors come from theme
 * tokens (`primary` for the active track + thumb). For fully custom visuals,
 * drop to `<pressable>` wrapping a custom drawing.
 *
 * Honors `native:model` with live / blur / debounce modifiers. Default is
 * `live` — every drag tick fires a change event. `blur` collapses to one
 * event per drag release. `debounce.Xms` coalesces rapid drags.
 */
class Slider extends Element
{

    protected string $type = 'slider';

    /** @var array<string, mixed> */
    protected array $sliderProps = [];

    protected ?string $changeCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['value']))    { $this->value((float) $attrs['value']); }
        if (isset($attrs['min']))      { $this->min((float) $attrs['min']); }
        if (isset($attrs['max']))      { $this->max((float) $attrs['max']); }
        if (isset($attrs['step']))     { $this->step((float) $attrs['step']); }
        if (! empty($attrs['disabled'])) { $this->disabled(); }

        if (isset($attrs['size']))     { $this->size($attrs['size']); }

        $this->applyA11yAttributes($attrs);

        // Sync mode + debounce, normally populated by the `native:model`
        // directive expansion. Can also be set manually.
        if (isset($attrs['sync-mode']) || isset($attrs['syncMode'])) {
            $this->syncMode($attrs['sync-mode'] ?? $attrs['syncMode']);
        }
        if (isset($attrs['debounce-ms']) || isset($attrs['debounceMs'])) {
            $this->debounceMs((int) ($attrs['debounce-ms'] ?? $attrs['debounceMs']));
        }
    }

    public function value(float $val): static
    {
        $this->sliderProps['value'] = $val;

        return $this;
    }

    public function min(float $val): static
    {
        $this->sliderProps['min'] = $val;

        return $this;
    }

    public function max(float $val): static
    {
        $this->sliderProps['max'] = $val;

        return $this;
    }

    public function step(float $val): static
    {
        $this->sliderProps['step'] = $val;

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->sliderProps['disabled'] = $value;

        return $this;
    }

    public function size(string $value): static
    {
        $this->sliderProps['size'] = $value;

        return $this;
    }

    public function syncMode(string $mode): static
    {
        $this->sliderProps['sync_mode'] = $mode;

        return $this;
    }

    public function debounceMs(int $ms): static
    {
        $this->sliderProps['debounce_ms'] = $ms;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->sliderProps;

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
