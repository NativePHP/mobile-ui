<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Modal — full-screen overlay presentation.
 *
 * Visibility is driven by the `visible` prop. PHP keeps that state and
 * toggles it via a callback, typically bound through `native:model` or a
 * dedicated `@dismiss` action. `dismissible` controls whether tapping the
 * backdrop or the close button fires `@dismiss`.
 *
 * Model 3: backdrop + surface colors come from theme tokens.
 */
class Modal extends Element
{

    protected string $type = 'modal';

    /** @var array<string, mixed> */
    protected array $modalProps = [];

    protected ?string $dismissCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['visible']))   { $this->visible((bool) $attrs['visible']); }
        if (isset($attrs['dismissible']) || isset($attrs['dismissable'])) {
            $this->dismissible((bool) ($attrs['dismissible'] ?? $attrs['dismissable']));
        }
        $this->applyA11yAttributes($attrs);
    }

    public function visible(bool $value = true): static
    {
        $this->modalProps['visible'] = $value;

        return $this;
    }

    public function dismissible(bool $value = true): static
    {
        $this->modalProps['dismissible'] = $value;

        return $this;
    }

    public function onDismiss(string $method): static
    {
        $this->dismissCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->modalProps;

        if ($this->dismissCallback !== null) {
            $props['on_dismiss'] = $registry->register($this->dismissCallback);
        }

        return $props;
    }
}
