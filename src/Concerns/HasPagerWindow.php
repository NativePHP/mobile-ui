<?php

namespace Native\Mobile\UI\Concerns;

/**
 * State holder for `<native:pager>`. Native fires `on_page_change(index)`
 * after each swipe settles; the handler records it and the next render
 * emits the pages around it.
 *
 * A feed has no total. `pagerLoaded` is how many items the screen has
 * fetched so far (the pager's `count`); when the settled page gets within
 * `pagerNeedsMore()`'s threshold of that edge, fetch the next batch and
 * `extendPager()` — the pager grows in place. While `pagerHasMore` is true
 * the pager appends a loading page after the last item, so the user can
 * pull into it instead of hitting a wall; settling there reports
 * `index === pagerLoaded`, which `pagerNeedsMore()` also treats as "more".
 *
 *   public function onPagerPage(int $index): void
 *   {
 *       $this->setPagerPage($index);
 *       if ($this->pagerNeedsMore()) {
 *           $batch = $this->api->feed(cursor: $this->cursor);
 *           $this->ids = [...$this->ids, ...$batch->ids];
 *           $this->cursor = $batch->nextCursor;
 *           $this->extendPager(count($batch->ids), hasMore: $batch->nextCursor !== null);
 *       }
 *   }
 *
 * Every page's root element must carry `native:key="page-{$index}"` (or
 * any position-independent key); see Pager's docblock for why.
 *
 * Single pager per screen for now.
 */
trait HasPagerWindow
{
    /** Absolute index of the page currently settled on screen. */
    public int $pagerPage = 0;

    /**
     * Pages shipped either side of the current one. 2 keeps a fast second
     * swipe on-device: the page after next is already there while the PHP
     * round-trip for the settle is still in flight. Each shipped page is
     * rendered Blade plus a buffering (not yet drawing) video, so keep it
     * small.
     */
    public int $pagerWindow = 2;

    /** Items fetched so far — the pager's `count`. */
    public int $pagerLoaded = 0;

    /** Whether another batch can be fetched; drives the trailing loading page. */
    public bool $pagerHasMore = true;

    public function setPagerPage(int $index): void
    {
        $this->pagerPage = max(0, $index);
    }

    /** Record a fetched batch: grows the pager and updates the tail state. */
    public function extendPager(int $added, bool $hasMore = true): void
    {
        $this->pagerLoaded += max(0, $added);
        $this->pagerHasMore = $hasMore;
    }

    /**
     * True when the settled page is within `$threshold` items of the end
     * of what's loaded (or on the loading page itself) and more can be
     * fetched. Three is the usual feed default: the PHP round-trip plus
     * the API call has to land before the user swipes there.
     */
    public function pagerNeedsMore(int $threshold = 3): bool
    {
        return $this->pagerHasMore
            && $this->pagerPage >= $this->pagerLoaded - max(0, $threshold);
    }

    /** First page index PHP should emit for the current window. */
    public function pagerWindowFrom(): int
    {
        return max(0, $this->pagerPage - $this->pagerWindow);
    }

    /** Last page index PHP should emit (inclusive), clamped to what's loaded. */
    public function pagerWindowTo(): int
    {
        $to = $this->pagerPage + $this->pagerWindow;

        return $this->pagerLoaded > 0 ? min($to, $this->pagerLoaded - 1) : $to;
    }
}
