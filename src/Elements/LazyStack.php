<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * A vertical scroll of children drawn lazily, for long feeds that change
 * often (a live log, a chat, a firehose of events). Only the children on
 * screen and near it are built.
 *
 * Unlike {@see NativeList}, it has no separators, swipe actions,
 * pull-to-refresh, sections or row callbacks: each child draws itself. In
 * return a stack that has taken thousands of inserts updates as fast as a
 * fresh one, where a list gets slower with every insert.
 *
 * Give each child a stable `key`. A child added above the screen then
 * doesn't move what's on it, and a reader at the very top sees it come in.
 *
 *   <native:lazy-stack class="w-full flex-1 gap-2" :content-padding="16">
 *       @foreach ($events as $event)
 *           <native:list-item :key="$event->id" :headline="$event->title" />
 *       @endforeach
 *   </native:lazy-stack>
 *
 * `gap-*` spaces the children. `p-*` pads the stack's frame, like any
 * element; {@see contentPadding()} (the `content-padding` attribute, which
 * a server screen sends as `contentPadding`) pads the scrolled content.
 *
 * iOS draws it with a LazyVStack, Android with a LazyColumn. A LazyColumn
 * has no scroll indicator, so `shows-indicators` does nothing there.
 */
class LazyStack extends Element
{
    protected string $type = 'lazy_stack';

    protected array $stackProps = [];

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['showsIndicators']) || isset($attrs['shows-indicators'])) {
            $this->showsIndicators((bool) ($attrs['showsIndicators'] ?? $attrs['shows-indicators']));
        }

        $padding = $attrs['content-padding'] ?? $attrs['contentPadding'] ?? null;
        if ($padding !== null && $padding !== '') {
            $values = is_array($padding)
                ? array_values($padding)
                : preg_split('/[\s,]+/', trim((string) $padding));
            $this->contentPadding(...array_map('floatval', array_slice($values, 0, 4)));
        }

        $this->applyA11yAttributes($attrs);
    }

    public function showsIndicators(bool $value = true): static
    {
        $this->stackProps['shows_indicators'] = $value;

        return $this;
    }

    /**
     * Pad the scrolled content, in points, the way CSS `padding` takes one to
     * four values: all sides, vertical and horizontal, top, horizontal and
     * bottom, or top, right, bottom and left. The first and last child sit
     * this far from the ends and the content scrolls through the padding.
     */
    public function contentPadding(float $top, ?float $right = null, ?float $bottom = null, ?float $left = null): static
    {
        $right ??= $top;
        $bottom ??= $top;
        $left ??= $right;

        $this->stackProps['content_padding_top'] = $top;
        $this->stackProps['content_padding_right'] = $right;
        $this->stackProps['content_padding_bottom'] = $bottom;
        $this->stackProps['content_padding_left'] = $left;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->stackProps;
    }
}
