<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Full-screen snap pager — the TikTok / Reels / Shorts feed. Each page
 * fills the container; a swipe settles on exactly one page. Vertical by
 * default, `horizontal` for a stories-style strip.
 *
 * Two ways to fill it:
 *
 *  - Windowed (`<reel item="feed.page" :count="$n" :page="$page" />`):
 *    the precompiler renders the `item` view once per index inside
 *    `[window_from..window_to]`; native lays out `count` logical pages
 *    and shows a placeholder for any page PHP hasn't shipped. Pair with
 *    `HasReelPage` — native fires `on_page_change(index)` after each
 *    swipe settles and the next render emits the pages around it.
 *  - Inline (`<reel> ...pages... </reel>`): the children are the pages.
 *
 * Native keeps the pager position across re-renders; `page` only moves
 * the pager when PHP changes it to something other than the index it
 * was last told about (a programmatic jump).
 */
class Reel extends Element
{
    protected string $type = 'reel';

    /** @var array<string, mixed> */
    protected array $reelProps = [];

    protected ?string $pageCallback = null;

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['count'])) {
            $this->count((int) $attrs['count']);
        }
        if (isset($attrs['page'])) {
            $this->page((int) $attrs['page']);
        }
        $from = $attrs['window_from'] ?? $attrs['windowFrom'] ?? $attrs['from'] ?? null;
        if ($from !== null) {
            $this->reelProps['window_from'] = (int) $from;
        }
        $to = $attrs['window_to'] ?? $attrs['windowTo'] ?? $attrs['to'] ?? null;
        if ($to !== null) {
            $this->reelProps['window_to'] = (int) $to;
        }
        if (isset($attrs['horizontal'])) {
            $this->horizontal(filter_var($attrs['horizontal'], FILTER_VALIDATE_BOOLEAN));
        }
        $cb = $attrs['on_page_change'] ?? $attrs['onPageChange'] ?? $attrs['on-page-change'] ?? null;
        if ($cb !== null) {
            $this->onPageChange($cb);
        }

        $this->applyA11yAttributes($attrs);
    }

    /** Total logical pages. Defaults to the number of inline children. */
    public function count(int $count): static
    {
        $this->reelProps['count'] = max(0, $count);

        return $this;
    }

    /** Page the pager should show; see the class doc for when it moves. */
    public function page(int $index): static
    {
        $this->reelProps['page'] = max(0, $index);

        return $this;
    }

    public function horizontal(bool $value = true): static
    {
        $this->reelProps['horizontal'] = $value;

        return $this;
    }

    public function onPageChange(string $method): static
    {
        $this->pageCallback = $method;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->reelProps;

        if (! isset($props['count'])) {
            $props['count'] = count($this->children);
        }

        if ($this->pageCallback !== null) {
            // 'reel_page' kind: NativeComponent::dispatch decodes the
            // TEXT_CHANGE payload as one int (the settled page index).
            $props['on_page_change'] = $registry->register($this->pageCallback, 'reel_page');
        }

        return $props;
    }
}
