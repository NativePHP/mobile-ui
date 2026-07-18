<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Radio — child of `<radio-group>`. Declares a value + optional label.
 * Selection state is owned by the parent group.
 *
 * Model 3: colors from theme.
 */
class Radio extends Element
{

    protected string $type = 'radio';

    /** @var array<string, mixed> */
    protected array $radioProps = [];

    public static function make(string $value = ''): static
    {
        $el = new static;
        if ($value !== '') {
            $el->radioProps['value'] = $value;
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        // `value` is the option's own value, distinct from the group's
        // selected value. We also accept `radioValue` as a legacy alias.
        if (isset($attrs['value']))      { $this->radioProps['value'] = (string) $attrs['value']; }
        if (isset($attrs['radioValue'])) { $this->radioProps['value'] = (string) $attrs['radioValue']; }
        if (isset($attrs['label']))      { $this->label($attrs['label']); }
        if (! empty($attrs['disabled'])) { $this->disabled(); }

        $this->applyA11yAttributes($attrs);
    }

    public function label(string $label): static
    {
        $this->radioProps['label'] = $label;

        return $this;
    }

    public function disabled(bool $value = true): static
    {
        $this->radioProps['disabled'] = $value;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->radioProps;
    }

    // ── Model 3 enforcement ──────────────────────────────────────────────────

    public function getStyle(): array
    {
        return [];
    }
}
