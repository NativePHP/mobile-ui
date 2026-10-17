<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Something laid over a {@see Pager}'s pages, hanging just under its tabs:
 * a "3 new posts" pill, say. It goes inside the pager, beside the pages,
 * and stays under the tabs wherever a {@see PagerHeader} has scrolled them
 * to. It doesn't move with a swipe.
 *
 * It's as wide as the pager, and touches on its empty space go through to
 * the page under it. Hide it (`hidden`) rather than leave it out, so the
 * pages around it keep their place in the tree.
 */
class PagerOverlay extends Element
{
    protected string $type = 'pager_overlay';

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
        return [];
    }
}
