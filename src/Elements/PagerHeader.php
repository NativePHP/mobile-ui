<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * The header of a horizontal {@see Pager}: a profile's avatar, bio and
 * counts above its Posts and Replies tabs, say. It goes inside the pager,
 * beside the pages:
 *
 *   <native:pager horizontal :tabs="['Posts', 'Replies']" ...>
 *       <native:pager-header> ... </native:pager-header>
 *       <native:column> <native:list> ... </native:list> </native:column>
 *       <native:column> <native:list> ... </native:list> </native:column>
 *   </native:pager>
 *
 * The header scrolls up with the page you're on, and the tabs pin under it
 * once it has gone. The pages swipe beneath the tabs, each its own list,
 * while the header and the tabs stay where they are. So every page needs a
 * list: the header and the tabs are its first rows, and pull to refresh
 * pulls them down with it.
 *
 * The pages scroll together while any of the header shows, so a swipe
 * always finds the header at the height it left it. Once the header has
 * gone, each page keeps its own place. A page too short to scroll the
 * header away gets room at its end to do so.
 */
class PagerHeader extends Element
{
    protected string $type = 'pager_header';

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
