<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

class Accordion extends Element
{
    protected string $type = 'accordion';

    protected array $props = [];

    protected ?string $changeCallback = null;

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['expanded'])) {
            $this->expanded((bool) $attrs['expanded']);
        }

        $this->applyA11yAttributes($attrs);
    }

    public function expanded(bool $expanded): static
    {
        $this->props['expanded'] = $expanded;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->props;

        if ($this->changeCallback !== null) {
            $props['on_change'] = $registry->register($this->changeCallback);
        }

        return $props;
    }
}
