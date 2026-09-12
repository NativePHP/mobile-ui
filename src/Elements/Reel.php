<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Full-screen snap pager — the TikTok / Reels / Shorts feed. Each page
 * fills the container; a swipe settles on exactly one page. Vertical by
 * default, `horizontal` for a stories-style strip.
 *
 * The children are the pages. For a feed, ship only a window of them and
 * tell the reel where that window sits:
 *
 *   <native:reel :count="$loaded" :page="$page" :from="$from" :to="$to"
 *                has-more on-page-change="onReelPage">
 *       @for ($i = $from; $i <= $to; $i++)
 *           @include('feed.page', ['index' => $i])
 *       @endfor
 *   </native:reel>
 *
 * Native lays out `count` logical pages and shows a placeholder for any
 * page outside `[from..to]`. `count` is how many items are loaded SO FAR,
 * not a total — a feed has none; grow it as batches arrive and the pager
 * grows in place. With `has-more` native appends a loading page after the
 * last item; settling on it reports `index === count`. Pair with the
 * `HasReelPage` trait — native fires `on_page_change(int $index)` after
 * each swipe settles and the next render emits the pages around it.
 *
 * Native keeps the pager position across re-renders; `page` only moves
 * the pager when PHP changes it to something other than the index it
 * was last told about (a programmatic jump).
 *
 * The page index rides the tab-change transport, so a single feed is
 * capped at 32,767 pages per screen.
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
        $more = $attrs['has_more'] ?? $attrs['hasMore'] ?? $attrs['has-more'] ?? null;
        if ($more !== null) {
            $this->hasMore(filter_var($more, FILTER_VALIDATE_BOOLEAN));
        }
        $cb = $attrs['on_page_change'] ?? $attrs['onPageChange'] ?? $attrs['on-page-change'] ?? null;
        if ($cb !== null) {
            $this->onPageChange($cb);
        }

        $this->applyA11yAttributes($attrs);
    }

    /** Items loaded so far. Defaults to the number of inline children. */
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

    /**
     * Append a loading page after the last loaded item. The user can pull
     * into it while the next batch is fetched; settling there reports
     * `index === count`.
     */
    public function hasMore(bool $value = true): static
    {
        $this->reelProps['has_more'] = $value;

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
            // Rides the TAB_CHANGE transport: dispatch hands the handler
            // one int — the settled page index.
            $props['on_page_change'] = $registry->register($this->pageCallback);
        }

        return $props;
    }
}
