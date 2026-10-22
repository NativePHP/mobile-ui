<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\Element;

/**
 * A row of a {@see NativeList} that pins to the top of the list once it
 * reaches it, while the rows after it scroll underneath, like CSS
 * `position: sticky`. The next sticky header pushes it off. It lays its
 * children out like a column, so give it a background to keep the rows
 * that pass under it from showing through.
 *
 * Renders as a pinned `Section` header in a plain `List` (iOS) / a
 * `stickyHeader` item in `LazyColumn` (Android). It only pins as a direct
 * child of a list without {@see ListSection}s. A hidden one takes no space.
 *
 *   NativeList::make(
 *       $composer,
 *       StickyHeader::make(Button::make('3 new posts')->onPress('showNewPosts'))->bg('#FFFFFF'),
 *       ...$posts,
 *   );
 */
class StickyHeader extends Element
{
    protected string $type = 'sticky_header';

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
}
