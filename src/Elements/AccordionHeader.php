<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

class AccordionHeader extends Element
{
    protected string $type = 'accordion_header';

    protected array $props = [];

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        $this->applyA11yAttributes($attrs);
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->props;
    }
}
